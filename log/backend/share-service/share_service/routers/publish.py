"""Spec-compliant publish endpoints (P08 API 规范).

Routes:
  POST /api/v1/share/publish              §4
  GET  /api/v1/share/{shortcode}/status   §6
  GET  /cache/{shortcode}/{filename}      §5.2 photo URLs
"""
from __future__ import annotations

import io
import json
import logging
import shutil
import time
from collections import deque
from pathlib import Path
from typing import Any, Deque, Optional

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse, JSONResponse
from pydantic import ValidationError

from ..core.audit_task import audit_share
from ..core.auth_tokens import require_share_token
from ..core.config import get_settings
from ..core.lifecycle import (
    REVOKE_REASON_PRIVATE,
    delete_share,
    revoke_shares_by_trip,
)
from ..core.photos import WIDTHS, assign_photos_to_nodes, process_one
from ..core.security import (
    compute_sig_v2,
    generate_short_code_v2,
    verify_sig_v2,
)
from ..db import repository_publish as repo
from ..models.publish import (
    PublishOk,
    PublishResponse,
    PublishTripData,
    RevokeByTripData,
    RevokeByTripRequest,
    RevokeByTripResponse,
    StatusOkData,
    StatusResponse,
    normalize_replay_prefs,
)

router = APIRouter(tags=["publish"])
log = logging.getLogger("publish")

# Spec §4.1 limits.
MAX_PHOTO_BYTES = 20 * 1024 * 1024     # 20 MB per photo
MAX_BODY_BYTES = 100 * 1024 * 1024     # 100 MB total
MIN_EXPIRY_SECONDS = 60                 # 1 min — relaxed below spec's 1h
                                        # so the frontend can offer a "5 分钟"
                                        # debug option (see /docs/CHANGES.md v0.5)
MAX_EXPIRY_SECONDS = 720 * 3600         # 30 days, per spec §4.1
DEFAULT_EXPIRY_SECONDS = 168 * 3600     # 7 days
MAX_NODES = 30

# IP rate-limit on /publish: 30 publishes/IP/hour. Spec doesn't pin a number;
# this is a sane default, swap with Redis token bucket once we move to AGC.
_PUBLISH_WINDOW: dict[str, Deque[float]] = {}
PUBLISH_LIMIT_PER_HOUR = 30


def _err(http: int, code: int, message: str, detail: str | None = None) -> JSONResponse:
    """Spec-format error envelope."""
    body: dict[str, Any] = {"code": code, "message": message}
    if detail is not None:
        body["detail"] = detail
    return JSONResponse(status_code=http, content=body)


def _check_publish_rate(ip: str) -> bool:
    now = time.time()
    cutoff = now - 3600
    bucket = _PUBLISH_WINDOW.setdefault(ip, deque())
    while bucket and bucket[0] < cutoff:
        bucket.popleft()
    if len(bucket) >= PUBLISH_LIMIT_PER_HOUR:
        return False
    bucket.append(now)
    return True


def _cache_root() -> Path:
    """Where transcoded WebP files live. Mirrored at /cache/... by FastAPI."""
    settings = get_settings()
    # Default: <db dir>/cache. Settings can override later if needed.
    db_path = Path(settings.db_path).resolve()
    root = db_path.parent / "cache"
    root.mkdir(parents=True, exist_ok=True)
    return root


# ---------------------------------------------------------------------------
# POST /api/v1/share/publish
# ---------------------------------------------------------------------------

