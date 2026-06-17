#!/usr/bin/env bash
# Focused Android export-artifact validator for VAL-SET-006/007/008/015.
#
# Mirrors the iOS focused validator:
#   1. Fresh-install the debug APK.
#   2. Use DEBUG-only intent hooks to inject bob's real bfonboard1 package,
#      drive the real onboard handshake, and save the resolved profile.
#   3. Use a DEBUG-only export intent that calls the same FfiApp export methods
#      as the product password prompt and writes the same Android clipboard.
#   4. Fetch the debug-private artifact with run-as and verify it with the Rust
#      export decoder. No package bytes are printed to stdout.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"

APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
HARNESS_DIR="$ROOT/.tmp/test-harness"
RELAY="ws://10.0.2.2:8194"

ACTION_INJECT="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"
ACTION_SAVE_TO_DASHBOARD="com.frostr.igloo.DEBUG_TEST_SAVE_TO_DASHBOARD"
ACTION_EXPORT="com.frostr.igloo.DEBUG_TEST_EXPORT_ACTION"

EXPORT_PASSWORD="validator-export-pwd"
DEVICE_NAME="focus-export-bob-android"

EVIDENCE_DIR="$APPS/library/evidence/mobile-export-artifact-validation-android-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-export-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  if [ -f "$EVIDENCE_DIR/hierarchy-${tag}.xml" ]; then
    python3 - <<PYEOF
import re
path = "$EVIDENCE_DIR/hierarchy-${tag}.xml"
with open(path, encoding="utf-8") as f:
    data = f.read()
data = re.sub(r'text="([^"]{50,})"', lambda m: f'text="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'content-desc="([^"]{50,})"', lambda m: f'content-desc="[REDACTED-{len(m.group(1))}chars]"', data)
with open("${EVIDENCE_DIR}/redacted-hierarchy-${tag}.xml", "w", encoding="utf-8") as f:
    f.write(data)
PYEOF
  fi
  echo "[focus-export-android snapshot $(date +%H:%M:%S)] ${tag}"
}

wait_for_hierarchy_text() {
  local needle="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"
  while true; do
    adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
    adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/.wait-window.xml" \
      >/dev/null 2>&1 || true
    if [ -f "$EVIDENCE_DIR/.wait-window.xml" ] && grep -Fq "$needle" "$EVIDENCE_DIR/.wait-window.xml"; then
      rm -f "$EVIDENCE_DIR/.wait-window.xml"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      rm -f "$EVIDENCE_DIR/.wait-window.xml"
      echo "[focus-export-android] timed out waiting for hierarchy text: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

fetch_debug_export() {
  local kind="$1"
  local out="$2"
  adb -s "$SERIAL" exec-out run-as "$APP_ID" cat "files/debug-last-export-${kind}.txt" > "$out"
  if [ ! -s "$out" ]; then
    echo "[focus-export-android] empty debug export artifact for $kind" >&2
    return 1
  fi
}

[ -f "$APK" ] || { echo "[focus-export-android] missing $APK; run 'just android-full' first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 \
  || { echo "[focus-export-android] $SERIAL not booted" >&2; exit 1; }
adb -s "$SERIAL" shell toybox nc -z 10.0.2.2 8194 \
  || { echo "[focus-export-android] relay unreachable from emulator; run make demo-start first" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "[focus-export-android] missing bob package; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "[focus-export-android] missing bob password; run make demo-onboard" >&2; exit 1; }

PACKAGE_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_bob_length=${#PACKAGE_BOB}
password_bob_length=${#PASSWORD_BOB}
relay=${RELAY}
export_password_length=${#EXPORT_PASSWORD}
EOF

echo "[focus-export-android $(date +%H:%M:%S)] fresh install + launch"
adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 3
snapshot "01-launch"

echo "[focus-export-android $(date +%H:%M:%S)] inject + connect bob (length=${#PACKAGE_BOB})"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_INJECT" \
  -n "$ACTIVITY" \
  --es package "$PACKAGE_BOB" \
  --es password "$PASSWORD_BOB" \
  --es relay "$RELAY" \
  --es device_name "$DEVICE_NAME" \
  --ez connect true >/dev/null
wait_for_hierarchy_text "$DEVICE_NAME" 180
snapshot "02-onboard-review"

echo "[focus-export-android $(date +%H:%M:%S)] diagnostics save to dashboard"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_SAVE_TO_DASHBOARD" \
  -n "$ACTIVITY" \
  --es device_name "$DEVICE_NAME" >/dev/null
wait_for_hierarchy_text "Signer Stopped" 60
snapshot "03-dashboard-ready"

echo "[focus-export-android $(date +%H:%M:%S)] export profile"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_EXPORT" \
  -n "$ACTIVITY" \
  --es kind profile \
  --es password "$EXPORT_PASSWORD" >/dev/null
sleep 2
fetch_debug_export profile "$EVIDENCE_DIR/clipboard-profile.txt"
PROFILE_CLIP="$(tr -d '\r\n' < "$EVIDENCE_DIR/clipboard-profile.txt")"
echo "[focus-export-android $(date +%H:%M:%S)] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-android $(date +%H:%M:%S)] profile_clipboard_prefix=${PROFILE_CLIP:0:12}"
bash "$APPS/scripts/verify-export-artifact.sh" profile "$EVIDENCE_DIR/clipboard-profile.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_profile.txt"
snapshot "04-after-export-profile"

echo "[focus-export-android $(date +%H:%M:%S)] export share"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_EXPORT" \
  -n "$ACTIVITY" \
  --es kind share \
  --es password "$EXPORT_PASSWORD" >/dev/null
sleep 2
fetch_debug_export share "$EVIDENCE_DIR/clipboard-share.txt"
SHARE_CLIP="$(tr -d '\r\n' < "$EVIDENCE_DIR/clipboard-share.txt")"
echo "[focus-export-android $(date +%H:%M:%S)] share_clipboard_length=${#SHARE_CLIP}"
echo "[focus-export-android $(date +%H:%M:%S)] share_clipboard_prefix=${SHARE_CLIP:0:12}"
bash "$APPS/scripts/verify-export-artifact.sh" share "$EVIDENCE_DIR/clipboard-share.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_share.txt"
snapshot "05-after-export-share"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
profile_clipboard_length=${#PROFILE_CLIP}
profile_clipboard_prefix=${PROFILE_CLIP:0:12}
share_clipboard_length=${#SHARE_CLIP}
share_clipboard_prefix=${SHARE_CLIP:0:12}
export_password_length=${#EXPORT_PASSWORD}
EOF

echo "[focus-export-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
echo "[focus-export-android RESULT] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-android RESULT] share_clipboard_length=${#SHARE_CLIP}"
