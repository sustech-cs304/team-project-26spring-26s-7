"""End-to-end API tests covering §10 DoD scenarios."""
import pytest
from fastapi.testclient import TestClient

from share_service.main import app
from share_service.routers import share as share_router

client = TestClient(app)


def H(uid: str = "alice"):
    return {"X-Dev-Uid": uid}


def _payload(photo_owner: str = "alice", trip_id: str = "trip-1"):
    return {
        "tripCloudId": trip_id,
        "expireDays": 7,
        "snapshot": {
            "v": 1,
            "trip": {"name": "西北 7 日"},
            "nodes": [
                {"title": "鸣沙山", "lat": 40.0883, "lng": 94.6764, "photos": []}
            ],
        },
        "photoManifest": [
            f"users/{photo_owner}/travels/1/nodes/1/photo_a.jpg",
        ],
        "consentVersion": "share-v1-2026-04",
    }


# --------------------------------------------------------------------------
# Health
# --------------------------------------------------------------------------

def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


# --------------------------------------------------------------------------
# Create
# --------------------------------------------------------------------------

def test_create_requires_auth():
    r = client.post("/api/share/create", json=_payload())
    assert r.status_code == 401


def test_create_returns_url_and_persists():
    r = client.post("/api/share/create", json=_payload(), headers=H())
    assert r.status_code == 200, r.text
    body = r.json()
    assert len(body["shortCode"]) == 8
    assert len(body["sig"]) == 8
    assert body["url"] == f"https://test.example/s/{body['shortCode']}.{body['sig']}"
    assert body["expireAt"] > 0


def test_create_invalid_expire_days_422():
    p = _payload()
    p["expireDays"] = 5
    r = client.post("/api/share/create", json=p, headers=H())
    assert r.status_code == 422


def test_create_cross_user_photo_403():
    p = _payload(photo_owner="bob")  # alice tries to ref bob's
    r = client.post("/api/share/create", json=p, headers=H("alice"))
    assert r.status_code == 403


def test_create_oversized_snapshot_422():
    p = _payload()
    # 256 KB +1 worth of payload in the snapshot.
    p["snapshot"]["bigfield"] = "x" * (256 * 1024 + 100)
    r = client.post("/api/share/create", json=p, headers=H())
    assert r.status_code == 422


def test_create_too_many_photos_422():
    p = _payload()
    p["photoManifest"] = [
        f"users/alice/travels/1/nodes/{i}/p.jpg" for i in range(51)
    ]
    r = client.post("/api/share/create", json=p, headers=H())
    # pydantic max_length=50 rejects at validation layer (422).
    assert r.status_code == 422


# --------------------------------------------------------------------------
# Public GET
# --------------------------------------------------------------------------

def test_get_returns_snapshot_and_increments_view_count():
    r = client.post("/api/share/create", json=_payload(), headers=H())
    body = r.json()
    code, sig = body["shortCode"], body["sig"]

    r1 = client.get(f"/api/share/{code}.{sig}")
    assert r1.status_code == 200
    j = r1.json()
    assert j["snapshot"]["trip"]["name"] == "西北 7 日"
    assert j["viewCount"] == 1
    photo_key = "users/alice/travels/1/nodes/1/photo_a.jpg"
    assert photo_key in j["photoUrls"]
    assert "mock.example" in j["photoUrls"][photo_key]
    assert "ttl=" in j["photoUrls"][photo_key]

    r2 = client.get(f"/api/share/{code}.{sig}")
    assert r2.json()["viewCount"] == 2


def test_get_tampered_sig_returns_404():
    r = client.post("/api/share/create", json=_payload(), headers=H())
    code = r.json()["shortCode"]
    r2 = client.get(f"/api/share/{code}.deadbeef")
    assert r2.status_code == 404
    assert "link_expired_or_invalid" in r2.text


def test_get_unknown_code_returns_404():
    r = client.get("/api/share/zzzzzzzz.aaaaaaaa")
    assert r.status_code == 404


def test_get_missing_dot_returns_404():
    r = client.get("/api/share/zzzzzzzz")
    assert r.status_code == 404


# --------------------------------------------------------------------------
# Revoke
# --------------------------------------------------------------------------

def test_revoke_then_get_404():
    r = client.post("/api/share/create", json=_payload(), headers=H())
    code, sig = r.json()["shortCode"], r.json()["sig"]

    rv = client.post(f"/api/share/{code}/revoke", headers=H())
    assert rv.status_code == 200
    assert rv.json() == {"revoked": True}

    r2 = client.get(f"/api/share/{code}.{sig}")
    assert r2.status_code == 404


def test_revoke_other_user_403():
    r = client.post("/api/share/create", json=_payload(), headers=H("alice"))
    code = r.json()["shortCode"]
    rv = client.post(f"/api/share/{code}/revoke", headers=H("eve"))
    assert rv.status_code == 403


def test_revoke_unknown_404():
    rv = client.post("/api/share/zzzzzzzz/revoke", headers=H())
    assert rv.status_code == 404


def test_revoke_idempotent():
    r = client.post("/api/share/create", json=_payload(), headers=H())
    code = r.json()["shortCode"]
    assert client.post(f"/api/share/{code}/revoke", headers=H()).status_code == 200
    assert client.post(f"/api/share/{code}/revoke", headers=H()).status_code == 200


# --------------------------------------------------------------------------
# Mine
# --------------------------------------------------------------------------

def test_mine_returns_only_owner_metadata():
    uid = "charlie"
    r = client.post("/api/share/create", json=_payload(photo_owner=uid), headers=H(uid))
    code = r.json()["shortCode"]
    rm = client.get("/api/share/mine", headers=H(uid))
    assert rm.status_code == 200
    items = rm.json()
    assert any(it["shortCode"] == code for it in items)
    # No snapshot leakage in list view.
    for it in items:
        assert "snapshot" not in it
        assert "snapshotJson" not in it


# --------------------------------------------------------------------------
# Rate limits
# --------------------------------------------------------------------------

def test_daily_create_limit_429():
    uid = "burst-user"
    for i in range(50):
        r = client.post(
            "/api/share/create",
            json=_payload(photo_owner=uid, trip_id=f"t-{i}"),
            headers=H(uid),
        )
        assert r.status_code == 200, f"create {i} failed: {r.text}"
    r51 = client.post(
        "/api/share/create",
        json=_payload(photo_owner=uid, trip_id="t-51"),
        headers=H(uid),
    )
    assert r51.status_code == 429


def test_get_ip_rate_limit_429(monkeypatch):
    # Reset bucket so other tests don't pollute the count for testclient IP.
    share_router._ip_window.clear()
    r = client.post("/api/share/create", json=_payload(), headers=H())
    code, sig = r.json()["shortCode"], r.json()["sig"]
    # 30 allowed, the 31st should 429.
    for _ in range(share_router.GET_LIMIT_PER_MIN):
        assert client.get(f"/api/share/{code}.{sig}").status_code == 200
    assert client.get(f"/api/share/{code}.{sig}").status_code == 429
    share_router._ip_window.clear()
