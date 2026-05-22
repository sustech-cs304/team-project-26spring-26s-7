"""Cloud Storage signed-URL adapter.

Demo phase: returns a deterministic mock URL so that the §5.2 GET endpoint
returns something a browser can render (or at least a URL the frontend can
display). When migrating to AGC, replace this with a call to
`agconnect.cloudStorage.getDownloadURL(key, ttl_seconds)`.
"""
import urllib.parse

from .config import get_settings


def sign_download_url(object_key: str, ttl_seconds: int) -> str:
    settings = get_settings()
    base = settings.mock_storage_base.rstrip("/")
    encoded = urllib.parse.quote(object_key, safe="/")
    return f"{base}/{encoded}?mockSig=demo&ttl={ttl_seconds}"
