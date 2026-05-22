"""v1.0 — replay preferences end-to-end:
publish accepts the 6 multipart fields, normalize_replay_prefs whitelists
them with default fallback, viewer_replay injects __REPLAY_PREFS__ + the
bgm-specific audio URL, audio routes serve only whitelisted BGM ids.
"""
from __future__ import annotations

import io
import json
import re

from fastapi.testclient import TestClient
from PIL import Image

from share_service.main import app
from share_service.models.publish import (
    REPLAY_DEFAULT,
    normalize_replay_prefs,
)


client = TestClient(app)
_AUTH = {"X-Dev-Uid": "test"}


# --- helpers (small clones so this file is self-contained) ----------------

def _jpeg(color=(180, 200, 80)) -> bytes:
    img = Image.new("RGB", (640, 480), color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return buf.getvalue()


def _trip_one_node() -> dict:
    return {
        "tripId": "trip_replay_prefs",
        "tripName": "回放偏好测试",
        "totalDistance": 0.0,
        "coverIndex": 0,
        "createdAt": 1714200000000,
        "nodes": [{
            "id": "n0",
            "title": "起点",
            "content": "测试节点",
            "poiName": "Origin",
            "photoCount": 1,
            "mood": "",
            "tags": [],
            "visitedAt": 1714200000000,
            "nodeOrder": 0,
            "latitude": 31.23,
            "longitude": 121.47,
        }],
    }


def _files(trip: dict, *, prefs: dict | None = None):
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("photo_0", ("p.jpg", _jpeg(), "image/jpeg")),
        ("expiryHours", (None, "168", "text/plain")),
    ]
    if prefs:
        for k, v in prefs.items():
            files.append((k, (None, str(v), "text/plain")))
    return files


# --- normalize_replay_prefs ------------------------------------------------

def test_normalize_returns_defaults_for_empty_input():
    assert normalize_replay_prefs({}) == REPLAY_DEFAULT
    assert normalize_replay_prefs(None) == REPLAY_DEFAULT  # type: ignore[arg-type]


def test_normalize_accepts_valid_wire_values():
    out = normalize_replay_prefs({
        "styleKitId": "dark_night",
        "bgmId": "jazz_night",
        "filterId": "mono",
        "transitionType": "slide",
        "enableBlurOverlay": True,
        "enableRouteAnimation": True,
        "enableRipple": True,
    })
    assert out["styleKitId"] == "dark_night"
    assert out["bgmId"] == "jazz_night"
    assert out["filterId"] == "mono"
    assert out["transitionType"] == "slide"
    assert out["enableBlurOverlay"] is True
    assert out["enableRouteAnimation"] is True
    assert out["enableRipple"] is True


def test_normalize_rejects_invalid_values_falling_back_to_defaults():
    out = normalize_replay_prefs({
        "styleKitId": "MINIMAL_WHITE",   # uppercase = old/bogus value
        "bgmId": "not-a-bgm",
        "filterId": "blackmagic",
        "transitionType": "warp",
        "enableBlurOverlay": "yes",      # not a bool → kept as default
    })
    assert out == REPLAY_DEFAULT


# --- POST /api/v1/share/publish accepts replay fields ---------------------

def test_publish_without_replay_fields_keeps_db_null():
    """No replay_* multipart keys → row.replay_prefs_json IS NULL.
    Viewer will then inject __REPLAY_PREFS__ = null and use defaults JS-side."""
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_files(_trip_one_node()),
    )
    assert r.status_code == 201, r.text
    code = r.json()["data"]["shortCode"]

    from share_service.db import repository_publish as repo
    row = repo.fetch_publish(code)
    assert row is not None
    assert row["replay_prefs_json"] is None


def test_publish_with_replay_fields_stores_normalized_json():
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_files(_trip_one_node(), prefs={
            "replayStyleKitId": "vintage_film",
            "replayBgmId": "tropical_chill_travel",
            "replayFilterId": "warm",
            "replayTransitionType": "scale",
            "replayEnableBlurOverlay": "true",
            "replayEnableRouteAnimation": "1",
            "replayEnableRipple": "true",
        }),
    )
    assert r.status_code == 201, r.text
    code = r.json()["data"]["shortCode"]

    from share_service.db import repository_publish as repo
    row = repo.fetch_publish(code)
    assert row["replay_prefs_json"] is not None
    stored = json.loads(row["replay_prefs_json"])
    assert stored["styleKitId"] == "vintage_film"
    assert stored["bgmId"] == "tropical_chill_travel"
    assert stored["filterId"] == "warm"
    assert stored["transitionType"] == "scale"
    assert stored["enableBlurOverlay"] is True
    assert stored["enableRouteAnimation"] is True
    assert stored["enableRipple"] is True


