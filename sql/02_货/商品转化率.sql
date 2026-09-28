-- ============================================
-- 功能：商品转化率
-- 板块：货
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：货 › 转化率
-- ============================================
--
-- 【转化率口径】
--     分子 = COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL))   买过的人
--     分母 = COUNT(DISTINCT user_id)                                    接触过的人
-- 即「接触过这个商品 / 品类的用户里，有多少最终买了」。
--
-- ⚠️ 前四列（pv / fav / cart / buy）存的是行为【次数】，最后一列是【人数】之比 ——
--    两种口径混在一张表里，读的时候别把它们当成同一种东西。
--
-- 产出两张结果表：
--     item_detail       每个商品的 pv/fav/cart/buy 与转化率
--     category_detail   每个品类的同上

USE taobao;

-- ────────────────────────────────────────────────
-- ① 商品转化率【小样本验证】
-- ────────────────────────────────────────────────
SELECT item_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy,
       COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) / COUNT(DISTINCT user_id) AS 商品转化率
FROM temp_behavior
GROUP BY item_id
ORDER BY 商品转化率 DESC;

-- ⚠️ 这个排序结果要小心读：转化率最高的往往不是最受欢迎的商品，
--    而是「只有一两个人看过、恰好买了」的长尾商品（1/1 = 100%）。
--    真要看转化好的商品，加一句 HAVING 卡掉样本量太小的：
--        HAVING pv >= 100
--    否则排在前面的大概率是噪声。

-- ────────────────────────────────────────────────
-- ② 商品结果表 +【全量执行】
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS item_detail;
CREATE TABLE item_detail (
    item_id       INT,
    pv            INT,
    fav           INT,
    cart          INT,
    buy           INT,
    user_buy_rate DECIMAL(8,6)   -- 转化率。用 DECIMAL 不用 FLOAT，避免二进制浮点误差
);

-- 这里的 ORDER BY 去掉了：INSERT 后面没有 LIMIT，排序不生效，白花开销
INSERT INTO item_detail
SELECT item_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)),
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)),
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)),
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)),
       COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) / COUNT(DISTINCT user_id)
FROM user_behavior
GROUP BY item_id;

-- 核对：只看有足够样本量的商品
SELECT *
FROM item_detail
WHERE pv >= 100
ORDER BY user_buy_rate DESC
LIMIT 20;

-- ────────────────────────────────────────────────
-- ③ 品类转化率【小样本验证】
-- ────────────────────────────────────────────────
SELECT category_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)) AS pv,
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)) AS fav,
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)) AS cart,
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)) AS buy,
       COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) / COUNT(DISTINCT user_id) AS 品类转化率
FROM temp_behavior
GROUP BY category_id
ORDER BY 品类转化率 DESC;

-- ────────────────────────────────────────────────
-- ④ 品类结果表 +【全量执行】
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS category_detail;
CREATE TABLE category_detail (
    category_id   INT,
    pv            INT,
    fav           INT,
    cart          INT,
    buy           INT,
    user_buy_rate DECIMAL(8,6)
);

INSERT INTO category_detail
SELECT category_id,
       COUNT(IF(behavior_type = 'pv',   behavior_type, NULL)),
       COUNT(IF(behavior_type = 'fav',  behavior_type, NULL)),
       COUNT(IF(behavior_type = 'cart', behavior_type, NULL)),
       COUNT(IF(behavior_type = 'buy',  behavior_type, NULL)),
       COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) / COUNT(DISTINCT user_id)
FROM user_behavior
GROUP BY category_id;

SELECT * FROM category_detail ORDER BY user_buy_rate DESC;
