"""SQLite repository for share_link rows.

Per-call short-lived connections keep things simple under FastAPI's
threadpool. WAL mode is enabled so concurrent reads + a single writer
behave well. Schema is auto-applied on first call.
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
        schema_sql = (Path(__file__).parent / "schema.sql").read_text()
        conn = sqlite3.connect(db_path, isolation_level=None)
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.executescript(schema_sql)
        finally:
            conn.close()
        _initialized_for_path = db_path
        return db_path


def reset_initialization() -> None:
    """Test helper — forces schema re-apply on next call."""
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


def insert_share(row: dict[str, Any]) -> None:
    with _open_conn() as conn:
        conn.execute(
            """
            INSERT INTO share_link
              (short_code, owner_uid, trip_cloud_id, snapshot_json, photo_manifest,
               created_at, expire_at, revoked, view_count, sig, consent_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
            """,
            (
                row["short_code"],
                row["owner_uid"],
                row["trip_cloud_id"],
                row["snapshot_json"],
                row["photo_manifest"],
                row["created_at"],
                row["expire_at"],
                row["sig"],
                row["consent_version"],
            ),
        )


def short_code_exists(code: str) -> bool:
    with _open_conn() as conn:
        cur = conn.execute("SELECT 1 FROM share_link WHERE short_code = ?", (code,))
        return cur.fetchone() is not None


def fetch_share(code: str) -> Optional[dict[str, Any]]:
    with _open_conn() as conn:
        cur = conn.execute("SELECT * FROM share_link WHERE short_code = ?", (code,))
        row = cur.fetchone()
        return dict(row) if row else None


def increment_view_count(code: str) -> int:
    with _open_conn() as conn:
        cur = conn.execute(
            "UPDATE share_link SET view_count = view_count + 1 "
            "WHERE short_code = ? RETURNING view_count",
            (code,),
        )
        row = cur.fetchone()
        return int(row["view_count"]) if row else 0


def revoke_share(code: str, owner_uid: str) -> tuple[bool, bool]:
    """Return (found, owned). Revokes only when owned. Idempotent."""
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT owner_uid FROM share_link WHERE short_code = ?", (code,)
        )
        row = cur.fetchone()
        if not row:
            return (False, False)
        if row["owner_uid"] != owner_uid:
            return (True, False)
        conn.execute(
            "UPDATE share_link SET revoked = 1 WHERE short_code = ?", (code,)
        )
        return (True, True)


def list_owner_shares(owner_uid: str, limit: int = 50) -> list[dict[str, Any]]:
    with _open_conn() as conn:
        cur = conn.execute(
            """
            SELECT short_code, trip_cloud_id, expire_at, revoked, view_count, created_at
            FROM share_link
            WHERE owner_uid = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (owner_uid, limit),
        )
        return [dict(r) for r in cur.fetchall()]


def count_creates_in_window(owner_uid: str, window_ms: int, now_ms: int) -> int:
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT COUNT(*) AS n FROM share_link "
            "WHERE owner_uid = ? AND created_at > ?",
            (owner_uid, now_ms - window_ms),
        )
        return int(cur.fetchone()["n"])


def purge_old(cutoff_ms: int) -> int:
    with _open_conn() as conn:
        cur = conn.execute(
            "DELETE FROM share_link WHERE expire_at < ?", (cutoff_ms,)
        )
        return cur.rowcount
