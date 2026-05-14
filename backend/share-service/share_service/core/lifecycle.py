"""Lifecycle (TTL / expiry) management for share_publish links.

Three paths trigger cleanup:
  1. Lazy delete on access — viewer / status / cache routes detect that the
     row's expires_at_s has passed and delete the row + cache subdir
     immediately, returning the appropriate error to the caller. This means
     a popular but expired link can self-clean without waiting for the cron.
  2. Cron purge — scripts/purge_expired.py runs periodically and sweeps
     anything the lazy-delete path missed (links that are never accessed
     after they expire just sit there forever otherwise).
  3. Publish rollback — handled in routers/publish.py, not here.

The functions here are deliberately small and side-effect-only; tests can
call them directly to assert disk + DB state.
"""
from __future__ import annotations

import logging
import shutil
from pathlib import Path

from ..core.config import get_settings
from ..db import repository_publish as repo

log = logging.getLogger("lifecycle")


def cache_root() -> Path:
    """Where transcoded WebP files live. Same logic as routers/publish.py;
    duplicated here so this module has no router-layer import."""
    db_path = Path(get_settings().db_path).resolve()
    root = db_path.parent / "cache"
    root.mkdir(parents=True, exist_ok=True)
    return root


def delete_share(short_code: str) -> bool:
    """Delete one share's DB row and its cache subdir. Idempotent.

    Returns True if anything was deleted (row, dir, or both), False if
    neither existed.
    """
    deleted_any = False

    # rmtree first — even if the row was already gone, the dir might still
    # be on disk (e.g. crash during publish before insert)
    cache_dir = cache_root() / short_code
    if cache_dir.exists():
        shutil.rmtree(cache_dir, ignore_errors=True)
        deleted_any = True

    if repo.delete_publish(short_code):
        deleted_any = True

    if deleted_any:
        log.info("delete_share %s (dir + row removed)", short_code)
    return deleted_any


def purge_expired_now(now_s: int) -> tuple[int, int]:
    """Delete every expired share row + its cache subdir.

    Returns (rows_deleted, cache_dirs_removed).
    """
    codes = repo.purge_expired(now_s)
    dirs_removed = 0
    root = cache_root()
    for code in codes:
        d = root / code
        if d.exists():
            shutil.rmtree(d, ignore_errors=True)
            dirs_removed += 1
    return len(codes), dirs_removed


# ---------------------------------------------------------------------------
# v0.8: Trip 改私密时撤销该 trip 全部分享
# ---------------------------------------------------------------------------

# 撤销原因枚举（写到 share_publish.revoked_reason 列里）
REVOKE_REASON_PRIVATE = "PRIVATE"


def revoke_shares_by_trip(trip_id: str, reason: str = REVOKE_REASON_PRIVATE) -> list[str]:
    """把某 trip 的所有活跃分享标记为 revoked + 删 cache 子目录。
    返回被撤销的 shortCode 列表，调用方可用来 log / 回写给前端。

    注意：DB 行**保留**（带 reason 标记），cache 文件**立即删**。这样
    viewer 还能识别到 reason 给出对应错误页（"该用户已设置该路线为私密"），
    而 cache 已经不可达 —— 既给出准确的关停原因，又确保数据真的不再可读。
    DB 行后面被 cron 自然清掉（30 天后随 expires_at_s 一并 purge）。
    """
    codes = repo.mark_revoked_by_trip(trip_id, reason)
    if not codes:
        return []
    root = cache_root()
    for code in codes:
        d = root / code
        if d.exists():
            shutil.rmtree(d, ignore_errors=True)
    log.info(
        "revoke_shares_by_trip trip=%s reason=%s revoked=%d",
        trip_id, reason, len(codes),
    )
    return codes
