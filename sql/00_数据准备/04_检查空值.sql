-- ============================================
-- 功能：检查残缺数据（空值）
-- 板块：数据准备 › 数据清洗
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 值 › 去空
-- ============================================

USE taobao;

-- 逐列统计 NULL 行数。表约 100 万行，各列均有索引，秒级返回。
SELECT COUNT(*) FROM user_behavior WHERE user_id       IS NULL;
SELECT COUNT(*) FROM user_behavior WHERE item_id       IS NULL;
SELECT COUNT(*) FROM user_behavior WHERE category_id   IS NULL;
SELECT COUNT(*) FROM user_behavior WHERE behavior_type IS NULL;
SELECT COUNT(*) FROM user_behavior WHERE timestamps    IS NULL;

-- 结论：无空值
