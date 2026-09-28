-- ============================================
-- 功能：数据概览（清洗结果确认）
-- 板块：数据准备 › 数据准备
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理
-- ============================================

USE taobao;

DESC user_behavior;
SELECT * FROM user_behavior LIMIT 5;
SELECT COUNT(1) FROM user_behavior;   -- 剩余 999489 条
