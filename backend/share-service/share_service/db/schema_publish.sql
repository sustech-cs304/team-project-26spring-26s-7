-- New share_publish table for the P08 API spec endpoint.
-- Kept separate from share_link (legacy demo flow) because the schemas
-- diverge on key fields (sig length, expire unit, no owner).

CREATE TABLE IF NOT EXISTS share_publish (
    short_code         TEXT PRIMARY KEY,
    trip_id            TEXT NOT NULL,
    trip_data_json     TEXT NOT NULL,        -- {tripId, tripName, totalDistance, coverIndex, createdAt, nodes:[...]}
    photo_index_json   TEXT NOT NULL,        -- list of {nodeOrder, photoIdx, paths:{375:..., 750:...}}
    cover_relpath      TEXT,                 -- relative path of cover photo (375w by convention)
    published_at_ms    INTEGER NOT NULL,
    expires_at_s       INTEGER NOT NULL,     -- spec uses Unix seconds
    sig_hex            TEXT NOT NULL,        -- 64-char lowercase hex
    view_count         INTEGER NOT NULL DEFAULT 0,
    revoked_reason     TEXT,                 -- v0.8: NULL = active or naturally expired,
                                             --       'PRIVATE' = trip 改为私密后被owner撤销
    replay_prefs_json  TEXT                  -- v1.0: 发布者在 ReplaySettingsSheet 选的回放偏好。
                                             -- 7 个字段 (styleKitId/bgmId/filterId/transitionType/
                                             -- enableBlurOverlay/enableRouteAnimation)。
                                             -- NULL 表示用全局默认。
);

CREATE INDEX IF NOT EXISTS idx_share_publish_expires
    ON share_publish(expires_at_s);
CREATE INDEX IF NOT EXISTS idx_share_publish_trip
    ON share_publish(trip_id);
