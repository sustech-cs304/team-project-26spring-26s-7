# coding=utf-8
"""SiliconFlow Relay —— OpenAI 兼容协议的 thin proxy，把客户端请求中转到硅基流动 API。

为什么存在：
- 当前客户端打 8000 端口的 openai_api.py（本地 Qwen-VL-Chat-Int4 推理）
- 用 SiliconFlow Cloud 替代本地后，无须改客户端协议
- 鉴权 / 限流 / 输入敏感词预检 / 输出敏感词打码全部保留
- 处理 Qwen3 系列的 thinking 模式（content 为空、真实回答在 reasoning_content 里）

模型映射：
- /v1/chat/completions       (text)  → SF Qwen/Qwen3.5-4B            (enable_thinking=False)
- /v1/chat/completions/image (image) → SF Qwen/Qwen3-VL-8B-Instruct  (multimodal messages)

敏感词检测调旁挂的 sensitive-filter (默认 :9100)，不在本进程加载词表。
"""
import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from collections import deque
from contextlib import asynccontextmanager
from threading import Lock
from typing import Any, Dict, List, Literal, Optional, Tuple

import httpx
import uvicorn
from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Request,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel


# ----- 全局配置（启动时由 _get_args 写入） -----
SF_BASE_URL = "https://api.siliconflow.cn/v1"
SF_KEY = ""
TEXT_MODEL = "Qwen/Qwen3.5-4B"
VISION_MODEL = "Qwen/Qwen3-VL-8B-Instruct"
# sensitive-check 服务地址（合并后在 9200，端点 /text_check）。
# 由 --sensitive-filter-url 参数覆盖；保留参数名兼容 systemd unit。
SF_FILTER_URL = "http://127.0.0.1:9200"
VALID_API_KEYS: set = set()
RATE_LIMIT_PER_MIN = 30
MAX_QUESTION_CHARS = 3000
HTTP_TIMEOUT = 60.0
SENSITIVE_REPLY = "抱歉，内容涉及敏感信息，无法提供相关回答。"

# ----- 鉴权 secrets（启动时从环境变量读） -----
# APP_SESSION_SECRET 与 sensitive-check 共享：ai-relay 验 sensitive-check 签发的 app_session_token
# VISION_TOKEN_SECRET ai-relay 独有：用于签发/验证 scope="vision" 短期 token
_APP_SESSION_SECRET = os.environ.get("APP_SESSION_SECRET", "")
_VISION_TOKEN_SECRET = os.environ.get("VISION_TOKEN_SECRET", "")
_VISION_TOKEN_TTL_SECONDS = int(os.environ.get("VISION_TOKEN_TTL_SECONDS", "1800"))


# ----- HMAC token 工具（与 sensitive-check 同样格式） -----
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


def _issue_vision_token(uid: str) -> Dict[str, Any]:
    now = int(time.time())
    payload = {
        "uid": uid,
        "scope": "vision",
        "iat": now,
        "exp": now + _VISION_TOKEN_TTL_SECONDS,
        "jti": secrets.token_urlsafe(12),
    }
    token = _sign_payload(payload, _VISION_TOKEN_SECRET, "vision_token_secret")
    return {
        "token_type": "Bearer",
        "vision_token": token,
        "issued_at": now,
        "expires_in": _VISION_TOKEN_TTL_SECONDS,
    }


