"""HTML viewer routes.

Three demo viewers (simple / 3D / map) and the spec-compliant publish
viewer all share the `/s/{path}` URL space. Branching rule:

  * `/s/{code}.{sig}`           → demo flow (path contains `.`)
  * `/s/{shortcode}?t=&s=`      → spec /publish flow (path is bare alnum)
  * `/s3d/...` and `/smap/...`  → demo only

Mixing them on the same prefix lets us honour the spec URL shape
(`/s/abc12345?t=...&s=...`) without retiring the demo links that have
already been handed out.
"""
import html as html_lib
import json
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse

from ..core.config import get_settings
from ..core.lifecycle import delete_share
from ..core.poster import compose_poster
from ..core.security import verify_sig_v2
from ..db import repository_publish as repo_publish

router = APIRouter(tags=["viewer"])

_STATIC = Path(__file__).parent.parent / "static"
_VIEWER_SIMPLE = _STATIC / "viewer.html"
_VIEWER_3D = _STATIC / "viewer_3d.html"
_VIEWER_MAP = _STATIC / "viewer_map.html"
_VIEWER_PUBLISH = _STATIC / "viewer_publish.html"
_VIEWER_REPLAY = _STATIC / "viewer_replay.html"     # v0.9
_REPLAY_AUDIO = _STATIC / "replay-audio.mp3"        # v0.9 — 兼容老 URL
_REPLAY_AUDIO_DIR = _STATIC / "replay-audio"        # v1.0 — 多 BGM
# 与 frontend ReplayMusicCatalog 的 enum **value**（小写 wire 值）对齐 —
# 同时也是 static/replay-audio/{id}.mp3 的文件名。
_REPLAY_BGM_IDS = {
    "morning_chill_birds", "city_lights_lofi", "jazz_night",
    "tropical_chill_travel", "cinematic_ambient",
}
_REPLAY_DEFAULT_BGM = "city_lights_lofi"

# Browsers cache aggressively behind cloudflared — no-store keeps edits
# visible on refresh without versioning the assets.
_NOCACHE = {"Cache-Control": "no-store"}


# ---------------------------------------------------------------------------
# /s/{path} — the contested route. Dispatches by whether `path` contains a dot.
# ---------------------------------------------------------------------------

@router.get("/s/{path}", include_in_schema=False)
async def viewer_s_dispatch(
    path: str,
    t: Optional[str] = Query(None),
    s: Optional[str] = Query(None),
):
    if "." in path:
        # Demo flow: legacy /s/{code}.{sig} → simple viewer (client fetches JSON)
        return FileResponse(
            _VIEWER_SIMPLE,
            media_type="text/html; charset=utf-8",
            headers=_NOCACHE,
        )
    return _render_publish_viewer(path, t, s)


@router.get("/s3d/{code_dot_sig}", include_in_schema=False)
async def viewer_3d(code_dot_sig: str) -> FileResponse:
    return FileResponse(
        _VIEWER_3D, media_type="text/html; charset=utf-8", headers=_NOCACHE,
    )


@router.get("/smap/{code_dot_sig}", include_in_schema=False)
async def viewer_map(code_dot_sig: str) -> HTMLResponse:
    """v1.0.6: 同样接 AMap，需要模板注入 key。"""
    settings = get_settings()
    template = _VIEWER_MAP.read_text(encoding="utf-8")
    html = (
        template
        .replace("{{AMAP_KEY}}",          html_lib.escape(settings.amap_key, quote=True))
        .replace("{{AMAP_SECURITY_CODE}}", html_lib.escape(settings.amap_security_code, quote=True))
    )
    return HTMLResponse(html, headers=_NOCACHE)


# ---------------------------------------------------------------------------
# Spec /s/{shortcode} renderer (P08 API 规范 §5)
# ---------------------------------------------------------------------------

