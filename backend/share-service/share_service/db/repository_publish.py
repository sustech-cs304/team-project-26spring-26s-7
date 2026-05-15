"""Repository for the spec-compliant `share_publish` table.

Mirrors the design of repository.py (per-call connection, lazy schema apply)
but operates on a different schema. Both repositories share the same
SQLite database file — they coexist as separate tables.
"""
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Optional

from ..core.config import get_settings

_init_lock = threading.Lock()
_initialized_for_path: Optional[str] = None


def _ensure_schema() -> str:
    global _initialized_for_path
    settings = get_settings()
    db_path = settings.db_path
    if _initialized_for_path == db_path:
        return db_path
    with _init_lock:
        if _initialized_for_path == db_path:
            return db_path
        schema_sql = (Path(__file__).parent / "schema_publish.sql").read_text()
        conn = sqlite3.connect(db_path, isolation_level=None)
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.executescript(schema_sql)
            # v0.8 migration: 早期 DB 没有 revoked_reason 列，CREATE IF NOT
            # EXISTS 不会改已有表，需要手动 ALTER。idempotent。
            cur = conn.execute("PRAGMA table_info(share_publish)")
            cols = {row[1] for row in cur.fetchall()}
            if "revoked_reason" not in cols:
                conn.execute(
                    "ALTER TABLE share_publish ADD COLUMN revoked_reason TEXT"
                )
            # v1.0 migration: 同样幂等加 replay_prefs_json
            if "replay_prefs_json" not in cols:
                conn.execute(
                    "ALTER TABLE share_publish ADD COLUMN replay_prefs_json TEXT"
                )
            # 新索引（CREATE INDEX IF NOT EXISTS 自身幂等）
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_share_publish_trip "
                "ON share_publish(trip_id)"
            )
        finally:
            conn.close()
        _initialized_for_path = db_path
        return db_path


def reset_initialization() -> None:
    global _initialized_for_path
    _initialized_for_path = None


@contextmanager
def _open_conn() -> Iterator[sqlite3.Connection]:
    db_path = _ensure_schema()
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def insert_publish(row: dict[str, Any]) -> None:
    with _open_conn() as conn:
        conn.execute(
            """
            INSERT INTO share_publish
              (short_code, trip_id, trip_data_json, photo_index_json,
               cover_relpath, published_at_ms, expires_at_s, sig_hex, view_count,
               replay_prefs_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            (
                row["short_code"],
                row["trip_id"],
                row["trip_data_json"],
                row["photo_index_json"],
                row.get("cover_relpath"),
                row["published_at_ms"],
                row["expires_at_s"],
                row["sig_hex"],
                row.get("replay_prefs_json"),
            ),
        )


def short_code_exists(code: str) -> bool:
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT 1 FROM share_publish WHERE short_code = ?", (code,)
        )
        return cur.fetchone() is not None


def fetch_publish(code: str) -> Optional[dict[str, Any]]:
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT * FROM share_publish WHERE short_code = ?", (code,)
        )
        row = cur.fetchone()
        return dict(row) if row else None


def increment_view_count(code: str) -> int:
    with _open_conn() as conn:
        cur = conn.execute(
            "UPDATE share_publish SET view_count = view_count + 1 "
            "WHERE short_code = ? RETURNING view_count",
            (code,),
        )
        r = cur.fetchone()
        return int(r["view_count"]) if r else 0


def delete_publish(short_code: str) -> bool:
    """Delete a single share row by shortCode. Returns True if a row was
    actually removed."""
    with _open_conn() as conn:
        cur = conn.execute(
            "DELETE FROM share_publish WHERE short_code = ?", (short_code,)
        )
        return cur.rowcount > 0


def mark_revoked_by_trip(trip_id: str, reason: str) -> list[str]:
    """v0.8: 把某 trip 的所有未撤销的分享都打上 revoked_reason。
    返回受影响的 shortCode 列表（调用方拿来删 cache 子目录）。
    已经被撤销 / 已自然过期的行不动。"""
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT short_code FROM share_publish "
            "WHERE trip_id = ? AND revoked_reason IS NULL",
            (trip_id,),
        )
        codes = [r["short_code"] for r in cur.fetchall()]
        if codes:
            placeholders = ",".join("?" * len(codes))
            params = [reason, *codes]
            conn.execute(
                f"UPDATE share_publish SET revoked_reason = ? "
                f"WHERE short_code IN ({placeholders})",
                params,
            )
        return codes


def purge_expired(now_s: int) -> list[str]:
    """Delete rows where expires_at_s < now_s. Returns deleted shortCodes
    so the caller can also remove their cache directories."""
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT short_code FROM share_publish WHERE expires_at_s < ?",
            (now_s,),
        )
        codes = [r["short_code"] for r in cur.fetchall()]
        if codes:
            conn.execute(
                f"DELETE FROM share_publish WHERE short_code IN "
                f"({','.join('?' * len(codes))})",
                codes,
            )
        return codes
