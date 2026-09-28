-- ============================================
-- 功能：独立访客数（Unique Visitor）
-- 板块：人 › 获客情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 获客情况 › 独立访客数（Unique Visitor）
-- ============================================
--
-- UV 去重：同一天里同一个 user_id 无论浏览多少次，都只算 1 个访客。
-- COUNT(DISTINCT user_id) 要比对去重，比 COUNT(*) 慢，
-- 但表上有 idx_user_id 索引可以支撑。

USE taobao;

-- 【小样本验证】基于沙箱表（10 万行），秒级出结果
SELECT dates,
       COUNT(DISTINCT user_id) AS uv
FROM temp_behavior
WHERE behavior_type = 'pv'
GROUP BY dates
ORDER BY dates;

-- 【全量执行】语法验证通过后，对真实表跑
SELECT dates,
       COUNT(DISTINCT user_id) AS uv
FROM user_behavior
WHERE behavior_type = 'pv'
GROUP BY dates
ORDER BY dates;
