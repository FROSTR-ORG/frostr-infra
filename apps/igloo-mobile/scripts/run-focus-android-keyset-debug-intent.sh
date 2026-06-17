#!/usr/bin/env bash
# Focused validation: exercises Android DEBUG_TEST_CREATE_KEYSET.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ACTION_CREATE="com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"

[ -f "$APK" ] || { echo "[focus-keyset-android] missing $APK; run just android-full first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[focus-keyset-android] $SERIAL not booted" >&2; exit 1; }

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="AndroidScriptKeyset-${RUN_TAG}"
DEVICE_NAME="AndroidScriptDevice-${RUN_TAG}"
THRESHOLD=2
COUNT=3
RELAY="ws://10.0.2.2:8194"

EVIDENCE_DIR="$APPS/library/evidence/mobile-android-keyset-debug-intent-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

echo "[focus-keyset-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
threshold=$THRESHOLD
count=$COUNT
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
  echo "[focus-keyset-android snapshot $(date +%H:%M:%S)] ${tag}"
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
      echo "[focus-keyset-android] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
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
      echo "[focus-keyset-android] timed out waiting for create-keyset proof" >&2
      snapshot "failure-create-keyset-proof"
      return 1
    fi
    sleep 1
  done
}

echo "[focus-keyset-android $(date +%H:%M:%S)] fresh install + launch"
adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 3
snapshot "01-launch"

echo "[focus-keyset-android $(date +%H:%M:%S)] create keyset"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_CREATE" \
  -n "$ACTIVITY" \
  --es group_name "$GROUP_NAME" \
  --ei threshold "$THRESHOLD" \
  --ei count "$COUNT" \
  --es device_name "$DEVICE_NAME" \
  --es relay "$RELAY" >/dev/null

wait_for_create_keyset_proof 90
wait_for_text "$DEVICE_NAME" 90
wait_for_text "Signer" 30
wait_for_text "Identity" 30
snapshot "02-dashboard"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
threshold=$THRESHOLD
count=$COUNT
relay=$RELAY
result=pass
EOF

echo "[focus-keyset-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
