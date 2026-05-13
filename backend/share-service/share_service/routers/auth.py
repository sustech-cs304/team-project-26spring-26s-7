"""AI 子服务 token 下发接口。

设计：
- release 包不再硬编码 ai-service / picture-check / sensitive-filter 的 master token，
  改为登录用户在线申领。
- 客户端用 AGC ID-token 调本接口（同 publish 鉴权），拿到三套 token + 过期时间，
  缓存到内存重复使用；过期或被服务端轮换后再来取。
- token 来源：环境变量 AI_VISION_TOKEN / AI_FILTER_TOKEN / AI_CENSOR_TOKEN，
  即 ai-service / sensitive-filter / picture-check 各自 *_API_KEYS 中的某一项。
  share_service 自己持有这些 master token，前端永远不见。
- TTL：默认 1800s。客户端可在到期前续。
"""
from __future__ import annotations

import os
import time

from fastapi import APIRouter, Depends, HTTPException

from ..core.auth import get_owner_uid


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


@router.post("/issue_ai_token")
async def issue_ai_token(uid: str = Depends(get_owner_uid)) -> dict:
    """登录用户领取一组 AI 子服务 token。"""
    issued_at = int(time.time())
    return {
        "vision_token": _read_token("AI_VISION_TOKEN"),
        "filter_token": _read_token("AI_FILTER_TOKEN"),
        "censor_token": _read_token("AI_CENSOR_TOKEN"),
        "issued_at": issued_at,
        "expires_in": _TOKEN_TTL,
    }
