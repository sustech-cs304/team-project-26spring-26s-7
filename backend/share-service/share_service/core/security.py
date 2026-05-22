import base64
import hashlib
import hmac
import secrets

# URL-safe charset, avoiding visually-confusable chars (0/O/o, l/1/I).
# Spec: §4.1 — `[A-Za-z0-9_-]` minus easily confused glyphs.
_CHARSET = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_"


def generate_short_code(length: int = 8) -> str:
    return "".join(secrets.choice(_CHARSET) for _ in range(length))


def compute_sig(key: bytes, short_code: str, owner_uid: str, expire_at: int) -> str:
    msg = f"{short_code}|{owner_uid}|{expire_at}".encode("utf-8")
    digest = hmac.new(key, msg, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")[:8]


def verify_sig(
    key: bytes, short_code: str, owner_uid: str, expire_at: int, sig: str
) -> bool:
    expected = compute_sig(key, short_code, owner_uid, expire_at)
    return hmac.compare_digest(expected, sig)


# ---------------------------------------------------------------------------
# Spec-compliant HMAC (P08 API 规范 §7) — used by /api/v1/share/publish.
#
# Differences vs the legacy compute_sig above:
#   * message format: "{shortCode}:{expiryTimestampSeconds}" (no owner_uid)
#   * output: lowercase hex, full 64 chars (not base64url-truncated to 8)
#   * expiry timestamp is in SECONDS (legacy uses ms)
#
# This pair coexists with the legacy version — the new POST /publish
# endpoint and GET /s/:shortcode (spec mode) use *_v2; the demo /s/{code}.{sig}
# routes still use the legacy version.
# ---------------------------------------------------------------------------

def compute_sig_v2(key: bytes, short_code: str, expiry_ts_seconds: int) -> str:
    msg = f"{short_code}:{expiry_ts_seconds}".encode("utf-8")
    return hmac.new(key, msg, hashlib.sha256).hexdigest()


def verify_sig_v2(
    key: bytes, short_code: str, expiry_ts_seconds: int, sig_hex: str
) -> bool:
    if not sig_hex or len(sig_hex) != 64:
        return False
    expected = compute_sig_v2(key, short_code, expiry_ts_seconds)
    return hmac.compare_digest(expected, sig_hex.lower())


# Spec §5.1: shortCode charset is [A-Za-z0-9], 8 chars. The demo charset
# (avoid-confusables) is stricter, so it would also satisfy the regex,
# but the spec is the contract — use exactly what it says.
_SPEC_CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"


def generate_short_code_v2(length: int = 8) -> str:
    return "".join(secrets.choice(_SPEC_CHARSET) for _ in range(length))
