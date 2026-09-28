-- ============================================
-- 功能：付费 / 非付费用户对比
-- 板块：人 › 用户定位
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-27
-- 对应思维导图：人 › 用户定位 › 付费与非付费
-- ============================================
--
-- 口径：整段观察期内有过 buy 行为的算【付费用户】，其余算【非付费用户】。
--       注意这是「是否转化过」的二值切分，和 RFM 的「价值高低」是两回事，
--       两份结果可以交叉着看：RFM 里的高价值用户一定在付费组里，
--       但付费组里也大量是只买过一次的低频用户。
--
-- 产出 user_pay_split 表，每行一个用户。

USE taobao;

-- ────────────────────────────────────────────────
-- ① 探索：付费 / 非付费各有多少人【小样本验证】
-- ────────────────────────────────────────────────
SELECT COUNT(DISTINCT user_id) AS 总用户数
FROM temp_behavior;

SELECT COUNT(DISTINCT user_id) AS 付费用户数
FROM temp_behavior
WHERE behavior_type = 'buy';

-- ────────────────────────────────────────────────
-- ② 结果表 +【全量执行】
-- ────────────────────────────────────────────────
-- 一次 GROUP BY 把每人各行为的次数都算出来，
-- 比后面用四个子查询分别统计快得多 —— 全表只需扫一遍。
DROP TABLE IF EXISTS user_pay_split;
CREATE TABLE user_pay_split (
    user_id     INT,
    is_pay      TINYINT,   -- 1 = 付费，0 = 非付费
    pv_num      INT,
    fav_num     INT,
    cart_num    INT,
    buy_num     INT,
    active_days INT        -- 活跃天数：去过重的日期数，用来衡量粘性
);

INSERT INTO user_pay_split (user_id, is_pay, pv_num, fav_num, cart_num, buy_num, active_days)
SELECT user_id,
       MAX(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END),
       SUM(CASE WHEN behavior_type = 'pv'   THEN 1 ELSE 0 END),
       SUM(CASE WHEN behavior_type = 'fav'  THEN 1 ELSE 0 END),
       SUM(CASE WHEN behavior_type = 'cart' THEN 1 ELSE 0 END),
       SUM(CASE WHEN behavior_type = 'buy'  THEN 1 ELSE 0 END),
       COUNT(DISTINCT dates)
FROM user_behavior
GROUP BY user_id;

SELECT COUNT(1) AS 用户数 FROM user_pay_split;

-- ────────────────────────────────────────────────
-- ③ 两组对比
-- ────────────────────────────────────────────────
-- 占比走子查询实时算，不写死百分比 —— 数据一变才不会悄悄算错
SELECT is_pay,
       COUNT(user_id) AS 人数,
       ROUND(COUNT(user_id) * 100 / (SELECT COUNT(1) FROM user_pay_split), 2) AS 占比,
       ROUND(AVG(pv_num), 1)      AS 人均浏览,
       ROUND(AVG(fav_num), 1)     AS 人均收藏,
       ROUND(AVG(cart_num), 1)    AS 人均加购,
       ROUND(AVG(buy_num), 1)     AS 人均购买,
       ROUND(AVG(active_days), 1) AS 人均活跃天数
FROM user_pay_split
GROUP BY is_pay;

-- ────────────────────────────────────────────────
-- ④ 再看一层：非付费用户卡在哪一步
-- ────────────────────────────────────────────────
-- 只看非付费组，按「是否收藏 / 加购过」再切一刀。
-- 目的是分清两种人：
--     有意向没成交（收藏加购过）→ 临门一脚的问题，靠优惠券 / 促销推一把
--     纯闲逛（什么都没做）      → 流量质量问题，推也推不动
SELECT CASE
           WHEN fav_num + cart_num > 0 THEN '有意向未成交'
           ELSE '纯闲逛'
       END AS 非付费细分,
       COUNT(user_id) AS 人数,
       ROUND(AVG(pv_num), 1)      AS 人均浏览,
       ROUND(AVG(active_days), 1) AS 人均活跃天数
FROM user_pay_split
WHERE is_pay = 0
GROUP BY 1
ORDER BY 人数 DESC;

-- ────────────────────────────────────────────────
-- 备注
-- ────────────────────────────────────────────────
-- 1. is_pay 用 TINYINT 而不是 BOOLEAN：MySQL 的 BOOLEAN 就是 TINYINT(1) 的别名，
--    直接写 TINYINT 语义更明确，取出来也是 0 / 1 两个整数。
--
-- 2. 这个口径把「看过就买」和「收藏了 20 次才买」都算作付费用户。
--    真要做精细化分层，应该结合 RFM 的 F 分一起看，
--    见同目录下的 RFM模型.sql。
