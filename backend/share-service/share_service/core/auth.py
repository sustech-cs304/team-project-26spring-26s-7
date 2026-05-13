"""AGC ID-token verification.

三档防御（从弱到强，由环境变量逐级开启）：

1. 默认（任何配置都没有）：解码 JWT body，校验三段格式 + `exp` 未过期 + `sub`/`uid` 存在。
   仍不验签名，但比此前"完全不校验"明显收紧。
2. 设了 AGC_TOKEN_ISSUER：额外校验 `iss` claim 必须等于该 issuer。
3. 设了 AGC_TOKEN_AUDIENCE：额外校验 `aud` claim 必须等于该 app id。
4. 设了 AGC_JWKS_URL：用 JWKS 取公钥做 RS256 / RS384 / RS512 / PS256 全签名验证。
   这是上线必开的开关。

同时保留原有 dev fallback：当 ALLOW_DEV_UID_HEADER=1 时，`X-Dev-Uid` 头直接当 uid。
该开关上线必须设为 0。
"""
import base64
import json
import logging
import os
import time
from typing import Any, Optional

import jwt
from fastapi import Header, HTTPException

from .config import get_settings

logger = logging.getLogger("share_service.auth")


_AGC_ISSUER = os.environ.get("AGC_TOKEN_ISSUER", "").strip()
_AGC_AUDIENCE = os.environ.get("AGC_TOKEN_AUDIENCE", "").strip()
_AGC_JWKS_URL = os.environ.get("AGC_JWKS_URL", "").strip()

# 允许多 issuer / 多 audience（逗号分隔）
_ALLOWED_ISSUERS = {s.strip() for s in _AGC_ISSUER.split(",") if s.strip()}
_ALLOWED_AUDIENCES = {s.strip() for s in _AGC_AUDIENCE.split(",") if s.strip()}

_jwk_client: Optional[jwt.PyJWKClient] = None
if _AGC_JWKS_URL:
    _jwk_client = jwt.PyJWKClient(_AGC_JWKS_URL, cache_keys=True)
    logger.info("AGC JWKS verification enabled url=%s", _AGC_JWKS_URL)
else:
    logger.warning(
        "AGC JWKS verification DISABLED — only claim-level checks. "
        "Production deployments MUST set AGC_JWKS_URL."
    )


def _decode_jwt_unverified_body(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        raise HTTPException(401, "invalid_token")
    body_b64 = parts[1]
    pad = "=" * (-len(body_b64) % 4)
    try:
        body = json.loads(base64.urlsafe_b64decode(body_b64 + pad))
    except Exception as exc:
        raise HTTPException(401, "invalid_token") from exc
    if not isinstance(body, dict):
        raise HTTPException(401, "invalid_token")
    return body


def _verify_token(token: str) -> dict[str, Any]:
    """优先 RS256 验签；未配置 JWKS 时回退到仅 body + claim 校验。"""
    if _jwk_client is not None:
        try:
            signing_key = _jwk_client.get_signing_key_from_jwt(token).key
            options = {"verify_aud": bool(_ALLOWED_AUDIENCES)}
            payload = jwt.decode(
                token,
                signing_key,
                algorithms=["RS256", "RS384", "RS512", "PS256"],
                audience=list(_ALLOWED_AUDIENCES) if _ALLOWED_AUDIENCES else None,
                issuer=next(iter(_ALLOWED_ISSUERS)) if len(_ALLOWED_ISSUERS) == 1 else None,
                options=options,
            )
        except jwt.PyJWTError as exc:
            logger.warning("JWT verify failed: %s", exc)
            raise HTTPException(401, "invalid_token") from exc
        # 多 issuer 时 jwt.decode 不能传 list，手动验证
        if _ALLOWED_ISSUERS and payload.get("iss") not in _ALLOWED_ISSUERS:
            raise HTTPException(401, "invalid_token")
        return payload

    # ---- fallback：无签名验证，但仍校验关键 claim ----
    body = _decode_jwt_unverified_body(token)

    # 1. exp 必须存在且未过期（留 60s 时钟漂移余量）
    exp = body.get("exp")
    if not isinstance(exp, (int, float)):
        raise HTTPException(401, "invalid_token")
    if time.time() > float(exp) + 60:
        raise HTTPException(401, "invalid_token")

    # 2. iss / aud 校验（仅在配置了白名单时启用）
    if _ALLOWED_ISSUERS and body.get("iss") not in _ALLOWED_ISSUERS:
        raise HTTPException(401, "invalid_token")
    if _ALLOWED_AUDIENCES:
        aud = body.get("aud")
        aud_set = {aud} if isinstance(aud, str) else set(aud or [])
        if not (aud_set & _ALLOWED_AUDIENCES):
            raise HTTPException(401, "invalid_token")

    return body


async def get_owner_uid(
    authorization: Optional[str] = Header(None),
    x_dev_uid: Optional[str] = Header(None, alias="X-Dev-Uid"),
) -> str:
    settings = get_settings()
    if settings.allow_dev_uid and x_dev_uid:
        return x_dev_uid
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "missing_token")
    token = authorization.split(None, 1)[1].strip()
    if not token:
        raise HTTPException(401, "missing_token")
    body = _verify_token(token)
    uid = body.get("sub") or body.get("uid")
    if not uid:
        raise HTTPException(401, "invalid_token")
    return str(uid)
