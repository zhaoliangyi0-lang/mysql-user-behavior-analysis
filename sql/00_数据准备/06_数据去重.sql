-- ============================================
-- 功能：数据去重
-- 板块：数据准备 › 数据清洗
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 值 › 去重
-- ============================================

USE taobao;

-- ① 加自增主键：给每一行一个唯一编号，作为去重时"留哪行删哪行"的依据
ALTER TABLE taobao.user_behavior ADD id INT FIRST;
SELECT * FROM user_behavior LIMIT 5;
ALTER TABLE user_behavior MODIFY id INT PRIMARY KEY auto_increment;

-- ② 每个重复组只保留 id 最小的一行
--    子查询先取出每组的 min(id)，外层删掉同组中 id 更大的行
DELETE user_behavior FROM
user_behavior,
(
SELECT user_id, item_id, timestamps, min(id) id FROM user_behavior
GROUP BY user_id, item_id, timestamps
HAVING COUNT(*) > 1
) t2
WHERE user_behavior.user_id  = t2.user_id
AND   user_behavior.item_id  = t2.item_id
AND   user_behavior.timestamps = t2.timestamps
AND   user_behavior.id > t2.id;
