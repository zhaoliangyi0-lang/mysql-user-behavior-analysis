-- ============================================
-- 功能：浏览深度（PV / UV）
-- 板块：人 › 获客情况
-- 依赖：taobao.user_behavior（小样本验证需先建沙箱表，见 10_开发沙箱_临时表.sql）
-- 状态：已完成
-- 更新：2026-09-20
-- 对应思维导图：人 › 获客情况 › 浏览深度 PV/UV
-- ============================================
--
-- PV / UV = 人均浏览页面数，值越高说明用户逛得越深、粘性越好。
-- 本文件把三个指标合到一条语句里算，并落地成结果表 pv_uv_puv，
-- 供后续数据可视化直接取数。

USE taobao;

-- ①【小样本验证】一条语句同时算出 PV / UV / PV·UV
SELECT dates,
       COUNT(*)                                AS pv,
       COUNT(DISTINCT user_id)                 AS uv,
       ROUND(COUNT(*) / COUNT(DISTINCT user_id), 1) AS puv
FROM temp_behavior
WHERE behavior_type = 'pv'
GROUP BY dates
ORDER BY dates;

-- ② 建立结果表
--    注意 pv / uv 写 INT 而不是 INT(9) / INT(0)：括号里的数字是「显示宽度」，
--    既不改变取值范围、也不影响存储，且 MySQL 8.0.17 起已标记废弃，写上会有 warning。
DROP TABLE IF EXISTS pv_uv_puv;
CREATE TABLE pv_uv_puv (
    dates CHAR(10),        -- 日期，如 2017-12-02
    pv    INT,             -- 当日浏览量
    uv    INT,             -- 当日独立访客数
    puv   DECIMAL(10,1)    -- 当日人均浏览量 = pv / uv
);

-- ③【全量执行】对真实表跑，结果写入 pv_uv_puv
--    AND dates IS NOT NULL 用来挡掉时间戳异常、拆不出日期的那几行。
--    不滤的话 GROUP BY 会把它们归成一个 NULL 组，
--    就得像原来的写法那样插完再补一句：
--    DELETE FROM pv_uv_puv WHERE dates IS NULL;
INSERT INTO pv_uv_puv
SELECT dates,
       COUNT(*)                                AS pv,
       COUNT(DISTINCT user_id)                 AS uv,
       ROUND(COUNT(*) / COUNT(DISTINCT user_id), 1) AS puv
FROM user_behavior
WHERE behavior_type = 'pv'
  AND dates IS NOT NULL
GROUP BY dates;

-- ④ 核对结果
SELECT * FROM pv_uv_puv ORDER BY dates;
