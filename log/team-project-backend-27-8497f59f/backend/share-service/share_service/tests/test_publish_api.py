"""End-to-end tests for the spec-compliant publish flow (P08 API 规范)."""
from __future__ import annotations

import io
import json
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from share_service.main import app
from share_service.core.security import compute_sig_v2, verify_sig_v2

client = TestClient(app)
_AUTH = {"X-Dev-Uid": "test"}


def _jpeg(width: int = 800, height: int = 600, color=(220, 90, 60)) -> bytes:
    """Build a tiny in-memory JPEG so multipart tests don't need fixture files."""
    img = Image.new("RGB", (width, height), color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return buf.getvalue()


def _trip(node_photo_counts=(2, 1)) -> dict:
    nodes = []
    for i, c in enumerate(node_photo_counts):
        nodes.append({
            "id": f"node_{i:03d}",
            "title": f"节点 {i}",
            "content": f"这是节点 {i} 的笔记。",
            "poiName": f"POI {i}",
            "photoCount": c,
            "mood": "惬意" if i % 2 == 0 else "感动",
            "tags": ["test", f"day{i}"],
            "visitedAt": 1714200000000 + i * 86400000,
            "nodeOrder": i,
        })
    return {
        "tripId": "trip_test_001",
        "tripName": "测试路线",
        "totalDistance": 12.5,
        "coverIndex": 0,
        "createdAt": 1714200000000,
        "nodes": nodes,
    }


def _multipart(trip: dict, photos: list[bytes], expiry_hours: int = 168):
    files = [("tripData", (None, json.dumps(trip), "text/plain"))]
    for i, p in enumerate(photos):
        files.append((f"photo_{i}", (f"photo_{i}.jpg", p, "image/jpeg")))
    files.append(("expiryHours", (None, str(expiry_hours), "text/plain")))
    return files


# ===========================================================================
# HMAC v2
# ===========================================================================

KEY = b"unit-test-key-please-replace-in-prod-32b"


def test_sigv2_is_64_char_hex():
    sig = compute_sig_v2(KEY, "abc12345", 1714800000)
    assert len(sig) == 64
    assert all(c in "0123456789abcdef" for c in sig)


def test_sigv2_msg_format_matches_spec():
    # Spec §7.1 — message MUST be `{shortCode}:{expiry}`.
    import hmac, hashlib
    short_code = "abc12345"
    expiry = 1714800000
    expected = hmac.new(
        KEY, f"{short_code}:{expiry}".encode("utf-8"), hashlib.sha256
    ).hexdigest()
    assert compute_sig_v2(KEY, short_code, expiry) == expected


def test_sigv2_verify_roundtrip():
    sig = compute_sig_v2(KEY, "abc12345", 1714800000)
    assert verify_sig_v2(KEY, "abc12345", 1714800000, sig)
    assert not verify_sig_v2(KEY, "abc12345", 1714800001, sig)
    assert not verify_sig_v2(KEY, "abc12346", 1714800000, sig)
    assert not verify_sig_v2(b"other-key", "abc12345", 1714800000, sig)


def test_sigv2_rejects_short_or_empty_sig():
    assert not verify_sig_v2(KEY, "abc12345", 1, "")
    assert not verify_sig_v2(KEY, "abc12345", 1, "abcd")


# ===========================================================================
# POST /api/v1/share/publish — happy path
# ===========================================================================

def test_publish_happy_path_returns_spec_envelope():
    trip = _trip(node_photo_counts=(2, 1))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [_jpeg(), _jpeg(), _jpeg()]),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["code"] == 0
    assert body["message"] == "ok"
    data = body["data"]
    assert len(data["shortCode"]) == 8
    assert "?t=" in data["url"] and "&s=" in data["url"]
    # url should not contain a dot in the path component (spec §5.1)
    path = data["url"].split("?")[0]
    assert "." not in path.rsplit("/", 1)[-1]
    assert data["expiresAt"] > int(time.time())


def test_publish_link_renders_via_viewer():
    trip = _trip(node_photo_counts=(1,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [_jpeg()]),
    )
    body = r.json()["data"]
    code = body["shortCode"]
    expires = body["expiresAt"]
    sig = body["url"].split("&s=")[-1]

    # The URL goes to /s/{code}?t=&s= → spec viewer renders HTML with
    # window.__ROUTE_DATA__ inlined
    r2 = client.get(f"/s/{code}?t={expires}&s={sig}")
    assert r2.status_code == 200
    assert "text/html" in r2.headers["content-type"]
    html = r2.text
    assert "__ROUTE_DATA__" in html
    assert trip["tripName"] in html
    # Should NOT still contain the placeholder
    assert "{{ROUTE_DATA_JSON}}" not in html


# ===========================================================================
# Validation errors (spec §4.5 error codes)
# ===========================================================================