def test_publish_with_partial_invalid_fields_falls_back_per_field():
    """Invalid styleKitId + valid bgmId → row stores defaults for kit but
    keeps bgm. (Backend normalize_replay_prefs is per-field.)"""
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_files(_trip_one_node(), prefs={
            "replayStyleKitId": "WHATEVER",          # invalid → default
            "replayBgmId": "morning_chill_birds",    # valid
        }),
    )
    assert r.status_code == 201
    code = r.json()["data"]["shortCode"]

    from share_service.db import repository_publish as repo
    row = repo.fetch_publish(code)
    stored = json.loads(row["replay_prefs_json"])
    assert stored["styleKitId"] == REPLAY_DEFAULT["styleKitId"]
    assert stored["bgmId"] == "morning_chill_birds"


# --- /sreplay viewer injection --------------------------------------------

def _publish_and_get_replay_html(prefs: dict | None) -> str:
    r = client.post(
        "/api/v1/share/publish",
        headers=_AUTH,
        files=_files(_trip_one_node(), prefs=prefs),
    )
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    code = data["shortCode"]
    sig = data["sig"]
    expires = data["expiresAt"]

    rv = client.get(f"/sreplay/{code}", params={"t": expires, "s": sig})
    assert rv.status_code == 200, rv.text
    return rv.text


def test_viewer_replay_with_no_prefs_injects_null():
    html = _publish_and_get_replay_html(prefs=None)
    assert "window.__REPLAY_PREFS__ = null;" in html
    # default audio URL points to default BGM (city_lights_lofi)
    assert "/assets/replay-audio/city_lights_lofi.mp3" in html


def test_viewer_replay_with_prefs_injects_full_object_and_correct_bgm_url():
    html = _publish_and_get_replay_html(prefs={
        "replayStyleKitId": "dark_night",
        "replayBgmId": "cinematic_ambient",
        "replayFilterId": "mono",
        "replayTransitionType": "slide",
        "replayEnableBlurOverlay": "true",
        "replayEnableRouteAnimation": "true",
        "replayEnableRipple": "true",
    })
    # BGM URL switched to the chosen bgm
    assert "/assets/replay-audio/cinematic_ambient.mp3" in html
    # __REPLAY_PREFS__ must have all 7 keys with normalized values
    m = re.search(r"window\.__REPLAY_PREFS__\s*=\s*(\{[^;]+\});", html)
    assert m, "__REPLAY_PREFS__ not found in viewer HTML"
    prefs = json.loads(m.group(1))
    assert prefs["styleKitId"] == "dark_night"
    assert prefs["bgmId"] == "cinematic_ambient"
    assert prefs["filterId"] == "mono"
    assert prefs["transitionType"] == "slide"
    assert prefs["enableBlurOverlay"] is True
    assert prefs["enableRouteAnimation"] is True
    assert prefs["enableRipple"] is True


# --- /assets/replay-audio/{bgmId}.mp3 -------------------------------------

def test_audio_route_serves_each_whitelisted_bgm():
    # The 5 wire-value bgm ids each map to their own .mp3 file.
    for bgm in [
        "morning_chill_birds", "city_lights_lofi", "jazz_night",
        "tropical_chill_travel", "cinematic_ambient",
    ]:
        r = client.get(f"/assets/replay-audio/{bgm}.mp3")
        assert r.status_code == 200, f"{bgm}: {r.status_code}"
        assert r.headers["content-type"] == "audio/mpeg"


def test_audio_route_rejects_unknown_bgm_id():
    r = client.get("/assets/replay-audio/nope.mp3")
    assert r.status_code == 404


def test_audio_route_blocks_path_traversal():
    # Path traversal characters can't even hit the route — bgm_id is path
    # param without slash. But explicit `..` in the id should still 404 via
    # whitelist + relative_to check.
    r = client.get("/assets/replay-audio/..%2Fetc%2Fpasswd.mp3")
    assert r.status_code == 404


# --- v1.0.4: HEAD support for WeChat/QQ social-card scrapers --------------

def test_head_supported_on_publish_viewer_and_cover():
    """微信卡片爬虫先 HEAD 探活，再 GET 抓 og:meta；GET-only 路由会 405
    导致它放弃，卡片只剩 title。HEAD 必须返 200，且头部跟 GET 一致。"""
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=_files(_trip_one_node()))
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    code = data["shortCode"]; sig = data["sig"]; expires = data["expiresAt"]

    # /s/{code} (publish viewer HTML)
    h = client.head(f"/s/{code}", params={"t": expires, "s": sig})
    assert h.status_code == 200, f"HEAD on /s/ should 200, got {h.status_code}"
    assert "text/html" in h.headers["content-type"]
    assert h.content == b""   # HEAD body must be empty

    # /cache/{code}/{filename} (og:image)
    # v1.0.4：cover 现在是 cover.jpg（JPEG），HEAD 也得 200 + 正确 content-type
    cover_path = data["coverPhotoUrl"].split("/cache/", 1)[1]
    assert cover_path.endswith("/cover.jpg")
    h2 = client.head(f"/cache/{cover_path}")
    assert h2.status_code == 200, f"HEAD on /cache should 200, got {h2.status_code}"
    assert h2.headers["content-type"] == "image/jpeg"
    assert h2.content == b""
