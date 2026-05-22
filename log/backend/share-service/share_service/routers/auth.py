"""share-service 的 auth 路由。

新机制（推荐）：
- POST /api/v1/auth/issue_share_token
  - body: 无
  - header: Authorization: Bearer <app_session_token>（sensitive-check 签发）
  - 返回 share_token (HMAC scope=share，默认 30 分钟)，给前端调 publish/revoke 用

旧机制（向后兼容，直到前端全部切完后再删）：
- POST /api/v1/auth/issue_ai_token
  - 老接口，dev 模式下返回环境变量里的固定 AI_*_TOKEN
"""
from __future__ import annotations

import os
import time

from fastapi import APIRouter, Depends, HTTPException

from ..core.auth import get_owner_uid
from ..core.auth_tokens import verify_app_session, issue_share_token


router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


_TOKEN_TTL = int(os.environ.get("AI_TOKEN_TTL_SECONDS", "1800"))


def _read_token(env_name: str) -> str:
    val = os.environ.get(env_name, "").strip()
    if not val:
        raise HTTPException(
            status_code=503,
            detail=f"{env_name} not configured on server",
        )
    return val


@router.post("/issue_share_token")
async def issue_share_token_endpoint(uid: str = Depends(verify_app_session)) -> dict:
    """前端拿 app_session_token 换短期 share_token，用于调 publish / revoke。"""
    return issue_share_token(uid)


@router.post("/issue_ai_token")
async def issue_ai_token(uid: str = Depends(get_owner_uid)) -> dict:
    """[DEPRECATED] 旧 fake-auth 接口。

    保留是为了让没切到新流程的前端继续能跑。新代码应该改为：
    - filter/censor token：调 sensitive-check /censor/api/v1/auth/issue_audit_token
    - vision token：调 ai-relay /v1/auth/issue_vision_token
    上线一段时间后可以删除本接口。
    """
    issued_at = int(time.time())
    return {
        "vision_token": _read_token("AI_VISION_TOKEN"),
        "filter_token": _read_token("AI_FILTER_TOKEN"),
        "censor_token": _read_token("AI_CENSOR_TOKEN"),
        "issued_at": issued_at,
        "expires_in": _TOKEN_TTL,
    }