def test_publish_invalid_photo_count_400_40001():
    trip = _trip(node_photo_counts=(2, 1))  # expects 3
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [_jpeg(), _jpeg()]),  # only 2
    )
    assert r.status_code == 400
    assert r.json()["code"] == 40001
    assert r.json()["message"] == "INVALID_PHOTO_COUNT"


def test_publish_empty_nodes_400_40002():
    trip = _trip(node_photo_counts=())
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    assert r.status_code == 400
    assert r.json()["code"] == 40002


def test_publish_too_many_nodes_400_40003():
    trip = _trip(node_photo_counts=tuple([0] * 31))  # 31 > 30
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    assert r.status_code == 400
    assert r.json()["code"] == 40003


def test_publish_invalid_json_400_40006():
    files = [
        ("tripData", (None, "this is not json", "text/plain")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    assert r.status_code == 400
    assert r.json()["code"] == 40006


def test_publish_invalid_expiry_400_40007():
    trip = _trip(node_photo_counts=(0,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [], expiry_hours=999),
    )
    assert r.status_code == 400
    assert r.json()["code"] == 40007


# ===========================================================================
# expiryMinutes (v0.5)
# ===========================================================================

def _multipart_minutes(trip: dict, photos: list[bytes], minutes: int):
    files = [("tripData", (None, json.dumps(trip), "text/plain"))]
    for i, p in enumerate(photos):
        files.append((f"photo_{i}", (f"photo_{i}.jpg", p, "image/jpeg")))
    files.append(("expiryMinutes", (None, str(minutes), "text/plain")))
    return files


def test_publish_with_expiry_minutes_5():
    """5-minute window — supports the dev/test option in the picker."""
    trip = _trip(node_photo_counts=(0,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_minutes(trip, [], 5),
    )
    assert r.status_code == 201
    body = r.json()["data"]
    delta = body["expiresAt"] - int(time.time())
    # 5 min = 300s, allow ±30s slack for test fixture overhead
    assert 270 <= delta <= 330


def test_publish_minutes_takes_precedence_over_hours():
    """If both fields are sent, expiryMinutes wins."""
    trip = _trip(node_photo_counts=(0,))
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("expiryMinutes", (None, "5", "text/plain")),
        ("expiryHours", (None, "168", "text/plain")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    assert r.status_code == 201
    delta = r.json()["data"]["expiresAt"] - int(time.time())
    assert delta < 600  # 10 min, way below 168h


def test_publish_below_min_expiry_400():
    """0 minutes is below the 60s floor."""
    trip = _trip(node_photo_counts=(0,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_minutes(trip, [], 0),
    )
    assert r.status_code == 400
    assert r.json()["code"] == 40007


# ===========================================================================
# replaceShortCode (v0.6) — auto-revoke previous link on republish
# ===========================================================================

def _multipart_with_replace(
    trip: dict, photos: list[bytes],
    replace_code: str, replace_expiry: int, replace_sig: str,
    expiry_minutes: int = 5,
):
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("expiryMinutes", (None, str(expiry_minutes), "text/plain")),
        ("replaceShortCode", (None, replace_code, "text/plain")),
        ("replaceExpiry",    (None, str(replace_expiry), "text/plain")),
        ("replaceSig",       (None, replace_sig, "text/plain")),
    ]
    for i, p in enumerate(photos):
        files.append((f"photo_{i}", (f"photo_{i}.jpg", p, "image/jpeg")))
    return files


def _publish_one(node_photo_counts=(1,), expiry_minutes: int = 60):
    trip = _trip(node_photo_counts=node_photo_counts)
    photos = [_jpeg() for _ in range(sum(node_photo_counts))]
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_minutes(trip, photos, expiry_minutes),
    )
    assert r.status_code == 201, r.text
    return r.json()["data"]   # { url, shortCode, expiresAt, sig }


def test_replace_happy_path_revokes_old_after_new_succeeds():
    from share_service.db import repository_publish as repo
    old = _publish_one()
    old_code = old["shortCode"]
    assert repo.fetch_publish(old_code) is not None

    trip = _trip(node_photo_counts=(1,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_with_replace(
            trip, [_jpeg()],
            replace_code=old_code,
            replace_expiry=old["expiresAt"],
            replace_sig=old["sig"],
        ),
    )
    assert r.status_code == 201
    new_code = r.json()["data"]["shortCode"]
    assert new_code != old_code
    # old must be gone now
    assert repo.fetch_publish(old_code) is None
    # new must exist
    assert repo.fetch_publish(new_code) is not None


def test_replace_bad_sig_rejects_400_and_old_preserved():
    from share_service.db import repository_publish as repo
    old = _publish_one()
    trip = _trip(node_photo_counts=(1,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_with_replace(
            trip, [_jpeg()],
            replace_code=old["shortCode"],
            replace_expiry=old["expiresAt"],
            replace_sig="0" * 64,   # forged
        ),
    )
    assert r.status_code == 400
    assert r.json()["code"] == 40006
    # old still alive
    assert repo.fetch_publish(old["shortCode"]) is not None


def test_replace_missing_companion_field_400():
    """replaceShortCode without replaceExpiry+replaceSig → 40006."""
    trip = _trip(node_photo_counts=(0,))
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("expiryMinutes", (None, "5", "text/plain")),
        ("replaceShortCode", (None, "AAAAAAAA", "text/plain")),
        # no replaceExpiry / replaceSig
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    assert r.status_code == 400
    assert r.json()["code"] == 40006


def test_replace_target_already_gone_is_not_an_error():
    """If the previous link already expired (lazy-deleted), the new
    publish should still succeed — the replace is best-effort cleanup."""
    from share_service.core.security import compute_sig_v2
    from share_service.core.config import get_settings
    # Construct a valid sig for a code that doesn't exist in DB
    nonexistent_code = "GHOSTAAA"
    expiry = int(time.time()) + 3600
    sig = compute_sig_v2(get_settings().share_hmac_key, nonexistent_code, expiry)

    trip = _trip(node_photo_counts=(1,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_with_replace(
            trip, [_jpeg()],
            replace_code=nonexistent_code,
            replace_expiry=expiry,
            replace_sig=sig,
        ),
    )
    # New publish succeeds even though "old" was a ghost.
    assert r.status_code == 201


def test_replace_atomicity_when_new_publish_fails(monkeypatch):
    """If the new publish fails (e.g. DB insert blows up), the old link
    must be preserved — caller's existing share should still work."""
    from share_service.db import repository_publish as repo
    from share_service.routers import publish as publish_router

    old = _publish_one()
    old_code = old["shortCode"]

    real_insert = repo.insert_publish

    def boom(_row):
        raise RuntimeError("simulated db failure")

    monkeypatch.setattr(repo, "insert_publish", boom)
    monkeypatch.setattr(publish_router.repo, "insert_publish", boom)

    trip = _trip(node_photo_counts=(1,))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart_with_replace(
            trip, [_jpeg()],
            replace_code=old_code,
            replace_expiry=old["expiresAt"],
            replace_sig=old["sig"],
        ),
    )
    assert r.status_code == 500

    # Restore the real insert so subsequent tests aren't broken
    monkeypatch.setattr(repo, "insert_publish", real_insert)
    monkeypatch.setattr(publish_router.repo, "insert_publish", real_insert)

    # Old link MUST still be alive
    assert repo.fetch_publish(old_code) is not None


def test_publish_response_includes_sig_field():
    """v0.6 response model exposes `sig` so clients can pass it back as
    replaceSig without parsing the URL."""
    data = _publish_one()
    assert "sig" in data
    assert len(data["sig"]) == 64
    assert data["sig"] in data["url"]


def test_publish_response_includes_cover_photo_url_when_photos_present():
    """v0.7.1: response carries coverPhotoUrl so frontend can fetch it as
    ArrayBuffer to use as systemShare thumbnail (QQ-compatible card preview).
    v1.0.4: cover 改为 cover.jpg（专门给 og:image 用，WeChat/QQ 卡片爬虫
    对 WebP 支持不稳；inline viewer 仍用 WebP variants 走 photo_index）。"""
    data = _publish_one(node_photo_counts=(1,))
    assert "coverPhotoUrl" in data
    assert data["coverPhotoUrl"] is not None
    assert "/cache/" in data["coverPhotoUrl"]
    assert data["coverPhotoUrl"].endswith("/cover.jpg")


def test_publish_response_cover_photo_url_null_when_no_photos():
    """0 photos → no cover, coverPhotoUrl is null (not an empty string)."""
    trip = _trip(node_photo_counts=(0,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    data = r.json()["data"]
    assert data.get("coverPhotoUrl") is None


# ===========================================================================
# revoke-by-trip (v0.8) — Trip 改私密 → 全部分享立刻失效
# ===========================================================================

def test_revoke_by_trip_marks_all_shares_for_that_trip():
    """同一 tripId 发的两条分享，调一次 revoke-by-trip 全部失活。
    其它 tripId 的分享不受影响。"""
    from share_service.db import repository_publish as repo

    # 同一 tripId 的两次发布（不同 expiry，都是新的 shortCode）
    trip_a = _trip(node_photo_counts=(1,))
    trip_a["tripId"] = "trip_target"
    r1 = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip_a, [_jpeg()]))
    code1 = r1.json()["data"]["shortCode"]

    r2 = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip_a, [_jpeg()]))
    code2 = r2.json()["data"]["shortCode"]

    # 一条另外 trip 的分享，不该被牵连
    trip_b = _trip(node_photo_counts=(1,))
    trip_b["tripId"] = "trip_bystander"
    r3 = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip_b, [_jpeg()]))
    code3 = r3.json()["data"]["shortCode"]

    # 调撤销
    rv = client.post(
        "/api/v1/share/revoke-by-trip",
        headers=_AUTH,
        json={"tripId": "trip_target"},
    )
    assert rv.status_code == 200
    body = rv.json()
    assert body["code"] == 0
    assert body["data"]["tripId"] == "trip_target"
    assert body["data"]["revokedCount"] == 2

    # 两条 target 都标了 PRIVATE
    assert repo.fetch_publish(code1)["revoked_reason"] == "PRIVATE"
    assert repo.fetch_publish(code2)["revoked_reason"] == "PRIVATE"
    # bystander 没动
    assert repo.fetch_publish(code3)["revoked_reason"] is None

    # 各自的 cache 子目录：target 的两个被删，bystander 的还在
    assert not _cache_dir_for(code1).exists()
    assert not _cache_dir_for(code2).exists()
    assert _cache_dir_for(code3).exists()


def test_revoke_by_trip_then_viewer_returns_specific_private_text():
    """规范要求：访问被撤销链接应该看到'该用户已设置该路线为私密'，
    不是泛泛的'此链接已过期'。"""
    trip = _trip(node_photo_counts=(1,))
    trip["tripId"] = "trip_priv_test"
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    body = r.json()["data"]
    code = body["shortCode"]

    client.post("/api/v1/share/revoke-by-trip", headers=_AUTH, json={"tripId": "trip_priv_test"})

    r2 = client.get(f"/s/{code}?t={body['expiresAt']}&s={body['sig']}")
    assert r2.status_code == 410
    assert "该用户已设置该路线为私密" in r2.text
    # 不应再带过期相关字样
    assert "此链接已过期" not in r2.text


def test_revoke_by_trip_status_endpoint_returns_40402():
    trip = _trip(node_photo_counts=(0,))
    trip["tripId"] = "trip_priv_status"
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    code = r.json()["data"]["shortCode"]

    client.post("/api/v1/share/revoke-by-trip", headers=_AUTH, json={"tripId": "trip_priv_status"})

    rs = client.get(f"/api/v1/share/{code}/status")
    assert rs.json()["code"] == 40402
    assert "PRIVATE" in rs.json()["message"]


def test_revoke_by_trip_cache_route_returns_404():
    trip = _trip(node_photo_counts=(1,))
    trip["tripId"] = "trip_priv_cache"
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    code = r.json()["data"]["shortCode"]

    client.post("/api/v1/share/revoke-by-trip", headers=_AUTH, json={"tripId": "trip_priv_cache"})

    rc = client.get(f"/cache/{code}/0_375w.webp")
    assert rc.status_code == 404


def test_revoke_by_trip_no_match_is_zero_count_no_error():
    """tripId 没对应任何 share — 不算错误，revokedCount=0。"""
    rv = client.post(
        "/api/v1/share/revoke-by-trip",
        headers=_AUTH,
        json={"tripId": "trip_does_not_exist"},
    )
    assert rv.status_code == 200
    assert rv.json()["data"]["revokedCount"] == 0


# ===========================================================================
# Replay viewer (v0.9) — Plan A
# ===========================================================================

def _trip_with_coords(node_photo_counts=(1,)):
    """trip helper — replay viewer 需要节点有 lat/lng，否则会 fallback 到错误页。"""
    nodes = []
    for i, c in enumerate(node_photo_counts):
        nodes.append({
            "id": f"node_{i:03d}",
            "title": f"节点 {i}",
            "content": f"节点 {i} 的笔记。",
            "poiName": f"POI {i}",
            "photoCount": c,
            "mood": "惬意",
            "tags": ["replay"],
            "visitedAt": 1714200000000 + i * 86400000,
            "nodeOrder": i,
            "latitude": 22.5 + i * 0.01,
            "longitude": 113.9 + i * 0.01,
        })
    return {
        "tripId": "trip_replay_test",
        "tripName": "回放测试",
        "totalDistance": 5.0,
        "coverIndex": 0,
        "createdAt": 1714200000000,
        "nodes": nodes,
    }


def test_replay_viewer_serves_html_with_route_data():
    trip = _trip_with_coords(node_photo_counts=(1, 1))
    photos = [_jpeg(), _jpeg()]
    # publish via the real /publish endpoint so all the data goes through
    files = [("tripData", (None, json.dumps(trip), "text/plain"))]
    for i, p in enumerate(photos):
        files.append((f"photo_{i}", (f"p{i}.jpg", p, "image/jpeg")))
    files.append(("expiryHours", (None, "168", "text/plain")))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    body = r.json()["data"]

    rep = client.get(f"/sreplay/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    assert rep.status_code == 200
    html = rep.text
    # 关键页面元素都在
    assert "leaflet" in html.lower()
    assert "__ROUTE_DATA__" in html
    assert "回放测试" in html
    # 经纬度被注入
    assert "22.5" in html
    # 占位符不应漏出
    assert "{{ROUTE_DATA_JSON}}" not in html
    assert "{{HTML_TITLE}}" not in html
    assert "{{AUDIO_URL}}" not in html


def test_replay_viewer_includes_audio_url():
    trip = _trip_with_coords(node_photo_counts=(1,))
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("photo_0", ("p.jpg", _jpeg(), "image/jpeg")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    body = r.json()["data"]
    rep = client.get(f"/sreplay/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    assert "/assets/replay-audio.mp3" in rep.text


def test_replay_viewer_403_on_bad_sig():
    trip = _trip_with_coords(node_photo_counts=(0,))
    files = [("tripData", (None, json.dumps(trip), "text/plain"))]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    body = r.json()["data"]
    rep = client.get(f"/sreplay/{body['shortCode']}?t={body['expiresAt']}&s={'0' * 64}")
    assert rep.status_code == 403


def test_replay_audio_served_with_strong_cache():
    r = client.get("/assets/replay-audio.mp3")
    assert r.status_code == 200
    assert r.headers["content-type"] == "audio/mpeg"
    cc = r.headers.get("cache-control", "")
    assert "max-age=31536000" in cc
    assert "immutable" in cc


def test_publish_viewer_embeds_replay_iframe_url():
    """v0.9.2: publish viewer 头部应该有 '路线回放' 按钮 + iframe 的
    data-replay-url 指向同 shortCode 的 /sreplay/... URL（同 sig 同 expiry）。
    用户点按钮 → JS 把 src 注入到 iframe 显示回放 overlay。"""
    trip = _trip_with_coords(node_photo_counts=(1,))
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("photo_0", ("p.jpg", _jpeg(), "image/jpeg")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    body = r.json()["data"]

    pub = client.get(f"/s/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    html = pub.text
    # iframe 的 data-replay-url 应该 = 同 shortCode 的 /sreplay/... URL
    expected_replay_url = (
        f"/sreplay/{body['shortCode']}?t={body['expiresAt']}&amp;s={body['sig']}"
    )
    assert expected_replay_url in html
    # 触发器按钮的 JS 标识符在
    assert 'id="replay-trigger"' in html
    assert 'id="replay-overlay"' in html
    # 占位符不应漏出
    assert "{{REPLAY_URL}}" not in html


def test_publish_response_route_data_now_includes_lat_lng():
    """v0.9: 加 latitude / longitude 到 ShareNodeData，给 replay viewer 用。
    之前没经纬度的节点会是 null（前端要兼容）。"""
    trip = _trip_with_coords(node_photo_counts=(1,))
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("photo_0", ("p.jpg", _jpeg(), "image/jpeg")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    body = r.json()["data"]
    # 通过 publish viewer 看 inline JSON
    pub = client.get(f"/s/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    assert '"latitude":22.5' in pub.text
    assert '"longitude":113.9' in pub.text


def test_revoke_by_trip_idempotent():
    """连调两次 revoke 也只算一次（第二次 revokedCount=0，因为第一次已经
    把全部行标了 PRIVATE，第二次 SQL 过滤掉了）。"""
    trip = _trip(node_photo_counts=(0,))
    trip["tripId"] = "trip_idempotent"
    client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))

    first = client.post(
        "/api/v1/share/revoke-by-trip", headers=_AUTH, json={"tripId": "trip_idempotent"},
    )
    assert first.json()["data"]["revokedCount"] == 1

    second = client.post(
        "/api/v1/share/revoke-by-trip", headers=_AUTH, json={"tripId": "trip_idempotent"},
    )
    assert second.json()["data"]["revokedCount"] == 0


# ===========================================================================
# OG / social meta tags (v0.7)
# ===========================================================================

def test_viewer_html_has_og_meta_tags():
    """When QQ/微信/Twitter抓预览时，<head> 里要有完整 OG/social meta。"""
    trip = _trip(node_photo_counts=(1,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    body = r.json()["data"]
    code = body["shortCode"]
    expires = body["expiresAt"]
    sig = body["sig"]

    r2 = client.get(f"/s/{code}?t={expires}&s={sig}")
    assert r2.status_code == 200
    html = r2.text

    # 关键 OG 标签都必须出现
    assert 'property="og:title"' in html
    assert 'property="og:description"' in html
    assert 'property="og:url"' in html
    assert 'property="og:image"' in html
    assert 'property="og:type"' in html
    assert 'property="og:site_name"' in html
    # Twitter 卡片
    assert 'name="twitter:card"' in html
    assert 'name="twitter:image"' in html
    # 普通 description（搜索引擎也用）
    assert 'name="description"' in html
    # 微信卡片预留位
    assert 'name="wxcard:title"' in html

    # tripName 应该出现在 title 与 og:title 内
    assert "测试路线" in html
    # 占位符不应该泄漏到最终 HTML
    assert "{{HTML_TITLE}}" not in html
    assert "{{SHARE_DESCRIPTION}}" not in html
    assert "{{COVER_PHOTO_URL}}" not in html
    assert "{{SHARE_URL}}" not in html


def test_viewer_html_first_screen_has_title_and_description():
    """SPA 站点的爬虫抓预览常常不执行 JS。<body> 里第一屏必须有标题/摘要
    HTML 内容，否则 og:image 之外的预览会空白。"""
    trip = _trip(node_photo_counts=(1,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    body = r.json()["data"]

    r2 = client.get(f"/s/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    html = r2.text

    # body 里第一屏 fallback 块（含 trip 名 + 描述）— 用占位符 tag 名标记
    body_section = html.split("<body>", 1)[1]
    assert "测试路线" in body_section


def test_viewer_html_escapes_meta_values():
    """tripName 含 HTML 特殊字符也不能破坏 meta 结构。"""
    trip = _trip(node_photo_counts=(1,))
    trip["tripName"] = '骑行</script><script>alert("xss")</script>'
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    body = r.json()["data"]

    r2 = client.get(f"/s/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    html = r2.text
    # 原始 </script> 不应作为标签出现在 head 里 —— 应该是被 HTML-escape
    head = html.split("</head>", 1)[0]
    assert "<script>alert" not in head
    # 但 escape 后的形态应该出现（&lt;script&gt;）
    assert "&lt;script&gt;" in head or "&amp;lt;script&amp;gt;" in head


def test_viewer_html_has_no_cover_when_zero_photos():
    """没照片的 trip — og:image 仍然存在但值为空字符串，不阻止页面渲染。"""
    trip = _trip(node_photo_counts=(0,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    body = r.json()["data"]

    r2 = client.get(f"/s/{body['shortCode']}?t={body['expiresAt']}&s={body['sig']}")
    assert r2.status_code == 200
    # 占位符仍被替换（即使是空），不能漏出去
    assert "{{COVER_PHOTO_URL}}" not in r2.text


# ===========================================================================
# GET /s/{shortcode} — spec dispatch
# ===========================================================================

def test_spec_viewer_403_on_bad_signature():
    trip = _trip(node_photo_counts=(0,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    code = r.json()["data"]["shortCode"]
    expires = r.json()["data"]["expiresAt"]
    bad_sig = "0" * 64
    r2 = client.get(f"/s/{code}?t={expires}&s={bad_sig}")
    assert r2.status_code == 403
    assert "无效或已过期" in r2.text


def test_spec_viewer_403_on_missing_query():
    r = client.get("/s/abcd1234")
    assert r.status_code == 403


def test_spec_viewer_404_on_unknown_shortcode():
    # Generate a valid signature for a code that doesn't exist in DB
    from share_service.core.config import get_settings
    sig = compute_sig_v2(get_settings().share_hmac_key, "ZZZZZZZZ", 9999999999)
    r = client.get(f"/s/ZZZZZZZZ?t=9999999999&s={sig}")
    assert r.status_code == 404


def test_spec_viewer_410_on_expired():
    """Manually insert a publish row whose expiry is in the past, then GET."""
    from share_service.db import repository_publish as repo
    from share_service.core.config import get_settings
    code = "EXPIRED1"
    past = int(time.time()) - 10
    sig = compute_sig_v2(get_settings().share_hmac_key, code, past)
    repo.insert_publish({
        "short_code": code,
        "trip_id": "x",
        "trip_data_json": "{}",
        "photo_index_json": "[]",
        "cover_relpath": None,
        "published_at_ms": int(time.time() * 1000) - 100000,
        "expires_at_s": past,
        "sig_hex": sig,
    })
    r = client.get(f"/s/{code}?t={past}&s={sig}")
    assert r.status_code == 410


# ===========================================================================
# Lazy delete (v0.5)
# ===========================================================================

def test_lazy_delete_removes_row_after_expired_viewer_access():
    """First GET on expired link returns 410 AND deletes the row.
    Second GET should now return 404 (row is gone)."""
    from share_service.db import repository_publish as repo
    from share_service.core.config import get_settings
    import shutil

    code = "LAZY0001"
    past = int(time.time()) - 10
    sig = compute_sig_v2(get_settings().share_hmac_key, code, past)
    cache_dir = _cache_dir_for(code)
    cache_dir.mkdir(parents=True, exist_ok=True)
    (cache_dir / "0_375w.webp").write_bytes(b"dummy")
    repo.insert_publish({
        "short_code": code, "trip_id": "x",
        "trip_data_json": "{}", "photo_index_json": "[]",
        "cover_relpath": "0_375w.webp",
        "published_at_ms": int(time.time() * 1000) - 100000,
        "expires_at_s": past, "sig_hex": sig,
    })
    assert repo.fetch_publish(code) is not None
    assert cache_dir.is_dir()

    r = client.get(f"/s/{code}?t={past}&s={sig}")
    assert r.status_code == 410

    # After lazy delete: no row, no cache dir
    assert repo.fetch_publish(code) is None
    assert not cache_dir.exists()

    r2 = client.get(f"/s/{code}?t={past}&s={sig}")
    # Now the row is gone, so we get 404 instead of 410
    assert r2.status_code == 404


def test_lazy_delete_via_status_endpoint():
    from share_service.db import repository_publish as repo
    from share_service.core.config import get_settings

    code = "LAZY0002"
    past = int(time.time()) - 10
    sig = compute_sig_v2(get_settings().share_hmac_key, code, past)
    repo.insert_publish({
        "short_code": code, "trip_id": "x",
        "trip_data_json": "{}", "photo_index_json": "[]",
        "cover_relpath": None,
        "published_at_ms": int(time.time() * 1000) - 100000,
        "expires_at_s": past, "sig_hex": sig,
    })
    r = client.get(f"/api/v1/share/{code}/status")
    assert r.json()["code"] == 40401
    assert repo.fetch_publish(code) is None


def test_lazy_delete_via_cache_route():
    from share_service.db import repository_publish as repo
    from share_service.core.config import get_settings

    code = "LAZY0003"
    past = int(time.time()) - 10
    sig = compute_sig_v2(get_settings().share_hmac_key, code, past)
    cache_dir = _cache_dir_for(code)
    cache_dir.mkdir(parents=True, exist_ok=True)
    (cache_dir / "0_375w.webp").write_bytes(b"dummy")
    repo.insert_publish({
        "short_code": code, "trip_id": "x",
        "trip_data_json": "{}", "photo_index_json": "[]",
        "cover_relpath": "0_375w.webp",
        "published_at_ms": int(time.time() * 1000) - 100000,
        "expires_at_s": past, "sig_hex": sig,
    })
    r = client.get(f"/cache/{code}/0_375w.webp")
    assert r.status_code == 404
    assert repo.fetch_publish(code) is None
    assert not cache_dir.exists()


# ===========================================================================
# Cron purge (v0.5)
# ===========================================================================

def test_cron_purge_removes_publish_rows_and_cache_dirs():
    """purge_expired_now sweeps everything past expires_at_s, including
    cache subdirs whose row was already lazy-deleted."""
    from share_service.db import repository_publish as repo
    from share_service.core.config import get_settings
    from share_service.core.lifecycle import purge_expired_now

    # Set up: 2 expired + 1 fresh
    expired_codes = ("CRON_EXP1", "CRON_EXP2")
    fresh_code = "CRON_OK01"
    past = int(time.time()) - 100
    future = int(time.time()) + 3600
    key = get_settings().share_hmac_key

    for code in expired_codes:
        cache_dir = _cache_dir_for(code)
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "0_375w.webp").write_bytes(b"d")
        repo.insert_publish({
            "short_code": code, "trip_id": "x",
            "trip_data_json": "{}", "photo_index_json": "[]",
            "cover_relpath": "0_375w.webp",
            "published_at_ms": int(time.time() * 1000) - 100000,
            "expires_at_s": past,
            "sig_hex": compute_sig_v2(key, code, past),
        })
    fresh_dir = _cache_dir_for(fresh_code)
    fresh_dir.mkdir(parents=True, exist_ok=True)
    (fresh_dir / "0_375w.webp").write_bytes(b"d")
    repo.insert_publish({
        "short_code": fresh_code, "trip_id": "x",
        "trip_data_json": "{}", "photo_index_json": "[]",
        "cover_relpath": "0_375w.webp",
        "published_at_ms": int(time.time() * 1000),
        "expires_at_s": future,
        "sig_hex": compute_sig_v2(key, fresh_code, future),
    })

    rows, dirs = purge_expired_now(int(time.time()))
    assert rows >= 2
    assert dirs >= 2
    for code in expired_codes:
        assert repo.fetch_publish(code) is None
        assert not _cache_dir_for(code).exists()
    # Fresh one untouched
    assert repo.fetch_publish(fresh_code) is not None
    assert fresh_dir.exists()


# ===========================================================================
# /api/v1/share/{shortcode}/status
# ===========================================================================

def test_status_ok_for_fresh_publish():
    trip = _trip(node_photo_counts=(0,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, []))
    code = r.json()["data"]["shortCode"]
    expires = r.json()["data"]["expiresAt"]

    r2 = client.get(f"/api/v1/share/{code}/status")
    j = r2.json()
    assert j["code"] == 0
    assert j["data"]["shortCode"] == code
    assert j["data"]["expiresAt"] == expires
    assert j["data"]["remainingSeconds"] > 0


def test_status_404_for_unknown():
    r = client.get("/api/v1/share/NOPE0000/status")
    assert r.json()["code"] == 40401


# ===========================================================================
# /cache/{shortcode}/{filename}
# ===========================================================================

def test_cache_serves_webp_for_valid_share():
    trip = _trip(node_photo_counts=(1,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    code = r.json()["data"]["shortCode"]

    # Path layout per core/photos.py: {flatIdx}_{w}w.webp (v0.4+).
    r2 = client.get(f"/cache/{code}/0_375w.webp")
    assert r2.status_code == 200
    assert r2.headers["content-type"] == "image/webp"


def test_cache_rejects_path_traversal():
    r = client.get("/cache/anycode/..%2Fsecret.webp")
    # Double-encoded ".." is normalised before hitting the route in some
    # stacks; either 404 or 400 is fine — must NOT serve anything.
    assert r.status_code in (400, 404)


def test_cache_rejects_non_webp_extension():
    r = client.get("/cache/anycode/foo.png")
    assert r.status_code == 404


def test_cache_does_not_serve_manifest_json():
    # manifest.json is internal — not exposed via /cache route.
    trip = _trip(node_photo_counts=(1,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    code = r.json()["data"]["shortCode"]
    r2 = client.get(f"/cache/{code}/manifest.json")
    assert r2.status_code == 404


# ===========================================================================
# Storage-layout regularity (v0.4)
# ===========================================================================

def _cache_dir_for(code: str) -> "Path":
    """Resolve the absolute cache subdir for a given shortCode.
    Mirrors routers/publish.py::_cache_root logic."""
    from pathlib import Path
    from share_service.core.config import get_settings
    db_path = Path(get_settings().db_path).resolve()
    return db_path.parent / "cache" / code


def test_publish_writes_manifest_json_alongside_webp():
    """Each cache subdir is self-describing: manifest.json + .webp files.
    Anyone inspecting the dir can reconstruct what's inside without DB."""
    import json as _json
    trip = _trip(node_photo_counts=(2, 1))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [_jpeg(), _jpeg(), _jpeg()]),
    )
    code = r.json()["data"]["shortCode"]
    cache_dir = _cache_dir_for(code)
    manifest_path = cache_dir / "manifest.json"
    assert manifest_path.is_file()
    m = _json.loads(manifest_path.read_text(encoding="utf-8"))
    assert m["schemaVersion"] == 1
    assert m["shortCode"] == code
    assert m["tripId"] == "trip_test_001"
    assert len(m["photos"]) == 3
    # Each photo entry references its actual on-disk filenames.
    for photo in m["photos"]:
        for w_str, rel in photo["paths"].items():
            assert (cache_dir / rel).is_file()


def test_publish_uses_flat_idx_filenames_unique_within_dir():
    """File naming uses {flatIdx}_{w}w.webp so duplicate nodeOrders cannot
    collide on disk (v0.4 regression guard)."""
    trip = _trip(node_photo_counts=(2, 1))
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_multipart(trip, [_jpeg(), _jpeg(), _jpeg()]),
    )
    code = r.json()["data"]["shortCode"]
    cache_dir = _cache_dir_for(code)
    webp_files = sorted(p.name for p in cache_dir.glob("*.webp"))
    # 3 photos × 2 widths = 6 files, all uniquely named
    assert len(webp_files) == 6
    expected = sorted([f"{i}_{w}w.webp" for i in range(3) for w in (375, 750)])
    assert webp_files == expected


def test_publish_rolled_back_on_db_insert_failure(monkeypatch):
    """If anything in the disk-write + DB-insert phase throws, the cache
    subdir must be wiped — no orphan files left for the next publish."""
    from pathlib import Path
    from share_service.db import repository_publish as repo
    from share_service.routers import publish as publish_router

    real_insert = repo.insert_publish

    def boom(_row):
        raise RuntimeError("simulated db insert failure")

    monkeypatch.setattr(repo, "insert_publish", boom)
    # Also patch the import that publish_router uses (it imported `repo` at
    # module load time; monkeypatching the source module flows through).
    monkeypatch.setattr(publish_router.repo, "insert_publish", boom)

    cache_root_before = {p.name for p in _cache_dir_for("").parent.iterdir()
                        if p.is_dir()}

    trip = _trip(node_photo_counts=(1,))
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_multipart(trip, [_jpeg()]))
    assert r.status_code == 500
    assert r.json()["code"] == 50000

    # Restore so the rest of the suite isn't poisoned
    monkeypatch.setattr(repo, "insert_publish", real_insert)
    monkeypatch.setattr(publish_router.repo, "insert_publish", real_insert)

    cache_root_after = {p.name for p in _cache_dir_for("").parent.iterdir()
                        if p.is_dir()}
    # No new cache subdir should remain after the failed publish
    new_dirs = cache_root_after - cache_root_before
    assert new_dirs == set(), f"orphan cache dirs left behind: {new_dirs}"


# ===========================================================================
# Demo flow (legacy /s/{code}.{sig}) still works
# ===========================================================================

def test_legacy_simple_viewer_still_served_when_path_has_dot():
    r = client.get("/s/abcd1234.efgh5678")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    # the simple viewer is the one that fetches /api/share/{code}.{sig}
    assert "/api/share/" in r.text
