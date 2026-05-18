# coding=utf-8
"""Baidu image/text content audit service."""

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import subprocess
import time
from logging.handlers import RotatingFileHandler
from typing import Any, Dict, List, Optional

import httpx
import requests
import uvicorn
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address



def _load_dotenv_from_same_dir() -> None:
    dotenv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if not os.path.exists(dotenv_path):
        return

    with open(dotenv_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if not key or key in os.environ:
                continue

            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            os.environ[key] = value


_load_dotenv_from_same_dir()

# ---------- 日志（轮转） ----------

_LOG_DIR = os.environ.get("BIC_LOG_DIR", "/home/26s-7/picture-check/logs")
_LOG_PATH = os.path.join(_LOG_DIR, "picture_check.log")
os.makedirs(_LOG_DIR, exist_ok=True)

_handler = RotatingFileHandler(_LOG_PATH, maxBytes=50 * 1024 * 1024, backupCount=5, encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))

logger = logging.getLogger("picture_check")
logger.setLevel(logging.INFO)
if not logger.handlers:
    logger.addHandler(_handler)


# ---------- Token 管理 ----------

# 全局配置，在 main 初始化后生效
_config = {"api_key": "", "secret_key": "", "access_token": "", "token_expires_at": 0.0}


def _fetch_access_token(api_key: str, secret_key: str) -> tuple[str, float]:
    url = "https://aip.baidubce.com/oauth/2.0/token"
    params = {
        "grant_type": "client_credentials",
        "client_id": api_key,
        "client_secret": secret_key,
    }
    resp = requests.post(url, params=params, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    if "access_token" not in data:
        raise RuntimeError(f"Baidu token fetch failed: {data}")
    return data["access_token"], time.time() + float(data.get("expires_in", 0))

_TOKEN_REFRESH_LEEWAY_SEC = 7200


def ensure_token() -> str:
    """Refresh the Baidu access token before it expires."""
    now = time.time()
    cfg = _config
    if cfg["access_token"] and now < cfg["token_expires_at"] - _TOKEN_REFRESH_LEEWAY_SEC:
        return cfg["access_token"]
    token, expires_at = _fetch_access_token(cfg["api_key"], cfg["secret_key"])
    cfg["access_token"] = token
    cfg["token_expires_at"] = expires_at
    expires_in = max(0, expires_at - now)
    logger.info("[token] refreshed, expires in %.0fs (~%s)",
                expires_in,
                time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(expires_at)))
    return token


# ---------- Pydantic 模型 ----------


class CheckUrlIn(BaseModel):
    imgUrl: str
    img_type: Optional[int] = 0


class CheckOut(BaseModel):
    conclusion: str          # 合规 / 不合规 / 疑似 / 审核失败
    conclusionType: int      # 1=合规, 2=不合规, 3=疑似, 4=审核失败
    log_id: int
    is_safe: bool            # True when conclusionType == 1
    is_hit: bool             # True when conclusionType in (2, 3)
    error_code: Optional[int] = None
    error_msg: Optional[str] = None
    data: List[dict] = []


# ---------- 文本审核模型 ----------

class TextCheckIn(BaseModel):
    text: str
    user_id: Optional[str] = None
    user_ip: Optional[str] = None


class TextCheckOut(BaseModel):
    conclusion: str          # 合规 / 不合规 / 疑似 / 审核失败
    conclusionType: int      # 1=合规, 2=不合规, 3=疑似, 4=审核失败
    log_id: int
    is_safe: bool
    is_hit: bool
    error_code: Optional[int] = None
    error_msg: Optional[str] = None
    data: List[dict] = []


class HuaweiLoginIn(BaseModel):
    authorization_code: str


class AgcLoginIn(BaseModel):
    access_token: str


class HuaweiLoginOut(BaseModel):
    token_type: str = "Bearer"
    app_session_token: str
    issued_at: int
    expires_in: int
    uid: str


class IssueAuditTokenOut(BaseModel):
    token_type: str = "Bearer"
    filter_token: str
    censor_token: str
    issued_at: int
    expires_in: int


