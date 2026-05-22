# coding=utf-8
"""独立敏感词检测服务（HTTP API）。

设计原则：
- 与 Qwen-VL / openai_api.py / share_service 解耦，不依赖任何 AI 服务
- 默认监听 0.0.0.0:9100，校园网内任意机器可直连
- 41887 词 trie + ASCII 词边界 + 单字过滤 + 内置/外置白名单（与 4-26 那版逻辑一致）
- 三个端点：/check 返回 blocked + 命中词；/mask 返回打码后文本；/batch_check 批量
"""

import hashlib
import logging
import os
from logging.handlers import RotatingFileHandler
from typing import List, Optional

import uvicorn
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address


# ---------- 日志（轮转 + 审计） ----------

_LOG_DIR = os.environ.get("SF_LOG_DIR", "/data2/cse12310817/logs")
_LOG_PATH = os.path.join(_LOG_DIR, "sensitive_filter.log")
os.makedirs(_LOG_DIR, exist_ok=True)

_handler = RotatingFileHandler(_LOG_PATH, maxBytes=50 * 1024 * 1024, backupCount=5, encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))

logger = logging.getLogger("sensitive_filter")
logger.setLevel(logging.INFO)
if not logger.handlers:
    logger.addHandler(_handler)
audit = logging.getLogger("sensitive_filter.audit")
audit.setLevel(logging.INFO)
if not audit.handlers:
    audit.addHandler(_handler)


def _hash_uid(uid: Optional[str]) -> str:
    if not uid:
        return "anon"
    return hashlib.sha256(uid.encode("utf-8")).hexdigest()[:12]


# ---------- 过滤器 ----------

class SensitiveWordFilter:
    DEFAULT_WHITELIST = frozenset([
        "活动", "活動", "小姐", "弟子", "戈壁", "谋杀",
        "套图", "逗比",
        "is", "ur",
    ])

    def __init__(self, words, whitelist=None, allow_single_char=False):
        self.trie = {}
        self.words_count = 0
        self.skipped_whitelist = 0
        self.skipped_single = 0
        wl = {w.strip().lower() for w in (whitelist or []) if w.strip()}
        wl.update(w.lower() for w in self.DEFAULT_WHITELIST)
        for raw in words:
            n = raw.strip().lower()
            if not n:
                continue
            if n in wl:
                self.skipped_whitelist += 1
                continue
            if not allow_single_char and len(n) == 1:
                self.skipped_single += 1
                continue
            node = self.trie
            for c in n:
                node = node.setdefault(c, {})
            node["$"] = {
                "word": raw.strip(),
                "ascii_only": all(c.isascii() and (c.isalnum() or c == "_") for c in n),
            }
            self.words_count += 1

    @staticmethod
    def _is_word_char(c):
        return c.isascii() and (c.isalnum() or c == "_")

    def find_all_hits(self, text):
        if not text:
            return []
        lowered = text.lower()
        n = len(lowered)
        hits = []
        i = 0
        while i < n:
            node = self.trie
            best_end = -1
            best_word = None
            for j in range(i, n):
                c = lowered[j]
                if c not in node:
                    break
                node = node[c]
                payload = node.get("$")
                if payload is None:
                    continue
                end = j + 1
                if payload["ascii_only"]:
                    left_ok = (i == 0) or (not self._is_word_char(lowered[i - 1]))
                    right_ok = (end == n) or (not self._is_word_char(lowered[end]))
                    if not (left_ok and right_ok):
                        continue
                if end > best_end:
                    best_end = end
                    best_word = payload["word"]
            if best_end > i:
                hits.append((i, best_end, best_word))
                i = best_end
            else:
                i += 1
        return hits

    def find_first_hit(self, text):
        hits = self.find_all_hits(text)
        return hits[0][2] if hits else None

    def mask_text(self, text, mask="***"):
        hits = self.find_all_hits(text)
        if not hits:
            return text, []
        parts = []
        cursor = 0
        for s, e, _ in hits:
            parts.append(text[cursor:s])
            parts.append(mask)
            cursor = e
        parts.append(text[cursor:])
        return "".join(parts), [w for _, _, w in hits]


