-- ============================================
-- 功能：检查重复值
-- 板块：数据准备 › 数据清洗
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 值 › 去重
-- ============================================

USE taobao;

-- 按 (user_id, item_id, timestamps) 分组，找出出现一次以上的组合
SELECT user_id, item_id, timestamps FROM user_behavior
GROUP BY user_id, item_id, timestamps
HAVING COUNT(*) > 1;
