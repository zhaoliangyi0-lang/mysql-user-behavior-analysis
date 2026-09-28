-- ============================================
-- 功能：页面浏览量（PageView）
-- 板块：人 › 获客情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 获客情况 › 页面浏览量（PageView）
-- ============================================
--
-- PV 不去重：每一条 behavior_type = 'pv' 的记录都算 1 次浏览。

USE taobao;

-- 【小样本验证】基于沙箱表（10 万行），秒级出结果
SELECT dates,
       COUNT(*) AS pv
FROM temp_behavior
WHERE behavior_type = 'pv'
GROUP BY dates
ORDER BY dates;

-- 【全量执行】语法验证通过后，对真实表跑
SELECT dates,
       COUNT(*) AS pv
FROM user_behavior
WHERE behavior_type = 'pv'
GROUP BY dates
ORDER BY dates;
