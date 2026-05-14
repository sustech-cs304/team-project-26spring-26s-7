import os
from functools import lru_cache


class Settings:
    def __init__(self) -> None:
        key = os.environ.get("SHARE_HMAC_KEY")
        if not key:
            raise RuntimeError(
                "SHARE_HMAC_KEY env var is required. Generate one with: "
                "python -c \"import secrets;print(secrets.token_urlsafe(32))\""
            )
        self.share_hmac_key: bytes = key.encode("utf-8")
        self.db_path: str = os.environ.get("DB_PATH", "./share.db")
        cors = os.environ.get("CORS_ORIGINS", "")
        self.cors_origins: list[str] = [o.strip() for o in cors.split(",") if o.strip()]
        self.mock_storage_base: str = os.environ.get(
            "MOCK_STORAGE_BASE", "https://mock-storage.travelpin.app"
        )
        self.public_base: str = os.environ.get(
            "SHARE_PUBLIC_BASE", "https://share.travelpin.app"
        )
        self.allow_dev_uid: bool = os.environ.get("ALLOW_DEV_UID_HEADER") == "1"
        # v1.0.6: AMap JS API。空字符串表示"未配置 AMap"，viewer 会回退到老 Leaflet。
        self.amap_key: str = os.environ.get("AMAP_KEY", "")
        self.amap_security_code: str = os.environ.get("AMAP_SECURITY_CODE", "")


@lru_cache
def get_settings() -> Settings:
    return Settings()


def reset_settings_cache() -> None:
    get_settings.cache_clear()
