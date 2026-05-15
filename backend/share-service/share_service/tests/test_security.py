from share_service.core.security import (
    compute_sig,
    generate_short_code,
    verify_sig,
)

KEY = b"unit-test-key-please-replace-in-prod-32b"


def test_short_code_length():
    assert len(generate_short_code()) == 8


def test_short_code_avoids_confusable_glyphs():
    forbidden = {"0", "O", "o", "l", "1", "I"}
    for _ in range(500):
        code = generate_short_code()
        assert not (set(code) & forbidden), f"contains forbidden glyph: {code}"


def test_short_code_uses_url_safe_charset_only():
    allowed = set(
        "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_"
    )
    for _ in range(200):
        assert set(generate_short_code()) <= allowed


def test_short_code_low_collision_rate():
    codes = {generate_short_code() for _ in range(2000)}
    # Expect near-zero collisions across 2k samples from a ~5e13 keyspace.
    assert len(codes) >= 1995


def test_sig_is_deterministic():
    s1 = compute_sig(KEY, "abc12345", "uid-1", 1_700_000_000_000)
    s2 = compute_sig(KEY, "abc12345", "uid-1", 1_700_000_000_000)
    assert s1 == s2


def test_sig_length_is_8():
    s = compute_sig(KEY, "abc", "uid", 1)
    assert len(s) == 8


def test_sig_changes_with_each_input():
    base = compute_sig(KEY, "abc12345", "uid-1", 100)
    assert compute_sig(KEY, "abc12346", "uid-1", 100) != base
    assert compute_sig(KEY, "abc12345", "uid-2", 100) != base
    assert compute_sig(KEY, "abc12345", "uid-1", 101) != base
    assert compute_sig(b"different-key", "abc12345", "uid-1", 100) != base


def test_verify_accepts_correct_sig():
    sig = compute_sig(KEY, "abc12345", "uid-1", 100)
    assert verify_sig(KEY, "abc12345", "uid-1", 100, sig) is True


def test_verify_rejects_tampered_sig():
    sig = compute_sig(KEY, "abc12345", "uid-1", 100)
    tampered = ("X" if sig[0] != "X" else "Y") + sig[1:]
    assert verify_sig(KEY, "abc12345", "uid-1", 100, tampered) is False


def test_verify_rejects_wrong_key():
    sig = compute_sig(KEY, "abc12345", "uid-1", 100)
    assert verify_sig(b"other-key", "abc12345", "uid-1", 100, sig) is False


def test_verify_rejects_empty_sig():
    assert verify_sig(KEY, "abc", "uid", 100, "") is False