# ----- 鉴权 / 限流 -----
def verify_bearer(authorization: Optional[str] = Header(None)) -> str:
    """接受两种 token：
    1. vision_token（HMAC scope=vision，新鉴权流程）
    2. VALID_API_KEYS 里的字符串（dev fallback + 老前端兼容）
    返回字符串作为 rate-limit / 日志 key（vision_token 返回 uid）。
    """
    if not authorization:
        # 没配 keys 也没 vision secret 时仍允许 anonymous（兼容老开发环境）
        if not VALID_API_KEYS and not _VISION_TOKEN_SECRET:
            return "anonymous"
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    parts = authorization.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Authorization must be 'Bearer <token>'")
    token = parts[1].strip()
    # 先按 vision_token 解码：HMAC 验签 + scope 校验，通过 → 拿 uid
    if _VISION_TOKEN_SECRET and "." in token:
        try:
            payload = _verify_signed_payload(token, _VISION_TOKEN_SECRET, "vision_token_secret", "vision")
            return f"uid:{payload.get('uid', 'unknown')}"
        except HTTPException as exc:
            # scope/exp 错的就直接拒，HMAC 不匹配的 fallback 到 api_keys
            if exc.detail in ("token_expired", "invalid_scope"):
                raise
            # invalid_token → 不是 vision_token，可能是老 api_key
    # api_keys fallback
    if VALID_API_KEYS and token in VALID_API_KEYS:
        return token
    raise HTTPException(status_code=401, detail="Invalid token")


def verify_app_session(authorization: Optional[str] = Header(None)) -> str:
    """专用于 /v1/auth/issue_vision_token：只接受 app_session_token。返回 uid。"""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    token = authorization.split(None, 1)[1].strip()
    payload = _verify_signed_payload(token, _APP_SESSION_SECRET, "app_session_secret", "app")
    uid = str(payload.get("uid", "")).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="session_missing_uid")
    return uid


_rate_lock = Lock()
_rate_state: Dict[str, deque] = {}


