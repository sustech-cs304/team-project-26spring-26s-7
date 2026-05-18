#!/usr/bin/env bash
# =============================================================================
# TravelPin HarmonyOS Security Audit Script
# Based on HarmonyOS NEXT Security Whitepaper requirements
# Designed for AppGallery submission compliance
#
# Usage: bash scripts/security_audit.sh [--verbose]
# Output: Terminal (colored) + scripts/security_audit_log.txt
# =============================================================================
set -uo pipefail

# ---- Configuration ----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/frontend/entry/src/main/ets"
MODULE_JSON5="$PROJECT_ROOT/frontend/entry/src/main/module.json5"
AGC_JSON="$PROJECT_ROOT/frontend/entry/src/main/resources/rawfile/agconnect-services.json"
LOG_FILE="$SCRIPT_DIR/security_audit_log.txt"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

# ---- Colors -----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---- Utility Functions -------------------------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

pass() {
  local id="$1"; shift
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "${GREEN}[PASS]${NC} $id: $*" | tee -a "$LOG_FILE"
}

fail() {
  local id="$1"; shift
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo -e "${RED}[FAIL]${NC} $id: $*" | tee -a "$LOG_FILE"
}

warn() {
  local id="$1"; shift
  WARN_COUNT=$((WARN_COUNT + 1))
  echo -e "${YELLOW}[WARN]${NC} $id: $*" | tee -a "$LOG_FILE"
}

info() {
  local id="$1"; shift
  INFO_COUNT=$((INFO_COUNT + 1))
  echo -e "${CYAN}[INFO]${NC} $id: $*" | tee -a "$LOG_FILE"
}

section() {
  echo "" | tee -a "$LOG_FILE"
  echo -e "${BOLD}=== $* ===${NC}" | tee -a "$LOG_FILE"
}

# Safe grep count — handles pipefail and returns clean integer
safe_count() {
  local pattern="$1"
  shift
  local files="$1"
  shift
  local extra_args="$*"
  local n
  n=$(grep -rn $extra_args "$pattern" "$files" 2>/dev/null | wc -l)
  # Trim whitespace robustly
  n=$(echo "$n" | tr -d '[:space:]')
  echo "${n:-0}"
}

# Count occurrences of a pattern in source files
count_in_src() {
  local pattern="$1"
  local extra_grep_args="${2:-}"
  safe_count "$pattern" "$SRC_DIR" --include='*.ets' $extra_grep_args
}

# Check a pattern exists (at least N occurrences)
assert_min_count() {
  local id="$1"; shift
  local desc="$1"; shift
  local pattern="$1"; shift
  local min="$1"; shift
  local extra_args="$*"
  local count
  count=$(safe_count "$pattern" "$SRC_DIR" --include='*.ets' $extra_args)
  if [ "$count" -ge "$min" ]; then
    pass "$id" "$desc (found $count >= $min)"
  else
    fail "$id" "$desc (found $count < $min)"
  fi
}

# Check a pattern does NOT exist
assert_zero() {
  local id="$1"; shift
  local desc="$1"; shift
  local pattern="$1"; shift
  local extra_args="$*"
  local count
  count=$(safe_count "$pattern" "$SRC_DIR" --include='*.ets' $extra_args)
  if [ "$count" -eq 0 ]; then
    pass "$id" "$desc (found 0)"
  else
    fail "$id" "$desc (found $count occurrences)"
    if $VERBOSE; then
      grep -rn $extra_args "$pattern" "$SRC_DIR" 2>/dev/null | head -5 | tee -a "$LOG_FILE"
    fi
  fi
}

# ---- Init Log ---------------------------------------------------------------
echo "TravelPin Security Audit - $(timestamp)" > "$LOG_FILE"
echo "Project: $PROJECT_ROOT" >> "$LOG_FILE"
echo "Source:  $SRC_DIR" >> "$LOG_FILE"
echo "============================================================" >> "$LOG_FILE"

echo -e "${BOLD}TravelPin Security Audit${NC}"
echo "Started at $(timestamp)"
echo "Log: $LOG_FILE"
echo ""

