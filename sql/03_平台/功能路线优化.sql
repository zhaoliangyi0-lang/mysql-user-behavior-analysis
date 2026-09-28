-- ============================================
-- 功能：功能路线优化（转化漏斗与流失点定位）
-- 板块：平台 › 功能路线
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-27
-- 对应思维导图：平台 › 功能路线优化
-- ============================================
--
-- 思路：用户从「浏览」到「成交」要穿过一串功能节点。
--       运营上真正关心的不是每一环各有几个人，
--       而是【哪一环一次掉的人最多】—— 那一环就是下一步该改的地方。
--
--       所以这里把漏斗算成一张带「对上一步流失率」的表，
--       排序直接看流失，而不是看绝对人数。
--
-- 产出 funnel_conversion 表，每行一个漏斗环节。
--
-- ⚠️ 用到了 LAG / FIRST_VALUE 窗口函数，需要 MySQL 8.0 及以上。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 漏斗各步人数【小样本验证】
-- ────────────────────────────────────────────────
-- 三个 COUNT(DISTINCT ...) 一次扫表算完。
-- CASE 不匹配时返回 NULL，而 COUNT 会跳过 NULL，正好当条件计数用。
SELECT COUNT(DISTINCT CASE WHEN behavior_type = 'pv'           THEN user_id END) AS 浏览用户,
       COUNT(DISTINCT CASE WHEN behavior_type IN ('fav','cart') THEN user_id END) AS 收藏加购用户,
       COUNT(DISTINCT CASE WHEN behavior_type = 'buy'          THEN user_id END) AS 购买用户
FROM temp_behavior;

-- ────────────────────────────────────────────────
-- ② 把三个数整理成漏斗的「步」【全量执行】
-- ────────────────────────────────────────────────
-- 三次条件聚合来自同一张表，用 UNION ALL 拼成纵向的步骤表。
-- 缺点是要扫三遍全表，100 万行下是秒级，可以接受；
-- 如果表再大一个量级，就该换成一次落表再拆。
DROP TABLE IF EXISTS temp_funnel_step;
CREATE TABLE temp_funnel_step (
    step_no  INT,
    step     VARCHAR(20),
    user_num INT
);

INSERT INTO temp_funnel_step (step_no, step, user_num)
SELECT 1, '浏览', COUNT(DISTINCT user_id) FROM user_behavior WHERE behavior_type = 'pv'
UNION ALL
SELECT 2, '收藏或加购', COUNT(DISTINCT user_id) FROM user_behavior WHERE behavior_type IN ('fav', 'cart')
UNION ALL
SELECT 3, '购买', COUNT(DISTINCT user_id) FROM user_behavior WHERE behavior_type = 'buy';

-- ────────────────────────────────────────────────
-- ③ 算转化率与流失，落成结果表
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS funnel_conversion;
CREATE TABLE funnel_conversion (
    step_no    INT,
    step       VARCHAR(20),
    user_num   INT,
    step_rate  DECIMAL(6,2),   -- 相对上一步的转化率（%）
    total_rate DECIMAL(6,2),   -- 相对第一步的累计转化率（%）
    lost_num   INT             -- 相对上一步流失的人数
);

INSERT INTO funnel_conversion (step_no, step, user_num, step_rate, total_rate, lost_num)
SELECT step_no,
       step,
       user_num,
       ROUND(user_num * 100 / LAG(user_num)         OVER (ORDER BY step_no), 2),
       ROUND(user_num * 100 / FIRST_VALUE(user_num) OVER (ORDER BY step_no), 2),
       LAG(user_num) OVER (ORDER BY step_no) - user_num
FROM temp_funnel_step;

-- 第一步没有「上一步」，step_rate / lost_num 是 NULL，不是算错了
SELECT * FROM funnel_conversion ORDER BY step_no;

-- 哪一步流失最狠，一眼就能看出来
SELECT step,
       lost_num,
       step_rate
FROM funnel_conversion
WHERE lost_num IS NOT NULL
ORDER BY lost_num DESC
LIMIT 1;

-- ────────────────────────────────────────────────
-- ④ 下钻：类目维度上，哪些「加购了却不买」
-- ────────────────────────────────────────────────
-- 整体漏斗只能告诉你「掉了多少人」，定位不到具体位置。
-- 按类目切一刀，就能看出流量到底卡在哪些商品上。
--
-- HAVING 里的 100 是【经验阈值】，只为了滤掉长尾类目
-- （一个类目就两三个人加购，算出来的转化率没有统计意义）。
-- 换数据集要重新看分布再定，别照搬。
SELECT category_id,
       COUNT(DISTINCT CASE WHEN behavior_type = 'cart' THEN user_id END) AS 加购用户,
       COUNT(DISTINCT CASE WHEN behavior_type = 'buy'  THEN user_id END) AS 购买用户,
       ROUND(
           COUNT(DISTINCT CASE WHEN behavior_type = 'buy' THEN user_id END) * 100
           / COUNT(DISTINCT CASE WHEN behavior_type = 'cart' THEN user_id END)
       , 2) AS 加购购买转化率
FROM user_behavior
GROUP BY category_id
HAVING 加购用户 >= 100
ORDER BY 加购购买转化率 ASC
LIMIT 20;

-- ────────────────────────────────────────────────
-- 备注
-- ────────────────────────────────────────────────
-- 1. 「加购购买转化率」只是个【指示性指标】，不是严格的漏斗转化：
--    用户可能没加购就直接下单，这部分会做大分母、低估转化率。
--    要算严格口径得回到行为路径层面，见
--    01_人/03_行为情况/行为路径分析.sql。
--
-- 2. 【实测结果】流失最狠的是「收藏加购 → 购买」这一环：
--        浏览 → 收藏加购    掉 1241 人（12.78%）
--        收藏加购 → 购买    掉 1884 人（22.24%）  ← 最大
--    所以优化重点该放在「临门一脚」：优惠券、限时折扣、运费提示这类促成交手段，
--    而不是商品卡片吸引力 —— 后者只影响已经进店的那批人。
--
-- 3. ⚠️ 这组漏斗数字【不能当真实业务结论】用。
--    浏览用户的累计购买转化率高达 67.83%，真实电商通常只有 1% ~ 5%，
--    差了整整一个数量级。原因在抽样方式：
--    这份数据取的是原始 CSV 的【前 100 万行】，不是随机抽样 ——
--    头部用户的记录特别密集，被整段取了进来，
--    所以剩下这 9768 个全是重度活跃用户，天然高转化。
--    要拿真实转化率，得先做随机抽样，不能直接 LIMIT N 行。
