-- ============================================
-- 功能：建库建表
-- 板块：数据准备 › 数据获取
-- 依赖：无（本文件是整个项目的起点）
-- 状态：已完成
-- 更新：2026-09-27
-- 对应思维导图：数据清洗和预处理 › 数据获取
-- ============================================
--
-- 说明：原始数据表当初是用 MySQL Workbench 的「Table Data Import Wizard」
--       导入建好的，没有留下 SQL。这里补一份等价的可复现版本，
--       让别人 clone 下来也能把表重建出来。
--
--       字段与导入后的实际表一致（user_id / item_id / category_id /
--       behavior_type / timestamps），但**不含 `id`** ——
--       自增主键是后面去重时才加的，见 06_数据去重.sql。

-- ────────────────────────────────────────────────
-- ① 建库
-- ────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS taobao
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

USE taobao;

-- ────────────────────────────────────────────────
-- ② 建表
-- ────────────────────────────────────────────────
-- ⚠️ 这里【故意不用】 DROP TABLE IF EXISTS。
--    其余文件建结果表都带 DROP，是为了脚本能重复执行；
--    但 user_behavior 是唯一的源表，DROP 一下 100 万行就没了，
--    重跑这个文件等于清库。所以改用 CREATE TABLE IF NOT EXISTS，
--    已存在就跳过，绝不误删数据。
CREATE TABLE IF NOT EXISTS user_behavior (
    user_id       INT        DEFAULT NULL,
    item_id       INT        DEFAULT NULL,
    category_id   INT        DEFAULT NULL,
    behavior_type VARCHAR(5) DEFAULT NULL,
    timestamps    INT        DEFAULT NULL
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  ROW_FORMAT = Dynamic;

-- ────────────────────────────────────────────────
-- ③ 核对
-- ────────────────────────────────────────────────
DESC user_behavior;

-- 建表后应为 0 行，导入数据见 02_导入数据.sql
SELECT COUNT(1) AS 当前行数 FROM user_behavior;

-- ────────────────────────────────────────────────
-- 备注：字段类型怎么定的
-- ────────────────────────────────────────────────
-- user_id / item_id / category_id
--     淘宝 UserBehavior 数据集的三个 ID 都是正整数，量级在百万以内，
--     INT（上限 21 亿）足够，不必上 BIGINT。
--
-- timestamps
--     存的是 Unix 秒（如 1511539200 = 2017-11-24 16:00:00）。
--     2017 年的时间戳约 15 亿，INT 放得下；
--     换成 2038 年以后的数据就得改 BIGINT。
--
-- behavior_type
--     只有 pv / buy / cart / fav 四种取值，最长的 'cart' 也就 4 个字符，
--     VARCHAR(5) 刚好够。后续所有查询都按字符串比较，如 WHERE behavior_type = 'buy'。
--
-- ────────────────────────────────────────────────
-- 备注：这张表的最终形态
-- ────────────────────────────────────────────────
-- 本文件建出来的是【导入后、清洗前】的样子，只有 5 个字段。
-- 后面几个文件会依次把它改造成最终形态：
--     06_数据去重.sql          加 id（自增主键，且位于第一列）
--     07_增加日期时间字段.sql   加 datetimes / dates / times / hours
--     03_创建索引.sql          加 5 个单列索引
--
-- 全部跑完后，SHOW CREATE TABLE 应该长这样：
--     id            int NOT NULL AUTO_INCREMENT   PRIMARY KEY
--     user_id       int
--     item_id       int
--     category_id   int
--     behavior_type varchar(5)
--     timestamps    int
--     datetimes     timestamp
--     dates         char(10)
--     times         char(8)
--     hours         char(2)
--     索引：idx_user_id / idx_item_id / idx_category_id
--           / idx_behavior_type / idx_timestamps
--     引擎 InnoDB，字符集 utf8mb4，排序规则 utf8mb4_0900_ai_ci
--     清洗完成后的行数：999489