# ---- Pre-flight Checks ------------------------------------------------------
if [ ! -d "$SRC_DIR" ]; then
  echo -e "${RED}ERROR: Source directory not found: $SRC_DIR${NC}"
  exit 1
fi
if [ ! -f "$MODULE_JSON5" ]; then
  echo -e "${RED}ERROR: module.json5 not found: $MODULE_JSON5${NC}"
  exit 1
fi

# =============================================================================
# A. Permission Minimization (HarmonyOS Whitepaper 7.4)
# =============================================================================
section "A. Permission Minimization (7.4 纯净权限)"

# A1: Only 4 permissions declared
# Count "ohos.permission." entries inside the file
perm_count=$(grep -c 'ohos\.permission\.' "$MODULE_JSON5" || true)
if [ "$perm_count" -eq 4 ]; then
  pass "A1" "Exactly 4 permissions declared in module.json5"
else
  fail "A1" "Expected 4 permissions, found $perm_count"
fi

# A2: Location permission scoped to inuse only
if grep -A5 'ohos.permission.LOCATION' "$MODULE_JSON5" | grep -q '"when": "inuse"'; then
  pass "A2" "LOCATION permission scoped to inuse only"
else
  fail "A2" "LOCATION permission not properly scoped to inuse"
fi

# A3: No dangerous permissions beyond declared set (SMS, phone, contacts, camera, microphone)
dangerous_perms="ohos.permission.READ_CONTACTS|ohos.permission.CALL_PHONE|ohos.permission.SEND_SMS|\
ohos.permission.RECEIVE_SMS|ohos.permission.CAMERA|ohos.permission.MICROPHONE|\
ohos.permission.READ_CALENDAR|ohos.permission.WRITE_CALENDAR|ohos.permission.READ_PHONE_STATE"
if grep -E "($dangerous_perms)" "$MODULE_JSON5" > /dev/null 2>&1; then
  fail "A3" "Found dangerous permission declarations beyond minimum"
  grep -E "($dangerous_perms)" "$MODULE_JSON5" | tee -a "$LOG_FILE"
else
  pass "A3" "No dangerous permissions (SMS/phone/contacts/camera/microphone) declared"
fi

# A4: Photo selection uses PhotoViewPicker (System Picker) instead of direct gallery permission
picker_count=$(count_in_src "PhotoViewPicker\|PhotoSelectOptions\|photoViewPicker")
if [ "$picker_count" -gt 0 ]; then
  pass "A4" "Uses HarmonyOS PhotoViewPicker (System Picker) for photo selection ($picker_count refs)"
else
  warn "A4" "Could not confirm PhotoViewPicker usage for photo selection"
fi

# =============================================================================
# B. Data Storage Security (6.1-6.2)
# =============================================================================
section "B. Data Storage Security (6.1-6.2 数据分级与加密)"

# B1: Database uses SecurityLevel.S2
assert_min_count "B1" "RdbHelper uses SecurityLevel.S2" "SecurityLevel\\.S2" 1

# B2: Session tokens stored in preferences (app-private encrypted)
assert_min_count "B2" "Session uses preferences storage" "preferences\\." 1

# B3: Database queries use owner_uid filtering
uid_filter_count=$(count_in_src "owner_uid")
if [ "$uid_filter_count" -ge 5 ]; then
  pass "B3" "Database uses owner_uid filtering ($uid_filter_count refs)"
else
  fail "B3" "Insufficient owner_uid filtering in database queries ($uid_filter_count refs)"
fi

# B4: Temporary sanitized files cleaned in finally blocks
finally_count=$(count_in_src "finally" "san_\|cleanupTemporaryPhotos\|deleteSanitized\|purgeAll")
if [ "$finally_count" -ge 1 ]; then
  pass "B4" "Temporary files cleaned in finally blocks"
else
  # Broader check
  cleanup_count=$(count_in_src "cleanupTemporaryPhotos\\|deleteSanitized\\|purgeAll")
  if [ "$cleanup_count" -ge 2 ]; then
    pass "B4" "Temporary file cleanup functions exist ($cleanup_count refs)"
  else
    warn "B4" "Could not confirm temporary file cleanup in finally blocks"
  fi