# Spec §5.4 dictates HTTP code per failure mode:
# Failure-mode page text per spec §5.4. The "有效期 7 天" parenthetical
# was removed in v0.6.1 — once expiryHours/expiryMinutes were exposed to
# the user (5min / 1d / 7d / 30d), claiming "7 天" on every expired page
# would be misleading.
_ERR_404 = ("页面不存在", 404)
_ERR_403 = ("此链接无效或已过期", 403)
_ERR_410 = ("此链接已过期", 410)
# v0.8: trip 改为私密时 owner 撤销了此分享，仍用 410（资源已不可达），
# 文案说明具体原因，与"自然过期"区分开。
_ERR_PRIVATE = ("该用户已设置该路线为私密", 410)
# v1.2: 内容审查命中（异步 audit 后 BackgroundTask 把行标为 rejected）。
# 既不暴露具体命中词，也明确告诉用户和接收方"为什么打不开"。
_ERR_CONTENT_VIOLATION = ("该分享因内容审核未通过已下线", 410)


def _err_html(text: str, status_code: int) -> HTMLResponse:
    body = (
        f'<!DOCTYPE html><html lang="zh-CN"><head>'
        f'<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>链接已失效</title>'
        f'<style>body{{font-family:-apple-system,sans-serif;background:#0a0a0f;color:#e8e8ed;'
        f'min-height:100vh;display:flex;align-items:center;justify-content:center;'
        f'flex-direction:column;padding:32px;text-align:center;}}'
        f'h1{{font-size:22px;margin-bottom:12px;}}p{{color:#86868b;}}</style>'
        f'</head><body><h1>{text}</h1>'
        f'<p>请向分享者重新索取链接。</p></body></html>'
    )
    return HTMLResponse(body, status_code=status_code, headers=_NOCACHE)


def _validate_and_fetch_share(
    short_code: str,
    t: Optional[str],
    s: Optional[str],
):
    """Validate the URL signature + fetch the share row.

    Returns the row (dict) on success, or an HTMLResponse error on
    failure (caller should return it directly).

    Centralized so /s/{...} (publish viewer) and /sreplay/{...}
    (replay viewer, v0.9) share the same auth pipeline.
    """
    if not t or not s:
        return _err_html(*_ERR_403)
    try:
        expiry_s = int(t)
    except ValueError:
        return _err_html(*_ERR_403)
    settings = get_settings()
    if not verify_sig_v2(settings.share_hmac_key, short_code, expiry_s, s):
        return _err_html(*_ERR_403)
    row = repo_publish.fetch_publish(short_code)
    if row is None:
        return _err_html(*_ERR_404)
    if row["sig_hex"] != s.lower() or row["expires_at_s"] != expiry_s:
        return _err_html(*_ERR_403)
    if row.get("revoked_reason") == "PRIVATE":
        return _err_html(*_ERR_PRIVATE)
    if row.get("revoked_reason") == "CONTENT_VIOLATION":
        return _err_html(*_ERR_CONTENT_VIOLATION)
    if row["expires_at_s"] <= int(time.time()):
        delete_share(short_code)
        return _err_html(*_ERR_410)
    return row


