-- ============================================
-- 功能：留存率
-- 板块：人 › 留存情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 留存情况 › 留存率
-- ============================================
--
-- 次日留存率 = 当天活跃的用户里，第二天仍然活跃的比例。
--
-- 做法：把「用户 × 日期」去重后自己跟自己自关联，
--       用 DATEDIFF 判断两个日期差几天。
--       DATEDIFF(晚, 早) = 1 → 次日留存，改成 7 / 30 就是 7 日 / 30 日留存。

USE taobao;

-- ────────────────────────────────────────────────
-- 第 0 步：搭出「用户 × 日期」的去重底座
-- ────────────────────────────────────────────────
-- 同一用户一天内会有多条行为记录（浏览、加购、收藏…），
-- 但留存只看「这天来没来」，所以先按 user_id + dates 去重。
SELECT user_id, dates
FROM temp_behavior
WHERE dates IS NOT NULL
GROUP BY user_id, dates
ORDER BY user_id, dates;

-- 下一步是把这个底座跟它自己连起来。
-- 只写 `WHERE a.user_id = b.user_id` 会得到笛卡尔积
-- （同一用户的所有日期两两组合，包括"自己连自己"），
-- 所以下面才对日期加约束，把范围收窄到「b 不早于 a」。

-- ────────────────────────────────────────────────
-- ① 留存数（多口径：当天 / 次日 / 3 日后）
-- ────────────────────────────────────────────────
-- a.dates <= b.dates 是分母能算出来的关键：
-- 用 <= 而不是 <，把「同一天」也留在连接结果里，
-- 于是 retention_0 就是当天自己的那一行，天然充当分母。
--
-- 注意 DATEDIFF 的参数顺序是「后减前」：DATEDIFF(b.dates, a.dates) 为正，表示 b 在 a 之后。
SELECT a.dates,
       COUNT(IF(DATEDIFF(b.dates, a.dates) = 0, b.user_id, NULL)) AS retention_0,  -- 当天
       COUNT(IF(DATEDIFF(b.dates, a.dates) = 1, b.user_id, NULL)) AS retention_1,  -- 次日
       COUNT(IF(DATEDIFF(b.dates, a.dates) = 3, b.user_id, NULL)) AS retention_3   -- 3 日后
FROM (SELECT user_id, dates FROM temp_behavior GROUP BY user_id, dates) a,
     (SELECT user_id, dates FROM temp_behavior GROUP BY user_id, dates) b
WHERE a.user_id = b.user_id
  AND a.dates <= b.dates
  AND a.dates IS NOT NULL
GROUP BY a.dates
ORDER BY a.dates;
-- 注：数据集最后一天（2017-12-03）的 retention_1 必然为 0，
--     因为它的「次日」没有数据，是截断造成的假象，不是真的没人留存。

-- ────────────────────────────────────────────────
-- ② 次日留存率 = retention_1 / retention_0
-- ────────────────────────────────────────────────
SELECT a.dates,
       COUNT(IF(DATEDIFF(b.dates, a.dates) = 1, b.user_id, NULL)) AS 留存用户数,
       COUNT(IF(DATEDIFF(b.dates, a.dates) = 0, b.user_id, NULL)) AS 当日用户数,
       ROUND(
           COUNT(IF(DATEDIFF(b.dates, a.dates) = 1, b.user_id, NULL))
         / COUNT(IF(DATEDIFF(b.dates, a.dates) = 0, b.user_id, NULL))
       , 4) AS 次日留存率
FROM (SELECT user_id, dates FROM temp_behavior GROUP BY user_id, dates) a,
     (SELECT user_id, dates FROM temp_behavior GROUP BY user_id, dates) b
WHERE a.user_id = b.user_id
  AND a.dates <= b.dates
  AND a.dates IS NOT NULL
  AND a.dates < '2017-12-03'   -- 最后一天没有「次日」，排除掉
GROUP BY a.dates
ORDER BY a.dates;

-- ────────────────────────────────────────────────
-- ③【全量执行】对真实表跑，结果写入 retention_rate
-- ────────────────────────────────────────────────
-- 留存率写 DECIMAL 而不是 FLOAT：FLOAT 是二进制近似值，
-- 0.1234 存进去可能变成 0.12339999…，后续做图或二次计算会冒出 0.12340001 这种噪声。
DROP TABLE IF EXISTS retention_rate;
CREATE TABLE retention_rate (
    dates       CHAR(10),        -- 日期，如 2017-12-02
    retention_1 DECIMAL(6,4)     -- 次日留存率，取值 0.0000 ~ 1.0000
);

INSERT INTO retention_rate
SELECT a.dates,
       ROUND(
           COUNT(IF(DATEDIFF(b.dates, a.dates) = 1, b.user_id, NULL))
         / COUNT(IF(DATEDIFF(b.dates, a.dates) = 0, b.user_id, NULL))
       , 4)
FROM (SELECT user_id, dates FROM user_behavior GROUP BY user_id, dates) a,
     (SELECT user_id, dates FROM user_behavior GROUP BY user_id, dates) b
WHERE a.user_id = b.user_id
  AND a.dates <= b.dates
  AND a.dates IS NOT NULL
  AND a.dates < '2017-12-03'
GROUP BY a.dates;

-- ④ 核对结果
SELECT * FROM retention_rate ORDER BY dates;
