-- ============================================
-- 功能：RFM 模型（用户价值分层）
-- 板块：人 › 用户定位
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 用户定位 › RFM模型
-- ============================================
--
-- 三个维度的本意：
--     R（Recency）   最近一次消费  →  MAX(dates)
--     F（Frequency） 消费频率      →  COUNT(*) 购买次数
--     M（Monetary）  消费金额      →  ⚠️ 本数据集没有价格 / 金额字段，M 维度做不了
--
-- 所以这里只做 R、F 两维，用「是否高于各自的平均值」把用户切成四类。
-- 产出 rfm_model 表，每行一个「有过购买行为」的用户。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 探索：最近购买时间 / 购买次数【小样本验证】
-- ────────────────────────────────────────────────
SELECT user_id,
       MAX(dates) AS 最近购买时间
FROM temp_behavior
WHERE behavior_type = 'buy'
GROUP BY user_id
ORDER BY 2 DESC;

SELECT user_id,
       COUNT(user_id) AS 购买次数
FROM temp_behavior
WHERE behavior_type = 'buy'
GROUP BY user_id
ORDER BY 2 DESC;

-- ────────────────────────────────────────────────
-- ② 结果表 +【全量执行】
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS rfm_model;
CREATE TABLE rfm_model (
    user_id   INT,
    frequency INT,        -- F：购买次数
    recent    CHAR(10)    -- R：最近一次购买日期
);

-- ORDER BY 去掉了：INSERT 后面没有 LIMIT，排序不生效，只是白花开销
INSERT INTO rfm_model (user_id, frequency, recent)
SELECT user_id,
       COUNT(user_id),
       MAX(dates)
FROM user_behavior
WHERE behavior_type = 'buy'
GROUP BY user_id;

SELECT COUNT(*) AS 用户数 FROM rfm_model;

-- ────────────────────────────────────────────────
-- ③ F 分：按购买次数分档
-- ────────────────────────────────────────────────
ALTER TABLE rfm_model ADD COLUMN fscore INT;

-- ⚠️ 这套阈值有实测问题：100~262 和 50~99 两档【一个人都没有】。
--    实际购买次数：10 万行沙箱最大 32，全量最大 67，都够不到 50。
--    结果是约 80% 的用户全挤在 1 分，F 维度基本失去区分度。
--    跑完那句 SELECT 看一眼分布，再按文件末尾的备注重定阈值。
UPDATE rfm_model
SET fscore = CASE
    WHEN frequency BETWEEN 100 AND 262 THEN 5
    WHEN frequency BETWEEN 50  AND 99  THEN 4
    WHEN frequency BETWEEN 20  AND 49  THEN 3
    WHEN frequency BETWEEN 5   AND 20  THEN 2
    ELSE 1
END;

SELECT fscore, COUNT(*) AS 人数
FROM rfm_model
GROUP BY fscore
ORDER BY fscore DESC;

-- ────────────────────────────────────────────────
-- ④ R 分：按最近购买日期分档（越近分越高）
-- ────────────────────────────────────────────────
ALTER TABLE rfm_model ADD COLUMN rscore INT;

UPDATE rfm_model
SET rscore = CASE
    WHEN recent = '2017-12-03' THEN 5
    WHEN recent IN ('2017-12-01', '2017-12-02') THEN 4
    WHEN recent IN ('2017-11-29', '2017-11-30') THEN 3
    WHEN recent IN ('2017-11-27', '2017-11-28') THEN 2
    ELSE 1
END;

-- 覆盖检查：数据只覆盖 2017-11-25 ~ 2017-12-03 共 9 天，上面五档正好铺满
SELECT rscore, COUNT(*) AS 人数
FROM rfm_model
GROUP BY rscore
ORDER BY rscore DESC;

-- ────────────────────────────────────────────────
-- ⑤ 分层：F 分、R 分各自与平均值比较
-- ────────────────────────────────────────────────
-- ⚠️ @f_avg / @r_avg 是【会话变量】，只活在当前这条连接里。
--    从下面 SET 到最后那句 UPDATE 必须【连着一次跑完】。
--    换个标签页（新连接）单独跑 UPDATE，变量是 NULL，
--    fscore > NULL 的结果还是 NULL，四个分支全不匹配，class 会全部变空 —— 而且不报错。
SET @f_avg = NULL;
SET @r_avg = NULL;
SELECT AVG(fscore) INTO @f_avg FROM rfm_model;
SELECT AVG(rscore) INTO @r_avg FROM rfm_model;

SELECT *,
       CASE
           WHEN fscore > @f_avg AND rscore > @r_avg THEN '价值用户'
           WHEN fscore > @f_avg AND rscore < @r_avg THEN '保持用户'
           WHEN fscore < @f_avg AND rscore > @r_avg THEN '发展用户'
           WHEN fscore < @f_avg AND rscore < @r_avg THEN '挽留用户'
           ELSE '一般用户'
       END AS class
FROM rfm_model;

-- 落库
ALTER TABLE rfm_model ADD COLUMN class VARCHAR(40);

UPDATE rfm_model
SET class = CASE
    WHEN fscore > @f_avg AND rscore > @r_avg THEN '价值用户'
    WHEN fscore > @f_avg AND rscore < @r_avg THEN '保持用户'
    WHEN fscore < @f_avg AND rscore > @r_avg THEN '发展用户'
    WHEN fscore < @f_avg AND rscore < @r_avg THEN '挽留用户'
    ELSE '一般用户'
END;

-- ────────────────────────────────────────────────
-- ⑥ 核对
-- ────────────────────────────────────────────────
SELECT class, COUNT(user_id) AS 人数
FROM rfm_model
GROUP BY class
ORDER BY 人数 DESC;

-- ────────────────────────────────────────────────
-- 备注：F 分阈值怎么重定
-- ────────────────────────────────────────────────
-- 先看实际分布：
--     SELECT frequency, COUNT(*) FROM rfm_model GROUP BY frequency ORDER BY frequency DESC;
--
-- 购买次数是典型的【长尾分布】—— 大多数人只买一两次，
-- 所以按"最大值的百分比"切档注定有几档是空的。两个可行的方向：
--
-- 方向 A：按分位数切（保证每档人数相当，RFM 的标准做法）
--     用 NTILE(5) OVER (ORDER BY frequency) 自动分成五档。
--
-- 方向 B：按业务含义切，例如
--     WHEN frequency >= 6 THEN 5
--     WHEN frequency >= 4 THEN 4
--     WHEN frequency >= 3 THEN 3
--     WHEN frequency =  2 THEN 2
--     ELSE 1
--   （这组是按 10 万行沙箱的分布定的，换成全量数据要重新看分布再定）