def _build_route_data(short_code: str, row: dict) -> dict:
    """Build the ShareRouteData payload that gets inlined into
    window.__ROUTE_DATA__ in any of the publish-flow viewers."""
    settings = get_settings()
    trip = json.loads(row["trip_data_json"])
    photo_index = json.loads(row["photo_index_json"])
    base = settings.public_base.rstrip("/")

    nodes_in: list[dict] = sorted(
        trip.get("nodes") or [], key=lambda n: n.get("nodeOrder", 0)
    )
    nodes_out: list[dict] = []
    for n in nodes_in:
        node_photos: list[dict] = []
        for entry in photo_index:
            if entry["nodeOrder"] != n.get("nodeOrder"):
                continue
            for w_str_or_int, rel in entry["paths"].items():
                w = int(w_str_or_int)
                node_photos.append({
                    "url": f"{base}/cache/{short_code}/{rel}",
                    "width": w,
                })
        # v0.9: 加 latitude/longitude（Phase 2 schema），replay viewer 用 —
        # 没收到坐标的旧 publish 数据这两个字段会是 None，前端要兼容。
        nodes_out.append({
            "id": n.get("id", ""),
            "title": n.get("title", ""),
            "content": n.get("content", ""),
            "poiName": n.get("poiName", ""),
            "photos": node_photos,
            "mood": n.get("mood", ""),
            "tags": n.get("tags") or [],
            "nodeOrder": n.get("nodeOrder", 0),
            "latitude": n.get("latitude"),
            "longitude": n.get("longitude"),
            "visitedAt": n.get("visitedAt"),
        })

    cover_url = (
        f"{base}/cache/{short_code}/{row['cover_relpath']}"
        if row["cover_relpath"] else ""
    )
    return {
        "tripId":         trip.get("tripId", ""),
        "tripName":       trip.get("tripName", ""),
        "totalDistance":  trip.get("totalDistance", 0),
        "nodeCount":      len(nodes_out),
        "coverPhotoUrl":  cover_url,
        "createdAt":      trip.get("createdAt", 0),
        "expiresAt":      row["expires_at_s"],
        "nodes":          nodes_out,
    }


def _render_publish_viewer(
    short_code: str,
    t: Optional[str],
    s: Optional[str],
) -> HTMLResponse:
    fetched = _validate_and_fetch_share(short_code, t, s)
    if isinstance(fetched, HTMLResponse):
        return fetched
    row = fetched
    route_data = _build_route_data(short_code, row)
    settings = get_settings()
    base = settings.public_base.rstrip("/")
    nodes_out = route_data["nodes"]
    trip_name = route_data["tripName"] or "ItsMapPin 分享"

    # Inline JSON has to survive being inside `<script>...</script>`. Two
    # particular escapes matter: `</script>` (would close early) and
    # `<!--`/`-->` (HTML comment trickery). The rest is plain JSON.
    payload = (
        json.dumps(route_data, ensure_ascii=False, separators=(",", ":"))
        .replace("</", "<\\/")
        .replace("<!--", "<\\!--")
        .replace("-->", "--\\>")
    )

    # ---- v0.7: build OG / social-meta values for the template ------------
    html_title = f"{trip_name} - ItsMapPin"
    description = _build_share_description(
        trip_name=trip_name,
        total_distance=route_data["totalDistance"],
        node_count=len(nodes_out),
        first_node_poi=(nodes_out[0]["poiName"] if nodes_out else ""),
        nodes=nodes_out,
    )
    share_url = f"{base}/s/{short_code}?t={row['expires_at_s']}&s={row['sig_hex']}"
    # v0.9.2: 同 short_code + sig 的 replay URL，前端用 iframe 嵌进 publish viewer
    replay_url = f"{base}/sreplay/{short_code}?t={row['expires_at_s']}&s={row['sig_hex']}"

    template = _VIEWER_PUBLISH.read_text(encoding="utf-8")
    html = (
        template
        .replace("{{ROUTE_DATA_JSON}}", payload)
        # HTML-attribute-safe escape for the meta tag values.
        .replace("{{HTML_TITLE}}",        html_lib.escape(html_title, quote=True))
        .replace("{{SHARE_DESCRIPTION}}", html_lib.escape(description, quote=True))
        .replace("{{COVER_PHOTO_URL}}",   html_lib.escape(route_data["coverPhotoUrl"], quote=True))
        .replace("{{SHARE_URL}}",         html_lib.escape(share_url, quote=True))
        .replace("{{REPLAY_URL}}",        html_lib.escape(replay_url, quote=True))
    )

    # Bump view_count — spec doesn't mandate it but the demo flow does so,
    # and it's useful telemetry. Also keeps the two flows symmetric.
    repo_publish.increment_view_count(short_code)

    return HTMLResponse(html, status_code=200, headers=_NOCACHE)


