#!/usr/bin/env bash
# Focused Android Rotate Share validator using real demo bfonboard artifacts.

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
ACTION_ROTATE="com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE"
ACTION_ROTATE_REPLACE="com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE_REPLACE"

[ -f "$APK" ] || { echo "[focus-rotate-android] missing $APK; run just android-full first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[focus-rotate-android] $SERIAL not booted" >&2; exit 1; }
adb -s "$SERIAL" shell toybox nc -z 10.0.2.2 8194 \
  || { echo "[focus-rotate-android] relay unreachable from emulator; run make demo-start first" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "[focus-rotate-android] missing bob package; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "[focus-rotate-android] missing bob password; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-carol.txt" ] || { echo "[focus-rotate-android] missing carol package; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-carol.password.txt" ] || { echo "[focus-rotate-android] missing carol password; run make demo-onboard" >&2; exit 1; }

PACKAGE_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
PACKAGE_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.txt")"
PASSWORD_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.password.txt")"
DEVICE_NAME="rotate-bob-android"

EVIDENCE_DIR="$APPS/library/evidence/mobile-android-rotate-share-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-rotate-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_bob_length=${#PACKAGE_BOB}
password_bob_length=${#PASSWORD_BOB}
package_carol_length=${#PACKAGE_CAROL}
password_carol_length=${#PASSWORD_CAROL}
relay=$RELAY
device_name=$DEVICE_NAME
EOF

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
  echo "[focus-rotate-android snapshot $(date +%H:%M:%S)] ${tag}"
}

wait_for_text() {
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
      echo "[focus-rotate-android] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

wait_for_rotate_proof() {
  local timeout_secs="$1"
  local started
  started="$(date +%s)"
  while true; do
    if adb -s "$SERIAL" exec-out run-as "$APP_ID" cat files/debug-last-rotate-share-proof.txt \
      > "$EVIDENCE_DIR/rotate-share-proof.txt" 2>/dev/null \
      && grep -Fq "replaced=yes" "$EVIDENCE_DIR/rotate-share-proof.txt" \
      && grep -Fq "profile_changed=true" "$EVIDENCE_DIR/rotate-share-proof.txt"; then
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-rotate-android] timed out waiting for rotate proof" >&2
      snapshot "failure-rotate-proof"
      return 1
    fi
    sleep 1
  done
}

echo "[focus-rotate-android $(date +%H:%M:%S)] fresh install + launch"
adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 3
snapshot "01-launch"

echo "[focus-rotate-android $(date +%H:%M:%S)] onboard bob"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_INJECT" \
  -n "$ACTIVITY" \
  --es package "$PACKAGE_BOB" \
  --es password "$PASSWORD_BOB" \
  --es relay "$RELAY" \
  --es device_name "$DEVICE_NAME" \
  --ez connect true >/dev/null
wait_for_text "$DEVICE_NAME" 180
snapshot "02-onboard-review"

adb -s "$SERIAL" shell am start \
  -a "$ACTION_SAVE_TO_DASHBOARD" \
  -n "$ACTIVITY" \
  --es device_name "$DEVICE_NAME" >/dev/null
wait_for_text "Signer Stopped" 60
snapshot "03-dashboard-before-rotate"

echo "[focus-rotate-android $(date +%H:%M:%S)] connect replacement package"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_ROTATE" \
  -n "$ACTIVITY" \
  --es package "$PACKAGE_CAROL" \
  --es password "$PASSWORD_CAROL" \
  --es relay "$RELAY" >/dev/null
sleep 4
adb -s "$SERIAL" shell input swipe 540 2200 540 600 800 >/dev/null
wait_for_text "Replacement Preview" 180
snapshot "04-replacement-preview"

echo "[focus-rotate-android $(date +%H:%M:%S)] replace share"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_ROTATE_REPLACE" \
  -n "$ACTIVITY" >/dev/null
wait_for_rotate_proof 90
ROTATED_SHORT_ID="$(awk -F= '$1 == "short_id" { print $2 }' "$EVIDENCE_DIR/rotate-share-proof.txt")"
[ -n "$ROTATED_SHORT_ID" ] \
  || { echo "[focus-rotate-android] rotate proof missing short_id" >&2; exit 1; }
wait_for_text "$DEVICE_NAME" 60
wait_for_text "$ROTATED_SHORT_ID" 60
wait_for_text "Signer" 30
snapshot "05-dashboard-after-rotate"

grep -Fq "$ROTATED_SHORT_ID" "$EVIDENCE_DIR/hierarchy-05-dashboard-after-rotate.xml" \
  || { echo "[focus-rotate-android] dashboard did not render rotated short id $ROTATED_SHORT_ID" >&2; exit 1; }

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
device_name=$DEVICE_NAME
relay=$RELAY
rotated_short_id=$ROTATED_SHORT_ID
result=pass
EOF

echo "[focus-rotate-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
