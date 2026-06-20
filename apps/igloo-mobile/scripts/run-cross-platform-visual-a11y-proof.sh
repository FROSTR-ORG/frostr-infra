#!/usr/bin/env bash
# Cross-platform visual screenshot + accessibility/layout proof.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
ANDROID_ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
ANDROID_CREATE_ACTION="com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-visual-a11y-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[visual-a11y $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

require_preflight() {
  [ -d "$APP_BUNDLE" ] || { echo "[visual-a11y] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
  [ -f "$APK" ] || { echo "[visual-a11y] missing $APK; run just android-assemble" >&2; exit 1; }
  adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[visual-a11y] Android $SERIAL not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "$UDID" || { echo "[visual-a11y] iOS simulator $UDID not booted" >&2; exit 1; }
}

ios_snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_ROOT/ios-${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_ROOT/ios-${tag}.hierarchy.txt" 2>&1 || true
  echo "[visual-a11y snapshot $(date +%H:%M:%S)] ios-${tag}"
}

android_snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_ROOT/android-${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_ROOT/android-${tag}.hierarchy.xml" >/dev/null 2>&1 || true
  echo "[visual-a11y snapshot $(date +%H:%M:%S)] android-${tag}"
}

verify_screenshot() {
  local file="$1"
  [ -s "$file" ] || { echo "[visual-a11y] missing screenshot $file" >&2; exit 1; }
  local bytes
  bytes="$(wc -c < "$file" | tr -d ' ')"
  [ "$bytes" -gt 50000 ] || { echo "[visual-a11y] suspiciously small screenshot $file ($bytes bytes)" >&2; exit 1; }
}

require_in_file() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || { echo "[visual-a11y] missing '$needle' in $file" >&2; exit 1; }
}

run_ios() {
  echo "[visual-a11y $(date +%H:%M:%S)] iOS fresh install + large content size"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size accessibility-large >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 3
  ios_snapshot "01-hub-large-text"

  local flow="$EVIDENCE_ROOT/ios-entry-screens.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    text: "Igloo"
- assertVisible:
    id: "tile_create_keyset"
- assertVisible:
    id: "tile_load_profile"
- assertVisible:
    id: "tile_onboard_device"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_create_new_keyset"
- assertVisible:
    id: "btn_rotate_keyset"
- tapOn:
    id: "btn_back"
- waitForAnimationToEnd
- tapOn:
    text: "Onboard Device"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_connect_entry"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-entry-maestro" > "$EVIDENCE_ROOT/ios-entry-maestro.log" 2>&1
  ios_snapshot "02-onboard-entry"

  local relay_enc
  relay_enc="$(python3 -c 'import urllib.parse; print(urllib.parse.quote("ws://127.0.0.1:8194"))')"
  xcrun simctl openurl "$UDID" "igloo://test-create-keyset?group_name=VisualA11yIOS&threshold=2&count=3&device_name=visual-ios&relay=${relay_enc}&auto_finish=true" >/dev/null
  sleep 8
  ios_snapshot "03-dashboard"

  cat > "$flow" <<EOF
appId: $APP_ID
---
- scrollUntilVisible:
    element:
      text: "Settings"
    timeout: 30000
- tapOn:
    text: "Settings"
- waitForAnimationToEnd
- assertVisible:
    text: "Settings"
- scrollUntilVisible:
    element:
      id: "btn_copy_profile"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    id: "btn_copy_profile"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-settings-maestro" > "$EVIDENCE_ROOT/ios-settings-maestro.log" 2>&1
  ios_snapshot "04-settings"

  require_in_file "tile_create_keyset" "$EVIDENCE_ROOT/ios-01-hub-large-text.hierarchy.txt"
  require_in_file "btn_connect_entry" "$EVIDENCE_ROOT/ios-02-onboard-entry.hierarchy.txt"
  require_in_file "visual-ios" "$EVIDENCE_ROOT/ios-03-dashboard.hierarchy.txt"
  require_in_file "btn_copy_profile" "$EVIDENCE_ROOT/ios-04-settings.hierarchy.txt"
}

run_android() {
  echo "[visual-a11y $(date +%H:%M:%S)] Android fresh install + large font scale"
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" shell settings put system font_scale 1.3 >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ANDROID_ACTIVITY" >/dev/null
  sleep 3
  android_snapshot "01-hub-large-text"

  local flow="$EVIDENCE_ROOT/android-entry-screens.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- assertVisible:
    text: "Igloo"
- assertVisible:
    id: "tile_create_keyset"
- assertVisible:
    id: "tile_load_profile"
- assertVisible:
    id: "tile_onboard_device"
- tapOn:
    id: "tile_create_keyset"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_create_new_keyset"
- assertVisible:
    id: "btn_rotate_keyset"
- tapOn:
    id: "btn_back"
- waitForAnimationToEnd
- tapOn:
    text: "Onboard Device"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_connect_entry"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-entry-maestro" > "$EVIDENCE_ROOT/android-entry-maestro.log" 2>&1
  android_snapshot "02-onboard-entry"

  adb -s "$SERIAL" shell am start \
    -a "$ANDROID_CREATE_ACTION" \
    -n "$ANDROID_ACTIVITY" \
    --es group_name "VisualA11yAndroid" \
    --ei threshold 2 \
    --ei count 3 \
    --es device_name "visual-android" \
    --es relay "ws://10.0.2.2:8194" \
    --ez auto_finish true >/dev/null
  sleep 8
  android_snapshot "03-dashboard"

  cat > "$flow" <<EOF
appId: $APP_ID
---
- scrollUntilVisible:
    element:
      text: "Settings"
    timeout: 30000
- tapOn:
    text: "Settings"
- waitForAnimationToEnd
- assertVisible:
    text: "Settings"
- scrollUntilVisible:
    element:
      id: "btn_copy_profile"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    id: "btn_copy_profile"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-settings-maestro" > "$EVIDENCE_ROOT/android-settings-maestro.log" 2>&1
  android_snapshot "04-settings"

  require_in_file "tile_create_keyset" "$EVIDENCE_ROOT/android-01-hub-large-text.hierarchy.xml"
  require_in_file "btn_connect_entry" "$EVIDENCE_ROOT/android-02-onboard-entry.hierarchy.xml"
  require_in_file "visual-android" "$EVIDENCE_ROOT/android-03-dashboard.hierarchy.xml"
  require_in_file "btn_copy_profile" "$EVIDENCE_ROOT/android-04-settings.hierarchy.xml"
}

require_preflight
run_ios
run_android

for image in "$EVIDENCE_ROOT"/*.png; do
  verify_screenshot "$image"
done

cat > "$SUMMARY" <<EOF
ios_content_size=accessibility-large
android_font_scale=1.3
screenshots=$(find "$EVIDENCE_ROOT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
result=pass
EOF

echo "[visual-a11y RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
