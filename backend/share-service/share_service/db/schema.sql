CREATE TABLE IF NOT EXISTS share_link (
    short_code      TEXT PRIMARY KEY,
    owner_uid       TEXT NOT NULL,
    trip_cloud_id   TEXT NOT NULL,
    snapshot_json   TEXT NOT NULL,
    photo_manifest  TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    expire_at       INTEGER NOT NULL,
    revoked         INTEGER NOT NULL DEFAULT 0,
    view_count      INTEGER NOT NULL DEFAULT 0,
    sig             TEXT NOT NULL,
    consent_version TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_share_owner_created
    ON share_link(owner_uid, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_share_expire
    ON share_link(expire_at);