def enforce_rate_limit(token: str) -> None:
    if RATE_LIMIT_PER_MIN <= 0:
        return
    now = time.monotonic()
    cutoff = now - 60.0
    with _rate_lock:
        bucket = _rate_state.setdefault(token, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT_PER_MIN:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        bucket.append(now)


# ----- HTTP 客户端 -----
# 分两个 client：sidecar 在本机（127.0.0.1），不能走 HTTP_PROXY env（否则
# 用户本地代理会把 localhost 流量也转出去再返 502）；SF API 在外网，走 env 代理。
_sidecar_client: Optional[httpx.AsyncClient] = None
_upstream_client: Optional[httpx.AsyncClient] = None


async def filter_check(text: str, filter_token: Optional[str]) -> bool:
    """调 sensitive-check /text_check。命中返回 True；未命中、sidecar 故障、或缺 filter_token → False（fail-open）。

    filter_token 是前端通过 X-Filter-Token 头透传过来的（前端从 sensitive-check /issue_audit_token
    拿到）。这样 ai-relay 不需要自己有 sensitive-check 的服务凭证，sensitive-check 也不需要任何改动。
    """
    if not text or _sidecar_client is None or not filter_token:
        return False
    try:
        r = await _sidecar_client.post(
            f"{SF_FILTER_URL}/text_check",
            json={"text": text},
            headers={"Authorization": f"Bearer {filter_token}"},
            timeout=5.0,
        )
        if r.status_code in (401, 403):
            # filter_token 过期 / 无效 → 不是 sensitive-check 的问题，是前端 token 问题
            # 不阻塞业务，但记日志
            print(f"[filter_check] auth failed: {r.status_code} {r.text[:200]}")
            return False
        r.raise_for_status()
        data = r.json()
        # sensitive-check /text_check 响应字段：is_hit (bool) / is_safe (bool) / conclusionType
        is_hit = bool(data.get("is_hit"))
        if is_hit:
            print(f"[filter_check] HIT: data={data!r}")
        return is_hit
    except Exception as exc:
        print(f"[filter_check] sidecar error: {exc!r}; fail-open")
        return False


# ----- Pydantic models（兼容当前客户端协议）-----
class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system", "function"]
    content: Optional[str] = None
    function_call: Optional[Dict] = None


class ChatCompletionRequest(BaseModel):
    model: Optional[str] = None
    messages: List[ChatMessage]
    functions: Optional[List[Dict]] = None
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    max_tokens: Optional[int] = None
    max_length: Optional[int] = None  # 兼容旧字段
    stream: Optional[bool] = False
    stop: Optional[List[str]] = None


# ----- FastAPI lifespan -----
@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _sidecar_client, _upstream_client
    # sidecar (127.0.0.1)：必须 trust_env=False，否则会被本机 HTTP_PROXY 截走
    _sidecar_client = httpx.AsyncClient(timeout=HTTP_TIMEOUT, trust_env=False)
    # SF API (外网)：保持默认 trust_env=True，让 HTTP_PROXY/HTTPS_PROXY 生效
    _upstream_client = httpx.AsyncClient(timeout=HTTP_TIMEOUT)
    print(
        f"[boot] siliconflow-relay text_model={TEXT_MODEL} vision_model={VISION_MODEL} "
        f"upstream={SF_BASE_URL}"
    )
    print(
        f"[boot] auth={'enabled' if VALID_API_KEYS else 'OPEN (no api keys)'}, "
        f"keys={len(VALID_API_KEYS)}, rate_limit/min={RATE_LIMIT_PER_MIN}, "
        f"max_question_chars={MAX_QUESTION_CHARS}, filter_url={SF_FILTER_URL}"
    )
    yield
    for c in (_sidecar_client, _upstream_client):
        if c is not None:
            await c.aclose()


app = FastAPI(lifespan=lifespan, title="SiliconFlow Relay")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ----- 工具：构造响应 -----
def make_blocked_resp(model: str) -> dict:
    return {
        "id": f"chatcmpl-blocked-{int(time.time())}",
        "model": model,
        "object": "chat.completion",
        "created": int(time.time()),
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": SENSITIVE_REPLY, "function_call": None},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


def normalize_response(sf_data: dict, override_model: str) -> dict:
    """硅基流动响应 → 客户端期望的 OpenAI 标准格式。

    主要工作：
    - 处理 Qwen3 thinking 模式：content 为空但 reasoning_content 非空 → 把 reasoning 当 content
    - 否则正常情况下删掉 reasoning_content 字段（客户端不需要）
    - model 字段改成客户端发的（不暴露后端真模型）
    """
    for ch in sf_data.get("choices", []) or []:
        msg = ch.get("message", {}) or {}
        content = msg.get("content") or ""
        reasoning = msg.get("reasoning_content") or ""
        if not content and reasoning:
            msg["content"] = reasoning
        msg.pop("reasoning_content", None)
        # 兼容客户端旧字段：function_call=None
        msg.setdefault("function_call", None)
        ch["message"] = msg
    sf_data["model"] = override_model
    sf_data["object"] = "chat.completion"
    return sf_data


async def call_siliconflow(body: dict) -> dict:
    """转发到 SF；上游 4xx/5xx 翻成 502 给前端。"""
    try:
        r = await _upstream_client.post(
            f"{SF_BASE_URL}/chat/completions",
            json=body,
            headers={"Authorization": f"Bearer {SF_KEY}"},
        )
    except httpx.HTTPError as exc:
        print(f"[upstream-error] {exc!r}")
        raise HTTPException(status_code=502, detail=f"upstream unreachable: {exc}")
    if r.status_code != 200:
        snippet = r.text[:200].replace("\n", " ")
        print(f"[upstream-error] HTTP {r.status_code}: {snippet}")
        raise HTTPException(status_code=502, detail=f"upstream returned {r.status_code}")
    return r.json()


# ----- 端点 1：纯文本聊天 -----
@app.post("/v1/chat/completions")
async def chat_completions(
    req: ChatCompletionRequest,
    request: Request,
    token: str = Depends(verify_bearer),
    x_filter_token: Optional[str] = Header(None, alias="X-Filter-Token"),
):
    enforce_rate_limit(token)

    last_user = ""
    for m in reversed(req.messages):
        if m.role == "user" and m.content:
            last_user = m.content
            break
    if len(last_user) > MAX_QUESTION_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"message too long: {len(last_user)} chars > {MAX_QUESTION_CHARS}",
        )
    # 输入命中 → 400 + content_violation。前端按 detail.message 提示用户。
    if await filter_check(last_user, x_filter_token):
        print("[input-blocked] text")
        raise HTTPException(
            status_code=400,
            detail={
                "code": "content_violation",
                "category": "input_text",
                "message": "内容涉及敏感信息，请调整后重试。",
            },
        )

    sf_body: dict = {
        "model": TEXT_MODEL,
        "messages": [m.model_dump(exclude_none=True) for m in req.messages],
        "enable_thinking": False,
    }
    if req.max_tokens or req.max_length:
        sf_body["max_tokens"] = req.max_tokens or req.max_length
    if req.temperature is not None:
        sf_body["temperature"] = req.temperature
    if req.top_p is not None:
        sf_body["top_p"] = req.top_p

    sf_data = await call_siliconflow(sf_body)
    data = normalize_response(sf_data, req.model or "qwen")

    # 输出审查：命中则替换为固定话术 + finish_reason=content_filter（OpenAI 兼容）
    out_msg = data["choices"][0]["message"]
    if await filter_check(out_msg.get("content", "") or "", x_filter_token):
        out_msg["content"] = SENSITIVE_REPLY
        data["choices"][0]["finish_reason"] = "content_filter"
        print("[output-blocked] text")

    print(
        f"[chat] msgs={len(req.messages)} max_tokens={req.max_tokens} "
        f"usage={data.get('usage')}"
    )
    return data


# ----- 端点 2：图片 + 提示词 -----
@app.post("/v1/chat/completions/image")
async def chat_completions_image(
    model_name: str = Form("qwen-vl"),
    question: str = Form(...),
    image: UploadFile = File(...),
    temperature: Optional[float] = Form(None),
    top_p: Optional[float] = Form(None),
    max_tokens: Optional[int] = Form(None),
    token: str = Depends(verify_bearer),
    x_filter_token: Optional[str] = Header(None, alias="X-Filter-Token"),
):
    enforce_rate_limit(token)

    if len(question) > MAX_QUESTION_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"question too long: {len(question)} chars > {MAX_QUESTION_CHARS}",
        )
    if await filter_check(question, x_filter_token):
        print("[input-blocked] image-question")
        raise HTTPException(
            status_code=400,
            detail={
                "code": "content_violation",
                "category": "input_text",
                "message": "问题涉及敏感信息，请调整后重试。",
            },
        )

    # 推断图片 mime type：
    # - 客户端没设 content_type → fallback 到文件名/jpeg
    # - 客户端传 image/* → 直接用
    # - 客户端传 application/octet-stream（HarmonyOS NetworkKit 默认）→ 按文件名推断
    # SF vision API 的 data URL 必须是标准 image/* mime，不能是 octet-stream
    raw_ct = (image.content_type or "").lower()
    fname = (image.filename or "").lower()
    if raw_ct.startswith("image/"):
        content_type = raw_ct
    else:
        if fname.endswith(".png"):
            content_type = "image/png"
        elif fname.endswith(".webp"):
            content_type = "image/webp"
        elif fname.endswith(".gif"):
            content_type = "image/gif"
        elif fname.endswith((".jpg", ".jpeg")) or raw_ct == "application/octet-stream":
            content_type = "image/jpeg"
        else:
            raise HTTPException(
                status_code=415,
                detail=f"unsupported content_type: {raw_ct or '(none)'} for filename: {fname or '(none)'}",
            )
    img_bytes = await image.read()
    if not img_bytes:
        raise HTTPException(status_code=400, detail="empty image upload")
    b64 = base64.b64encode(img_bytes).decode()
    data_url = f"data:{content_type};base64,{b64}"

    sf_body: dict = {
        "model": VISION_MODEL,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": data_url}},
                    {"type": "text", "text": question},
                ],
            }
        ],
    }
    if max_tokens:
        sf_body["max_tokens"] = max_tokens
    if temperature is not None:
        sf_body["temperature"] = temperature
    if top_p is not None:
        sf_body["top_p"] = top_p

    sf_data = await call_siliconflow(sf_body)
    data = normalize_response(sf_data, model_name)

    out_msg = data["choices"][0]["message"]
    if await filter_check(out_msg.get("content", "") or "", x_filter_token):
        out_msg["content"] = SENSITIVE_REPLY
        data["choices"][0]["finish_reason"] = "content_filter"
        print("[output-blocked] image")

    print(
        f"[image] q_len={len(question)} img_size={len(img_bytes)} "
        f"max_tokens={max_tokens} usage={data.get('usage')}"
    )
    return data