@router.post(
    "/api/v1/share/publish",
    status_code=status.HTTP_201_CREATED,
    response_model=PublishResponse,
)
async def publish(
    request: Request,
    background_tasks: BackgroundTasks,
    owner_uid: str = Depends(require_share_token),
):
    settings = get_settings()
    client_host = request.client.host if request.client else "unknown"
    if not _check_publish_rate(client_host):
        return _err(429, 42901, "RATE_LIMITED")

    # Parse multipart manually (instead of via Form/File deps) so we can
    # iterate parts in order and tolerate variable photo_N counts.
    try:
        form = await request.form()
    except Exception as e:
        return _err(400, 40005, "BODY_TOO_LARGE", detail=str(e))

    # ---- expiry resolution -------------------------------------------------
    # Two equivalent forms accepted: `expiryMinutes` (preferred when present,
    # supports sub-hour windows for dev) or `expiryHours` (spec original).
    # If both are sent, expiryMinutes wins.
    minutes_raw = form.get("expiryMinutes")
    hours_raw = form.get("expiryHours")
    expiry_seconds: int
    if minutes_raw is not None:
        try:
            expiry_seconds = int(str(minutes_raw)) * 60
        except ValueError:
            return _err(400, 40007, "INVALID_EXPIRY",
                        detail=f"expiryMinutes={minutes_raw}")
    elif hours_raw is not None:
        try:
            expiry_seconds = int(str(hours_raw)) * 3600
        except ValueError:
            return _err(400, 40007, "INVALID_EXPIRY",
                        detail=f"expiryHours={hours_raw}")
    else:
        expiry_seconds = DEFAULT_EXPIRY_SECONDS
    if not (MIN_EXPIRY_SECONDS <= expiry_seconds <= MAX_EXPIRY_SECONDS):
        return _err(
            400, 40007, "INVALID_EXPIRY",
            detail=f"expiry must be in [{MIN_EXPIRY_SECONDS}s, {MAX_EXPIRY_SECONDS}s]; got {expiry_seconds}s",
        )

    # ---- v1.0: 可选 replay 偏好（一组 multipart 文本字段，全可选）---------
    # 字段名与 frontend ReplayPreferences 严格对齐：
    #   replayStyleKitId, replayBgmId, replayFilterId, replayTransitionType,
    #   replayEnableBlurOverlay, replayEnableRouteAnimation
    # 容错：bool 字段接受 "true" / "false" / "1" / "0"，其它当 false。
    # 任何 enum 不在白名单内 → fallback 到 default（不报错）。
    def _bool_form(v):
        if v is None: return None
        s = str(v).strip().lower()
        if s in ("1", "true", "yes", "y"): return True
        if s in ("0", "false", "no", "n", ""): return False
        return None
    replay_raw: dict[str, Any] = {}
    for key, src in [
        ("styleKitId",     "replayStyleKitId"),
        ("bgmId",          "replayBgmId"),
        ("filterId",       "replayFilterId"),
        ("transitionType", "replayTransitionType"),
    ]:
        v = form.get(src)
        if v is not None:
            replay_raw[key] = str(v).strip()
    for key, src in [
        ("enableBlurOverlay",    "replayEnableBlurOverlay"),
        ("enableRouteAnimation", "replayEnableRouteAnimation"),
        ("enableRipple",         "replayEnableRipple"),
    ]:
        v = _bool_form(form.get(src))
        if v is not None:
            replay_raw[key] = v
    replay_prefs = normalize_replay_prefs(replay_raw)
    # 没传任何 replay 字段 → replay_prefs_json 存 None 表示"用默认"
    has_any_replay = bool(replay_raw)

    # ---- optional replaceShortCode (auto-revoke previous link) ------------
    # Frontend's "切档时自动撤销上一条" feature: caller passes the previous
    # link's shortCode + expiry + sig. We verify the sig matches what we
    # signed (i.e. caller actually held that URL — preventing random
    # third parties from publishing a junk trip with replaceShortCode set
    # to someone else's code). If valid we'll delete the old row + cache
    # AFTER the new publish has fully succeeded — atomicity flows:
    #   new fails → old preserved (status quo)
    #   new succeeds → old deleted (caller intent fulfilled)
    settings_for_replace = settings  # alias for clarity
    replace_code: Optional[str] = None
    rc_raw = form.get("replaceShortCode")
    rt_raw = form.get("replaceExpiry")
    rs_raw = form.get("replaceSig")
    if rc_raw is not None:
        if rt_raw is None or rs_raw is None:
            return _err(
                400, 40006, "INVALID_JSON",
                detail="replaceShortCode requires replaceExpiry + replaceSig",
            )
        try:
            replace_t = int(str(rt_raw))
        except ValueError:
            return _err(400, 40006, "INVALID_JSON",
                        detail=f"replaceExpiry not an int: {rt_raw}")
        if not verify_sig_v2(
            settings_for_replace.share_hmac_key,
            str(rc_raw), replace_t, str(rs_raw),
        ):
            return _err(400, 40006, "INVALID_JSON",
                        detail="replaceSig does not match shortCode/expiry")
        replace_code = str(rc_raw)

    # ---- tripData ----------------------------------------------------------
    trip_raw = form.get("tripData")
    if trip_raw is None:
        return _err(400, 40006, "INVALID_JSON", detail="tripData missing")
    if hasattr(trip_raw, "read"):  # UploadFile (some clients send as file)
        trip_text = (await trip_raw.read()).decode("utf-8", errors="replace")
    else:
        trip_text = str(trip_raw)
    try:
        trip_obj = json.loads(trip_text)
    except json.JSONDecodeError as e:
        return _err(400, 40006, "INVALID_JSON", detail=str(e))
    try:
        trip = PublishTripData.model_validate(trip_obj)
    except ValidationError as e:
        return _err(400, 40006, "INVALID_JSON", detail=e.errors()[:3])

    if not trip.nodes:
        return _err(400, 40002, "EMPTY_NODES")
    if len(trip.nodes) > MAX_NODES:
        return _err(400, 40003, "TOO_MANY_NODES", detail=f"got {len(trip.nodes)}")

    # ---- photo_N collection -----------------------------------------------
    nodes_sorted = sorted(trip.nodes, key=lambda n: n.nodeOrder)
    expected_count = sum(n.photoCount for n in nodes_sorted)

    photo_files: list[UploadFile] = []
    idx = 0
    while True:
        f = form.get(f"photo_{idx}")
        if f is None:
            break
        if not hasattr(f, "read"):  # not a file part — bad client
            return _err(400, 40001, "INVALID_PHOTO_COUNT",
                        detail=f"photo_{idx} is not a file part")
        photo_files.append(f)
        idx += 1
    if len(photo_files) != expected_count:
        return _err(
            400, 40001, "INVALID_PHOTO_COUNT",
            detail=f"expected {expected_count} photos, got {len(photo_files)}",
        )

    # ---- read + size-check -------------------------------------------------
    photo_bytes: list[bytes] = []
    total = 0
    for i, uf in enumerate(photo_files):
        data = await uf.read()
        if len(data) > MAX_PHOTO_BYTES:
            return _err(400, 40004, "PHOTO_TOO_LARGE",
                        detail=f"photo_{i} = {len(data)} bytes")
        total += len(data)
        if total > MAX_BODY_BYTES:
            return _err(400, 40005, "BODY_TOO_LARGE",
                        detail=f"running total {total}")
        photo_bytes.append(data)

    # ---- shortCode (spec charset, 8 chars, retry on collision) ------------
    short_code: Optional[str] = None
    for _ in range(5):
        candidate = generate_short_code_v2()
        if not repo.short_code_exists(candidate):
            short_code = candidate
            break
    if short_code is None:
        return _err(500, 50000, "INTERNAL_ERROR", detail="shortCode collision")

    # ---- transcode + persist (atomic: any failure → wipe cache dir) -------
    #
    # We do all disk writes (WebP files + manifest.json) and the DB insert
    # under one try. On any failure we shutil.rmtree the cache dir so the
    # next publish doesn't inherit half-written state. Process kill -9
    # between WebP write and DB insert can still leave orphan files; that
    # case is the orphan-scan cron's job.
    out_dir = _cache_root() / short_code
    out_dir.mkdir(parents=True, exist_ok=True)
    now_ms = int(time.time() * 1000)
    expires_at_s = int(time.time()) + expiry_seconds
    sig_hex = compute_sig_v2(settings.share_hmac_key, short_code, expires_at_s)

    photo_index: list[dict[str, Any]] = []
    grouped = assign_photos_to_nodes(
        photo_bytes, [n.photoCount for n in nodes_sorted]
    )

    try:
        flat_idx = 0
        for node, group in zip(nodes_sorted, grouped):
            for j, raw in enumerate(group):
                pp = process_one(raw, out_dir, flat_idx)
                photo_index.append({
                    "nodeOrder": node.nodeOrder,
                    "nodeId": node.id,
                    "photoIdx": j,
                    "flatIdx": flat_idx,
                    "paths": pp.relative_paths,
                })
                flat_idx += 1

        cover_relpath: Optional[str] = None
        if photo_index:
            cover = photo_index[
                max(0, min(trip.coverIndex, len(photo_index) - 1))
            ]
            # v1.0.4：og:image 单独生成一份 JPEG（cover.jpg, 1200w），不复用 WebP。
            # 微信 / QQ 的卡片爬虫历史上对 WebP 支持不稳，JPEG 是 100% 兼容的
            # 安全选项。inline viewer 仍然用 photo_index 的 375w/750w WebP，
            # 两条路独立。
            try:
                from PIL import Image, ImageOps
                with Image.open(io.BytesIO(photo_bytes[cover["flatIdx"]])) as cimg:
                    cimg = ImageOps.exif_transpose(cimg)
                    if cimg.mode != "RGB":
                        cimg = cimg.convert("RGB")
                    sw, sh = cimg.size
                    target_w = 1200
                    if sw > target_w:
                        target_h = round(sh * target_w / sw)
                        cimg = cimg.resize(
                            (target_w, target_h), resample=Image.LANCZOS
                        )
                    (out_dir / "cover.jpg").write_bytes(b"")  # touch first to fail
                    cimg.save(
                        out_dir / "cover.jpg",
                        format="JPEG",
                        quality=85,
                        optimize=True,
                        exif=b"",
                    )
                cover_relpath = "cover.jpg"
            except Exception:
                # Fallback：JPEG 写不出来就老老实实用 WebP；至少 inline 视图正常。
                log.exception("cover.jpg generation failed; using WebP fallback")
                cover_relpath = cover["paths"][375]

        # Self-describing manifest — debug-friendly, lets future tools
        # reconstruct what's in this dir without touching the DB.
        manifest = {
            "schemaVersion": 1,
            "shortCode": short_code,
            "tripId": trip.tripId,
            "tripName": trip.tripName,
            "publishedAtMs": now_ms,
            "expiresAtS": expires_at_s,
            "coverRelpath": cover_relpath,
            "photos": photo_index,
        }
        (out_dir / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        # v1.0：replay prefs 全没传时存 NULL（让 viewer 走全局默认）；
        # 至少传了一个就把整套 prefs（缺的字段已被 normalize 回填默认）落库
        replay_prefs_json: Optional[str] = (
            json.dumps(replay_prefs, ensure_ascii=False, separators=(",", ":"))
            if has_any_replay else None
        )
        repo.insert_publish({
            "short_code": short_code,
            "trip_id": trip.tripId,
            "trip_data_json": json.dumps(
                trip_obj, ensure_ascii=False, separators=(",", ":")
            ),
            "photo_index_json": json.dumps(
                photo_index, ensure_ascii=False, separators=(",", ":")
            ),
            "cover_relpath": cover_relpath,
            "published_at_ms": now_ms,
            "expires_at_s": expires_at_s,
            "sig_hex": sig_hex,
            "replay_prefs_json": replay_prefs_json,
        })
        # v1.2：异步审查文本 + 图片。命中后台静默 revoke (写 audit_status='rejected'
        # + revoked_reason='CONTENT_VIOLATION' + 清 cache)，viewer 显示固定话术。
        # FastAPI BackgroundTasks 在 response 返回后 schedule，所以不影响 publish 响应延迟。
        background_tasks.add_task(audit_share, short_code)
    except Exception as e:
        # rmtree is robust against partial state — empty dirs, dirs with
        # only some webp files, missing manifest, all fine. Anything we
        # can't clean up here will be picked up by the orphan-scan cron.
        shutil.rmtree(out_dir, ignore_errors=True)
        log.exception("publish failed; rolled back %s", short_code)
        return _err(500, 50000, "INTERNAL_ERROR", detail=str(e))
    log.info("publish ok code=%s photos=%d body_bytes=%d expiry_s=%d",
             short_code, len(photo_files), total, expiry_seconds)

    # ---- post-success: revoke the caller-designated previous link ---------
    # Done AFTER the new row is committed, so on any failure path above
    # the old link survives (callers can still recover).
    if replace_code is not None and replace_code != short_code:
        if delete_share(replace_code):
            log.info("publish replaced: %s -> %s", replace_code, short_code)
        else:
            # Already gone (expired and lazy-deleted, or never existed).
            # Not an error — the new link still went out fine.
            log.info("publish replace target %s already gone", replace_code)

    # ---- response ----------------------------------------------------------
    base = settings.public_base.rstrip("/")
    url = f"{base}/s/{short_code}?t={expires_at_s}&s={sig_hex}"
    cover_url = (
        f"{base}/cache/{short_code}/{cover_relpath}"
        if cover_relpath else None
    )
    return PublishResponse(
        data=PublishOk(
            url=url,
            shortCode=short_code,
            expiresAt=expires_at_s,
            sig=sig_hex,
            coverPhotoUrl=cover_url,
        )
    )


# ---------------------------------------------------------------------------
# GET /api/v1/share/{shortcode}/status
# ---------------------------------------------------------------------------

@router.get("/api/v1/share/{shortcode}/status", response_model=StatusResponse)
async def status_endpoint(shortcode: str) -> StatusResponse:
    row = repo.fetch_publish(shortcode)
    now_s = int(time.time())
    if not row:
        return StatusResponse(code=40401, message="NOT_FOUND_OR_EXPIRED")
    # v0.8: trip 改私密 → 链接已被 owner 撤销，特定 code
    if row.get("revoked_reason") == REVOKE_REASON_PRIVATE:
        return StatusResponse(code=40402, message="REVOKED_BY_OWNER_PRIVATE")
    if row["expires_at_s"] <= now_s:
        # Lazy delete on expired status check too.
        delete_share(shortcode)
        return StatusResponse(code=40401, message="NOT_FOUND_OR_EXPIRED")
    return StatusResponse(
        code=0,
        data=StatusOkData(
            shortCode=shortcode,
            expiresAt=row["expires_at_s"],
            remainingSeconds=row["expires_at_s"] - now_s,
            publishedAt=row["published_at_ms"] // 1000,
        ),
    )


# ---------------------------------------------------------------------------
# POST /api/v1/share/revoke-by-trip — owner toggled trip to private
# ---------------------------------------------------------------------------

@router.post(
    "/api/v1/share/revoke-by-trip",
    response_model=RevokeByTripResponse,
)
async def revoke_by_trip(
    body: RevokeByTripRequest,
    owner_uid: str = Depends(require_share_token),
) -> RevokeByTripResponse:
    """v0.8: Trip 改为私密时由前端调用，关停该 trip 全部分享链接。

    DB 行保留（带 revoked_reason='PRIVATE'）让 viewer 能识别原因显示
    "该用户已设置该路线为私密"；cache 子目录立刻删干净，确保数据真的
    不再可读。

    v1.2: 要求 share_token (HMAC scope=share) 或 dev X-Dev-Uid 头。
    AGC Auth 已接入；tripId 仍由前端传，后续会加 ownerUid 强校验作为二次防御。
    """
    if not body.tripId:
        return RevokeByTripResponse(
            code=40006, message="INVALID_JSON",
            data=RevokeByTripData(tripId="", revokedCount=0),
        )
    codes = revoke_shares_by_trip(body.tripId, REVOKE_REASON_PRIVATE)
    return RevokeByTripResponse(
        code=0, message="ok",
        data=RevokeByTripData(tripId=body.tripId, revokedCount=len(codes)),
    )


# ---------------------------------------------------------------------------
# GET /cache/{shortcode}/{filename} — static photo serving
# ---------------------------------------------------------------------------

@router.get("/cache/{shortcode}/{filename}", include_in_schema=False)
async def cache_serve(shortcode: str, filename: str) -> FileResponse:
    # Defence-in-depth path traversal：只允许两种 inline 文件名：
    #   * {flatIdx}_{w}w.webp     —— viewer 内联用
    #   * cover.jpg               —— v1.0.4 og:image 专用 JPEG 副本
    if "/" in filename or "\\" in filename or filename.startswith("."):
        raise HTTPException(404, "not_found")
    if filename.endswith(".webp"):
        media_type = "image/webp"
    elif filename == "cover.jpg":
        media_type = "image/jpeg"
    else:
        raise HTTPException(404, "not_found")
    full = (_cache_root() / shortcode / filename).resolve()
    root = _cache_root().resolve()
    try:
        full.relative_to(root)
    except ValueError:
        raise HTTPException(404, "not_found")
    if not full.is_file():
        raise HTTPException(404, "not_found")

    # Enforce the link's lifetime: if the parent share has expired, refuse
    # to serve cached photos even if the file hasn't been swept yet.
    row = repo.fetch_publish(shortcode)
    if not row:
        raise HTTPException(404, "not_found")
    # v0.8: trip 改私密时同步删了 cache 子目录，理论上 full.is_file() 会先
    # 返 404；这里再加一层 belt-and-braces，行为一致。
    if row.get("revoked_reason") is not None:
        raise HTTPException(404, "not_found")
    if row["expires_at_s"] <= int(time.time()):
        # Lazy delete: drop the row + all cache files now.
        delete_share(shortcode)
        raise HTTPException(404, "not_found")
    return FileResponse(full, media_type=media_type)
