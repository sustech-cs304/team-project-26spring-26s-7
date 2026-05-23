"""v1.1 — share poster (QR + cover + title) endpoints."""
from __future__ import annotations

import io
import json
import re

from fastapi.testclient import TestClient
from PIL import Image

from share_service.main import app


client = TestClient(app)
_AUTH = {"X-Dev-Uid": "test"}


def _jpeg(color=(180, 100, 40)) -> bytes:
    img = Image.new("RGB", (1024, 768), color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return buf.getvalue()


def _trip() -> dict:
    return {
        "tripId": "trip_poster_test",
        "tripName": "深圳湾骑行测试",
        "totalDistance": 12.5,
        "coverIndex": 0,
        "createdAt": 1714200000000,
        "nodes": [
            {"id": "n0", "title": "红树林湿地", "content": "起点",
             "poiName": "红树林", "photoCount": 1, "mood": "惬意",
             "tags": [], "visitedAt": 1714200000000, "nodeOrder": 0,
             "latitude": 22.52, "longitude": 113.93},
            {"id": "n1", "title": "深圳湾公园", "content": "中段",
             "poiName": "深圳湾公园", "photoCount": 0, "mood": "舒展",
             "tags": [], "visitedAt": 1714203600000, "nodeOrder": 1,
             "latitude": 22.50, "longitude": 113.95},
        ],
    }


def _publish() -> dict:
    files = [
        ("tripData", (None, json.dumps(_trip()), "text/plain")),
        ("photo_0", ("p.jpg", _jpeg(), "image/jpeg")),
        ("expiryHours", (None, "168", "text/plain")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    assert r.status_code == 201, r.text
    return r.json()["data"]


def _parse(url: str):
    m = re.search(r"/s/([^?]+)\?t=(\d+)&s=([0-9a-f]+)", url)
    return m.group(1), m.group(2), m.group(3)


# --- /share/{code}/qrcode.png -------------------------------------------

def test_qrcode_endpoint_returns_png():
    data = _publish()
    code, t, s = _parse(data["url"])
    r = client.get(f"/share/{code}/qrcode.png", params={"t": t, "s": s})
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/png"
    # Validate it actually decodes as a PNG with the QR's standard size band
    img = Image.open(io.BytesIO(r.content))
    assert img.format == "PNG"
    assert img.size[0] == img.size[1]   # square
    assert img.size[0] >= 200            # at least 200×200 readable


def test_qrcode_endpoint_rejects_bad_sig():
    data = _publish()
    code, t, _ = _parse(data["url"])
    r = client.get(
        f"/share/{code}/qrcode.png",
        params={"t": t, "s": "0" * 64},
    )
    assert r.status_code == 403


def test_qrcode_endpoint_rejects_missing_params():
    data = _publish()
    code, _, _ = _parse(data["url"])
    r = client.get(f"/share/{code}/qrcode.png")
    assert r.status_code == 403


# --- /share/{code}/poster.jpg -------------------------------------------

def test_poster_endpoint_returns_jpeg_with_correct_dimensions():
    data = _publish()
    code, t, s = _parse(data["url"])
    r = client.get(f"/share/{code}/poster.jpg", params={"t": t, "s": s})
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/jpeg"
    img = Image.open(io.BytesIO(r.content))
    assert img.format == "JPEG"
    assert img.size == (750, 1334)   # locked layout in core/poster.py


def test_poster_endpoint_caches_to_disk():
    """First call composes + writes cache/{code}/poster.jpg. Second call
    serves the same bytes from disk (no recomposition)."""
    data = _publish()
    code, t, s = _parse(data["url"])
    r1 = client.get(f"/share/{code}/poster.jpg", params={"t": t, "s": s})
    r2 = client.get(f"/share/{code}/poster.jpg", params={"t": t, "s": s})
    assert r1.status_code == 200 and r2.status_code == 200
    # bytes must be identical (cached file is served verbatim)
    assert r1.content == r2.content


def test_poster_endpoint_rejects_bad_sig():
    data = _publish()
    code, t, _ = _parse(data["url"])
    r = client.get(
        f"/share/{code}/poster.jpg",
        params={"t": t, "s": "0" * 64},
    )
    assert r.status_code == 403


def test_poster_endpoint_works_with_zero_photos():
    """0-photo trips should still get a poster — just no cover image
    (gradient fallback inside compose_poster)."""
    trip = _trip()
    for n in trip["nodes"]:
        n["photoCount"] = 0
    files = [
        ("tripData", (None, json.dumps(trip), "text/plain")),
        ("expiryHours", (None, "168", "text/plain")),
    ]
    r = client.post("/api/v1/share/publish", headers=_AUTH, files=files)
    assert r.status_code == 201, r.text
    data = r.json()["data"]
    code, t, s = _parse(data["url"])
    r2 = client.get(f"/share/{code}/poster.jpg", params={"t": t, "s": s})
    assert r2.status_code == 200
    img = Image.open(io.BytesIO(r2.content))
    assert img.size == (750, 1334)


def test_poster_head_supported_for_card_scrapers():
    """HEAD must work on poster.jpg too — same head_as_get middleware
    that covers /s and /cache/...webp must also cover this route."""
    data = _publish()
    code, t, s = _parse(data["url"])
    h = client.head(f"/share/{code}/poster.jpg", params={"t": t, "s": s})
    assert h.status_code == 200
    assert h.headers["content-type"] == "image/jpeg"
    assert h.content == b""
