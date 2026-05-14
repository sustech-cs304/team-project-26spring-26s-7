from typing import Any

from pydantic import BaseModel, Field


class CreateShareRequest(BaseModel):
    tripCloudId: str = Field(..., min_length=1, max_length=128)
    expireDays: int
    snapshot: dict[str, Any]
    photoManifest: list[str] = Field(default_factory=list, max_length=50)
    consentVersion: str = Field(..., min_length=1, max_length=64)


class CreateShareResponse(BaseModel):
    shortCode: str
    sig: str
    url: str
    expireAt: int


class ShareViewResponse(BaseModel):
    snapshot: dict[str, Any]
    photoUrls: dict[str, str]
    expireAt: int
    viewCount: int


class RevokeResponse(BaseModel):
    revoked: bool


class MyShareItem(BaseModel):
    shortCode: str
    tripCloudId: str
    expireAt: int
    revoked: bool
    viewCount: int
    createdAt: int
