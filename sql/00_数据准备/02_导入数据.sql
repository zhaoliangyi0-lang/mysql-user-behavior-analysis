-- ============================================
-- 功能：导入数据
-- 板块：数据准备 › 数据获取
-- 依赖：taobao.user_behavior（需先执行 01_建库建表.sql）
-- 状态：已完成
-- 更新：2026-09-27
-- 对应思维导图：数据清洗和预处理 › 数据获取
-- ============================================
--
-- 说明：和 01_建库建表.sql 一样，原始导入走的是 Workbench 图形界面，
--       这里补一份 LOAD DATA 的可复现版本，两种方式都写在下面。

-- ────────────────────────────────────────────────
-- 方式一：LOAD DATA（命令行 / 脚本）
-- ────────────────────────────────────────────────
USE taobao;

-- ⚠️⚠️ 最容易踩的一个坑：local_infile 有【服务端】和【客户端】两个开关，
--     只开服务端没用，客户端一样会报
--         Error 2068: LOAD DATA LOCAL INFILE file request rejected
--                             due to restrictions on access
--
--     服务端（本机已经是 ON，换个环境才需要开）：
SET GLOBAL local_infile = 1;
--     客户端：必须在启动 mysql 时加参数，SQL 里怎么写都改不了它
--         mysql --local-infile=1 -u root -p
--     或者写进 my.ini 常驻：
--         [mysql]
--         local_infile=1
--
--     MySQL 8.0.28 起客户端默认就是关的（防恶意服务端读本机文件），
--     所以这条以前不是问题、现在几乎必踩。

-- ⚠️ 路径要改成你自己放数据文件的位置，下面是【占位符】。
--    Windows 上要写盘符风格，反斜杠双写或直接用正斜杠：
--         'C:/你的路径/UserBehavior.csv'      ✓
--         'C:\\你的路径\\UserBehavior.csv'    ✓
--    ⚠️ 如果你在 Git Bash 里执行，别顺手写成 MSYS 的 /c/... 格式，
--       它会原样传进去，报
--           File '\c\Users\...' not found (OS errno 2)
--
--    另外，如果哪天把 LOCAL 去掉（改成服务端读文件），
--    就会受 secure_file_priv 限制 —— 本机当前的值是
--        C:\ProgramData\MySQL\MySQL Server 26.7\Uploads\
--    文件必须放在那个目录下。查当前值：
--        SHOW VARIABLES LIKE 'secure_file_priv';
LOAD DATA LOCAL INFILE 'C:/你的路径/UserBehavior.csv'
INTO TABLE user_behavior
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(user_id, item_id, category_id, behavior_type, timestamps);

-- ⚠️ IGNORE 1 LINES：原始 CSV 带表头。如果拿到的文件确定没有表头，
--    把这行去掉，否则会白白丢掉第一行真实数据。

-- ⚠️ 另外注意：mysql 客户端在【非交互模式读文件时遇到错误会直接中止】
--    （不像交互式窗口那样继续往下跑）。
--    所以这条 LOAD DATA 一旦失败，本文件末尾的核对 SELECT 根本不会执行，
--    别以为没报错就是全跑完了 —— 看命令的退出码更靠谱。

-- ────────────────────────────────────────────────
-- 方式二：Workbench 导入向导（当初实际用的方式）
-- ────────────────────────────────────────────────
-- 1. 左侧 SCHEMAS 面板里右键 taobao 库 → Table Data Import Wizard
-- 2. 选中 UserBehavior.csv
-- 3. 目标选「Create new table」，表名填 user_behavior
-- 4. 逐列核对类型：三个 ID 和 timestamps 选 INT，
--    behavior_type 选 VARCHAR(10)（向导默认可能给成 TEXT，要手动改）
-- 5. Next → Next → Import，等进度条走完
--
-- 向导适合一次性的初次导入；文件路径换了、要重跑，就用上面的 LOAD DATA。

-- ────────────────────────────────────────────────
-- ③ 核对
-- ────────────────────────────────────────────────
-- 原始数据约 9100 万行 / 9.09 GB，本项目按全量导入。
SELECT COUNT(1) AS 导入行数 FROM user_behavior;
SELECT * FROM user_behavior LIMIT 5;

-- ────────────────────────────────────────────────
-- 备注：全量导入后的性能准备
-- ────────────────────────────────────────────────
-- 全量 9100 万行下，GROUP BY 查重、自连接去重与窗口函数都很重，
-- 需要索引与足够的缓冲池支撑；必要时按 user_id 分批执行。
--
-- 缓冲池不是越大越好：本机曾按「经验值」把它设成 8G，导致 MySQL 直接崩溃，
-- 后按机器实际可用内存降到 4G 才稳定
-- （见仓库外 _本机专用/个人笔记/性能诊断报告.md）。
-- 全量分析建议在 ≥ 16 GB 缓冲池的环境执行。
--
-- 调试阶段仍建议用 sql/00_数据准备/10_开发沙箱_临时表.sql
-- 复制 10 万行到 temp_behavior，先在沙箱验证语法与结果，再对全量执行。
