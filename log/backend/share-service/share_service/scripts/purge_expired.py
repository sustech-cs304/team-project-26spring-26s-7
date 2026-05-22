"""Daily cron: purge expired share_publish rows + their cache subdirs,
and (optionally) sweep the legacy share_link table.

Usage:
    python -m share_service.scripts.purge_expired

Wire it up via cron locally or AGC scheduled trigger in cloud.
"""
import logging
import time

from ..core.lifecycle import purge_expired_now
from ..db.repository import purge_old as legacy_purge_old


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    now_s = int(time.time())

    # Spec-compliant publish flow: delete every share_publish row that has
    # passed expires_at_s + remove its cache subdir.
    rows, dirs = purge_expired_now(now_s)
    logging.info(
        "purge_expired (publish): rows=%d cache_dirs=%d", rows, dirs
    )

    # Legacy demo flow: sweep share_link rows older than 30 days past
    # their expireAt. (Keep this around so the cron handles both
    # generations.) Cleanup of cloud refs is handled by the AGC side.
    cutoff_ms = now_s * 1000 - 30 * 24 * 3600 * 1000
    legacy = legacy_purge_old(cutoff_ms)
    logging.info("purge_expired (legacy share_link): rows=%d", legacy)


if __name__ == "__main__":
    main()
