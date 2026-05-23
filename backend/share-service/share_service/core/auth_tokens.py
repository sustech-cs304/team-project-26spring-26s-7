"""统一审核架构里 share-service 这一侧的 HMAC token 工具。

- 验证 sensitive-check 签发的 app_session_token（共享 APP_SESSION_SECRET）
- 签发 / 验证 share-service 自己的 share_token（独立 SHARE_TOKEN_SECRET，scope="share"）

跟 sensitive-check / ai-relay 用的 HMAC 格式完全一致：
    token = base64url(json_body).base64url(HMAC_SHA256(secret, json_body))

接 dev fallback：当 ALLOW_DEV_UID_HEADER=1 且请求带 X-Dev-Uid 时直接放行。
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Any, Dict, Optional

from fastapi import Header, HTTPException

_APP_SESSION_SECRET = os.environ.get("APP_SESSION_SECRET", "")
_SHARE_TOKEN_SECRET = os.environ.get("SHARE_TOKEN_SECRET", "")
_SHARE_TOKEN_TTL_SECONDS = int(os.environ.get("SHARE_TOKEN_TTL_SECONDS", "1800"))
_ALLOW_DEV_UID = os.environ.get("ALLOW_DEV_UID_HEADER", "0") == "1"


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode((data + padding).encode("ascii"))


def _sign_payload(payload: Dict[str, Any], secret: str, secret_name: str) -> str:
    if not secret:
        raise HTTPException(status_code=500, detail=f"{secret_name}_not_configured")
    body = _b64url_encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
    return f"{body}.{_b64url_encode(signature)}"


def _verify_signed_payload(token: str, secret: str, secret_name: str, scope: str) -> Dict[str, Any]:
    if not secret:
        raise HTTPException(status_code=500, detail=f"{secret_name}_not_configured")
    try:
        body, signature = token.rsplit(".", 1)
    except ValueError:
        raise HTTPException(status_code=401, detail="invalid_token")
    expected = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
    actual = _b64url_decode(signature)
    if not hmac.compare_digest(expected, actual):
        raise HTTPException(status_code=401, detail="invalid_token")
    try:
        payload = json.loads(_b64url_decode(body).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(status_code=401, detail="invalid_token")
    if int(payload.get("exp", 0)) <= int(time.time()):
        raise HTTPException(status_code=401, detail="token_expired")
    if payload.get("scope") != scope:
        raise HTTPException(status_code=403, detail="invalid_scope")
    return payload


def verify_app_session(authorization: Optional[str] = Header(None)) -> str:
    """从 Authorization: Bearer <app_session_token> 头里取出 uid（sensitive-check 签发）。"""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    token = authorization.split(None, 1)[1].strip()
    payload = _verify_signed_payload(token, _APP_SESSION_SECRET, "app_session_secret", "app")
    uid = str(payload.get("uid", "")).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="session_missing_uid")
    return uid


def issue_share_token(uid: str) -> Dict[str, Any]:
    """前端用 app_session_token 换 share_token；返回结构含 token + 过期信息。"""
    now = int(time.time())
    payload = {
        "uid": uid,
        "scope": "share",
        "iat": now,
        "exp": now + _SHARE_TOKEN_TTL_SECONDS,
        "jti": secrets.token_urlsafe(12),
    }
    token = _sign_payload(payload, _SHARE_TOKEN_SECRET, "share_token_secret")
    return {
        "token_type": "Bearer",
        "share_token": token,
        "issued_at": now,
        "expires_in": _SHARE_TOKEN_TTL_SECONDS,
    }


def require_share_token(
    authorization: Optional[str] = Header(None),
    x_dev_uid: Optional[str] = Header(None, alias="X-Dev-Uid"),
) -> str:
    """publish / revoke 等需要保护的接口用这个依赖。

    优先级：
    1. share_token（HMAC scope=share，新流程）
    2. X-Dev-Uid 头（ALLOW_DEV_UID_HEADER=1 时，dev / 老前端兼容）
    都没有 → 401。
    """
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(None, 1)[1].strip()
        if token:
            payload = _verify_signed_payload(token, _SHARE_TOKEN_SECRET, "share_token_secret", "share")
            uid = str(payload.get("uid", "")).strip()
            if uid:
                return uid
    if _ALLOW_DEV_UID and x_dev_uid:
        return x_dev_uid
    raise HTTPException(status_code=401, detail="missing_token")
