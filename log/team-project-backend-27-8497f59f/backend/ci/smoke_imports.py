#!/usr/bin/env python3
"""Smoke test — verify the entry module of each backend service imports cleanly.

Three of the four services do import-time work (open log files, etc.) using
hardcoded /home/ or /data2/ paths from dev machines. Before any import, this
script redirects those paths to a writable tmpdir so the smoke test passes as
the jenkins user (or any other CI user).

share-service has its own pytest suite and is exercised in the Test stage; we
don't import it here to avoid double-loading FastAPI.

Exits non-zero if any service fails to import — bubbles up to Jenkins as a Test failure.
"""
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import traceback
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]  # team-project/backend/

# Some service modules touch the filesystem (e.g. create log dirs) at import
# time using hardcoded paths from dev machines. Redirect to a writable tmpdir
# BEFORE any import so the smoke test works in any CI environment.
_SMOKE_TMP = Path(tempfile.gettempdir()) / "ci-smoke-imports"
_SMOKE_TMP.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("BIC_LOG_DIR", str(_SMOKE_TMP / "picture-check"))    # picture-check/baidu_image_censor.py
os.environ.setdefault("SF_LOG_DIR",  str(_SMOKE_TMP / "sensitive-filter")) # sensitive-filter/sensitive_filter_service.py
os.environ.setdefault("LOG_DIR",     str(_SMOKE_TMP / "generic"))

# (label, dir relative to repo, module file)
TARGETS = [
    ("ai-relay",         "ai-relay",         "siliconflow_relay.py"),
    ("sensitive-filter", "sensitive-filter", "sensitive_filter_service.py"),
    ("picture-check",    "picture-check",    "baidu_image_censor.py"),
]


def _import_file(label: str, file_path: Path) -> bool:
    if not file_path.exists():
        print(f"  [skip] {label}: {file_path} does not exist")
        return True  # not a failure — repo just doesn't have this service
    sys.path.insert(0, str(file_path.parent))
    try:
        spec = importlib.util.spec_from_file_location(f"smoke_{label.replace('-', '_')}", file_path)
        if spec is None or spec.loader is None:
            print(f"  [FAIL] {label}: could not build import spec for {file_path}")
            return False
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        print(f"  [ ok ] {label}: imported {file_path.name}")
        return True
    except Exception:
        print(f"  [FAIL] {label}: import raised exception")
        traceback.print_exc()
        return False
    finally:
        sys.path.pop(0)


def main() -> int:
    print(f"smoke_imports.py — repo root: {REPO_ROOT}")
    failures = 0
    for label, subdir, module_file in TARGETS:
        ok = _import_file(label, REPO_ROOT / subdir / module_file)
        if not ok:
            failures += 1
    if failures:
        print(f"\nsmoke import: {failures} failure(s)")
        return 1
    print("\nsmoke import: all clear")
    return 0


if __name__ == "__main__":
    sys.exit(main())