# ---------- 鉴权与限流 ----------

_RATE_LIMIT = os.environ.get("BIC_RATE_LIMIT", "30/minute")

# 百度审核 API 的硬约束：图像 QPS=1 + 文本 QPS=1（**两个独立桶**，不互相算）。
# v1.2 修：之前两类共用一个 Semaphore，导致 ai-relay 频繁调 /text_check 时
# 头像审核 /check 被卡 >30s 触发前端超时（nginx 看到 HTTP 499）。
# 现在 image / text 各自一组 sem + qps lock。
_BAIDU_QPS_INTERVAL = float(os.environ.get("BIC_BAIDU_QPS_INTERVAL", "1.05"))
_BAIDU_QUEUE_DEPTH = int(os.environ.get("BIC_BAIDU_QUEUE_DEPTH", "5"))
_baidu_image_sem: Optional[asyncio.Semaphore] = None
_baidu_text_sem: Optional[asyncio.Semaphore] = None
_baidu_image_lock: Optional[asyncio.Lock] = None
_baidu_text_lock: Optional[asyncio.Lock] = None
_baidu_image_last_t: float = 0.0
_baidu_text_last_t: float = 0.0
_baidu_client: Optional[httpx.AsyncClient] = None


async def _baidu_call_serial(url: str, *, kind: str, data: dict,
                              headers: Optional[dict] = None,
                              timeout: float = 30.0) -> httpx.Response:
    """串行调百度，强制 1 QPS，队列上限 5。

    kind="image" → /check + /check_url，走 _baidu_image_sem
    kind="text"  → /text_check，走 _baidu_text_sem
    两类独立 — 百度图像和文本 QPS 是分开计的。
    """
    global _baidu_image_last_t, _baidu_text_last_t
    if kind == "image":
        sem = _baidu_image_sem
        lock = _baidu_image_lock
    elif kind == "text":
        sem = _baidu_text_sem
        lock = _baidu_text_lock
    else:
        raise HTTPException(status_code=500, detail=f"unknown baidu kind: {kind}")

    if sem is None or lock is None or _baidu_client is None:
        raise HTTPException(status_code=503, detail="audit_service_initializing")
    # 拿不到 sem（队列满）→ 立刻 503
    try:
        await asyncio.wait_for(sem.acquire(), timeout=0.1)
    except asyncio.TimeoutError:
        raise HTTPException(
            status_code=503,
            detail={"code": "audit_queue_full", "message": "审核队列繁忙，请稍后重试。"},
            headers={"Retry-After": "5"},
        )
    try:
        # 强制 1 QPS：跟该类型上次调用至少间隔 _BAIDU_QPS_INTERVAL
        async with lock:
            now = time.monotonic()
            last_t = _baidu_image_last_t if kind == "image" else _baidu_text_last_t
            wait = _BAIDU_QPS_INTERVAL - (now - last_t)
            if wait > 0:
                await asyncio.sleep(wait)
            if kind == "image":
                _baidu_image_last_t = time.monotonic()
            else:
                _baidu_text_last_t = time.monotonic()
        return await _baidu_client.post(url, data=data, headers=headers or {}, timeout=timeout)
    finally:
        sem.release()