fi

# B5: Account deletion performs full data wipe
wipe_count=$(count_in_src "wipeAllUserData\\|deleteUserFromCloud\\|clearAllConsent")
if [ "$wipe_count" -ge 2 ]; then
  pass "B5" "Account deletion wipes all user data ($wipe_count cleanup refs)"
else
  fail "B5" "Account deletion may not fully clean user data ($wipe_count refs)"
fi

# =============================================================================
# C. Network Communication Security (6.3)
# =============================================================================
section "C. Network Communication Security (6.3 数据传输安全)"

# C1: No plaintext http:// API endpoints (excluding license headers and xmlns)
http_api_count=$(grep -rn 'http://' --include='*.ets' "$SRC_DIR" 2>/dev/null \
  | grep -v 'Licensed\|Apache\|xmlns\|http://www.w3\|http://schemas\|licenses/LICENSE' \
  | grep -iv 'license\|copyright' \
  | wc -l | tr -d '[:space:]')
http_api_count=${http_api_count:-0}
if [ "$http_api_count" -eq 0 ]; then
  pass "C1" "No plaintext http:// API endpoints found"
else
  fail "C1" "Found $http_api_count plaintext HTTP references"
  grep -rn 'http://' --include='*.ets' "$SRC_DIR" 2>/dev/null \
    | grep -v 'Licensed\|Apache\|xmlns\|http://www.w3' \
    | head -5 | tee -a "$LOG_FILE"
fi

# C2: HTTPS base URL used for all API endpoints
https_count=$(count_in_src "https://")
if [ "$https_count" -ge 1 ]; then
  pass "C2" "HTTPS URLs found in source ($https_count refs)"
else
  fail "C2" "No HTTPS URLs found"
fi

# C3: Bearer token authentication used for API calls
bearer_count=$(count_in_src "Bearer ")
if [ "$bearer_count" -ge 2 ]; then
  pass "C3" "Bearer token authentication used ($bearer_count refs)"
else
  warn "C3" "Limited Bearer token usage ($bearer_count refs) — check HttpClient.ets TODO"
fi

# C4: No TLS certificate pinning (informational)
pinning_count=$(count_in_src "certificatePinner\|CertificatePinning")
if [ "$pinning_count" -eq 0 ]; then
  info "C4" "No TLS certificate pinning implemented (common for dev, recommended for production)"
else
  pass "C4" "TLS certificate pinning found ($pinning_count refs)"
fi

# =============================================================================
# D. Authentication Security (4.1-4.3)
# =============================================================================
section "D. Authentication Security (4.1-4.3 身份管理与认证)"

# D1: OAuth state parameter validation
assert_min_count "D1" "OAuth state parameter validated in callback" \
  "state.*!==\\|response.state\\|state.*!==.*loginRequest\\|state.*!=.*request" 1

# D2: Uses PS256 signing algorithm
assert_min_count "D2" "Uses PS256 (RSA-PSS-SHA256) signing" "PS256" 1

# D3: Token TTL with early refresh
assert_min_count "D3" "Token expiry with buffer/leeway check" \
  "expiry\\|expir\\|TOKEN_LEEWAY\\|60.*1000\\|leeway" 1

# D4: Tokens stored in memory only (not persisted to disk)
token_persist_count=$(count_in_src "token.*write\|token.*save\|persist.*token\|token.*persist")
if [ "$token_persist_count" -eq 0 ]; then
  pass "D4" "Tokens appear to be memory-only (no explicit persistence)"
else
  warn "D4" "Found $token_persist_count potential token persistence calls - verify manually"
fi

# D5: Hardcoded DEV fallback token (critical gap)
dev_token_count=$(grep -rn 'FALLBACK_DEV_TOKEN\|DEV_[0-9a-f]\{16,\}' \
  --include='*.ets' "$SRC_DIR" 2>/dev/null | wc -l | tr -d '[:space:]')
