#!/usr/bin/env bash
# Focused Android Rotate Share validator using a native-generated bfonboard package.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
RELAY="${ROTATE_RELAY:-${KEYSET_RELAY:-ws://10.0.2.2:8194}}"
SHARE_IDX="${SHARE_IDX:-2}"

ACTION_CREATE="com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"
ACTION_SEED_PASSWORD="com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_PASSWORD"
ACTION_DISTRIBUTE_SUBMIT="com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_SUBMIT"
ACTION_DISTRIBUTE_FINISH="com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_FINISH"
ACTION_ROTATE="com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE"
ACTION_ROTATE_REPLACE="com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE_REPLACE"

[ -f "$APK" ] || { echo "[focus-rotate-android] missing $APK; run just android-assemble first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[focus-rotate-android] $SERIAL not booted" >&2; exit 1; }

RELAY_HOST="${RELAY#ws://}"
RELAY_HOST="${RELAY_HOST%%/*}"
RELAY_PORT="${RELAY_HOST##*:}"
RELAY_HOST="${RELAY_HOST%:*}"
adb -s "$SERIAL" shell toybox nc -z "$RELAY_HOST" "$RELAY_PORT" \
  || { echo "[focus-rotate-android] relay $RELAY unreachable from emulator; start the local relay first" >&2; exit 1; }

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="RotateAndroid-${RUN_TAG}"
DEVICE_NAME="RotateAndroid-${RUN_TAG}"
PASSWORD="rotateandroid${RUN_TAG}"
EVIDENCE_DIR="$APPS/library/evidence/mobile-android-rotate-share-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-rotate-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
share_idx=$SHARE_IDX
password_length=${#PASSWORD}
relay=$RELAY
package_source=native-create-keyset-distribute
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

wait_for_distribute_package() {
  local timeout_secs="$1"
  local started
  local tmp="$EVIDENCE_DIR/.native-replacement-package.txt"
  started="$(date +%s)"
  while true; do
    if adb -s "$SERIAL" exec-out run-as "$APP_ID" cat files/debug-last-keyset-distribute-package.txt \
      > "$tmp" 2>/dev/null \
      && [ -s "$tmp" ] \
      && grep -Fq "bfonboard1" "$tmp"; then
      adb -s "$SERIAL" exec-out run-as "$APP_ID" cat files/debug-last-keyset-distribute-package-proof.txt \
        > "$EVIDENCE_DIR/distribute-package-proof.txt" 2>/dev/null || true
      tr -d '\r\n' < "$tmp"
      rm -f "$tmp"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      rm -f "$tmp"
      echo "[focus-rotate-android] timed out waiting for native distribute package" >&2
      snapshot "failure-distribute-package"
      return 1
    fi
    sleep 1
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

echo "[focus-rotate-android $(date +%H:%M:%S)] create local keyset to Distribute"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_CREATE" \
  -n "$ACTIVITY" \
  --es group_name "$GROUP_NAME" \
  --ei threshold 2 \
  --ei count 3 \
  --es device_name "$DEVICE_NAME" \
  --es relay "$RELAY" \
  --ez auto_finish false >/dev/null
wait_for_text "Distribute" 90
wait_for_text "Package password" 30
snapshot "02-distribute"

echo "[focus-rotate-android $(date +%H:%M:%S)] generate native replacement package"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_SEED_PASSWORD" \
  -n "$ACTIVITY" \
  --ei share_idx "$SHARE_IDX" \
  --es password "$PASSWORD" >/dev/null
sleep 1
adb -s "$SERIAL" shell am start \
  -a "$ACTION_DISTRIBUTE_SUBMIT" \
  -n "$ACTIVITY" \
  --ei share_idx "$SHARE_IDX" \
  --es method copy >/dev/null
PACKAGE_REPLACEMENT="$(wait_for_distribute_package 90)"
[ "${PACKAGE_REPLACEMENT:0:10}" = "bfonboard1" ] \
  || { echo "[focus-rotate-android] native replacement package has unexpected prefix" >&2; exit 1; }
[ "${#PACKAGE_REPLACEMENT}" -ge 600 ] \
  || { echo "[focus-rotate-android] native replacement package too short: ${#PACKAGE_REPLACEMENT}" >&2; exit 1; }
printf '%s' "$PACKAGE_REPLACEMENT" | shasum -a 256 | awk '{ print "replacement_package_sha256=" $1 }' > "$EVIDENCE_DIR/replacement-package-redacted-proof.txt"
{
  echo "replacement_package_prefix=${PACKAGE_REPLACEMENT:0:10}"
  echo "replacement_package_length=${#PACKAGE_REPLACEMENT}"
} >> "$EVIDENCE_DIR/replacement-package-redacted-proof.txt"

echo "[focus-rotate-android $(date +%H:%M:%S)] finish keyset and land on dashboard"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_DISTRIBUTE_FINISH" \
  -n "$ACTIVITY" >/dev/null
wait_for_text "$DEVICE_NAME" 60
wait_for_text "Signer" 60
snapshot "03-dashboard-before-rotate"

echo "[focus-rotate-android $(date +%H:%M:%S)] connect native replacement package"
adb -s "$SERIAL" shell am start \
  -a "$ACTION_ROTATE" \
  -n "$ACTIVITY" \
  --es package "$PACKAGE_REPLACEMENT" \
  --es password "$PASSWORD" \
  --es relay "$RELAY" >/dev/null
sleep 4
adb -s "$SERIAL" shell input swipe 540 2200 540 600 800 >/dev/null
wait_for_text "Replacement Preview" 180
wait_for_text "$DEVICE_NAME" 60
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
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
relay=$RELAY
share_idx=$SHARE_IDX
replacement_package_length=${#PACKAGE_REPLACEMENT}
rotated_short_id=$ROTATED_SHORT_ID
result=pass
EOF

echo "[focus-rotate-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
