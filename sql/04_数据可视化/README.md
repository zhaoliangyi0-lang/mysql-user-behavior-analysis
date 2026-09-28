# 数据可视化

对应思维导图的「数据可视化」板块。这里存放 SQL 取数之后的**展示层**工作：

- 图表原型（Python / matplotlib / pyecharts）
- BI 看板配置
- 可视化结果截图与说明

> `.sql` 只负责把数据查出来，图表代码放这里。

## 仪表板总览

![仪表板总览](../../images/dashboard.png)

Tableau 工作簿 `MYSQL实战.twb` 由 **12 个工作表 + 1 个仪表板**组成，
上方为导出的静态快照（`images/dashboard.png`，1200 × 2400）。

工作簿源文件是 XML，里面写死了本机数据库连接信息（server / port / username / dbname），
已由 `.gitignore` 的 `*.twb` / `*.twbx` 规则排除，不入库。分享作品请用 Tableau Public 的在线链接。

## 图表清单

每张图都不直接查原始表，而是取 `00 ~ 03` 板块落库的**结果表**——
这样图表层和数据加工层解耦，改口径只用重跑上游 SQL，不用动工作簿。

| # | 工作表 | 取数结果表 | 用到的字段 |
|---|---|---|---|
| 1 | 用户行为趋势图 | `taobao` | `dates`、`pv`、`cart`、`fav`、`buy` |
| 2 | 用户日内行为趋势图 | `taobao` | `hours`、`pv`、`cart`、`fav`、`buy` |
| 3 | 用户日内详细分析行为图 | `taobao` | `dates`、`hours`、`pv`、`cart`、`fav`、`buy` |
| 4 | 购买率、收藏加购率日内变化图 | `taobao` | `hours`、`pv`、`cart`、`fav`、`buy` |
| 5 | 活跃用户次日留存率 | `retention_rate` | `dates`、`retention_1` |
| 6 | 用户定位RFM模型 | `rfm_model` | `user_id`、`frequency`、`recent`、`fscore`、`rscore`、`class` |
| 7 | 用户定位RFM模型分类 | `category_detail` | `category_id`、`pv`、`fav`、`cart`、`buy`、`user_buy_rate` |
| 8 | 热门商品 | `popular_items` | `item_id`、`pv` |
| 9 | 热门类别 | `popular_categories` | `category_id`、`pv` |
| 10 | 热门的各类别最热门商品 | `popular_cateitems` | `category_id`、`item_id`、`pv` |
| 11 | 用户行为路径分析 | `path_result` | `path_type`、`description`、`num` |
| 12 | 收藏加购流量转化率 | `sankey_flow` | `From`、`To`、`Value`、`FromRank`、`ToRank`、`NodeName` |

**结果表出处**

| 结果表 | 由哪支 SQL 产出 |
|---|---|
| `taobao`（日期 × 小时聚合） | `01_人/03_行为情况/日内行为.sql` |
| `retention_rate` | `01_人/02_留存情况/留存率.sql` |
| `rfm_model` | `01_人/04_用户定位/RFM模型.sql` |
| `category_detail` | `02_货/商品转化率.sql` |
| `popular_items` / `popular_categories` / `popular_cateitems` | `02_货/按热度分类.sql` |
| `path_result` | `01_人/03_行为情况/行为路径分析.sql` |
| `sankey_flow` | 桑基图源数据在仓库外手工整理（原为 CSV），非 SQL 产出 |

## 取数约定

- 结果表统一 `DROP TABLE IF EXISTS` + `CREATE TABLE ... AS SELECT`，可重复执行
- 表名不加前缀，与 SQL 文件里写的一致，方便对照
- 同一张图如果要换口径，改上游 `.sql` 后重跑，再在 Tableau 里「刷新数据源」即可

## 计划

- [ ] 图表原型改用 Python 复刻一遍（matplotlib / pyecharts），摆脱对 Tableau 的依赖
- [ ] 补每张图的分析结论（现在只有图，没有解读文字）
- [ ] 仪表板改造成 Tableau Public 在线版并补链接