# ----- 鉴权端点：登录用户用 app_session_token 换 vision_token -----
@app.post("/v1/auth/issue_vision_token")
async def issue_vision_token_endpoint(uid: str = Depends(verify_app_session)):
    """前端流程：AGC 登录 → sensitive-check /agc_login 拿 app_session_token →
    本接口换短期 vision_token（30 分钟）→ 调 /v1/chat/completions。"""
    return _issue_vision_token(uid)


# ----- 健康检查 + models 列表（OpenAI 兼容） -----
@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "siliconflow-relay",
        "text_model": TEXT_MODEL,
        "vision_model": VISION_MODEL,
        "upstream": SF_BASE_URL,
        "filter_url": SF_FILTER_URL,
        "auth": {
            "app_session_secret_configured": bool(_APP_SESSION_SECRET),
            "vision_token_secret_configured": bool(_VISION_TOKEN_SECRET),
            "api_keys_count": len(VALID_API_KEYS),
        },
    }


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {"id": "qwen", "object": "model", "owned_by": "siliconflow"},
            {"id": "qwen-vl", "object": "model", "owned_by": "siliconflow"},
        ],
    }


# ----- CLI -----
def _get_args():
    parser = argparse.ArgumentParser(description="SiliconFlow Relay — OpenAI-compatible proxy")
    parser.add_argument("--server-host", default="127.0.0.1")
    parser.add_argument("--server-port", type=int, default=8002)
    parser.add_argument("--api-keys", type=str, default="",
                        help="Comma-separated bearer tokens accepted by this relay. Empty = OPEN.")
    parser.add_argument("--rate-limit-per-min", type=int, default=30)
    parser.add_argument("--max-question-chars", type=int, default=3000)
    parser.add_argument("--siliconflow-key", type=str,
                        default=os.environ.get("SF_KEY", ""),
                        help="SiliconFlow API key (or set SF_KEY env var).")
    parser.add_argument("--siliconflow-base", type=str, default="https://api.siliconflow.cn/v1")
    parser.add_argument("--text-model", type=str, default="Qwen/Qwen3.5-4B")
    parser.add_argument("--vision-model", type=str, default="Qwen/Qwen3-VL-8B-Instruct")
    parser.add_argument("--sensitive-filter-url", type=str, default="http://127.0.0.1:9100")
    parser.add_argument("--http-timeout", type=float, default=60.0)
    return parser.parse_args()


if __name__ == "__main__":
    args = _get_args()
    if not args.siliconflow_key:
        raise SystemExit("--siliconflow-key (or SF_KEY env) required")
    SF_KEY = args.siliconflow_key
    SF_BASE_URL = args.siliconflow_base
    TEXT_MODEL = args.text_model
    VISION_MODEL = args.vision_model
    SF_FILTER_URL = args.sensitive_filter_url
    VALID_API_KEYS = {k.strip() for k in args.api_keys.split(",") if k.strip()}
    RATE_LIMIT_PER_MIN = max(0, int(args.rate_limit_per_min))
    MAX_QUESTION_CHARS = max(1, int(args.max_question_chars))
    HTTP_TIMEOUT = float(args.http_timeout)

    uvicorn.run(app, host=args.server_host, port=args.server_port, workers=1, log_level="info")
