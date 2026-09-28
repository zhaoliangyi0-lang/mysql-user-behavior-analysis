-- ============================================
-- 功能：剔除时间范围外的异常数据
-- 板块：数据准备 › 数据清洗
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 值 › 去异常
-- ============================================

USE taobao;

-- ① 先看数据的实际时间范围
SELECT MAX(datetimes), MIN(datetimes) FROM user_behavior;

-- ② 剔除范围外（数据集本身覆盖 2017-11-25 ~ 2017-12-03）
DELETE FROM user_behavior
WHERE datetimes < '2017-11-25 00:00:00'
   OR datetimes > '2017-12-03 23:59:59';
