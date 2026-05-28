-- ItsMapPin 用户反馈表 (帮助与客服)
-- 接收前端 ProfileView 帮助与客服 → 反馈表单的提交
-- 跟 share_publish 同库 (share.db)

CREATE TABLE IF NOT EXISTS user_feedback (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    uid           TEXT,                  -- 用户 uid (从 X-Dev-Uid 或 audit token 解出，可能为 NULL：未登录)
    category      TEXT NOT NULL,         -- 'bug' / 'feature' / 'experience' / 'other'
    content       TEXT NOT NULL,         -- 反馈正文 (≤ 2000 chars)
    contact       TEXT,                  -- 可选联系方式 (邮箱 / 微信 / QQ)，留空表示不希望回访
    app_version   TEXT,                  -- 客户端版本 (e.g. "1.0.0")
    os_version    TEXT,                  -- HarmonyOS NEXT 版本
    device_model  TEXT,                  -- 机型
    submitted_at  INTEGER NOT NULL,      -- Unix seconds
    client_ip     TEXT,                  -- 服务端记录的来源 IP (排查恶意提交用)
    status        TEXT NOT NULL DEFAULT 'new'   -- 'new' / 'reviewed' / 'replied' / 'closed'
);

CREATE INDEX IF NOT EXISTS idx_feedback_submitted ON user_feedback(submitted_at);
CREATE INDEX IF NOT EXISTS idx_feedback_status    ON user_feedback(status);
CREATE INDEX IF NOT EXISTS idx_feedback_uid       ON user_feedback(uid);
