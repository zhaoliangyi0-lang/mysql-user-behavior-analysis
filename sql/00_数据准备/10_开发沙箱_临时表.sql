-- ============================================
-- 功能：开发沙箱（10 万行临时表）
-- 板块：数据准备 › 开发环境
-- 依赖：taobao.user_behavior
-- 状态：已完成
-- 更新：2026-09-20
-- ============================================
--
-- 用途：全表 100 万行跑一次 GROUP BY 要数十秒，调 SQL 时反复执行代价太大。
--       先把 10 万行复制到临时表，语法和结果在秒级验证通过，再对全表执行。
--       01_人 / 02_货 / 03_平台 下的分析文件都以它为调试底座。

USE taobao;

-- ① 重建沙箱表
--    CREATE TABLE ... LIKE 只复制表结构（字段 + 索引 + 主键），不复制数据。
--
--    DROP 这一步不能省：沙箱表会被反复重建，若旧表残留着上次的数据，
--    下面的 INSERT 会在第一行就撞上主键，报
--    Error 1062 Duplicate entry '1' for key 'temp_behavior.PRIMARY'
DROP TABLE IF EXISTS temp_behavior;
CREATE TABLE temp_behavior LIKE user_behavior;

-- ② 灌入前 10 万行作为样本
--    没有 ORDER BY，取哪 10 万行由存储引擎决定（通常是按主键顺序），
--    但对"缩小规模调语法"这个目的没有影响。
INSERT INTO temp_behavior
SELECT * FROM user_behavior
LIMIT 100000;

-- ③ 核对沙箱
SELECT COUNT(*) AS rows_in_sandbox FROM temp_behavior;   -- 期望 100000
SELECT * FROM temp_behavior LIMIT 5;