_APP_SESSION_TTL_SECONDS = int(os.environ.get("APP_SESSION_TTL_SECONDS", str(7 * 24 * 3600)))
_APP_SESSION_SECRET = os.environ.get("APP_SESSION_SECRET", "")
_AUDIT_TOKEN_TTL_SECONDS = int(os.environ.get("BIC_AUDIT_TOKEN_TTL_SECONDS", "1800"))
_AUDIT_TOKEN_SECRET = os.environ.get("BIC_AUDIT_TOKEN_SECRET", "")
_AGC_CREDENTIAL_PATH = os.environ.get("AGC_API_CLIENT_CREDENTIAL_PATH", "")
_HUAWEI_OAUTH_TOKEN_URL = os.environ.get(
    "HUAWEI_OAUTH_TOKEN_URL",
    "https://account-api.cloud.huawei.com/restapi/oauth2/v2/token",
)
_HUAWEI_REDIRECT_URI = os.environ.get("HUAWEI_REDIRECT_URI", "")
_AGC_AUTH_VERIFY_SCRIPT = os.environ.get(
    "AGC_AUTH_VERIFY_SCRIPT",
    os.path.join(os.path.dirname(__file__), "agc_verify_token.js"),
)
_AGC_NODE_BIN = os.environ.get("AGC_NODE_BIN", "node")
_AGC_AUTH_VERIFY_TIMEOUT_SECONDS = int(os.environ.get("AGC_AUTH_VERIFY_TIMEOUT_SECONDS", "8"))


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode((data + padding).encode("ascii"))


def _get_secret(value: str, name: str) -> bytes:
    if not value:
        raise HTTPException(status_code=500, detail=f"{name}_not_configured")
    return value.encode("utf-8")


def _sign_payload(payload: Dict[str, Any], secret: str, secret_name: str) -> str:
    body = _b64url_encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = hmac.new(_get_secret(secret, secret_name), body.encode("ascii"), hashlib.sha256).digest()
    return f"{body}.{_b64url_encode(signature)}"


def _verify_signed_payload(token: str, secret: str, secret_name: str, scope: str) -> Dict[str, Any]:
    try:
        body, signature = token.rsplit(".", 1)
    except ValueError:
        raise HTTPException(status_code=401, detail="invalid_token")

    expected = hmac.new(_get_secret(secret, secret_name), body.encode("ascii"), hashlib.sha256).digest()
    actual = _b64url_decode(signature)
    if not hmac.compare_digest(expected, actual):
        raise HTTPException(status_code=401, detail="invalid_token")

    try:
        payload = json.loads(_b64url_decode(body).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(status_code=401, detail="invalid_token")

    now = int(time.time())
    if int(payload.get("exp", 0)) <= now:
        raise HTTPException(status_code=401, detail="token_expired")
    if payload.get("scope") != scope:
        raise HTTPException(status_code=403, detail="invalid_scope")
    return payload


def _issue_audit_token(uid: str) -> IssueAuditTokenOut:
    now = int(time.time())
    payload: Dict[str, Any] = {
        "uid": uid,
        "scope": "audit",
        "iat": now,
        "exp": now + _AUDIT_TOKEN_TTL_SECONDS,
        "jti": secrets.token_urlsafe(12),
    }
    token = _sign_payload(payload, _AUDIT_TOKEN_SECRET, "audit_token_secret")
    return IssueAuditTokenOut(
        filter_token=token,
        censor_token=token,
        issued_at=now,
        expires_in=_AUDIT_TOKEN_TTL_SECONDS,
    )


def _issue_app_session_token(uid: str) -> HuaweiLoginOut:
    now = int(time.time())
    payload: Dict[str, Any] = {
        "uid": uid,
        "scope": "app",
        "iat": now,
        "exp": now + _APP_SESSION_TTL_SECONDS,
        "jti": secrets.token_urlsafe(12),
    }
    token = _sign_payload(payload, _APP_SESSION_SECRET, "app_session_secret")
    return HuaweiLoginOut(
        app_session_token=token,
        issued_at=now,
        expires_in=_APP_SESSION_TTL_SECONDS,
        uid=uid,
    )


def _verify_app_session_token(token: str) -> str:
    payload = _verify_signed_payload(token, _APP_SESSION_SECRET, "app_session_secret", "app")
    uid = str(payload.get("uid", "")).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="session_missing_uid")
    return uid


def _verify_audit_token(token: str) -> Dict[str, Any]:
    return _verify_signed_payload(token, _AUDIT_TOKEN_SECRET, "audit_token_secret", "audit")


_INTERNAL_SHARED_SECRET = os.environ.get("INTERNAL_SHARED_SECRET", "").strip()


