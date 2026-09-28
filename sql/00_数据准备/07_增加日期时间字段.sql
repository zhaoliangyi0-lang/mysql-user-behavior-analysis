-- ============================================
-- 功能：增加日期 / 时间 / 小时段字段
-- 板块：数据准备 › 数据清洗
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 按需求增减
-- ============================================

USE taobao;

-- ① 时间戳 → 可读日期时间（timestamps 存的是 Unix 秒数）
ALTER TABLE user_behavior add datetimes TIMESTAMP(0);
UPDATE user_behavior SET datetimes = FROM_UNIXTIME(timestamps);

-- ② 拆出日期 / 时间 / 小时，供后续「周内行为」「日内行为」分析使用
ALTER TABLE user_behavior add dates CHAR(10);
ALTER TABLE user_behavior add times CHAR(8);
ALTER TABLE user_behavior add hours CHAR(2);

UPDATE user_behavior SET dates = substring(datetimes, 1, 10);   -- 2017-12-02
UPDATE user_behavior SET times = substring(datetimes, 12, 8);   -- 23:03:08
UPDATE user_behavior SET hours = substring(datetimes, 12, 2);   -- 23

SELECT * FROM user_behavior LIMIT 5;
