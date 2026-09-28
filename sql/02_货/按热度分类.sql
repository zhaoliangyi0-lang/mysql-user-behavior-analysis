-- ============================================
-- 功能：商品按热度分类
-- 板块：货
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：货 › 按热度分类
-- ============================================
--
-- 热度统一用「浏览量」衡量 = pv 行为的记录条数。
-- 产出三张结果表：
--     popular_categories    浏览量 TOP10 的品类
--     popular_items         浏览量 TOP10 的商品
--     popular_cateitems     每个品类里浏览量最高的那件商品（再取 TOP10）

USE taobao;

-- ────────────────────────────────────────────────
-- ① 热门品类 TOP 10【小样本验证】
-- ────────────────────────────────────────────────
SELECT category_id,
       COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) AS 品类浏览量
FROM temp_behavior
GROUP BY category_id
ORDER BY 2 DESC
LIMIT 10;

-- ────────────────────────────────────────────────
-- ② 热门商品 TOP 10【小样本验证】
-- ────────────────────────────────────────────────
SELECT item_id,
       COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) AS 商品浏览量
FROM temp_behavior
GROUP BY item_id
ORDER BY 2 DESC
LIMIT 10;

-- ────────────────────────────────────────────────
-- ③ 每个品类里的头号商品【小样本验证】
-- ────────────────────────────────────────────────
-- RANK() 按品类分区，给品类内部的商品按浏览量排名，r = 1 就是该品类的第一名。
-- 窗口函数里要写完整的聚合表达式，不能引用别名 —— 那时别名还没算出来。
SELECT category_id,
       item_id,
       品类商品浏览量
FROM (
    SELECT category_id,
           item_id,
           COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) AS 品类商品浏览量,
           RANK() OVER (
               PARTITION BY category_id
               ORDER BY COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) DESC
           ) AS r
    FROM temp_behavior
    GROUP BY category_id, item_id
) a
WHERE a.r = 1
ORDER BY a.品类商品浏览量 DESC
LIMIT 10;

-- ════════════════════════════════════════════════
-- 结果表
-- ════════════════════════════════════════════════
DROP TABLE IF EXISTS popular_categories;
CREATE TABLE popular_categories (
    category_id INT,
    pv          INT
);

DROP TABLE IF EXISTS popular_items;
CREATE TABLE popular_items (
    item_id INT,
    pv      INT
);

DROP TABLE IF EXISTS popular_cateitems;
CREATE TABLE popular_cateitems (
    category_id INT,
    item_id     INT,
    pv          INT
);

-- ════════════════════════════════════════════════
-- ④【全量执行】对真实表跑
-- ════════════════════════════════════════════════
-- 这里的 ORDER BY 不能删：后面跟着 LIMIT 10，
-- 要「取前 10 名」就得先排出顺序，才知道截哪 10 行。
-- （没有 LIMIT 的 ORDER BY 在 INSERT 里才是白写的）
INSERT INTO popular_categories
SELECT category_id,
       COUNT(IF(behavior_type = 'pv', behavior_type, NULL))
FROM user_behavior
GROUP BY category_id
ORDER BY 2 DESC
LIMIT 10;

INSERT INTO popular_items
SELECT item_id,
       COUNT(IF(behavior_type = 'pv', behavior_type, NULL))
FROM user_behavior
GROUP BY item_id
ORDER BY 2 DESC
LIMIT 10;

INSERT INTO popular_cateitems
SELECT category_id,
       item_id,
       品类商品浏览量
FROM (
    SELECT category_id,
           item_id,
           COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) AS 品类商品浏览量,
           RANK() OVER (
               PARTITION BY category_id
               ORDER BY COUNT(IF(behavior_type = 'pv', behavior_type, NULL)) DESC
           ) AS r
    FROM user_behavior
    GROUP BY category_id, item_id
) a
WHERE a.r = 1
ORDER BY a.品类商品浏览量 DESC
LIMIT 10;

-- ════════════════════════════════════════════════
-- ⑤ 核对结果
-- ════════════════════════════════════════════════
SELECT * FROM popular_categories;
SELECT * FROM popular_items;
SELECT * FROM popular_cateitems;
