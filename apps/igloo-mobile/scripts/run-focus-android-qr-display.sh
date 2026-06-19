#!/usr/bin/env bash
# Focused Android QR display validator for VAL-QR-001.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ACTION_CREATE="com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"
ACTION_SEED_PASSWORD="com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_PASSWORD"
ACTION_DISTRIBUTE_SUBMIT="com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_SUBMIT"

[ -f "$APK" ] || { echo "[focus-qr-android] missing $APK; run just android-full first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[focus-qr-android] $SERIAL not booted" >&2; exit 1; }
command -v zbarimg >/dev/null || { echo "[focus-qr-android] missing zbarimg; brew install zbar" >&2; exit 1; }

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="QrDisplayAndroid-${RUN_TAG}"
DEVICE_NAME="QrDisplayAndroid-${RUN_TAG}"
PASSWORD="qrdisplay${RUN_TAG}"
KEYSET_THRESHOLD="${KEYSET_THRESHOLD:-2}"
KEYSET_COUNT="${KEYSET_COUNT:-3}"
SHARE_IDX="${SHARE_IDX:-2}"
RELAY="${RELAY_URL:-ws://10.0.2.2:8194}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$APPS/library/evidence/mobile-android-qr-display-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_DIR"

echo "[focus-qr-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
password_length=${#PASSWORD}
share_idx=$SHARE_IDX
relay=$RELAY
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
  echo "[focus-qr-android snapshot $(date +%H:%M:%S)] ${tag}"
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
      echo "[focus-qr-android] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

echo "[focus-qr-android $(date +%H:%M:%S)] fresh install + launch"
adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 3
snapshot "01-launch"

echo "[focus-qr-android $(date +%H:%M:%S)] create keyset to Distribute"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_CREATE" \
  -n "$ACTIVITY" \
  --es group_name "$GROUP_NAME" \
  --ei threshold "$KEYSET_THRESHOLD" \
  --ei count "$KEYSET_COUNT" \
  --es device_name "$DEVICE_NAME" \
  --es relay "$RELAY" \
  --ez auto_finish false >/dev/null

wait_for_text "Distribute" 90
wait_for_text "Package password" 30
snapshot "02-distribute"

echo "[focus-qr-android $(date +%H:%M:%S)] seed distribute password"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_SEED_PASSWORD" \
  -n "$ACTIVITY" \
  --ei share_idx "$SHARE_IDX" \
  --es password "$PASSWORD" >/dev/null
sleep 2

echo "[focus-qr-android $(date +%H:%M:%S)] open QR modal via diagnostics submit"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_DISTRIBUTE_SUBMIT" \
  -n "$ACTIVITY" \
  --ei share_idx "$SHARE_IDX" \
  --es method qr >/dev/null
sleep 2

FLOW="$EVIDENCE_DIR/qr-display-android.yaml"
cat > "$FLOW" <<EOF
appId: $APP_ID
---
- scrollUntilVisible:
    element:
      id: "qr_payload_text"
    timeout: 45000
- assertVisible:
    id: "qr_payload_text"
- assertVisible:
    id: "qr_image"
EOF

echo "[focus-qr-android $(date +%H:%M:%S)] verify QR modal"
maestro --device "$SERIAL" test "$FLOW" --debug-output "$EVIDENCE_DIR/maestro" 2>&1 \
  | tee "$EVIDENCE_DIR/maestro.log"
snapshot "03-qr-modal"

DECODED="$(
  zbarimg --quiet --raw "$EVIDENCE_DIR/03-qr-modal.png" 2>/dev/null \
    | grep -E '^bfonboard1' \
    | head -1 || true
)"
[ -n "$DECODED" ] || { echo "[focus-qr-android] zbarimg did not decode bfonboard1 from QR modal screenshot" >&2; exit 1; }
[ "${#DECODED}" -ge 600 ] || { echo "[focus-qr-android] decoded bfonboard1 too short: ${#DECODED}" >&2; exit 1; }

printf '%s' "$DECODED" | shasum -a 256 | awk '{ print "decoded_sha256=" $1 }' > "$EVIDENCE_DIR/qr-decode-proof.txt"
{
  echo "decoded_prefix=${DECODED:0:10}"
  echo "decoded_length=${#DECODED}"
  echo "result=pass"
} >> "$EVIDENCE_DIR/qr-decode-proof.txt"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
relay=$RELAY
decoded_length=${#DECODED}
result=pass
EOF

echo "[focus-qr-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
