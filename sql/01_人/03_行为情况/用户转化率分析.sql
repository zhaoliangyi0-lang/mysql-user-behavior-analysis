-- ============================================
-- 功能：用户转化率分析
-- 板块：人 › 行为情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 行为情况 › 用户转化率分析
-- ============================================
--
-- 产出两张结果表：
--     behavior_user_num  各类行为的「去重用户数」→ 算用户维度的转化率
--     behavior_num       各类行为的「总次数」    → 算行为维度的转化率
-- 两个口径不通用：前者回答"多少人做过"，后者回答"做了多少次"。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 各类行为的去重用户数
-- ────────────────────────────────────────────────
-- 小样本验证
SELECT behavior_type,
       COUNT(DISTINCT user_id) AS user_num
FROM temp_behavior
GROUP BY behavior_type
ORDER BY behavior_type DESC;

-- 结果表 + 全量执行
DROP TABLE IF EXISTS behavior_user_num;
CREATE TABLE behavior_user_num (
    behavior_type VARCHAR(5),   -- pv / cart / fav / buy
    user_num      INT           -- 做过该行为的去重用户数
);

INSERT INTO behavior_user_num
SELECT behavior_type,
       COUNT(DISTINCT user_id)
FROM user_behavior
GROUP BY behavior_type;

-- ────────────────────────────────────────────────
-- ② 各类行为的总次数（不去重）
-- ────────────────────────────────────────────────
SELECT behavior_type,
       COUNT(*) AS behavior_count
FROM temp_behavior
GROUP BY behavior_type
ORDER BY behavior_type DESC;

DROP TABLE IF EXISTS behavior_num;
CREATE TABLE behavior_num (
    behavior_type  VARCHAR(5),
    behavior_count INT
);

INSERT INTO behavior_num
SELECT behavior_type,
       COUNT(*)
FROM user_behavior
GROUP BY behavior_type;

-- ────────────────────────────────────────────────
-- ③ 转化率（从结果表动态计算）
-- ────────────────────────────────────────────────
-- 这一步替代了原来手抄数字的做法（`SELECT 6589 / 9714`）。
-- 硬编码的分子分母，数据一变就全错，而且看不出数字是哪来的。
-- 从结果表读数，既有出处，又能跟着数据自动更新。

-- 用户维度：购买用户 / 浏览用户
SELECT
    MAX(IF(behavior_type = 'pv',  user_num, NULL)) AS 浏览用户数,
    MAX(IF(behavior_type = 'buy', user_num, NULL)) AS 购买用户数,
    ROUND(
        MAX(IF(behavior_type = 'buy', user_num, NULL))
      / MAX(IF(behavior_type = 'pv',  user_num, NULL))
    , 4) AS 用户购买转化率
FROM behavior_user_num;

-- 行为维度：购买次数 / 浏览次数
SELECT
    MAX(IF(behavior_type = 'pv',  behavior_count, NULL)) AS 浏览次数,
    MAX(IF(behavior_type = 'buy', behavior_count, NULL)) AS 购买次数,
    ROUND(
        MAX(IF(behavior_type = 'buy', behavior_count, NULL))
      / MAX(IF(behavior_type = 'pv',  behavior_count, NULL))
    , 4) AS 行为购买转化率
FROM behavior_num;

-- 收藏 + 加购 相对浏览的比例（"有意向"的占比）
SELECT ROUND(
    (MAX(IF(behavior_type = 'fav',  behavior_count, NULL))
   + MAX(IF(behavior_type = 'cart', behavior_count, NULL)))
  / MAX(IF(behavior_type = 'pv',     behavior_count, NULL))
, 4) AS 收藏加购占比
FROM behavior_num;

-- ────────────────────────────────────────────────
-- ④ 手工验算记录（当初的原始结果，用于核对上面动态计算的输出）
-- ────────────────────────────────────────────────
-- 购买用户数 6589 / 浏览用户数 9714          → 用户购买转化率
-- 购买次数 19340 / 浏览次数 897283          → 行为购买转化率
-- (收藏 27319 + 加购 55547) / 浏览次数 897283 → 收藏加购占比