# ---------------------------------------------------------------------------
# v0.9: GET /sreplay/{shortcode}?t=&s= — replay viewer (Plan A)
# ---------------------------------------------------------------------------

@router.get("/sreplay/{shortcode}", include_in_schema=False)
async def viewer_replay(
    shortcode: str,
    t: Optional[str] = Query(None),
    s: Optional[str] = Query(None),
):
    """v0.9: Plan A 路线回放 viewer。
    复用 publish 流程的 sig+expiry+revoke 校验，server-render 回放页面。
    时序状态机和 TripReplayPage 完全对齐：
      FADE_IN 2s → STAYING 3s → FADE_OUT 1s → MOVING 1.5s
    地图引擎用 Leaflet（与 viewer_map.html 一致），暂不上 3D bearing/tilt。
    """
    fetched = _validate_and_fetch_share(shortcode, t, s)
    if isinstance(fetched, HTMLResponse):
        return fetched
    row = fetched
    route_data = _build_route_data(shortcode, row)
    settings = get_settings()
    base = settings.public_base.rstrip("/")
    nodes_out = route_data["nodes"]
    trip_name = route_data["tripName"] or "ItsMapPin 分享"

    payload = (
        json.dumps(route_data, ensure_ascii=False, separators=(",", ":"))
        .replace("</", "<\\/")
        .replace("<!--", "<\\!--")
        .replace("-->", "--\\>")
    )

    html_title = f"{trip_name} · 路线回放"
    description = _build_share_description(
        trip_name=trip_name,
        total_distance=route_data["totalDistance"],
        node_count=len(nodes_out),
        first_node_poi=(nodes_out[0]["poiName"] if nodes_out else ""),
        nodes=nodes_out,
    )
    share_url = f"{base}/sreplay/{shortcode}?t={row['expires_at_s']}&s={row['sig_hex']}"

    # v1.0: 读 replay_prefs，按 bgmId 选 BGM 文件；prefs 注入 __REPLAY_PREFS__
    prefs_raw = row.get("replay_prefs_json")
    if prefs_raw:
        try:
            prefs = json.loads(prefs_raw)
        except Exception:
            prefs = {}
    else:
        prefs = {}
    bgm_id = prefs.get("bgmId") if prefs.get("bgmId") in _REPLAY_BGM_IDS \
        else _REPLAY_DEFAULT_BGM
    audio_url = f"{base}/assets/replay-audio/{bgm_id}.mp3"
    prefs_payload = (
        json.dumps(prefs, ensure_ascii=False, separators=(",", ":"))
        .replace("</", "<\\/")
        .replace("<!--", "<\\!--")
        .replace("-->", "--\\>")
    )

    template = _VIEWER_REPLAY.read_text(encoding="utf-8")
    html = (
        template
        .replace("{{ROUTE_DATA_JSON}}",   payload)
        .replace("{{REPLAY_PREFS_JSON}}", prefs_payload if prefs_payload != "{}" else "null")
        .replace("{{HTML_TITLE}}",        html_lib.escape(html_title, quote=True))
        .replace("{{SHARE_DESCRIPTION}}", html_lib.escape(description, quote=True))
        .replace("{{COVER_PHOTO_URL}}",   html_lib.escape(route_data["coverPhotoUrl"], quote=True))
        .replace("{{SHARE_URL}}",         html_lib.escape(share_url, quote=True))
        .replace("{{AUDIO_URL}}",         html_lib.escape(audio_url, quote=True))
        .replace("{{AMAP_KEY}}",          html_lib.escape(settings.amap_key, quote=True))
        .replace("{{AMAP_SECURITY_CODE}}", html_lib.escape(settings.amap_security_code, quote=True))
    )
    repo_publish.increment_view_count(shortcode)
    return HTMLResponse(html, status_code=200, headers=_NOCACHE)


# ---------------------------------------------------------------------------
# v0.9: GET /assets/replay-audio.mp3 — background music for replay viewer
# ---------------------------------------------------------------------------

