-- ============================================
-- 功能：数据前置检查（M2 第 0 步）
-- 板块：数据准备 › 研究前置
-- 依赖：taobao.user_behavior
-- 状态：待执行
-- 更新：2026-11-22
-- 对应研究设计：docs/00_研究设计.md 第六节「数据完整性」
-- ============================================
--
-- 为什么先做这一步：
--   本项目的留存、转化时延、召回窗口都依赖时间维度。
--   全量数据理论上覆盖完整观测期，但仍需确认：时间范围是否连续、
--   是否存在缺口或异常时间戳、加购是否集中在极短时间。
--   这些问题会直接影响时延类结论，必须在建模前看清。
--
-- 执行方式：在 Workbench 中逐段执行，把【检查 2】到【检查 9】的结果贴回讨论。

USE taobao;

-- ────────────────────────────────────────────────
-- 【检查 1】版本、时区与表字段
-- ────────────────────────────────────────────────
SELECT VERSION()          AS 版本,
       @@session.time_zone AS 会话时区,
       @@global.time_zone  AS 全局时区;

SHOW COLUMNS FROM user_behavior;

-- ────────────────────────────────────────────────
-- 【检查 2】总行数、时间范围与覆盖天数
-- ────────────────────────────────────────────────
SELECT COUNT(*)                                AS 总行数,
       MIN(timestamps)                         AS 最早时间戳,
       MAX(timestamps)                         AS 最晚时间戳,
       FROM_UNIXTIME(MIN(timestamps))          AS 最早时间,
       FROM_UNIXTIME(MAX(timestamps))          AS 最晚时间,
       ROUND((MAX(timestamps) - MIN(timestamps)) / 86400, 2) AS 覆盖天数
FROM user_behavior;

-- ────────────────────────────────────────────────
-- 【检查 3】每天的行数分布（关键）
-- ────────────────────────────────────────────────
-- 判定标准：
--   覆盖完整观测期且每天行数在同一量级 → 时间维度可用；
--   存在缺口、某天骤降或覆盖不全 → 先补齐或标注，再进入时延分析。
SELECT DATE(FROM_UNIXTIME(timestamps))  AS 日期,
       COUNT(*)                         AS 行数,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS 占比
FROM user_behavior
GROUP BY DATE(FROM_UNIXTIME(timestamps))
ORDER BY 日期;

-- ────────────────────────────────────────────────
-- 【检查 4】行为类型分布
-- ────────────────────────────────────────────────
SELECT behavior_type                            AS 行为,
       COUNT(*)                                 AS 行数,
       COUNT(DISTINCT user_id)                  AS 用户数,
       COUNT(DISTINCT item_id)                  AS 商品数,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS 行数占比
FROM user_behavior
GROUP BY behavior_type;

-- ────────────────────────────────────────────────
-- 【检查 5】基数与稀疏度
-- ────────────────────────────────────────────────
SELECT COUNT(DISTINCT user_id)                     AS 用户数,
       COUNT(DISTINCT item_id)                     AS 商品数,
       COUNT(DISTINCT category_id)                 AS 品类数,
       ROUND(COUNT(*) / COUNT(DISTINCT user_id), 2) AS 人均行为数,
       ROUND(COUNT(*) / COUNT(DISTINCT item_id), 2) AS 单商品平均交互数
FROM user_behavior;

-- ────────────────────────────────────────────────
-- 【检查 6】空值
-- ────────────────────────────────────────────────
SELECT SUM(user_id IS NULL)       AS user_id空值,
       SUM(item_id IS NULL)       AS item_id空值,
       SUM(category_id IS NULL)   AS category_id空值,
       SUM(behavior_type IS NULL) AS behavior_type空值,
       SUM(timestamps IS NULL)    AS timestamps空值
FROM user_behavior;

-- ────────────────────────────────────────────────
-- 【检查 7】完全重复行
-- ────────────────────────────────────────────────
-- 外层 SUM(cnt - 1) 是多出来的重复行数，COUNT(*) 是重复组合的种类数。
SELECT SUM(cnt - 1) AS 多余重复行数,
       COUNT(*)     AS 重复组合数
FROM (
    SELECT user_id,
           item_id,
           category_id,
           behavior_type,
           timestamps,
           COUNT(*) AS cnt
    FROM user_behavior
    GROUP BY user_id, item_id, category_id, behavior_type, timestamps
    HAVING COUNT(*) > 1
) t;

-- ────────────────────────────────────────────────
-- 【检查 8】加购行为的时间覆盖
-- ────────────────────────────────────────────────
-- 加购事件构造要用相邻加购的间隔。若加购集中在极短时间，
-- 30 分钟阈值可能把大量记录并成少数事件，阈值需重新评估。
SELECT COUNT(*)                                 AS 加购行数,
       COUNT(DISTINCT user_id)                  AS 加购用户数,
       COUNT(DISTINCT item_id)                  AS 加购商品数,
       FROM_UNIXTIME(MIN(timestamps))           AS 最早加购,
       FROM_UNIXTIME(MAX(timestamps))           AS 最晚加购,
       ROUND((MAX(timestamps) - MIN(timestamps)) / 3600, 2) AS 覆盖小时数
FROM user_behavior
WHERE behavior_type = 'cart';

-- ────────────────────────────────────────────────
-- 【检查 9】同一用户-商品对的加购次数分布
-- ────────────────────────────────────────────────
-- 极端最大值通常意味着刷单或异常重复，需在报告中说明。
SELECT MAX(cnt) AS 单对最大加购次数,
       ROUND(AVG(cnt), 2) AS 单对平均加购次数,
       SUM(cnt > 1) AS 多次加购的组合数
FROM (
    SELECT user_id,
           item_id,
           COUNT(*) AS cnt
    FROM user_behavior
    WHERE behavior_type = 'cart'
    GROUP BY user_id, item_id
) t;
