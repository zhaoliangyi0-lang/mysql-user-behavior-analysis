-- ============================================
-- 功能：推荐系统（基于物品的协同过滤）
-- 板块：平台 › 推荐系统
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-27
-- 对应思维导图：平台 › 推荐系统的构建与完善
-- ============================================
--
-- 思路：纯 SQL 就能实现的 Item-CF（基于物品的协同过滤）——
--       不依赖任何模型训练，核心只有一句话：
--       【被同一批用户反复一起交互的商品，就是相似的】。
--
--       做法是先统计商品两两之间共同被多少用户碰过（共现），
--       再把共现次数最高的几个商品，作为每个商品的推荐位。
--
--       这是电商「看了又看」「买了又买」栏目的最朴素实现，
--       能跑通之后再谈矩阵分解、向量召回。
--
-- 产出 item_similarity（商品共现）和 recommend_result（TopN 推荐）两张表。
--
-- ⚠️ 中间那步自连接是本文件最重的地方，务必先在沙箱上跑通再上全量，
--    具体见下面 ③ 的警告。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 先看用户-商品交互有多密【小样本验证】
-- ────────────────────────────────────────────────
SELECT user_id,
       COUNT(DISTINCT item_id) AS 交互商品数
FROM temp_behavior
GROUP BY user_id
ORDER BY 交互商品数 DESC
LIMIT 10;

-- ────────────────────────────────────────────────
-- ② 整理出「用户-商品」交互表
-- ────────────────────────────────────────────────
-- ⚠️ 这步的 DISTINCT 是必须的，不是优化。
--    原始表里同一用户对同一商品可能有几十条记录（反复浏览），
--    不去重的话，下面自连接产生的商品对数量会以平方级膨胀，
--    跑不完还占满磁盘。
--
--    这里把 fav / cart / buy 都算作「交互」而不是只用 buy：
--    采购数据太稀疏了，只用 buy 建出来的共现矩阵大部分是空的。
DROP TABLE IF EXISTS temp_user_item;
CREATE TABLE temp_user_item (
    user_id INT,
    item_id INT,
    KEY idx_user (user_id),
    KEY idx_item (item_id)
);

INSERT INTO temp_user_item (user_id, item_id)
SELECT DISTINCT user_id, item_id
FROM user_behavior
WHERE behavior_type IN ('fav', 'cart', 'buy');

SELECT COUNT(1) AS 交互记录数 FROM temp_user_item;

-- ────────────────────────────────────────────────
-- ③ 商品两两共现【全量执行】
-- ────────────────────────────────────────────────
-- 自连接要点：
--     a.item_id < b.item_id  只取上三角，一次拿到「A 和 B」这一对，
--                            既排除了自己配自己，也排除了 (B,A) 的重复
--     COUNT(DISTINCT a.user_id)  共同交互过这一对商品的【人数】
--
-- 【实测规模】本项目这 100 万行下去重后只有 94191 条交互、9183 个用户，
--    平均每人 10.3 个商品（最多 167 个），商品对总数约 99 万行，跑完 21 秒。
--    用不着任何优化。
--
--    但要留个心眼：商品对数量是 sum(n*(n-1)/2)，随「每人交互商品数」【平方】增长。
--    换一份更稠密的数据集，行数会迅速失控。上全量前先跑这句估算：
--        SELECT SUM(n*(n-1)/2) FROM (
--            SELECT user_id, COUNT(DISTINCT item_id) n FROM user_behavior
--            WHERE behavior_type IN ('fav','cart','buy') GROUP BY user_id) x;
DROP TABLE IF EXISTS item_similarity;
CREATE TABLE item_similarity (
    item_a INT,
    item_b INT,
    co_num INT,          -- 共同交互的用户数，越大越相似
    KEY idx_a (item_a)
);

INSERT INTO item_similarity (item_a, item_b, co_num)
SELECT a.item_id,
       b.item_id,
       COUNT(DISTINCT a.user_id)
FROM temp_user_item a
JOIN temp_user_item b
    ON  a.user_id = b.user_id
    AND a.item_id < b.item_id
GROUP BY a.item_id, b.item_id;

SELECT COUNT(1) AS 商品对数 FROM item_similarity;