@router.get("/assets/replay-audio.mp3", include_in_schema=False)
async def replay_audio_legacy() -> FileResponse:
    """v0.9 旧路径：单文件背景音乐。
    保留是为了兼容 v0.9 publish 出去的旧 HTML — 那些 HTML 里硬编码了
    /assets/replay-audio.mp3。新发布的 viewer_replay 都走 v1.0 的
    /assets/replay-audio/{bgmId}.mp3。"""
    if not _REPLAY_AUDIO.is_file():
        raise HTTPException(404, "audio_not_found")
    return FileResponse(
        _REPLAY_AUDIO,
        media_type="audio/mpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


# ---------------------------------------------------------------------------
# v1.1: 分享海报（QR + 封面 + 标题 + 路线预览）
# ---------------------------------------------------------------------------
# 两条路：
#   * GET /share/{code}/qrcode.png  纯 QR PNG（透明背景候选；目前白底黑码）
#   * GET /share/{code}/poster.jpg  完整海报 JPG（750×1334）
#
# 鉴权用同一套 sig+expiry，与 /s, /sreplay 一致。海报第一次请求时合成，
# 落盘到 cache/{code}/poster.jpg；后续请求直接 FileResponse。share 撤销 /
# 自然过期时整个 cache 子目录被 rmtree，海报跟着清掉。
# ---------------------------------------------------------------------------

@router.get("/share/{shortcode}/qrcode.png", include_in_schema=False)
async def share_qrcode(
    shortcode: str,
    t: Optional[str] = Query(None),
    s: Optional[str] = Query(None),
):
    fetched = _validate_and_fetch_share(shortcode, t, s)
    if isinstance(fetched, HTMLResponse):
        return fetched
    row = fetched
    settings = get_settings()
    base = settings.public_base.rstrip("/")
    share_url = (
        f"{base}/s/{shortcode}?t={row['expires_at_s']}&s={row['sig_hex']}"
    )
    # qrcode → PNG bytes
    import io as _io
    import qrcode as _qrcode
    qr = _qrcode.QRCode(
        version=None,
        error_correction=_qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=2,
    )
    qr.add_data(share_url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#111111", back_color="#FFFFFF").convert("RGB")
    buf = _io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    from fastapi.responses import Response
    return Response(
        content=buf.getvalue(),
        media_type="image/png",
        headers={"Cache-Control": "public, max-age=3600"},
    )


@router.get("/share/{shortcode}/poster.jpg", include_in_schema=False)
async def share_poster(
    shortcode: str,
    t: Optional[str] = Query(None),
    s: Optional[str] = Query(None),
):
    fetched = _validate_and_fetch_share(shortcode, t, s)
    if isinstance(fetched, HTMLResponse):
        return fetched
    row = fetched

    settings = get_settings()
    # poster 落盘路径：与 cover.jpg 同目录。orphans 跟随整个 cache 子目录被清。
    cache_dir = Path(settings.db_path).resolve().parent / "cache" / shortcode
    poster_path = cache_dir / "poster.jpg"

    # 已合成过 → 直接复用。改了 trip 数据需 republish；本身海报内容跟 row 一一对应。
    if poster_path.is_file():
        return FileResponse(
            poster_path,
            media_type="image/jpeg",
            headers={"Cache-Control": "public, max-age=3600"},
        )

    # 合成所需材料
    route_data = _build_route_data(shortcode, row)
    base = settings.public_base.rstrip("/")
    share_url = f"{base}/s/{shortcode}?t={row['expires_at_s']}&s={row['sig_hex']}"
    cover_path: Optional[Path] = None
    if row.get("cover_relpath"):
        candidate = cache_dir / row["cover_relpath"]
        if candidate.is_file():
            cover_path = candidate

    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        poster_bytes = compose_poster(
            share_url=share_url,
            trip_name=route_data.get("tripName", "") or "ItsMapPin 分享",
            node_count=len(route_data.get("nodes") or []),
            total_distance=float(route_data.get("totalDistance") or 0),
            route_preview=_build_route_preview(route_data.get("nodes") or []),
            cover_path=cover_path,
        )
        poster_path.write_bytes(poster_bytes)
    except Exception as e:
        raise HTTPException(500, f"poster_compose_failed: {e}")

    return FileResponse(
        poster_path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=3600"},
    )


# ---------------------------------------------------------------------------
# v1.0: BGM 资源（保留以兼容老链接）
# ---------------------------------------------------------------------------

@router.get("/assets/replay-audio/{bgm_id}.mp3", include_in_schema=False)
async def replay_audio_v1(bgm_id: str) -> FileResponse:
    """v1.0: 多 BGM 背景音乐。bgmId 必须在白名单内，否则 404 防 path traversal。
    对应文件：static/replay-audio/{bgmId}.mp3"""
    if bgm_id not in _REPLAY_BGM_IDS:
        raise HTTPException(404, "audio_not_found")
    full = (_REPLAY_AUDIO_DIR / f"{bgm_id}.mp3").resolve()
    # 二次确认 path traversal（即使 bgm_id 能通过 set 过滤也保险一手）
    try:
        full.relative_to(_REPLAY_AUDIO_DIR.resolve())
    except ValueError:
        raise HTTPException(404, "audio_not_found")
    if not full.is_file():
        raise HTTPException(404, "audio_not_found")
    return FileResponse(
        full,
        media_type="audio/mpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


def _build_route_preview(nodes: list[dict]) -> str:
    """前 3 个节点 POI / title 用 " → " 连接，>3 个尾接 "…"。
    单段限 8 字，超长省略。空列表 / 全无名字 → 返回空串。
    共享给 og:description 和 poster 两条路。"""
    names: list[str] = []
    for n in nodes[:3]:
        name = (n.get("poiName") or n.get("title") or "").strip()
        if not name:
            continue
        if len(name) > 8:
            name = name[:8] + "…"
        names.append(name)
    if not names:
        return ""
    preview = " → ".join(names)
    if len(nodes) > 3:
        preview += " → …"
    return preview


def _build_share_description(
    trip_name: str,
    total_distance: float,
    node_count: int,
    first_node_poi: str,
    nodes: Optional[list[dict]] = None,
) -> str:
    """Compose the og:description / meta description value.

    v1.0.2 增强（微信卡片之前太空）：
      ① 节点数 · 总距离  ←前置 chip
      ② 路线预览：前 3 个节点的 POI / 标题用 → 串起来；多于 3 个尾接"…"
      ③ 第一节点的 mood 当氛围 chip（如有）
      ④ 收尾标识"ItsMapPin 旅行回放"
    保持 ~140 字以内（微信描述大约 120-150 截断）；不做 HTML 实体（调用方
    用 html.escape 包一层）。"""
    nodes = nodes or []

    # ① count + distance
    chip_parts: list[str] = []
    if node_count:
        chip_parts.append(f"{node_count} 节点")
    if total_distance and total_distance > 0:
        chip_parts.append(f"{total_distance:.1f}km")

    # ② 路线预览：共享 _build_route_preview，避免和 poster 不一致
    preview = _build_route_preview(nodes)

    # ③ 首节点 mood
    mood = ""
    if nodes:
        mood = (nodes[0].get("mood") or "").strip()
        if len(mood) > 6:                # 防止用户把 mood 当 note 写
            mood = mood[:6]

    parts: list[str] = []
    if chip_parts:
        parts.append(" · ".join(chip_parts))
    if preview:
        parts.append(preview)
    if mood:
        parts.append(f"#{mood}")
    parts.append("ItsMapPin 旅行回放")
    desc = "  ".join(parts) if parts else f"{trip_name} · ItsMapPin 分享"
    # 兜底裁剪到 150（避免极端长 trip_name 撑爆）
    return desc[:150]
