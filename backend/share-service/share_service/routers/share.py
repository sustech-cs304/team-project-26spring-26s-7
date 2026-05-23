"""Share-link API endpoints (§5)."""
import json
import logging
import threading
import time
from collections import deque
from typing import Deque

from fastapi import APIRouter, Depends, HTTPException, Request

from ..core.auth import get_owner_uid
from ..core.config import get_settings
from ..core.security import compute_sig, generate_short_code, verify_sig
from ..core.storage import sign_download_url
from ..db import repository as repo
from ..models.share import (
    CreateShareRequest,
    CreateShareResponse,
    MyShareItem,
    RevokeResponse,
    ShareViewResponse,
)

router = APIRouter(prefix="/api/share", tags=["share"])
log = logging.getLogger("share")

ALLOWED_EXPIRE_DAYS = {1, 7, 30}
MAX_SNAPSHOT_BYTES = 256 * 1024
MAX_MANIFEST = 50
DAILY_CREATE_LIMIT = 50
ONE_DAY_MS = 24 * 3600 * 1000

# §5.2: 30 req/min/IP (anti-scrape on the public GET).
_ip_window: dict[str, Deque[float]] = {}
_ip_window_lock = threading.Lock()
GET_LIMIT_PER_MIN = 30


def _check_ip_rate_limit(ip: str) -> bool:
    now = time.time()
    cutoff = now - 60.0
    with _ip_window_lock:
        bucket = _ip_window.setdefault(ip, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= GET_LIMIT_PER_MIN:
            return False
        bucket.append(now)
        return True


def _now_ms() -> int:
    return int(time.time() * 1000)


# Order matters: /mine and /{code}/revoke must be declared before the
# catch-all /{code_dot_sig} so they aren't shadowed.

@router.post("/create", response_model=CreateShareResponse)
async def create_share(
    body: CreateShareRequest,
    owner_uid: str = Depends(get_owner_uid),
) -> CreateShareResponse:
    if body.expireDays not in ALLOWED_EXPIRE_DAYS:
        raise HTTPException(422, "expire_days_not_allowed")
    if len(body.photoManifest) > MAX_MANIFEST:
        raise HTTPException(422, "manifest_too_large")

    snapshot_str = json.dumps(body.snapshot, ensure_ascii=False, separators=(",", ":"))
    snapshot_bytes = len(snapshot_str.encode("utf-8"))
    if snapshot_bytes > MAX_SNAPSHOT_BYTES:
        raise HTTPException(422, "snapshot_too_large")

    # Cross-user object-reference defense (§六.2). Every key must live under
    # the caller's own users/{ownerUid}/ prefix.
    expected_prefix = f"users/{owner_uid}/"
    for key in body.photoManifest:
        if not isinstance(key, str) or not key.startswith(expected_prefix):
            raise HTTPException(403, "cross_user_object_reference")

    now = _now_ms()
    if repo.count_creates_in_window(owner_uid, ONE_DAY_MS, now) >= DAILY_CREATE_LIMIT:
        raise HTTPException(429, "daily_limit_exceeded")

    settings = get_settings()
    expire_at = now + body.expireDays * ONE_DAY_MS

    code: str | None = None
    for _ in range(3):
        candidate = generate_short_code()
        if not repo.short_code_exists(candidate):
            code = candidate
            break
    if code is None:
        raise HTTPException(503, "short_code_collision")

    sig = compute_sig(settings.share_hmac_key, code, owner_uid, expire_at)

    repo.insert_share(
        {
            "short_code": code,
            "owner_uid": owner_uid,
            "trip_cloud_id": body.tripCloudId,
            "snapshot_json": snapshot_str,
            "photo_manifest": json.dumps(body.photoManifest),
            "created_at": now,
            "expire_at": expire_at,
            "sig": sig,
            "consent_version": body.consentVersion,
        }
    )
    log.info(
        "share_create code=%s owner=%s size=%d photos=%d",
        code, owner_uid, snapshot_bytes, len(body.photoManifest),
    )

    url = f"{settings.public_base.rstrip('/')}/s/{code}.{sig}"
    return CreateShareResponse(shortCode=code, sig=sig, url=url, expireAt=expire_at)


@router.get("/mine", response_model=list[MyShareItem])
async def my_shares(owner_uid: str = Depends(get_owner_uid)) -> list[MyShareItem]:
    rows = repo.list_owner_shares(owner_uid)
    return [
        MyShareItem(
            shortCode=r["short_code"],
            tripCloudId=r["trip_cloud_id"],
            expireAt=r["expire_at"],
            revoked=bool(r["revoked"]),
            viewCount=r["view_count"],
            createdAt=r["created_at"],
        )
        for r in rows
    ]


@router.post("/{code}/revoke", response_model=RevokeResponse)
async def revoke_share(
    code: str, owner_uid: str = Depends(get_owner_uid)
) -> RevokeResponse:
    found, owned = repo.revoke_share(code, owner_uid)
    if not found:
        raise HTTPException(404, "not_found")
    if not owned:
        raise HTTPException(403, "not_owner")
    return RevokeResponse(revoked=True)


@router.get("/{code_dot_sig}", response_model=ShareViewResponse)
async def get_share(code_dot_sig: str, request: Request) -> ShareViewResponse:
    client_host = request.client.host if request.client else "unknown"
    if not _check_ip_rate_limit(client_host):
        raise HTTPException(429, "too_many_requests")

    if "." not in code_dot_sig:
        raise HTTPException(404, "link_expired_or_invalid")
    code, sig = code_dot_sig.rsplit(".", 1)

    settings = get_settings()
    row = repo.fetch_share(code)
    now = _now_ms()
    # §5.2 check order: revoked → expired → sig. All failures collapse into a
    # single 404 so attackers can't distinguish the failure mode.
    if (
        row is None
        or row["revoked"]
        or row["expire_at"] <= now
        or not verify_sig(
            settings.share_hmac_key, code, row["owner_uid"], row["expire_at"], sig
        )
    ):
        raise HTTPException(404, "link_expired_or_invalid")

    view_count = repo.increment_view_count(code)
    snapshot = json.loads(row["snapshot_json"])
    manifest = json.loads(row["photo_manifest"])
    ttl_seconds = max(60, min(3600, (row["expire_at"] - now) // 1000))
    photo_urls = {key: sign_download_url(key, ttl_seconds) for key in manifest}

    return ShareViewResponse(
        snapshot=snapshot,
        photoUrls=photo_urls,
        expireAt=row["expire_at"],
        viewCount=view_count,
    )