def verify_bearer(
    authorization: Optional[str] = Header(None),
    x_internal_auth: Optional[str] = Header(None, alias="X-Internal-Auth"),
) -> str:
    """同时接受两种来源：
    - 用户请求：Authorization: Bearer <audit_token>
    - 服务间请求：X-Internal-Auth: <INTERNAL_SHARED_SECRET>（仅 share-service 等内部服务用）

    内部调用走 X-Internal-Auth，避免 share-service 还要去 mint audit_token；
    这个 secret 只在服务器 .env 里，公网用户无法获取。
    """
    if _INTERNAL_SHARED_SECRET and x_internal_auth and \
            hmac.compare_digest(x_internal_auth, _INTERNAL_SHARED_SECRET):
        return "internal:share-service"
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    token = authorization.split(None, 1)[1].strip()
    payload = _verify_audit_token(token)
    return str(payload.get("uid", "unknown"))


def _require_bearer_token(authorization: Optional[str]) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    return authorization.split(None, 1)[1].strip()


def _load_agc_credential() -> Dict[str, Any]:
    if not _AGC_CREDENTIAL_PATH:
        raise HTTPException(status_code=500, detail="agc_credential_path_not_configured")
    try:
        with open(_AGC_CREDENTIAL_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except OSError as exc:
        logger.exception("[auth] cannot read AGC credential: %s", exc)
        raise HTTPException(status_code=500, detail="agc_credential_unreadable")

    if not data.get("client_id") or not data.get("client_secret"):
        raise HTTPException(status_code=500, detail="agc_credential_missing_client")
    return data


def _decode_jwt_payload_unverified(token: str) -> Dict[str, Any]:
    try:
        parts = token.split(".")
        if len(parts) < 2:
            raise ValueError("not a jwt")
        return json.loads(_b64url_decode(parts[1]).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=401, detail=f"invalid_id_token: {exc}")


def _exchange_huawei_authorization_code(code: str) -> Dict[str, Any]:
    credential = _load_agc_credential()
    form = {
        "grant_type": "authorization_code",
        "code": code,
        "client_id": credential["client_id"],
        "client_secret": credential["client_secret"],
    }
    if _HUAWEI_REDIRECT_URI:
        form["redirect_uri"] = _HUAWEI_REDIRECT_URI

    try:
        resp = requests.post(_HUAWEI_OAUTH_TOKEN_URL, data=form, timeout=15)
    except requests.RequestException as exc:
        logger.exception("[auth] Huawei token exchange request failed: %s", exc)
        raise HTTPException(status_code=502, detail="huawei_token_exchange_failed")

    if resp.status_code != 200:
        logger.warning("[auth] Huawei token exchange rejected: status=%s body=%s", resp.status_code, resp.text[:500])
        raise HTTPException(status_code=401, detail="invalid_authorization_code")

    body = resp.json()
    id_token = body.get("id_token")
    if not id_token:
        uid = body.get("openid") or body.get("open_id") or body.get("unionid") or body.get("union_id")
        if uid:
            return {"uid": str(uid), "claims": body}
        raise HTTPException(status_code=401, detail="huawei_response_missing_identity")

    claims = _decode_jwt_payload_unverified(id_token)
    now = int(time.time())
    exp = int(claims.get("exp", 0) or 0)
    if exp and exp <= now:
        raise HTTPException(status_code=401, detail="id_token_expired")

    aud = str(claims.get("aud", ""))
    if aud and aud != str(credential["client_id"]):
        raise HTTPException(status_code=401, detail="id_token_audience_mismatch")

    uid = claims.get("sub") or claims.get("uid") or claims.get("user_id") or claims.get("open_id")
    if not uid:
        raise HTTPException(status_code=401, detail="id_token_missing_uid")
    return {"uid": str(uid), "claims": claims}


def _verify_agc_access_token(access_token: str) -> Dict[str, Any]:
    """Verify an AGC Auth access token through Huawei's Node.js Server SDK."""
    token = access_token.strip()
    if not token:
        raise HTTPException(status_code=400, detail="missing_access_token")
    if not _AGC_CREDENTIAL_PATH:
        raise HTTPException(status_code=500, detail="agc_credential_path_not_configured")
    if not os.path.exists(_AGC_AUTH_VERIFY_SCRIPT):
        raise HTTPException(status_code=500, detail="agc_auth_verifier_missing")

    try:
        proc = subprocess.run(
            [_AGC_NODE_BIN, _AGC_AUTH_VERIFY_SCRIPT, _AGC_CREDENTIAL_PATH],
            input=token,
            text=True,
            capture_output=True,
            timeout=_AGC_AUTH_VERIFY_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="node_runtime_missing")
    except subprocess.TimeoutExpired as exc:
        stderr = exc.stderr or ""
        stdout = exc.stdout or ""
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        logger.warning(
            "[auth] AGC token verify timeout after %ss stderr=%s stdout=%s",
            _AGC_AUTH_VERIFY_TIMEOUT_SECONDS,
            stderr.strip()[:500],
            stdout.strip()[:200],
        )
        if stdout.strip():
            try:
                body = json.loads(stdout)
            except ValueError:
                pass
            else:
                uid = str(body.get("uid", "")).strip()
                if uid:
                    return {"uid": uid, "claims": body}
        raise HTTPException(status_code=502, detail="agc_token_verify_timeout")

    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()[:500]
        logger.warning("[auth] AGC token verify rejected: code=%s stderr=%s", proc.returncode, stderr)
        if "Cannot find module" in stderr:
            raise HTTPException(status_code=500, detail=f"agc_verifier_module_missing: {stderr}")
        raise HTTPException(status_code=401, detail=f"invalid_agc_access_token: {stderr}")

    stderr = (proc.stderr or "").strip()
    if stderr:
        logger.info("[auth] AGC token verify stderr=%s", stderr[:500])

    try:
        body = json.loads(proc.stdout)
    except ValueError as exc:
        logger.warning("[auth] AGC token verify invalid output: %s", proc.stdout[:500])
        raise HTTPException(status_code=502, detail=f"agc_token_verify_invalid_output: {exc}")

    uid = str(body.get("uid", "")).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="agc_token_missing_uid")
    return body


