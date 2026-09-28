-- ============================================
-- 功能：行为路径分析
-- 板块：人 › 行为情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 行为情况 › 行为路径分析
-- ============================================
--
-- 思路：把每个「用户 × 商品」的四种行为压成 4 位 0/1 码，
--       再统计各种路径的出现次数，看用户都是怎么走到购买的。
--
-- 【编码规则】concat(已浏览, 已收藏, 已加购, 已购买)
--     第 1 位 = 已浏览    第 3 位 = 已加购
--     第 2 位 = 已收藏    第 4 位 = 已购买
--   例：'1001' = 浏览过 + 购买过（没收藏没加购）
--
-- 中间搭了 4 层视图，一层做一件事：
--     user_behavior_view      行为次数透视（每用户每商品一行）
--     user_behavior_standard  次数 → 0/1（只看"做没做过"）
--     user_behavior_path      拼出 4 位路径码，只保留最终购买了的
--     path_count              按路径码分组计数

USE taobao;

-- ════════════════════════════════════════════════
-- ①【小样本验证】在沙箱表上把 4 层视图跑通
-- ════════════════════════════════════════════════
CREATE OR REPLACE VIEW user_behavior_view AS
SELECT user_id, item_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy
FROM temp_behavior
GROUP BY user_id, item_id;

-- 次数 → 0/1：路径分析只关心"做没做过"，不关心做了几次
CREATE OR REPLACE VIEW user_behavior_standard AS
SELECT user_id,
       item_id,
       (CASE WHEN pv   > 0 THEN 1 ELSE 0 END) AS 已浏览,
       (CASE WHEN fav  > 0 THEN 1 ELSE 0 END) AS 已收藏,
       (CASE WHEN cart > 0 THEN 1 ELSE 0 END) AS 已加购,
       (CASE WHEN buy  > 0 THEN 1 ELSE 0 END) AS 已购买
FROM user_behavior_view;

-- 拼路径码，只保留最终购买了的用户-商品对
CREATE OR REPLACE VIEW user_behavior_path AS
SELECT *,
       CONCAT(已浏览, 已收藏, 已加购, 已购买) AS 购买路径类型
FROM user_behavior_standard
WHERE 已购买 > 0;

CREATE OR REPLACE VIEW path_count AS
SELECT 购买路径类型,
       COUNT(*) AS 数量
FROM user_behavior_path
GROUP BY 购买路径类型;

-- ════════════════════════════════════════════════
-- ② 路径类型码表（把 4 位码翻译成人话）
-- ════════════════════════════════════════════════
DROP TABLE IF EXISTS renhua;
CREATE TABLE renhua (
    path_type   CHAR(4),
    description VARCHAR(40)
);

INSERT INTO renhua VALUES
    ('0001', '直接购买'),
    ('1001', '浏览后购买'),
    ('0011', '加购后购买'),
    ('0101', '收藏后购买'),
    ('1011', '浏览加购后购买'),
    ('1101', '浏览收藏后购买'),
    ('0111', '收藏加购后购买'),
    ('1111', '浏览收藏加购后购买');

-- 查沙箱里的路径分布
SELECT p.购买路径类型, r.description, p.数量
FROM path_count p
JOIN renhua r ON p.购买路径类型 = r.path_type
ORDER BY p.数量 DESC;

-- ════════════════════════════════════════════════
-- ③【全量执行】拆掉沙箱视图，对真实表重建
-- ════════════════════════════════════════════════
-- 沙箱视图这名字占着正式的位，必须拆掉才能换成全量版本
DROP VIEW IF EXISTS user_behavior_view;
DROP VIEW IF EXISTS user_behavior_standard;
DROP VIEW IF EXISTS user_behavior_path;
DROP VIEW IF EXISTS path_count;

-- 结果表
DROP TABLE IF EXISTS path_result;
CREATE TABLE path_result (
    path_type   CHAR(4),        -- 4 位路径码
    description VARCHAR(40),    -- 路径中文说明
    num         INT             -- 该路径的购买次数
);

-- 重建 4 层视图，这次数据源换成全量 user_behavior
CREATE VIEW user_behavior_view AS
SELECT user_id, item_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy
FROM user_behavior
GROUP BY user_id, item_id;

CREATE VIEW user_behavior_standard AS
SELECT user_id,
       item_id,
       (CASE WHEN pv   > 0 THEN 1 ELSE 0 END) AS 已浏览,
       (CASE WHEN fav  > 0 THEN 1 ELSE 0 END) AS 已收藏,
       (CASE WHEN cart > 0 THEN 1 ELSE 0 END) AS 已加购,
       (CASE WHEN buy  > 0 THEN 1 ELSE 0 END) AS 已购买
FROM user_behavior_view;

CREATE VIEW user_behavior_path AS
SELECT *,
       CONCAT(已浏览, 已收藏, 已加购, 已购买) AS 购买路径类型
FROM user_behavior_standard
WHERE 已购买 > 0;

CREATE VIEW path_count AS
SELECT 购买路径类型,
       COUNT(*) AS 数量
FROM user_behavior_path
GROUP BY 购买路径类型;

-- 落结果表
INSERT INTO path_result
SELECT p.path_type, r.description, p.数量
FROM path_count p
JOIN renhua r ON p.购买路径类型 = r.path_type;

-- 核对
SELECT * FROM path_result ORDER BY num DESC;

-- ════════════════════════════════════════════════
-- ④ 延伸分析：购买前有没有经过「收藏 / 加购」
-- ════════════════════════════════════════════════
-- 没收藏也没加购就直接下单的购买量
SELECT SUM(buy) AS 无收藏加购的购买次数
FROM user_behavior_view
WHERE buy > 0
  AND fav  = 0
  AND cart = 0;

-- 当初的验算记录（数字取自上面的查询结果）：
--     无收藏加购的购买量   14625
--     总购买量             19340
--     收藏 + 加购量        27319 + 55547
--     经收藏加购后的购买量 19340 - 14625 = 4715
--     收藏加购 → 购买转化率 4715 / (27319 + 55547) ≈ 0.0569
--
-- 含义：在收藏或加购过的行为里，最终只有约 5.7% 走到了购买。
