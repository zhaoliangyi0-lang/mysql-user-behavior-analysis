-- ============================================
-- 功能：创建索引
-- 板块：数据准备 › 数据准备
-- 依赖：taobao.user_behavior
-- 对应思维导图：数据清洗和预处理 › 字段 › 字段约束
-- ============================================

USE taobao;

-- 会话准备：加大读写等待时间（注意：这只影响服务器端，Workbench 自身的
-- 断连由 Edit → Preferences → SQL Editor → Read Timeout 控制）
SET GLOBAL net_read_timeout  = 3600;
SET GLOBAL net_write_timeout = 3600;

-- 为后续的残缺检查、重复检查建立索引
CREATE INDEX idx_user_id       ON taobao.user_behavior(user_id);
CREATE INDEX idx_item_id       ON taobao.user_behavior(item_id);
CREATE INDEX idx_category_id   ON taobao.user_behavior(category_id);
CREATE INDEX idx_behavior_type ON taobao.user_behavior(behavior_type);
CREATE INDEX idx_timestamps    ON taobao.user_behavior(timestamps);
