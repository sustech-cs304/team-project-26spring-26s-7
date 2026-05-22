"""分享内容异步审查任务。

调用链：
  publish endpoint 成功后 → BackgroundTasks 排进来 → 本任务异步跑

行为：
  1. 拼合 tripData 里所有用户输入文本 (tripName + node.title + content + poiName)，
     一次性调 sensitive-check /text_check
  2. 遍历 photo_index_json 里的每张照片 (375w 版本即可，更小更快)，逐张调
     sensitive-check /check
  3. 任何一项命中 → mark_audit_rejected: 写 audit_status='rejected'
     + revoked_reason='CONTENT_VIOLATION' + 删除整个 cache/{short_code}/
  4. 全部通过 → mark_audit_passed
  5. 服务间走 X-Internal-Auth header，避免要 mint audit_token

fail-open：任何调用 sensitive-check 失败 (超时 / 5xx / 网络错) 都当通过处理，
只记日志，不影响业务。和 ai-relay filter_check 的策略保持一致。
"""
from __future__ import annotations

import json
import logging
import os
import shutil
from pathlib import Path
from typing import Any, Optional

import httpx

from ..db import repository_publish as repo

logger = logging.getLogger("share_service.audit")


_SENSITIVE_CHECK_URL = os.environ.get("SENSITIVE_CHECK_URL", "http://127.0.0.1:9200").rstrip("/")
_INTERNAL_SHARED_SECRET = os.environ.get("INTERNAL_SHARED_SECRET", "").strip()
_AUDIT_TIMEOUT_S = float(os.environ.get("AUDIT_TIMEOUT_S", "30.0"))


def _internal_headers() -> dict[str, str]:
    if not _INTERNAL_SHARED_SECRET:
        # 没配 secret → 服务间调用走 anonymous，sensitive-check 会拒；
        # 等价于"审核不可用"→ fail-open
        return {}
    return {"X-Internal-Auth": _INTERNAL_SHARED_SECRET}


def _collect_texts(trip_data: dict[str, Any]) -> str:
    """从 tripData 里抽取所有用户输入文本，用换行拼成一段大文本。
    保留 trip 级和 node 级的所有可填字段。"""
    parts: list[str] = []
    if trip_data.get("tripName"):
        parts.append(str(trip_data["tripName"]))
    nodes = trip_data.get("nodes") or []
    for n in nodes:
        for k in ("title", "content", "poiName"):
            v = n.get(k)
            if v and isinstance(v, str) and v.strip():
                parts.append(v.strip())
    return "\n".join(parts)


def _cache_root_path() -> Path:
    from ..core.config import get_settings  # 延迟 import 避免循环
    return Path(get_settings().db_path).resolve().parent / "cache"


async def _check_text(client: httpx.AsyncClient, text: str) -> tuple[bool, Optional[str]]:
    """调 sensitive-check /text_check。返回 (is_hit, hit_reason)。
    任何异常 → (False, None)，fail-open。"""
    if not text.strip():
        return False, None
    try:
        r = await client.post(
            f"{_SENSITIVE_CHECK_URL}/text_check",
            json={"text": text},
            headers=_internal_headers(),
            timeout=_AUDIT_TIMEOUT_S,
        )
        if r.status_code != 200:
            logger.warning("[audit] text_check returned %s: %s", r.status_code, r.text[:200])
            return False, None
        data = r.json()
        is_hit = bool(data.get("is_hit"))
        if is_hit:
            reason = data.get("conclusion") or "命中敏感内容"
            return True, reason
        return False, None
    except Exception as exc:
        logger.warning("[audit] text_check failed: %r", exc)
        return False, None


async def _check_image(client: httpx.AsyncClient, image_path: Path) -> tuple[bool, Optional[str]]:
    """调 sensitive-check /check。返回 (is_hit, hit_reason)。fail-open。"""
    if not image_path.is_file():
        logger.warning("[audit] image missing: %s", image_path)
        return False, None
    try:
        with open(image_path, "rb") as f:
            files = {"image": (image_path.name, f, "application/octet-stream")}
            data = {"img_type": "0"}
            r = await client.post(
                f"{_SENSITIVE_CHECK_URL}/check",
                files=files,
                data=data,
                headers=_internal_headers(),
                timeout=_AUDIT_TIMEOUT_S,
            )
        if r.status_code != 200:
            logger.warning("[audit] /check %s returned %s: %s",
                           image_path.name, r.status_code, r.text[:200])
            return False, None
        body = r.json()
        is_hit = bool(body.get("is_hit"))
        if is_hit:
            return True, body.get("conclusion") or "命中"
        return False, None
    except Exception as exc:
        logger.warning("[audit] /check %s failed: %r", image_path.name, exc)
        return False, None


async def audit_share(short_code: str) -> None:
    """主任务入口。FastAPI BackgroundTasks 在 publish response 返回后调度执行。"""
    row = repo.fetch_publish(short_code)
    if not row:
        logger.info("[audit] %s: row missing, skip", short_code)
        return
    if row.get("audit_status") != "pending":
        logger.info("[audit] %s: status=%s, not pending, skip", short_code, row.get("audit_status"))
        return
    if row.get("revoked_reason"):
        logger.info("[audit] %s: already revoked (%s), skip", short_code, row["revoked_reason"])
        return

    try:
        trip_data = json.loads(row["trip_data_json"])
    except Exception as exc:
        logger.error("[audit] %s: trip_data_json parse fail: %r", short_code, exc)
        repo.mark_audit_passed(short_code)  # fail-open
        return
    try:
        photo_index = json.loads(row["photo_index_json"])
    except Exception:
        photo_index = []

    cache_dir = _cache_root_path() / short_code

    async with httpx.AsyncClient() as client:
        # 1) 文本审核（一次调用聚合所有文本）
        consolidated_text = _collect_texts(trip_data)
        if consolidated_text:
            is_hit, reason = await _check_text(client, consolidated_text)
            if is_hit:
                _reject(short_code, f"text: {reason or '命中'}", cache_dir)
                return

        # 2) 图片审核：逐张 375w 版本。任一命中即终止 + reject。
        for entry in photo_index:
            paths = entry.get("paths") or {}
            relpath = paths.get("375") or paths.get("750")
            if not relpath:
                continue
            img_path = cache_dir / relpath
            is_hit, reason = await _check_image(client, img_path)
            if is_hit:
                _reject(short_code, f"image[{relpath}]: {reason or '命中'}", cache_dir)
                return

    # 3) 全过 → passed
    if repo.mark_audit_passed(short_code):
        logger.info("[audit] %s: passed", short_code)


def _reject(short_code: str, reason: str, cache_dir: Path) -> None:
    """命中后的统一处理：DB 改 rejected + 清 cache 子目录。"""
    changed = repo.mark_audit_rejected(short_code, reason)
    if changed:
        logger.warning("[audit] %s: REJECTED (%s); clearing cache dir", short_code, reason)
        try:
            shutil.rmtree(cache_dir, ignore_errors=True)
        except Exception as exc:
            logger.error("[audit] %s: rmtree failed: %r", short_code, exc)
    else:
        logger.info("[audit] %s: reject skipped (not pending anymore)", short_code)
