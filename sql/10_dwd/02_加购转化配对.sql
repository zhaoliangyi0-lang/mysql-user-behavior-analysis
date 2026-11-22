-- ============================================
-- 功能：加购转化配对（M2 第 2 步）
-- 板块：dwd › 加购转化
-- 依赖：dwd_cart_event（需先执行 01_加购事件构造.sql）
-- 状态：待执行
-- 更新：2026-11-22
-- 对应研究设计：docs/00_研究设计.md 4.3 转化定义
-- ============================================
--
-- 口径（已确认）：
--   1. 转化 = 加购事件之后、同一 (user_id, item_id) 出现 buy 记录；
--   2. 主窗口 7 天，同时标记 1 小时 / 1 天 / 3 天是否转化，用于累积曲线；
--   3. 转化归属：同一用户-商品的多次加购，一笔购买只归入最近的上一次事件。
--      窗口上界 = LEAST(加购 + 7 天, 下一次加购时间)，事件之间不重叠；
--   4. 右删失：距离数据集终点不足 7 天的加购，observation_complete = 0，
--      事件级主指标剔除，用户级口径保留；
--   5. was_bought_before = 1 表示加购前已购买过该商品（复购型加购）。
--
-- 产出 dwd_cart_convert：每个加购事件一行。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 建目标表
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS dwd_cart_convert;
CREATE TABLE dwd_cart_convert (
    event_id             INT NOT NULL,
    user_id              INT NOT NULL,
    item_id              INT NOT NULL,
    category_id          INT DEFAULT NULL,
    event_start_ts       INT NOT NULL,
    event_end_ts         INT NOT NULL,
    cart_cnt             INT NOT NULL,
    buy_ts               INT DEFAULT NULL,
    is_converted         TINYINT NOT NULL DEFAULT 0,
    latency_seconds      INT DEFAULT NULL,
    latency_hours        DECIMAL(12, 2) DEFAULT NULL,
    conv_1h              TINYINT NOT NULL DEFAULT 0,
    conv_1d              TINYINT NOT NULL DEFAULT 0,
    conv_3d              TINYINT NOT NULL DEFAULT 0,
    conv_7d              TINYINT NOT NULL DEFAULT 0,
    was_bought_before    TINYINT NOT NULL DEFAULT 0,
    observation_complete TINYINT NOT NULL DEFAULT 0,
    is_last7d            TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (event_id),
    KEY idx_user (user_id),
    KEY idx_item (item_id),
    KEY idx_convert (is_converted)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4;

-- ────────────────────────────────────────────────
-- ② 配对并写入
-- ────────────────────────────────────────────────
-- 层说明：
--   event_with_next  取每个事件的下一次加购时间，用于截断窗口
--   buy_in_window    在 [事件时间, 窗口上界) 内找最早的购买
--                    （严格小于上界：恰好落在下一次加购同一秒的购买归后一次）
--   first_buy        每个用户-商品的首次购买时间，判断复购型加购
--   data_bounds      数据集观测终点，判断右删失
--
-- ⚠️ 性能：buy_in_window 是对全量 9100 万行的关联扫描，是 M2 最重的查询。
--    执行前先补联合索引，并预留足够的临时表空间：
--        CREATE INDEX idx_user_item_behavior
--            ON user_behavior (user_id, item_id, behavior_type, timestamps);
--    该索引只在已有静态数据上建一次，建过就跳过，重复执行会报重名。
INSERT INTO dwd_cart_convert (
    event_id,
    user_id,
    item_id,
    category_id,
    event_start_ts,
    event_end_ts,
    cart_cnt,
    buy_ts,
    is_converted,
    latency_seconds,
    latency_hours,
    conv_1h,
    conv_1d,
    conv_3d,
    conv_7d,
    was_bought_before,
    observation_complete,
    is_last7d
)
WITH data_bounds AS (
    SELECT MAX(timestamps) AS max_ts
    FROM user_behavior
),
event_with_next AS (
    SELECT
        e.*,
        LEAD(e.event_start_ts) OVER (
            PARTITION BY e.user_id, e.item_id
            ORDER BY e.event_start_ts
        ) AS next_event_ts
    FROM dwd_cart_event e
),
buy_in_window AS (
    SELECT
        e.event_id,
        MIN(b.timestamps) AS buy_ts
    FROM event_with_next e
    JOIN user_behavior b
        ON b.user_id = e.user_id
       AND b.item_id = e.item_id
       AND b.behavior_type = 'buy'
       AND b.timestamps >= e.event_start_ts
       AND b.timestamps < LEAST(
               e.event_start_ts + 604800,
               COALESCE(e.next_event_ts, e.event_start_ts + 604800)
           )
    GROUP BY e.event_id
),
first_buy AS (
    SELECT
        user_id,
        item_id,
        MIN(timestamps) AS first_buy_ts
    FROM user_behavior
    WHERE behavior_type = 'buy'
    GROUP BY user_id, item_id
)
SELECT
    e.event_id,
    e.user_id,
    e.item_id,
    e.category_id,
    e.event_start_ts,
    e.event_end_ts,
    e.cart_cnt,
    w.buy_ts,
    CASE WHEN w.buy_ts IS NULL THEN 0 ELSE 1 END AS is_converted,
    CASE WHEN w.buy_ts IS NULL THEN NULL
         ELSE w.buy_ts - e.event_start_ts
    END AS latency_seconds,
    CASE WHEN w.buy_ts IS NULL THEN NULL
         ELSE ROUND((w.buy_ts - e.event_start_ts) / 3600, 2)
    END AS latency_hours,
    CASE
        WHEN w.buy_ts IS NULL THEN 0
        WHEN w.buy_ts - e.event_start_ts <= 3600 THEN 1
        ELSE 0
    END AS conv_1h,
    CASE
        WHEN w.buy_ts IS NULL THEN 0
        WHEN w.buy_ts - e.event_start_ts <= 86400 THEN 1
        ELSE 0
    END AS conv_1d,
    CASE
        WHEN w.buy_ts IS NULL THEN 0
        WHEN w.buy_ts - e.event_start_ts <= 259200 THEN 1
        ELSE 0
    END AS conv_3d,
    CASE WHEN w.buy_ts IS NULL THEN 0 ELSE 1 END AS conv_7d,
    CASE
        WHEN fb.first_buy_ts IS NOT NULL
         AND fb.first_buy_ts < e.event_start_ts THEN 1
        ELSE 0
    END AS was_bought_before,
    CASE
        WHEN d.max_ts - e.event_start_ts >= 604800 THEN 1
        ELSE 0
    END AS observation_complete,
    CASE
        WHEN d.max_ts - e.event_start_ts < 604800 THEN 1
        ELSE 0
    END AS is_last7d
FROM event_with_next e
CROSS JOIN data_bounds d
LEFT JOIN buy_in_window w
    ON w.event_id = e.event_id
LEFT JOIN first_buy fb
    ON fb.user_id = e.user_id
   AND fb.item_id = e.item_id;

-- ────────────────────────────────────────────────
-- ③ 自检 1：转化率总览（事件级，含右删失对比）
-- ────────────────────────────────────────────────
-- 主指标看 observation_complete = 1 的部分；
-- 全量对照用来看右删失造成的低估幅度。
SELECT COUNT(*)                                            AS 全部事件数,
       SUM(observation_complete)                           AS 观察完整事件数,
       SUM(is_last7d)                                      AS 末段事件数,
       ROUND(AVG(is_converted) * 100, 2)                   AS 全量转化率百分比,
       ROUND(SUM(IF(observation_complete = 1, is_converted, NULL))
             / SUM(observation_complete) * 100, 2)         AS 观察完整转化率百分比,
       ROUND(AVG(conv_1h) * 100, 2)                        AS 1小时转化率百分比,
       ROUND(AVG(conv_1d) * 100, 2)                        AS 1天转化率百分比,
       ROUND(AVG(conv_3d) * 100, 2)                        AS 3天转化率百分比
FROM dwd_cart_convert;

-- ────────────────────────────────────────────────
-- ④ 自检 2：转化时延分布
-- ────────────────────────────────────────────────
SELECT
       CASE
           WHEN latency_hours <= 1  THEN '1小时内'
           WHEN latency_hours <= 24 THEN '1小时内-1天'
           WHEN latency_hours <= 72 THEN '1-3天'
           WHEN latency_hours <= 168 THEN '3-7天'
           ELSE '7天以上'
       END AS 时延区间,
       COUNT(*) AS 事件数
FROM dwd_cart_convert
WHERE is_converted = 1
GROUP BY 时延区间
ORDER BY 事件数 DESC;

-- ────────────────────────────────────────────────
-- ⑤ 自检 3：口径一致性
-- ────────────────────────────────────────────────
-- 期望：is_converted = 1 时 buy_ts、latency_hours 都不为空；
-- 且 conv_1h ≤ conv_1d ≤ conv_3d ≤ conv_7d，违反说明窗口逻辑有错。
SELECT SUM(is_converted = 1 AND buy_ts IS NULL)                     AS 转化但无购买时间,
       SUM(is_converted = 0 AND buy_ts IS NOT NULL)                 AS 未转化但有购买时间,
       SUM(conv_1h > conv_1d OR conv_1d > conv_3d OR conv_3d > conv_7d) AS 窗口标志倒挂
FROM dwd_cart_convert;

-- ────────────────────────────────────────────────
-- ⑥ 自检 4：复购型加购占比
-- ────────────────────────────────────────────────
SELECT was_bought_before                              AS 加购前已购买过,
       COUNT(*)                                       AS 事件数,
       ROUND(AVG(is_converted) * 100, 2)              AS 转化率百分比
FROM dwd_cart_convert
WHERE observation_complete = 1
GROUP BY was_bought_before;
