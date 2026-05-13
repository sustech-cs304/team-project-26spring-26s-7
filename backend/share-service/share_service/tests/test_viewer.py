from fastapi.testclient import TestClient

from share_service.main import app

client = TestClient(app)


def test_viewer_simple_returns_html():
    r = client.get("/s/anycode.anysig")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    body = r.text
    assert "<title>TravelPin" in body
    assert "/api/share/" in body  # the JS fetch URL is embedded


def test_viewer_simple_no_cache():
    r = client.get("/s/x.y")
    assert "no-store" in r.headers.get("cache-control", "")


def test_viewer_3d_returns_html():
    r = client.get("/s3d/anycode.anysig")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    body = r.text
    # Vue + Three.js are both expected to be loaded
    assert "vue@3" in body
    assert "three" in body.lower()
    assert "/api/share/" in body


def test_viewer_3d_no_cache():
    r = client.get("/s3d/x.y")
    assert "no-store" in r.headers.get("cache-control", "")


def test_viewer_map_returns_html():
    r = client.get("/smap/anycode.anysig")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    body = r.text
    assert "leaflet" in body.lower()
    assert "/api/share/" in body


def test_viewer_map_no_cache():
    r = client.get("/smap/x.y")
    assert "no-store" in r.headers.get("cache-control", "")
