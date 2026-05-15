"""Pydantic models matching P08 API 规范 §4 + §6.

These intentionally use the spec field names (camelCase) — they're parsed
from / serialized to the wire exactly. The envelope `{code, message, data}`
also follows the spec verbatim (§4.4, §4.5).
"""
from typing import Any, Optional

from pydantic import BaseModel, Field


# ---- 4.2 tripData JSON ----------------------------------------------------

class PublishNode(BaseModel):
    id: str
    title: str
    content: str = ""
    poiName: str = ""
    photoCount: int = Field(..., ge=0)
    mood: str = ""
    tags: list[str] = Field(default_factory=list)
    visitedAt: Optional[int] = None
    nodeOrder: int = Field(..., ge=0)
    # alignment-doc fields, optional in spec
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class PublishTripData(BaseModel):
    tripId: str
    tripName: str
    totalDistance: float = 0.0
    coverIndex: int = 0
    createdAt: Optional[int] = None
    nodes: list[PublishNode]


# ---- 4.4 / 4.5 response envelope ------------------------------------------

class PublishOk(BaseModel):
    url: str
    shortCode: str
    expiresAt: int           # spec: Unix seconds
    sig: str                 # 64-char hex (the same value already embedded in `url`,
                             # surfaced here so clients can pass it back in
                             # `replaceShortCode` flow without re-parsing the URL.
    coverPhotoUrl: Optional[str] = None   # 公网可访问的封面图 URL（v0.7.1）。
                                          # 客户端做 QQ / 微博等系统分享时，
                                          # 把它 fetch 成 ArrayBuffer 塞进
                                          # SharedRecord.thumbnail，目标 app
                                          # 能直接渲染卡片。无封面（0 张照片）
                                          # 时为 null。


class PublishResponse(BaseModel):
    code: int = 0
    message: str = "ok"
    data: PublishOk


class ErrorResponse(BaseModel):
    code: int
    message: str
    detail: Optional[str] = None


# ---- 6.2 status -----------------------------------------------------------

class StatusOkData(BaseModel):
    shortCode: str
    expiresAt: int
    remainingSeconds: int
    publishedAt: int


class StatusResponse(BaseModel):
    code: int
    data: Optional[StatusOkData] = None
    message: Optional[str] = None


# ---- v1.0 ReplayPrefs (镜像 frontend ReplayPreferences) ------------------
# 7 个字段全部可选；publish 时缺失就用各自的 default。
# 字段值在后端做白名单校验，不在白名单内 → 直接当成 default 处理（不报错，
# 容错优先：旧前端 / 新前端 之间 enum 不同步时不至于阻塞 publish）。

# 严格对齐前端 ReplayStyleKitId / ReplayBgmId / ReplayFilterId /
# ReplayTransitionType 的 enum **value**（而非 enum 名）。值是 ArkTS 枚举里
# 等号右侧那一串小写字符串，会原样出现在 JSON wire 上。任何一边改 value
# 都要同步另一边，否则 publish 时 fallback 到 default。
REPLAY_STYLE_KITS = {"minimal_white", "dark_night", "vintage_film"}
REPLAY_BGMS       = {"morning_chill_birds", "city_lights_lofi", "jazz_night",
                     "tropical_chill_travel", "cinematic_ambient"}
REPLAY_FILTERS    = {"none", "film", "warm", "cool", "mono"}
REPLAY_TRANSITIONS = {"fade", "slide", "scale"}

REPLAY_DEFAULT = {
    "styleKitId":            "minimal_white",
    "bgmId":                 "city_lights_lofi",
    "filterId":              "none",
    "transitionType":        "fade",
    "enableBlurOverlay":     False,
    "enableRouteAnimation":  False,
    "enableRipple":          False,
}


def normalize_replay_prefs(raw: dict[str, Any]) -> dict[str, Any]:
    """白名单校验 + 缺省回填，失败容错（不抛错）。"""
    out = dict(REPLAY_DEFAULT)
    if not isinstance(raw, dict):
        return out
    if raw.get("styleKitId") in REPLAY_STYLE_KITS:
        out["styleKitId"] = raw["styleKitId"]
    if raw.get("bgmId") in REPLAY_BGMS:
        out["bgmId"] = raw["bgmId"]
    if raw.get("filterId") in REPLAY_FILTERS:
        out["filterId"] = raw["filterId"]
    if raw.get("transitionType") in REPLAY_TRANSITIONS:
        out["transitionType"] = raw["transitionType"]
    if isinstance(raw.get("enableBlurOverlay"), bool):
        out["enableBlurOverlay"] = raw["enableBlurOverlay"]
    if isinstance(raw.get("enableRouteAnimation"), bool):
        out["enableRouteAnimation"] = raw["enableRouteAnimation"]
    if isinstance(raw.get("enableRipple"), bool):
        out["enableRipple"] = raw["enableRipple"]
    return out


# ---- v0.8 revoke-by-trip -------------------------------------------------

class RevokeByTripRequest(BaseModel):
    """POST /api/v1/share/revoke-by-trip 请求体。
    tripId 是前端 RDB 里 Trip.id 对应的值（与 publish 时上传 tripData.tripId 一致）。"""
    tripId: str


class RevokeByTripData(BaseModel):
    tripId: str
    revokedCount: int


class RevokeByTripResponse(BaseModel):
    code: int = 0
    message: str = "ok"
    data: RevokeByTripData
