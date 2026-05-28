"""ItsMapPin 用户反馈持久化层。
跟 share_publish 同库 (share.db)，但单独走 schema_feedback.sql 建表。
懒加载 + 幂等 ALTER 模式跟 repository_publish.py 保持一致。
"""
from __future__ import annotations

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
        schema_sql = (Path(__file__).parent / "schema_feedback.sql").read_text()
        conn = sqlite3.connect(db_path, isolation_level=None)
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.executescript(schema_sql)
        finally:
            conn.close()
        _initialized_for_path = db_path
        return db_path


@contextmanager
def _open_conn() -> Iterator[sqlite3.Connection]:
    db_path = _ensure_schema()
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def insert_feedback(row: dict[str, Any]) -> int:
    """写入一条反馈，返回新行的 id。"""
    with _open_conn() as conn:
        cur = conn.execute(
            """
            INSERT INTO user_feedback
              (uid, category, content, contact, app_version, os_version,
               device_model, submitted_at, client_ip, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'new')
            """,
            (
                row.get("uid"),
                row["category"],
                row["content"],
                row.get("contact"),
                row.get("app_version"),
                row.get("os_version"),
                row.get("device_model"),
                row["submitted_at"],
                row.get("client_ip"),
            ),
        )
        return int(cur.lastrowid or 0)


def list_recent(limit: int = 100) -> list[dict[str, Any]]:
    """运维查最近反馈（命令行/admin 用，不暴露公网 API）。"""
    with _open_conn() as conn:
        cur = conn.execute(
            "SELECT * FROM user_feedback ORDER BY submitted_at DESC LIMIT ?",
            (limit,),
        )
        return [dict(r) for r in cur.fetchall()]
