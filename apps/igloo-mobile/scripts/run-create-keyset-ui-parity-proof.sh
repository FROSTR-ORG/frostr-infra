#!/usr/bin/env bash
# Focused create-keyset UI parity proof for native iOS + Android shells.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-gfmlzuzzqodrwgcnlcvexnisxixq/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
ANDROID_ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-create-keyset-ui-parity-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"

echo "[create-keyset-ui $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

[ -d "$APP_BUNDLE" ] || { echo "[create-keyset-ui] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
[ -f "$APK" ] || { echo "[create-keyset-ui] missing $APK; run just android-assemble" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[create-keyset-ui] Android $SERIAL not ready" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" || { echo "[create-keyset-ui] iOS simulator $UDID not booted" >&2; exit 1; }

ios_snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_ROOT/ios-${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_ROOT/ios-${tag}.hierarchy.txt" 2>&1 || true
  echo "[create-keyset-ui snapshot $(date +%H:%M:%S)] ios-${tag}"
}

android_snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_ROOT/android-${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_ROOT/android-${tag}.hierarchy.xml" >/dev/null 2>&1 || true
  echo "[create-keyset-ui snapshot $(date +%H:%M:%S)] android-${tag}"
}

verify_screenshot() {
  local file="$1"
  [ -s "$file" ] || { echo "[create-keyset-ui] missing screenshot $file" >&2; exit 1; }
  local bytes
  bytes="$(wc -c < "$file" | tr -d ' ')"
  [ "$bytes" -gt 50000 ] || { echo "[create-keyset-ui] suspiciously small screenshot $file ($bytes bytes)" >&2; exit 1; }
}

run_ios() {
  echo "[create-keyset-ui $(date +%H:%M:%S)] iOS fresh install"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 3

  local flow="$EVIDENCE_ROOT/ios-create-entry.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    id: "tile_create_keyset"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_create_new_keyset"
- assertVisible:
    id: "btn_rotate_keyset"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-create-entry-maestro" > "$EVIDENCE_ROOT/ios-create-entry-maestro.log" 2>&1
  ios_snapshot "01-create-entry"

  flow="$EVIDENCE_ROOT/ios-generate.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- tapOn:
    id: "btn_create_new_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_mode_create"
- assertVisible:
    id: "btn_mode_rotate"
- assertVisible:
    id: "input_group_name"
- assertVisible:
    id: "btn_generate"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-generate-maestro" > "$EVIDENCE_ROOT/ios-generate-maestro.log" 2>&1
  ios_snapshot "02-generate"
}

run_android() {
  echo "[create-keyset-ui $(date +%H:%M:%S)] Android fresh install"
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" shell settings put system font_scale 1.0 >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ANDROID_ACTIVITY" >/dev/null
  sleep 4

  local flow="$EVIDENCE_ROOT/android-create-entry.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    id: "tile_create_keyset"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_create_new_keyset"
- assertVisible:
    id: "btn_rotate_keyset"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-create-entry-maestro" > "$EVIDENCE_ROOT/android-create-entry-maestro.log" 2>&1
  android_snapshot "01-create-entry"

  flow="$EVIDENCE_ROOT/android-generate.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- tapOn:
    id: "btn_create_new_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_mode_create"
- assertVisible:
    id: "btn_mode_rotate"
- assertVisible:
    id: "input_group_name"
- assertVisible:
    id: "btn_generate"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-generate-maestro" > "$EVIDENCE_ROOT/android-generate-maestro.log" 2>&1
  android_snapshot "02-generate"
}

run_ios
run_android

for image in "$EVIDENCE_ROOT"/*.png; do
  verify_screenshot "$image"
done

{
  echo "ios=pass"
  echo "android=pass"
  echo "screenshots=$(find "$EVIDENCE_ROOT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
  echo "result=pass"
} | tee "$EVIDENCE_ROOT/summary.txt"

echo "[create-keyset-ui RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
