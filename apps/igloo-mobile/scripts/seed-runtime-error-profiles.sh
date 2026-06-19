#!/usr/bin/env bash
# Seed deterministic runtime-error profiles:
#   - iOS simulator: bob via igloo://test-inject + diagnostics save
#   - Android emulator: carol via DEBUG_TEST_INJECT_ONBOARD + diagnostics save
#
# This keeps VAL-ERR runtime flows focused on runtime behavior instead of
# long-form onboarding text transport.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
HARNESS_DIR="$ROOT/.tmp/test-harness"
EVIDENCE_DIR="${EVIDENCE_DIR:-$APPS/library/evidence/mobile-runtime-profile-seed-$(date +%Y-%m-%d-%H%M%S)}"
RELAY_PORT="${DEV_RELAY_PORT:-8194}"
IOS_RELAY_URL="ws://127.0.0.1:${RELAY_PORT}"
ANDROID_RELAY_URL="ws://10.0.2.2:${RELAY_PORT}"

mkdir -p "$EVIDENCE_DIR"
echo "[runtime-seed $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

b64() {
  python3 -c 'import sys, base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())'
}

require_file() {
  [ -f "$1" ] || { echo "[runtime-seed] missing $1" >&2; exit 1; }
}

ios_hierarchy() {
  local out="$1"
  maestro --device "$UDID" hierarchy > "$out" 2>&1 || true
}

android_hierarchy() {
  local out="$1"
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$out" >/dev/null 2>&1 || true
}

wait_for_ios_text() {
  local needle="$1"
  local timeout="$2"
  local started
  started="$(date +%s)"
  while true; do
    ios_hierarchy "$EVIDENCE_DIR/.ios-wait.txt"
    if grep -Fq "$needle" "$EVIDENCE_DIR/.ios-wait.txt" 2>/dev/null; then
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout" ]; then
      cp "$EVIDENCE_DIR/.ios-wait.txt" "$EVIDENCE_DIR/ios-timeout-${needle//[^A-Za-z0-9]/-}.txt" 2>/dev/null || true
      echo "[runtime-seed] timed out waiting for iOS text/id: $needle" >&2
      return 1
    fi
    sleep 2
  done
}

wait_for_android_text() {
  local needle="$1"
  local timeout="$2"
  local started
  started="$(date +%s)"
  while true; do
    android_hierarchy "$EVIDENCE_DIR/.android-wait.xml"
    if grep -Fq "$needle" "$EVIDENCE_DIR/.android-wait.xml" 2>/dev/null; then
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout" ]; then
      cp "$EVIDENCE_DIR/.android-wait.xml" "$EVIDENCE_DIR/android-timeout-${needle//[^A-Za-z0-9]/-}.xml" 2>/dev/null || true
      echo "[runtime-seed] timed out waiting for Android text/id: $needle" >&2
      return 1
    fi
    sleep 2
  done
}

seed_ios_bob() {
  local package password package_b64 relay relay_enc device device_enc save_url
  package="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
  password="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
  package_b64="$(printf '%s' "$package" | b64)"
  relay="$IOS_RELAY_URL"
  relay_enc="$(urlencode "$relay")"
  device="bob"
  device_enc="$(urlencode "$device")"

  echo "[runtime-seed $(date +%H:%M:%S)] iOS fresh install + diagnostics launch"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 2

  echo "[runtime-seed $(date +%H:%M:%S)] iOS inject bob"
  xcrun simctl openurl "$UDID" "igloo://test-inject?package=${package_b64}&password=${password}&relay=${relay_enc}&device_name=${device_enc}" \
    > "$EVIDENCE_DIR/ios-inject-openurl.txt" 2>&1
  wait_for_ios_text "input_device_name" 240

  save_url="igloo://test-save-to-dashboard?device_name=${device_enc}"
  xcrun simctl openurl "$UDID" "$save_url" >> "$EVIDENCE_DIR/ios-inject-openurl.txt" 2>&1
  wait_for_ios_text "bob" 60
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/ios-bob-seeded.png" >/dev/null 2>&1 || true
  ios_hierarchy "$EVIDENCE_DIR/ios-bob-seeded-hierarchy.txt"
}

seed_android_carol() {
  local package password relay device
  package="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.txt")"
  password="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.password.txt")"
  relay="$ANDROID_RELAY_URL"
  device="carol"

  echo "[runtime-seed $(date +%H:%M:%S)] Android fresh install"
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null

  echo "[runtime-seed $(date +%H:%M:%S)] Android inject carol + connect"
  adb -s "$SERIAL" shell am start -W \
    -a "com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es package "$package" \
    --es password "$password" \
    --es relay "$relay" \
    --es device_name "$device" \
    --ez connect true \
    > "$EVIDENCE_DIR/android-inject-result.txt" 2>&1
  wait_for_android_text "input_device_name" 240

  adb -s "$SERIAL" shell am start -W \
    -a "com.frostr.igloo.DEBUG_TEST_SAVE_TO_DASHBOARD" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es device_name "$device" \
    >> "$EVIDENCE_DIR/android-inject-result.txt" 2>&1
  wait_for_android_text "carol" 60
  adb -s "$SERIAL" exec-out screencap -p > "$EVIDENCE_DIR/android-carol-seeded.png" || true
  android_hierarchy "$EVIDENCE_DIR/android-carol-seeded-hierarchy.xml"
}

require_file "$APK"
[ -d "$APP_BUNDLE" ] || { echo "[runtime-seed] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
require_file "$HARNESS_DIR/onboard-bob.txt"
require_file "$HARNESS_DIR/onboard-bob.password.txt"
require_file "$HARNESS_DIR/onboard-carol.txt"
require_file "$HARNESS_DIR/onboard-carol.password.txt"
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[runtime-seed] Android device $SERIAL not ready" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" || { echo "[runtime-seed] iOS simulator $UDID not booted" >&2; exit 1; }

{
  echo "ios_profile=bob"
  echo "ios_relay=$IOS_RELAY_URL"
  echo "android_profile=carol"
  echo "android_relay=$ANDROID_RELAY_URL"
  echo "bob_package_length=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')"
  echo "carol_package_length=$(wc -c < "$HARNESS_DIR/onboard-carol.txt" | tr -d ' ')"
} > "$EVIDENCE_DIR/input.txt"

seed_ios_bob
seed_android_carol

{
  echo "result=pass"
  echo "evidence=$EVIDENCE_DIR"
} > "$EVIDENCE_DIR/summary.txt"

echo "[runtime-seed RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