def load_filter():
    words_file = os.environ.get("SF_WORDS_FILE", "/data2/cse12310817/sensitive_words.txt")
    wl_file = os.environ.get("SF_WHITELIST_FILE", "/data2/cse12310817/whitelist.txt")
    allow_single = os.environ.get("SF_ALLOW_SINGLE_CHAR", "0") not in ("0", "", "false", "False")

    whitelist = set()
    if os.path.exists(wl_file):
        with open(wl_file, encoding="utf-8") as f:
            whitelist = {ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")}

    words = []
    if os.path.exists(words_file):
        with open(words_file, encoding="utf-8") as f:
            words = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")]

    f = SensitiveWordFilter(words, whitelist, allow_single_char=allow_single)
    print(f"[load] words={f.words_count} whitelisted={f.skipped_whitelist} "
          f"single_char_skipped={f.skipped_single}")
    return f


# ---------- 鉴权 + 限流 ----------

# 逗号分隔的允许 token；空表示开放（dev only）。配在 ~/.env 的 SENSITIVE_API_KEYS。
_SENSITIVE_API_KEYS = {
    k.strip() for k in os.environ.get("SENSITIVE_API_KEYS", "").split(",") if k.strip()
}
_RATE_LIMIT = os.environ.get("SENSITIVE_RATE_LIMIT", "60/minute")


def verify_bearer(authorization: Optional[str] = Header(None)) -> str:
    """缺/错 token → 401；空 _SENSITIVE_API_KEYS（dev 模式）→ 放行。返回 token 用于审计。"""
    if not _SENSITIVE_API_KEYS:
        return "anon"  # dev 开放模式
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing_token")
    token = authorization.split(None, 1)[1].strip()
    if token not in _SENSITIVE_API_KEYS:
        raise HTTPException(status_code=401, detail="invalid_token")
    return token


limiter = Limiter(key_func=get_remote_address, default_limits=[])


# ---------- HTTP API ----------

app = FastAPI(title="Sensitive Word Filter Service", version="1.0")
app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "rate_limited"})


flt = load_filter()


class CheckIn(BaseModel):
    text: str


class CheckOut(BaseModel):
    blocked: bool
    hit: Optional[str] = None
    hits_count: int = 0


class MaskIn(BaseModel):
    text: str
    mask: Optional[str] = "***"


class MaskOut(BaseModel):
    masked: str
    hits: List[str]
    hits_count: int


class BatchCheckIn(BaseModel):
    texts: List[str]


class BatchCheckOut(BaseModel):
    results: List[CheckOut]


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "sensitive-filter",
        "words_loaded": flt.words_count,
        "whitelist_skipped": flt.skipped_whitelist,
        "single_char_skipped": flt.skipped_single,
    }


@app.post("/check", response_model=CheckOut)
@limiter.limit(_RATE_LIMIT)
def check(
    request: Request,
    req: CheckIn,
    _token: str = Depends(verify_bearer),
    x_user_uid: Optional[str] = Header(None, alias="X-User-Uid"),
):
    hits = flt.find_all_hits(req.text)
    if not hits:
        return CheckOut(blocked=False)
    audit.info("HIT endpoint=/check uid=%s text_len=%d hit=%s hits_count=%d",
               _hash_uid(x_user_uid), len(req.text), hits[0][2], len(hits))
    return CheckOut(blocked=True, hit=hits[0][2], hits_count=len(hits))


@app.post("/mask", response_model=MaskOut)
@limiter.limit(_RATE_LIMIT)
def mask(
    request: Request,
    req: MaskIn,
    _token: str = Depends(verify_bearer),
    x_user_uid: Optional[str] = Header(None, alias="X-User-Uid"),
):
    masked, hit_words = flt.mask_text(req.text, mask=req.mask or "***")
    if hit_words:
        audit.info("HIT endpoint=/mask uid=%s text_len=%d hits_count=%d hits=%s",
                   _hash_uid(x_user_uid), len(req.text), len(hit_words), ",".join(hit_words[:5]))
    return MaskOut(masked=masked, hits=hit_words, hits_count=len(hit_words))


@app.post("/batch_check", response_model=BatchCheckOut)
@limiter.limit(_RATE_LIMIT)
def batch_check(
    request: Request,
    req: BatchCheckIn,
    _token: str = Depends(verify_bearer),
    x_user_uid: Optional[str] = Header(None, alias="X-User-Uid"),
):
    out = []
    blocked_count = 0
    for t in req.texts:
        hits = flt.find_all_hits(t)
        if hits:
            blocked_count += 1
            out.append(CheckOut(blocked=True, hit=hits[0][2], hits_count=len(hits)))
        else:
            out.append(CheckOut(blocked=False))
    if blocked_count:
        audit.info("HIT endpoint=/batch_check uid=%s total=%d blocked=%d",
                   _hash_uid(x_user_uid), len(req.texts), blocked_count)
    return BatchCheckOut(results=out)


if __name__ == "__main__":
    host = os.environ.get("SF_HOST", "0.0.0.0")
    port = int(os.environ.get("SF_PORT", "9100"))
    print(f"[boot] sensitive-filter on {host}:{port}")
    uvicorn.run(app, host=host, port=port, log_level="info")
