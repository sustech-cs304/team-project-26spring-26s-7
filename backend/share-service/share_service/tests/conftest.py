"""Test bootstrap: env vars must be set BEFORE the app is imported, because
config.py reads them eagerly at import time."""
import os
import tempfile

os.environ.setdefault("SHARE_HMAC_KEY", "unit-test-key-please-replace-in-prod-32b")
os.environ.setdefault("DB_PATH", os.path.join(tempfile.gettempdir(), "share_test.db"))
os.environ.setdefault("ALLOW_DEV_UID_HEADER", "1")
os.environ.setdefault("SHARE_PUBLIC_BASE", "https://test.example")
os.environ.setdefault("MOCK_STORAGE_BASE", "https://mock.example")
os.environ.setdefault("CORS_ORIGINS", "https://share.travelpin.app,http://localhost:5173")

# Wipe the test DB at session start so each run is deterministic.
_db = os.environ["DB_PATH"]
for suffix in ("", "-wal", "-shm", "-journal"):
    p = _db + suffix
    if os.path.exists(p):
        os.remove(p)


# All publish-via-TestClient calls hit the same fake client IP, so the
# 30-publish/hour limit accumulates across tests; once the suite size
# exceeds that, late tests get 429 instead of their expected status.
# Reset the rate-limit windows before each test.
import pytest


@pytest.fixture(autouse=True)
def _reset_rate_limit_windows():
    from share_service.routers import publish as _publish_router
    from share_service.routers import share as _share_router
    _publish_router._PUBLISH_WINDOW.clear()
    _share_router._ip_window.clear()
    yield