def _audit_rate_key(request: Request) -> str:
    """slowapi key_func：优先按 Bearer audit_token 解 uid 限流。
    nginx 反代后 client.host 全是 127.0.0.1，per-IP 退化成全局桶，所以必须 per-uid。
    内部服务间调用（X-Internal-Auth）单独走 'internal' 桶，不挤公网用户。
    """
    # 内部调用单独桶
    if _INTERNAL_SHARED_SECRET:
        x_internal = request.headers.get("x-internal-auth", "")
        if x_internal and hmac.compare_digest(x_internal, _INTERNAL_SHARED_SECRET):
            return "internal:share-service"
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        token = auth.split(None, 1)[1].strip()
        try:
            payload = _verify_signed_payload(token, _AUDIT_TOKEN_SECRET, "audit_token_secret", "audit")
            uid = str(payload.get("uid", "")).strip()
            if uid:
                return f"uid:{uid}"
        except Exception:
            pass
    return get_remote_address(request)


limiter = Limiter(key_func=_audit_rate_key, default_limits=[])


# ---------- FastAPI 应用 ----------

app = FastAPI(title="Baidu Image Censor Service", version="1.0")
app.state.limiter = limiter


@app.on_event("startup")
async def _init_baidu_gateway():
    """初始化百度审核 API 的串行调用 gateway（image / text 独立）。"""
    global _baidu_image_sem, _baidu_text_sem, _baidu_image_lock, _baidu_text_lock, _baidu_client
    _baidu_image_sem = asyncio.Semaphore(_BAIDU_QUEUE_DEPTH)
    _baidu_text_sem = asyncio.Semaphore(_BAIDU_QUEUE_DEPTH)
    _baidu_image_lock = asyncio.Lock()
    _baidu_text_lock = asyncio.Lock()
    _baidu_client = httpx.AsyncClient(timeout=30.0)
    logger.info(
        "[boot] baidu gateway initialized: qps_interval=%.2fs queue_depth=%d (image+text independent)",
        _BAIDU_QPS_INTERVAL, _BAIDU_QUEUE_DEPTH,
    )