dev_token_count=${dev_token_count:-0}
if [ "$dev_token_count" -gt 0 ]; then
  fail "D5" "CRITICAL: Hardcoded DEV fallback token found ($dev_token_count occurrences)"
  grep -rn 'FALLBACK_DEV_TOKEN\|DEV_[0-9a-f]\{16,\}' --include='*.ets' "$SRC_DIR" \
    | head -3 | tee -a "$LOG_FILE"
else
  pass "D5" "No hardcoded DEV fallback tokens"
fi

# =============================================================================
# E. Privacy Compliance (7.3-7.4)
# =============================================================================
section "E. Privacy Compliance (7.3-7.4 隐私访问可知可控)"

# E1: Mandatory first-launch privacy consent
assert_min_count "E1" "Mandatory first-launch privacy consent gate" \
  "hasAcceptedPrivacy\\|isPrivacyAccepted\\|PrivacyPolicy\\|privacy.*consent" 2

# E2: JIT consent for cloud features
assert_min_count "E2" "JIT consent dialog for cloud features" \
  "cloudConsent\\|hasConsentedCloud\\|showConsentDialog\\|cloud.*consent" 2

# E3: Versioned privacy policy with re-consent on upgrade
assert_min_count "E3" "Versioned privacy policy with re-consent" \
  "PRIVACY_VERSION\|privacyVersion\|PrivacyVersion\|privacy.*version" 1

# E4: Account deletion clears consent states
assert_min_count "E4" "Account deletion clears consent states" \
  "clearAllConsent\\|clearConsent\\|removeConsent\\|consent.*clear\\|consent.*delete" 1

# =============================================================================
# F. Photo & EXIF Security (6.1 S3 个人多媒体数据)
# =============================================================================
section "F. Photo & EXIF Security (6.1 S3 个人多媒体数据)"

# F1: ImageSanitizer uses PixelMap re-encoding (strips all EXIF)
assert_min_count "F1" "ImageSanitizer uses PixelMap re-encoding" \
  "packing\\|PixelMap\\|image\\.createImagePacker\\|jpeg" 2

# F2: Temporary files use randomized filenames
assert_min_count "F2" "Randomized temp filenames (san_timestamp_random)" \
  "san_\\|Math.random\\|generateRandomUUID\\|randomUUID" 1

# F3: App startup purges stale sanitized files
assert_min_count "F3" "App startup calls purgeAll for crash recovery" "purgeAll" 1

# F4: SharePreflight blocks publishing on EXIF sanitization failure
assert_min_count "F4" "SharePreflight blocks on sanitization failure" \
  "SANITIZE_FAILED\\|sanitize.*fail\\|PHOTO_SANITIZE" 1

# =============================================================================
# G. Content Moderation (7.3 纯净上架)
# =============================================================================
section "G. Content Moderation (7.3 纯净上架)"

# G1: User profile text undergoes content moderation before save
assert_min_count "G1" "Profile text content moderation before save" \
  "ContentFilter\\|contentFilter\\|textCensor\\|moderate.*text\\|textModerat" 1

# G2: moderateContent stub check (hardcoded is_safe: true)
stub_count=$(grep -rn 'is_safe.*true\|isSafe.*true\|is_safe.*:.*true' \
  --include='*.ets' "$SRC_DIR" 2>/dev/null \
  | grep -v 'test\|mock\|spec' \
  | wc -l | tr -d '[:space:]')
stub_count=${stub_count:-0}
if [ "$stub_count" -gt 0 ]; then
  warn "G2" "Possible stub content moderation ($stub_count refs with hardcoded is_safe: true)"
  grep -rn 'is_safe.*true\|isSafe.*true' --include='*.ets' "$SRC_DIR" 2>/dev/null \
    | head -3 | tee -a "$LOG_FILE"
else
  pass "G2" "No hardcoded content moderation stubs found"
fi

# G3: Share content undergoes backend async review
assert_min_count "G3" "Share content async review mechanism" \
  "audit\\|review\\|censor\\|moderate\\|content.*check\\|sensitive" 2

# =============================================================================
# H. Sensitive Information Leakage (7.2 纯净开发)
# =============================================================================
section "H. Sensitive Information Leakage (7.2 纯净开发)"

