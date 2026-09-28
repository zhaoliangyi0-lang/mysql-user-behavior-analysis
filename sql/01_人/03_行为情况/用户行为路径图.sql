-- ============================================
-- 功能：用户行为路径图（按人数）
-- 板块：人 › 行为情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：待验证
-- 更新：2026-09-21
-- 对应思维导图：人 › 行为情况 › 行为路径分析
-- ============================================
--
-- 与「行为路径分析.sql」的口径差异：
--   那份按「用户 × 商品」对统计购买路径码，只保留买了的；
--   这份按「用户」统计，把没买的也画进路径，能看出流失卡在哪一步。
--
-- 【路径定义】一个用户只归一类，按下面的顺序判定：
--   浏览 → 收藏/加购 → 购买     有购买，且收藏或加购过
--   浏览 → 购买                 有购买，但没收藏也没加购
--   浏览 → 收藏/加购 → 未购买   没购买，但收藏或加购过
--   浏览 → 退出                 从头到尾只有浏览
--
-- 注意：按用户聚合意味着「只要他买过任意一件商品」就归入购买类，
--       不再区分是哪个商品。要看单品粒度请用「行为路径分析.sql」。
--       最后两类如果不需要区分，合并起来就是「浏览 → 流失」。

USE taobao;

-- ════════════════════════════════════════════════
-- ①【小样本验证】先在沙箱表上把 3 层视图跑通
-- ════════════════════════════════════════════════

-- 第 1 层：每用户一行，四种行为各发生了几次
CREATE OR REPLACE VIEW user_path_view AS
SELECT user_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy
FROM temp_behavior
GROUP BY user_id;

-- 第 2 层：判路径（CASE 的分支顺序就是优先级，不要调换）
CREATE OR REPLACE VIEW user_path_type AS
SELECT user_id,
       (CASE
           WHEN buy > 0 AND (fav > 0 OR cart > 0) THEN '浏览→收藏/加购→购买'
           WHEN buy > 0                           THEN '浏览→购买'
           WHEN fav > 0 OR cart > 0               THEN '浏览→收藏/加购→未购买'
           ELSE                                        '浏览→退出'
       END) AS 路径
FROM user_path_view;

-- 第 3 层：按路径汇总人数
CREATE OR REPLACE VIEW path_user_count AS
SELECT 路径,
       COUNT(*) AS 人数
FROM user_path_type
GROUP BY 路径
ORDER BY 人数 DESC;

SELECT * FROM path_user_count;

-- ════════════════════════════════════════════════
-- ②【全量执行】拆掉沙箱视图，对真实表重建并落库
-- ════════════════════════════════════════════════
DROP VIEW IF EXISTS user_path_view;
DROP VIEW IF EXISTS user_path_type;
DROP VIEW IF EXISTS path_user_count;

-- 结果表
DROP TABLE IF EXISTS user_path_result;
CREATE TABLE user_path_result (
    路径 VARCHAR(30),       -- 路径名称
    人数 INT                -- 落在该路径上的用户数
);

CREATE VIEW user_path_view AS
SELECT user_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy
FROM user_behavior
GROUP BY user_id;

CREATE VIEW user_path_type AS
SELECT user_id,
       (CASE
           WHEN buy > 0 AND (fav > 0 OR cart > 0) THEN '浏览→收藏/加购→购买'
           WHEN buy > 0                           THEN '浏览→购买'
           WHEN fav > 0 OR cart > 0               THEN '浏览→收藏/加购→未购买'
           ELSE                                        '浏览→退出'
       END) AS 路径
FROM user_path_view;

-- 落结果表
INSERT INTO user_path_result
SELECT 路径,
       COUNT(*) AS 人数
FROM user_path_type
GROUP BY 路径;

-- 核对：四类人数相加应等于去重后的用户总数
SELECT * FROM user_path_result ORDER BY 人数 DESC;

-- ════════════════════════════════════════════════
-- ③ 整体转化率
-- ════════════════════════════════════════════════
SELECT
    COUNT(*)                                                  AS 总用户数,
    SUM(CASE WHEN 路径 IN ('浏览→购买', '浏览→收藏/加购→购买')
             THEN 1 ELSE 0 END)                               AS 购买用户数,
    ROUND(SUM(CASE WHEN 路径 IN ('浏览→购买', '浏览→收藏/加购→购买')
                   THEN 1 ELSE 0 END) * 100 / COUNT(*), 2)    AS 购买转化率百分比,
    SUM(CASE WHEN 路径 = '浏览→收藏/加购→未购买'
             THEN 1 ELSE 0 END)                               AS 加购收藏后流失人数
FROM user_path_type;