@app.on_event("shutdown")
async def _close_baidu_gateway():
    if _baidu_client is not None:
        await _baidu_client.aclose()


@app.exception_handler(RateLimitExceeded)
async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "rate_limited"})


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "baidu-image-censor",
        "token_cached": bool(_config["access_token"]),
        "token_expires_at": _config["token_expires_at"],
    }


@app.post("/api/v1/auth/huawei_login", response_model=HuaweiLoginOut)
def huawei_login(req: HuaweiLoginIn):
    code = req.authorization_code.strip()
    if not code:
        raise HTTPException(status_code=400, detail="missing_authorization_code")
    identity = _exchange_huawei_authorization_code(code)
    return _issue_app_session_token(identity["uid"])


@app.post("/api/v1/auth/agc_login", response_model=HuaweiLoginOut)
def agc_login(req: AgcLoginIn):
    identity = _verify_agc_access_token(req.access_token)
    return _issue_app_session_token(identity["uid"])


@app.post("/api/v1/auth/issue_audit_token", response_model=IssueAuditTokenOut)
def issue_audit_token(
    authorization: Optional[str] = Header(None),
):
    """Exchange an app session token for a short-lived audit token."""
    uid = _verify_app_session_token(_require_bearer_token(authorization))
    return _issue_audit_token(uid)


_MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB; Baidu has its own Base64 size limit, keep some buffer here.


@app.post("/check", response_model=CheckOut)
@limiter.limit(_RATE_LIMIT)
async def check(
    request: Request,
    image: UploadFile = File(...),
    img_type: Optional[int] = Form(0),
    _token: str = Depends(verify_bearer),
):
    """Upload an image file and send it to Baidu image censor."""
    contents = await image.read()
    if len(contents) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"image too large: {len(contents)} bytes > limit {_MAX_UPLOAD_BYTES}",
        )
    b64 = base64.b64encode(contents).decode("utf-8")
    return await _do_censor(image_b64=b64, img_type=img_type)


@app.post("/check_url", response_model=CheckOut)
@limiter.limit(_RATE_LIMIT)
async def check_url(
    request: Request,
    req: CheckUrlIn,
    _token: str = Depends(verify_bearer),
):
    return await _do_censor(img_url=req.imgUrl, img_type=req.img_type)


async def _do_censor(
    image_b64: Optional[str] = None,
    img_url: Optional[str] = None,
    img_type: int = 0,
) -> CheckOut:
    token = ensure_token()
    endpoint = (f"https://aip.baidubce.com/rest/2.0/solution/v1/img_censor/v2/user_defined"
                f"?access_token={token}")

    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    data: dict = {"imgType": str(img_type)}

    if image_b64 is not None:
        data["image"] = image_b64
    elif img_url is not None:
        data["imgUrl"] = img_url
    else:
        raise HTTPException(status_code=400, detail="Either image or imgUrl must be provided")

    resp = await _baidu_call_serial(endpoint, kind="image", data=data, headers=headers, timeout=60.0)
    raw = resp.json()

    log_id = raw.get("log_id", 0)
    conclusion = raw.get("conclusion", "审核失败")
    conclusion_type = int(raw.get("conclusionType", 4))
    error_code = raw.get("error_code")
    error_msg = raw.get("error_msg")

    raw_data = raw.get("data") or []
    data_list = [
        {
            "type": d.get("type"),
            "subType": d.get("subType"),
            "msg": d.get("msg"),
            "probability": d.get("probability"),
            "location": d.get("location"),
        }
        for d in raw_data
    ]

    if error_code is not None:
        logger.warning("[censor] Baidu error: code=%s, msg=%s", error_code, error_msg)

    return CheckOut(
        conclusion=conclusion,
        conclusionType=conclusion_type,
        log_id=log_id,
        is_safe=conclusion_type == 1,
        is_hit=conclusion_type in (2, 3),
        error_code=error_code,
        error_msg=error_msg,
        data=data_list,
    )


