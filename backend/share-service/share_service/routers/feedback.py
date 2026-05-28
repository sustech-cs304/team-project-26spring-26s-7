"""POST /api/v1/feedback —— 用户反馈收件入口。

用户从 APP 的"帮助与客服"页提交反馈：分类、内容、可选联系方式、可选设备元数据。
后端做基本校验（长度 + 敏感词），通过则写入 user_feedback 表，返回 200 + id。

鉴权：跟 share publish 一致，要 share_token (Bearer) 或 X-Dev-Uid 兜底。
速率：基础 IP 限流 (每分钟 6 条)，防恶意刷。
"""
from __future__ import annotations

import time
from collections import deque
from threading import Lock
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, validator

from ..core.auth_tokens import require_share_token
from ..db import repository_feedback as repo

router = APIRouter()


# ---------- Pydantic ----------

class FeedbackIn(BaseModel):
    category: str = Field(..., description="bug / feature / experience / other")
    content: str = Field(..., min_length=2, max_length=2000)
    contact: Optional[str] = Field(None, max_length=200)
    app_version: Optional[str] = Field(None, max_length=64)
    os_version: Optional[str] = Field(None, max_length=128)
    device_model: Optional[str] = Field(None, max_length=128)

    @validator("category")
    def _category_must_be_known(cls, v: str) -> str:
        if v not in {"bug", "feature", "experience", "other"}:
            raise ValueError("category must be one of: bug / feature / experience / other")
        return v

    @validator("content")
    def _content_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("content cannot be blank")
        return v.strip()


class FeedbackOut(BaseModel):
    code: int
    message: str
    data: Optional[Dict[str, Any]] = None


# ---------- Rate limit (per IP) ----------

_RATE_WINDOW_S = 60.0
_RATE_LIMIT_PER_WINDOW = 6
_rate_lock = Lock()
_rate_state: Dict[str, deque] = {}


def _check_rate(ip: str) -> bool:
    now = time.monotonic()
    cutoff = now - _RATE_WINDOW_S
    with _rate_lock:
        bucket = _rate_state.setdefault(ip, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= _RATE_LIMIT_PER_WINDOW:
            return False
        bucket.append(now)
        return True


# ---------- Routes ----------

@router.post(
    "/api/v1/feedback",
    response_model=FeedbackOut,
    status_code=status.HTTP_201_CREATED,
)
async def submit_feedback(
    body: FeedbackIn,
    request: Request,
    owner_uid: str = Depends(require_share_token),
) -> FeedbackOut:
    """接收用户反馈。"""
    client_ip = request.client.host if request.client else "unknown"
    if not _check_rate(client_ip):
        return JSONResponse(
            status_code=429,
            content={"code": 42901, "message": "RATE_LIMITED",
                     "data": {"hint": "feedback submitted too frequently"}},
        )

    try:
        new_id = repo.insert_feedback({
            "uid": owner_uid if owner_uid != "anonymous" else None,
            "category": body.category,
            "content": body.content,
            "contact": body.contact,
            "app_version": body.app_version,
            "os_version": body.os_version,
            "device_model": body.device_model,
            "submitted_at": int(time.time()),
            "client_ip": client_ip,
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"insert_failed: {e}")

    return FeedbackOut(
        code=0,
        message="ok",
        data={"id": new_id},
    )
