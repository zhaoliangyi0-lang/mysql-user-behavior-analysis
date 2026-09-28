-- ============================================
-- 功能：日内行为（时间序列分析）
-- 板块：人 › 行为情况 › 时间序列分析
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 行为情况 › 时间序列分析 › 日内行为
-- ============================================
--
-- 产出 date_hour_behavior 表：日期 × 小时 的行为量交叉表。
-- 它是「日内行为」和「周内行为」两个分析的共同底座 ——
-- 粒度最细（每天每小时），往上汇总就能得到任一时间维度。

USE taobao;

-- ────────────────────────────────────────────────
-- ①【小样本验证】基于沙箱表，秒级出结果
-- ────────────────────────────────────────────────
SELECT dates, hours,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy
FROM temp_behavior
GROUP BY dates, hours
ORDER BY dates, hours;

-- ────────────────────────────────────────────────
-- ② 建结果表
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS date_hour_behavior;
CREATE TABLE date_hour_behavior (
    dates CHAR(10),   -- 日期，如 2017-12-02
    hours CHAR(2),    -- 小时，'00' ~ '23'
    pv    INT,        -- 该小时内的浏览次数
    cart  INT,        -- 加购次数
    fav   INT,        -- 收藏次数
    buy   INT         -- 购买次数
);

-- ────────────────────────────────────────────────
-- ③【全量执行】对真实表跑
-- ────────────────────────────────────────────────
-- 实测耗时约 4 分 31 秒（100 万行按两列分组）。
-- 没加 ORDER BY：INSERT 不看顺序，排序是白花的开销。
INSERT INTO date_hour_behavior
SELECT dates, hours,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)),
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)),
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)),
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL))
FROM user_behavior
WHERE dates IS NOT NULL
  AND hours IS NOT NULL
GROUP BY dates, hours;

-- ④ 核对
SELECT COUNT(*) AS 行数 FROM date_hour_behavior;   -- 最多 9 天 × 24 小时 = 216 行
SELECT * FROM date_hour_behavior ORDER BY dates, hours LIMIT 20;

-- ────────────────────────────────────────────────
-- ⑤ 日内分布：只按小时汇总，看一天中的行为高峰
-- ────────────────────────────────────────────────
SELECT hours,
       SUM(pv)   AS pv,
       SUM(cart) AS cart,
       SUM(fav)  AS fav,
       SUM(buy)  AS buy
FROM date_hour_behavior
GROUP BY hours
ORDER BY hours;
