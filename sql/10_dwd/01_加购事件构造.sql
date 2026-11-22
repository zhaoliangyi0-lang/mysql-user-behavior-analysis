-- ============================================
-- 功能：加购事件构造（M2 第 1 步）
-- 板块：dwd › 加购事件
-- 依赖：taobao.user_behavior（建议先跑 11_前置检查.sql）
-- 状态：待执行
-- 更新：2026-11-22
-- 对应研究设计：docs/00_研究设计.md 4.2 加购事件
-- ============================================
--
-- 口径（已确认）：
--   1. 只取 behavior_type = 'cart'，fav 不在主口径内；
--   2. 同一 (user_id, item_id) 的加购按 timestamps 排序，
--      相邻两条间隔 > 1800 秒（30 分钟）切分为新事件；
--   3. 事件时间取该事件内【首次】加购时间；
--   4. category_id 取事件内 MIN()，同一商品品类本应唯一，
--      取到多个值说明存在脏数据，跑完可用【自检 2】核对。
--
-- 数据没有 session 标识，30 分钟是设计选择而非数据事实，
-- 15 / 60 分钟的敏感性检验在 90_验证 中做。
--
-- 产出 dwd_cart_event：每个加购事件一行。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 建目标表
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS dwd_cart_event;
CREATE TABLE dwd_cart_event (
    event_id        INT NOT NULL,
    user_id         INT NOT NULL,
    item_id         INT NOT NULL,
    category_id     INT DEFAULT NULL,
    event_start_ts  INT NOT NULL,
    event_end_ts    INT NOT NULL,
    cart_cnt        INT NOT NULL,
    PRIMARY KEY (event_id),
    KEY idx_user_item (user_id, item_id),
    KEY idx_start_ts (event_start_ts)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4;

-- ────────────────────────────────────────────────
-- ② 构造事件并写入
-- ────────────────────────────────────────────────
-- 分四层，一层只做一件事：
--   cart_dedup     去掉完全相同的加购行（同一秒重复上报）
--   cart_lagged    取同一用户-商品的上一条加购时间
--   cart_marked    间隔 > 1800 秒或没有上一条 → 新事件标记 1
--   cart_eventized 按用户-商品做前缀和，得到事件序号
--
-- 全量约 9100 万行时，这段会触发大规模排序与临时表，耗时可能以小时计。
-- 执行建议：
--   1. 先建 (user_id, item_id) 联合索引；
--   2. 调大 sort_buffer_size 与 tmp_table_size；
--   3. 必要时按 user_id 分批构造，再合并结果。
-- 若 Workbench 报断连，先把 Read Timeout 调到 3600
-- （Edit → Preferences → SQL Editor → Read Timeout）。
INSERT INTO dwd_cart_event (
    event_id,
    user_id,
    item_id,
    category_id,
    event_start_ts,
    event_end_ts,
    cart_cnt
)
WITH cart_dedup AS (
    SELECT DISTINCT
        user_id,
        item_id,
        category_id,
        timestamps
    FROM user_behavior
    WHERE behavior_type = 'cart'
),
cart_lagged AS (
    SELECT
        user_id,
        item_id,
        category_id,
        timestamps,
        LAG(timestamps) OVER (
            PARTITION BY user_id, item_id
            ORDER BY timestamps
        ) AS prev_ts
    FROM cart_dedup
),
cart_marked AS (
    SELECT
        user_id,
        item_id,
        category_id,
        timestamps,
        CASE
            WHEN prev_ts IS NULL THEN 1
            WHEN timestamps - prev_ts > 1800 THEN 1
            ELSE 0
        END AS is_new_event
    FROM cart_lagged
),
cart_eventized AS (
    SELECT
        user_id,
        item_id,
        category_id,
        timestamps,
        SUM(is_new_event) OVER (
            PARTITION BY user_id, item_id
            ORDER BY timestamps
            ROWS UNBOUNDED PRECEDING
        ) AS event_seq
    FROM cart_marked
)
SELECT
    ROW_NUMBER() OVER (ORDER BY user_id, item_id, event_seq) AS event_id,
    user_id,
    item_id,
    MIN(category_id)  AS category_id,
    MIN(timestamps)   AS event_start_ts,
    MAX(timestamps)   AS event_end_ts,
    COUNT(*)          AS cart_cnt
FROM cart_eventized
GROUP BY user_id, item_id, event_seq;

-- ────────────────────────────────────────────────
-- ③ 自检 1：事件规模是否合理
-- ────────────────────────────────────────────────
-- 期望：事件数 ≤ 加购行数；若事件数远小于行数，
-- 说明 30 分钟阈值把大量记录并到了一起，需结合【前置检查 8】判断。
SELECT COUNT(*)              AS 加购事件数,
       COUNT(DISTINCT user_id) AS 加购用户数,
       COUNT(DISTINCT item_id) AS 加购商品数,
       ROUND(AVG(cart_cnt), 2) AS 平均每事件加购次数,
       MAX(cart_cnt)           AS 单事件最大加购次数
FROM dwd_cart_event;

-- ────────────────────────────────────────────────
-- ④ 自检 2：同一商品是否出现多个品类
-- ────────────────────────────────────────────────
-- 期望 0 行。有结果说明原始数据里商品-品类映射不唯一。
SELECT item_id,
       COUNT(DISTINCT category_id) AS 品类数
FROM user_behavior
WHERE category_id IS NOT NULL
GROUP BY item_id
HAVING COUNT(DISTINCT category_id) > 1
LIMIT 20;

-- ────────────────────────────────────────────────
-- ⑤ 自检 3：事件样例
-- ────────────────────────────────────────────────
SELECT *
FROM dwd_cart_event
ORDER BY event_id
LIMIT 20;