# H1: Hardcoded API keys / secrets / passwords
secret_count=$(grep -rn -iE '(api_key|apiKey|apiSecret|api_secret)\s*[=:]\s*["\x27][^"\x27]{8,}' \
  --include='*.ets' "$SRC_DIR" 2>/dev/null \
  | grep -v 'process\.\|config\.\|env\.\|getArgument\|DEPRECATED' \
  | wc -l | tr -d '[:space:]')
secret_count=${secret_count:-0}
if [ "$secret_count" -gt 0 ]; then
  fail "H1" "Potential hardcoded API keys/secrets ($secret_count refs)"
  grep -rn -iE '(api_key|apiKey|apiSecret|api_secret)\s*[=:]\s*["\x27][^"\x27]{8,}' \
    --include='*.ets' "$SRC_DIR" 2>/dev/null | head -5 | tee -a "$LOG_FILE"
else
  pass "H1" "No hardcoded API keys/secrets in source code"
fi

# H2: Logger does not output sensitive data (no password/token/secret logging)
sensitive_log_count=$(grep -rn -iE 'Logger\.\w+\(.*?(password|token|secret|credential)' \
  --include='*.ets' "$SRC_DIR" 2>/dev/null | wc -l | tr -d '[:space:]')
sensitive_log_count=${sensitive_log_count:-0}
if [ "$sensitive_log_count" -eq 0 ]; then
  pass "H2" "No sensitive data in Logger calls"
else
  fail "H2" "Found $sensitive_log_count Logger calls with potentially sensitive data"
  grep -rn -iE 'Logger\.\w+\(.*?(password|token|secret|credential)' \
    --include='*.ets' "$SRC_DIR" 2>/dev/null | head -5 | tee -a "$LOG_FILE"
fi

# H3: agconnect-services.json contains credentials (informational)
if [ -f "$AGC_JSON" ]; then
  has_client_secret=$(grep -c 'client_secret\|api_key' "$AGC_JSON" 2>/dev/null | tr -d '[:space:]')
has_client_secret=${has_client_secret:-0}
  if [ "$has_client_secret" -gt 0 ]; then
    warn "H3" "agconnect-services.json contains $has_client_secret credential entries — ensure .gitignore covers it"
    # Check if gitignored
    if git -C "$PROJECT_ROOT" check-ignore "$AGC_JSON" > /dev/null 2>&1; then
      info "H3b" "File IS gitignored (good)"
    else
      fail "H3b" "File is NOT gitignored — credentials are tracked in git history"
    fi
  else
    pass "H3" "agconnect-services.json does not contain raw credentials"
  fi
else
  info "H3" "agconnect-services.json not found (may be injected at build time)"
fi

# H4: Crash reporter is local-only, no third-party telemetry
telemetry_count=$(count_in_src "third.*party\|analytics\|telemetry\|Bugly\|Sentry\|Firebase")
if [ "$telemetry_count" -eq 0 ]; then
  pass "H4" "No third-party telemetry/analytics SDK references found"
else
  warn "H4" "Found $telemetry_count potential telemetry references — verify manually"
fi

# =============================================================================
# Summary
# =============================================================================
echo "" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
echo -e "${BOLD}AUDIT SUMMARY${NC}" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + INFO_COUNT))
echo -e "  ${GREEN}PASS${NC}: $PASS_COUNT" | tee -a "$LOG_FILE"
echo -e "  ${RED}FAIL${NC}: $FAIL_COUNT" | tee -a "$LOG_FILE"
echo -e "  ${YELLOW}WARN${NC}: $WARN_COUNT" | tee -a "$LOG_FILE"
echo -e "  ${CYAN}INFO${NC}: $INFO_COUNT" | tee -a "$LOG_FILE"
echo "  TOTAL: $TOTAL" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo -e "${RED}${BOLD}$FAIL_COUNT test(s) FAILED — review and fix before submission${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  echo -e "${YELLOW}$WARN_COUNT warning(s) — investigate and document decisions${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
fi

echo "Full log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Completed at $(timestamp)" | tee -a "$LOG_FILE"

# Exit with failure if any FAIL items
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
