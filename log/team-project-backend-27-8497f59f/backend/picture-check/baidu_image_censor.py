# coding=utf-8
"""
百度云智能平台图片审核 RESTful API。

设计原则：
- 与 ai-service / sensitive_filter_service 解耦，不依赖任何 AI 服务/GPU
- 默认监听 0.0.0.0:9200，校园网内任意机器可直连
- 支持图片文件上传（Base64）或图片 URL 两种方式
- Baidu access_token 启动时获取并缓存，同时打印过期时间供监控

依赖：fastapi, uvicorn, requests
"""

import argparse
import base64
import logging
import os
import time
from logging.handlers import RotatingFileHandler
from typing import List, Optional

import requests
import uvicorn
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address


# ---------- 日志（轮转） ----------

_LOG_DIR = os.environ.get("BIC_LOG_DIR", "/data2/cse12310817/logs")
_LOG_PATH = os.path.join(_LOG_DIR, "picture_check.log")
os.makedirs(_LOG_DIR, exist_ok=True)

_handler = RotatingFileHandler(_LOG_PATH, maxBytes=50 * 1024 * 1024, backupCount=5, encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))

logger = logging.getLogger("picture_check")
logger.setLevel(logging.INFO)
if not logger.handlers:
    logger.addHandler(_handler)


# ---------- Token 管理 ----------

# 全局配置（main 块初始化后生效）
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


_TOKEN_REFRESH_LEEWAY_SEC = 7200  # 提前 2h 刷新，避免高并发瞬间过期


def ensure_token() -> str:
    """Token 临近过期（剩余 < 2h）时自动刷新。"""
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


# ---------- 鉴权 + 限流 ----------

# 逗号分隔的允许 token；空表示开放（dev only）。配在 ~/.env 的 BIC_API_KEYS。
_BIC_API_KEYS = {
    k.strip() for k in os.environ.get("BIC_API_KEYS", "").split(",") if k.strip()
}
_RATE_LIMIT = os.environ.get("BIC_RATE_LIMIT", "30/minute")


def verify_bearer(authorization: Optional[str] = Header(None)) -> str:
    if not _BIC_API_KEYS:
        return "anon"
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    token = authorization.split(None, 1)[1].strip()
    if token not in _BIC_API_KEYS:
        raise HTTPException(status_code=401, detail="invalid_token")
    return token


limiter = Limiter(key_func=get_remote_address, default_limits=[])


# ---------- FastAPI 应用 ----------

app = FastAPI(title="Baidu Image Censor Service", version="1.0")
app.state.limiter = limiter


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


_MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB；百度云本身上限 4MB Base64，留余量


@app.post("/check", response_model=CheckOut)
@limiter.limit(_RATE_LIMIT)
def check(
    request: Request,
    image: UploadFile = File(...),
    img_type: Optional[int] = Form(0),
    _token: str = Depends(verify_bearer),
):
    """
    上传图片文件，Base64 发送给百度审核。
    img_type: 0=静态图（默认），1=GIF 动态图
    """
    contents = image.file.read()
    if len(contents) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"image too large: {len(contents)} bytes > limit {_MAX_UPLOAD_BYTES}",
        )
    b64 = base64.b64encode(contents).decode("utf-8")
    return _do_censor(image_b64=b64, img_type=img_type)


@app.post("/check_url", response_model=CheckOut)
@limiter.limit(_RATE_LIMIT)
def check_url(
    request: Request,
    req: CheckUrlIn,
    _token: str = Depends(verify_bearer),
):
    return _do_censor(img_url=req.imgUrl, img_type=req.img_type)


def _do_censor(
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

    resp = requests.post(endpoint, headers=headers, data=data, timeout=60)
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


_MAX_TEXT_BYTES = 20000  # 百度文本审核上限约 20000 字节


def _do_text_censor(text: str, user_id: Optional[str] = None, user_ip: Optional[str] = None) -> TextCheckOut:
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

    resp = requests.post(endpoint, headers=headers, data=data, timeout=30)
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
def text_check(
    request: Request,
    req: TextCheckIn,
    _token: str = Depends(verify_bearer),
):
    """
    文本审核，支持最长 20000 字节文本。
    """
    return _do_text_censor(req.text, user_id=req.user_id, user_ip=req.user_ip)


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