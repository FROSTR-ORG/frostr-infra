#!/usr/bin/env bash
# Cross-platform proof: create a keyset by driving the visible wizard.

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

RUN_TAG="$(date +%H%M%S)"
IOS_GROUP="ManualIOS-${RUN_TAG}"
IOS_DEVICE="manual-ios-${RUN_TAG}"
ANDROID_GROUP="ManualAndroid-${RUN_TAG}"
ANDROID_DEVICE="manual-android-${RUN_TAG}"
DISTRIBUTE_PASSWORD="manualpass-${RUN_TAG}"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-create-keyset-manual-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[manual-create-keyset $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

[ -d "$APP_BUNDLE" ] || { echo "[manual-create-keyset] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
[ -f "$APK" ] || { echo "[manual-create-keyset] missing $APK; run just android-assemble" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[manual-create-keyset] Android $SERIAL not ready" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" || { echo "[manual-create-keyset] iOS simulator $UDID not booted" >&2; exit 1; }

record() {
  printf '%s=%s\n' "$1" "$2" >> "$SUMMARY"
}

verify_screenshot() {
  local file="$1"
  [ -s "$file" ] || { echo "[manual-create-keyset] missing screenshot $file" >&2; exit 1; }
  local bytes
  bytes="$(wc -c < "$file" | tr -d ' ')"
  [ "$bytes" -gt 50000 ] || { echo "[manual-create-keyset] suspiciously small screenshot $file ($bytes bytes)" >&2; exit 1; }
}

ios_snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_ROOT/ios-${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_ROOT/ios-${tag}.hierarchy.txt" 2>&1 || true
  echo "[manual-create-keyset snapshot $(date +%H:%M:%S)] ios-${tag}"
}

android_snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_ROOT/android-${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_ROOT/android-${tag}.hierarchy.xml" >/dev/null 2>&1 || true
  echo "[manual-create-keyset snapshot $(date +%H:%M:%S)] android-${tag}"
}

run_ios() {
  echo "[manual-create-keyset $(date +%H:%M:%S)] iOS visible wizard"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 3

  local flow="$EVIDENCE_ROOT/ios-manual-create-keyset.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    id: "tile_create_keyset"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- tapOn:
    id: "btn_create_new_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "input_group_name"
- tapOn:
    id: "input_group_name"
- eraseText: 64
- setClipboard: "$IOS_GROUP"
- pasteText
- pressKey: Enter
- waitForAnimationToEnd
- tapOn:
    id: "btn_generate"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 90000
- assertVisible:
    id: "input_relays"
- tapOn:
    id: "input_device_name"
- eraseText: 64
- setClipboard: "$IOS_DEVICE"
- pasteText
- pressKey: Enter
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_continue_to_review"
    timeout: 30000
- tapOn:
    id: "btn_continue_to_review"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_accept_review"
    timeout: 30000
- assertVisible:
    id: "display_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- tapOn:
    id: "btn_accept_review"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "distribute_password_2"
    timeout: 30000
- tapOn:
    id: "distribute_password_2"
- eraseText: 64
- setClipboard: "$DISTRIBUTE_PASSWORD"
- pasteText
- pressKey: Enter
- tapOn:
    id: "distribute_confirm_2"
- eraseText: 64
- setClipboard: "$DISTRIBUTE_PASSWORD"
- pasteText
- pressKey: Enter
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "distribute_copy_2"
    timeout: 30000
- tapOn:
    id: "distribute_copy_2"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_finish_distribute"
    timeout: 30000
- tapOn:
    id: "btn_finish_distribute"
- waitForAnimationToEnd
- assertVisible:
    id: "dashboard_header_title"
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    id: "identity_device_name"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-manual-maestro" > "$EVIDENCE_ROOT/ios-manual-maestro.log" 2>&1
  ios_snapshot "manual-dashboard"
  record "ios" "pass"
}

run_android() {
  echo "[manual-create-keyset $(date +%H:%M:%S)] Android visible wizard"
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" shell settings put system font_scale 1.0 >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ANDROID_ACTIVITY" >/dev/null
  sleep 4

  local flow="$EVIDENCE_ROOT/android-manual-create-keyset.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    id: "tile_create_keyset"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- tapOn:
    id: "btn_create_new_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "input_group_name"
- tapOn:
    id: "input_group_name"
- eraseText: 64
- setClipboard: "$ANDROID_GROUP"
- pasteText
- pressKey: Enter
- tapOn:
    id: "btn_generate"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 90000
- assertVisible:
    id: "input_relays"
- tapOn:
    id: "input_device_name"
- eraseText: 64
- setClipboard: "$ANDROID_DEVICE"
- pasteText
- pressKey: Enter
- scrollUntilVisible:
    element:
      id: "btn_continue_to_review"
    timeout: 30000
- tapOn:
    id: "btn_continue_to_review"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_accept_review"
    timeout: 30000
- assertVisible:
    id: "display_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- tapOn:
    id: "btn_accept_review"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_password_2"
    timeout: 30000
- tapOn:
    id: "input_password_2"
- eraseText: 64
- setClipboard: "$DISTRIBUTE_PASSWORD"
- pasteText
- pressKey: Enter
- tapOn:
    id: "input_confirm_password_2"
- eraseText: 64
- setClipboard: "$DISTRIBUTE_PASSWORD"
- pasteText
- pressKey: Enter
- scrollUntilVisible:
    element:
      id: "distribute_copy_2"
    timeout: 30000
- tapOn:
    id: "distribute_copy_2"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_finish_distribute"
    timeout: 30000
- tapOn:
    id: "btn_finish_distribute"
- waitForAnimationToEnd
- assertVisible:
    id: "dashboard_header_title"
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    id: "identity_device_name"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-manual-maestro" > "$EVIDENCE_ROOT/android-manual-maestro.log" 2>&1
  android_snapshot "manual-dashboard"
  record "android" "pass"
}

run_ios
run_android

for image in "$EVIDENCE_ROOT"/*.png; do
  verify_screenshot "$image"
done

record "ios_group" "$IOS_GROUP"
record "ios_device" "$IOS_DEVICE"
record "android_group" "$ANDROID_GROUP"
record "android_device" "$ANDROID_DEVICE"
record "screenshots" "$(find "$EVIDENCE_ROOT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
record "result" "pass"

echo "[manual-create-keyset RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