_MAX_TEXT_BYTES = 20000  # Baidu text audit limit is about 20000 bytes.


async def _do_text_censor(text: str, user_id: Optional[str] = None, user_ip: Optional[str] = None) -> TextCheckOut:
    if len(text.encode("utf-8")) > _MAX_TEXT_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"text too large: {len(text.encode('utf-8'))} bytes > limit {_MAX_TEXT_BYTES}",
        )

    token = ensure_token()
    endpoint = (f"https://aip.baidubce.com/rest/2.0/solution/v1/text_censor/v2/user_defined"
                f"?access_token={token}")

    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    data: dict = {"text": text}
    if user_id:
        data["userId"] = user_id
    if user_ip:
        data["userIp"] = user_ip

    resp = await _baidu_call_serial(endpoint, kind="text", data=data, headers=headers, timeout=30.0)
    raw = resp.json()

    log_id = raw.get("log_id", 0)
    conclusion = raw.get("conclusion", "审核失败")
    conclusion_type = int(raw.get("conclusionType", 4))
    error_code = raw.get("error_code")
    error_msg = raw.get("error_msg")

    raw_data = raw.get("data") or []
    data_list = [
        {
            "type": d.get("type"),
            "subType": d.get("subType"),
            "msg": d.get("msg"),
            "probability": d.get("probability"),
            "keyword": d.get("keyword"),
        }
        for d in raw_data
    ]

    if error_code is not None:
        logger.warning("[text_censor] Baidu error: code=%s, msg=%s", error_code, error_msg)
        raise HTTPException(status_code=502, detail=f"baidu_text_censor_error:{error_code}:{error_msg}")

    return TextCheckOut(
        conclusion=conclusion,
        conclusionType=conclusion_type,
        log_id=log_id,
        is_safe=conclusion_type == 1,
        is_hit=conclusion_type in (2, 3),
        error_code=error_code,
        error_msg=error_msg,
        data=data_list,
    )


@app.post("/text_check", response_model=TextCheckOut)
@limiter.limit(_RATE_LIMIT)
async def text_check(
    request: Request,
    req: TextCheckIn,
    _token: str = Depends(verify_bearer),
):
    """Send text to Baidu text censor."""
    return await _do_text_censor(req.text, user_id=req.user_id, user_ip=req.user_ip)


# ---------- 启动 ----------

def _get_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Baidu Image Censor Service")
    parser.add_argument(
        "--api-key", default=os.environ.get("BIC_API_KEY", ""),
        help="Baidu API Key (or env BIC_API_KEY)")
    parser.add_argument(
        "--secret-key", default=os.environ.get("BIC_SECRET_KEY", ""),
        help="Baidu Secret Key (or env BIC_SECRET_KEY)")
    parser.add_argument(
        "--host", default=os.environ.get("BIC_HOST", "0.0.0.0"),
        help="Listen host (default 0.0.0.0)")
    parser.add_argument(
        "--port", type=int, default=int(os.environ.get("BIC_PORT", "9200")),
        help="Listen port (default 9200)")
    return parser.parse_args()


if __name__ == "__main__":
    args = _get_args()

    if not args.api_key or not args.secret_key:
        logger.error("[boot] --api-key and --secret-key are required")
        logger.error("  Set env BIC_API_KEY / BIC_SECRET_KEY or pass --api-key / --secret-key")
        exit(1)

    _config["api_key"] = args.api_key
    _config["secret_key"] = args.secret_key

    try:
        tok = ensure_token()
        logger.info("[boot] token OK, starts with: %s...", tok[:8])
    except Exception as e:
        logger.exception("[boot] FATAL: cannot fetch Baidu access token: %s", e)
        exit(1)

    logger.info("[boot] baidu-image-censor on %s:%s", args.host, args.port)
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