-- ────────────────────────────────────────────────
-- ④ 每个商品取 TopN 相似商品
-- ────────────────────────────────────────────────
-- 共现表是有方向的（只存了 a < b 的那一侧），
-- 所以要把两个方向都展开，保证每个商品都有完整的推荐位：
--     a → b   正向
--     b → a   反向
--
-- ⚠️ WHERE co_num >= 2 这个门槛不是可有可无的，是【先跑一遍才发现必须加】的：
--    不加门槛时，实测推荐结果里绝大多数 co_num = 1，
--    也就是"这两个商品只有一个人同时看过"—— 跟随机撞上没区别。
--    原因看 co_num 分布就明白了：
--        co_num = 1   992491 对   占 99.94%
--        co_num = 2      546 对
--        co_num = 3       21 对
--        co_num >= 4       1 对
--    门槛提到 2 之后只剩 568 对、覆盖 463 个商品。
--    换句话说：这个数据集对 Item-CF 来说【太稀疏了】，见末尾备注。
DROP TABLE IF EXISTS recommend_result;
CREATE TABLE recommend_result (
    item_id  INT,        -- 被推荐的商品（用户正在看的那个）
    rank_no  INT,        -- 推荐位序号，1 最相似
    rec_item INT,        -- 推荐出来的商品
    co_num   INT
);

INSERT INTO recommend_result (item_id, rank_no, rec_item, co_num)
SELECT item_id,
       rank_no,
       rec_item,
       co_num
FROM
(
    SELECT item_id,
           co_num,
           rec_item,
           ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY co_num DESC) AS rank_no
    FROM
    (
        SELECT item_a AS item_id, item_b AS rec_item, co_num FROM item_similarity WHERE co_num >= 2
        UNION ALL
        SELECT item_b AS item_id, item_a AS rec_item, co_num FROM item_similarity WHERE co_num >= 2
    ) both_ways
) ranked
WHERE rank_no <= 10;

SELECT COUNT(1) AS 推荐条目数 FROM recommend_result;

-- 挑一个商品看看它被推了些什么
SELECT *
FROM recommend_result
WHERE item_id = (SELECT item_a FROM item_similarity ORDER BY co_num DESC LIMIT 1)
ORDER BY rank_no;

-- ────────────────────────────────────────────────
-- 备注：跑完之后才知道的事 —— 这个方案在本数据集上不成立
-- ────────────────────────────────────────────────
-- 代码是能跑的，21 秒出结果，SQL 本身没写错。
-- 但【结论是：这份数据太稀疏，撑不起 Item-CF】。
--
-- 实测数字：
--     商品总数          68788
--     商品对总数        993059
--     其中 co_num = 1   992491（99.94%）
--     加门槛 >= 2 后     568 对，覆盖 463 个商品（占全部商品的 0.67%）
--
-- 为什么这么惨：9183 个用户分摊到 68788 个商品上，平均每人只碰过 10.3 个。
-- 两个商品要"有人同时看过"，本来就是小概率事件；
-- 样本再一分散，几乎所有共现都只出现一次 —— 那是噪声，不是相似度。
--
-- 所以真正该做的是【先解决稀疏性】，而不是调 SQL：
--     1. 换更粗的粒度 —— 用 category_id 代替 item_id 做共现。
--        数据集里 category 只有几千个，共现密度会高得多，
--        虽然损失了个体精度，但至少能出有统计意义的关联。
--     2. 换数据量 —— 用原始的 9100 万行全量跑，而不是抽样的 100 万行。
--        交互数涨 90 倍，共现（平方级）会涨得更多。
--     3. 换模型 —— 矩阵分解 / 向量召回本来就是为了对付稀疏而生，
--        但那已经不是纯 SQL 能做的了，得上 Python。
--
-- 至于 Item-CF 本身固有的三个毛病（这份数据稠密起来之后也会遇到）：
--     冷启动 —— 新商品没有共现记录，进不了推荐池
--     热门偏置 —— 爆款跟谁都共现，会占满推荐位（补救：除以流行度，即余弦相似度）
--     千人一面 —— 这是「看过这个的人还看了」，不是「为你推荐」
