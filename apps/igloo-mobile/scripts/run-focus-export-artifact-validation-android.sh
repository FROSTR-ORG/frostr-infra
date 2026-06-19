#!/usr/bin/env bash
# Focused Android export-artifact validator for VAL-SET-006/007/008/015.
#
# Strategy:
#   1. Fresh-install the debug APK.
#   2. Create a real local keyset profile with the DEBUG_TEST_CREATE_KEYSET
#      intent, avoiding the external demo provisioner while still using
#      production profile storage.
#   3. Trigger the password-gated export intent for profile and share.
#   4. Fetch the debug-private artifacts with run-as and decode both.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ACTION_CREATE="com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"
ACTION_EXPORT="com.frostr.igloo.DEBUG_TEST_EXPORT_ACTION"

EXPORT_PASSWORD="validator-export-pwd"
RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="AndroidExportKeyset-${RUN_TAG}"
DEVICE_NAME="AndroidExportDevice-${RUN_TAG}"
THRESHOLD=2
COUNT=3
KEYSET_RELAY="${KEYSET_RELAY:-ws://10.0.2.2:8194}"

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

wait_for_create_keyset_proof() {
  local timeout_secs="$1"
  local started
  started="$(date +%s)"
  while true; do
    if adb -s "$SERIAL" exec-out run-as "$APP_ID" cat files/debug-last-create-keyset-proof.txt \
      > "$EVIDENCE_DIR/create-keyset-proof.txt" 2>/dev/null \
      && grep -Fq "stored=yes" "$EVIDENCE_DIR/create-keyset-proof.txt"; then
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-export-android] timed out waiting for create-keyset proof" >&2
      snapshot "failure-create-keyset-proof"
      return 1
    fi
    sleep 1
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

cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
threshold=$THRESHOLD
count=$COUNT
keyset_relay=$KEYSET_RELAY
export_password_length=${#EXPORT_PASSWORD}
EOF

echo "[focus-export-android $(date +%H:%M:%S)] fresh install + launch"
adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 3
snapshot "01-launch"

echo "[focus-export-android $(date +%H:%M:%S)] creating keyset profile"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_CREATE" \
  -n "$ACTIVITY" \
  --es group_name "$GROUP_NAME" \
  --ei threshold "$THRESHOLD" \
  --ei count "$COUNT" \
  --es device_name "$DEVICE_NAME" \
  --es relay "$KEYSET_RELAY" >/dev/null

wait_for_create_keyset_proof 90
sleep 2
snapshot "02-dashboard-ready"

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
if [[ "$PROFILE_CLIP" != bfprofile1* ]]; then
  echo "[focus-export-android] expected bfprofile1 export, got prefix ${PROFILE_CLIP:0:12}" >&2
  snapshot "failure-export-profile"
  exit 1
fi
bash "$APPS/scripts/verify-export-artifact.sh" profile "$EVIDENCE_DIR/clipboard-profile.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_profile.txt"
snapshot "03-after-export-profile"

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
if [[ "$SHARE_CLIP" != bfshare1* ]]; then
  echo "[focus-export-android] expected bfshare1 export, got prefix ${SHARE_CLIP:0:12}" >&2
  snapshot "failure-export-share"
  exit 1
fi
bash "$APPS/scripts/verify-export-artifact.sh" share "$EVIDENCE_DIR/clipboard-share.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_share.txt"
snapshot "04-after-export-share"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
keyset_relay=$KEYSET_RELAY
profile_clipboard_length=${#PROFILE_CLIP}
profile_clipboard_prefix=${PROFILE_CLIP:0:12}
share_clipboard_length=${#SHARE_CLIP}
share_clipboard_prefix=${SHARE_CLIP:0:12}
export_password_length=${#EXPORT_PASSWORD}
result=pass
EOF

echo "[focus-export-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
echo "[focus-export-android RESULT] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-android RESULT] share_clipboard_length=${#SHARE_CLIP}"
