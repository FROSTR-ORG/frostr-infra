#!/usr/bin/env bash
# Cross-platform reinstall/upgrade migration proof.

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
ANDROID_SAVE_SETTINGS_ACTION="com.frostr.igloo.DEBUG_TEST_SAVE_SETTINGS"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-upgrade-migration-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[upgrade-migration $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

require_preflight() {
  [ -d "$APP_BUNDLE" ] || { echo "[upgrade-migration] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
  [ -f "$APK" ] || { echo "[upgrade-migration] missing $APK; run just android-assemble" >&2; exit 1; }
  adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[upgrade-migration] Android $SERIAL not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "$UDID" || { echo "[upgrade-migration] iOS simulator $UDID not booted" >&2; exit 1; }
}

ios_snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_ROOT/ios-${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_ROOT/ios-${tag}.hierarchy.txt" 2>&1 || true
}

android_snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_ROOT/android-${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_ROOT/android-${tag}.hierarchy.xml" >/dev/null 2>&1 || true
}

require_in_file() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || { echo "[upgrade-migration] missing '$needle' in $file" >&2; exit 1; }
}

run_ios() {
  echo "[upgrade-migration $(date +%H:%M:%S)] seed iOS profile before reinstall"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 \
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
    xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 2

  local relay_enc
  relay_enc="$(python3 -c 'import urllib.parse; print(urllib.parse.quote("ws://127.0.0.1:8194"))')"
  xcrun simctl openurl "$UDID" "igloo://test-create-keyset?group_name=UpgradeIOS&threshold=2&count=3&device_name=upgrade-ios&relay=${relay_enc}&auto_finish=true" >/dev/null
  sleep 8
  xcrun simctl openurl "$UDID" "igloo://test-save-settings?sign_timeout_secs=45&peer_selection_strategy=random" >/dev/null
  sleep 2
  ios_snapshot "01-before-reinstall"
  require_in_file "upgrade-ios" "$EVIDENCE_ROOT/ios-01-before-reinstall.hierarchy.txt"

  echo "[upgrade-migration $(date +%H:%M:%S)] reinstall iOS without clearing data"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 \
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
    xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 4
  ios_snapshot "02-after-reinstall-hub"

  local flow="$EVIDENCE_ROOT/ios-open-upgraded-profile.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "upgrade-ios"
      - waitForAnimationToEnd
- assertVisible:
    text: "upgrade-ios"
- scrollUntilVisible:
    element:
      text: "Settings"
    timeout: 30000
- tapOn:
    text: "Settings"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      text: "45"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    text: "45"
- scrollUntilVisible:
    element:
      text: "random"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    text: "random"
EOF
  maestro --device "$UDID" test "$flow" --debug-output "$EVIDENCE_ROOT/ios-upgrade-maestro" > "$EVIDENCE_ROOT/ios-upgrade-maestro.log" 2>&1
  ios_snapshot "03-after-reinstall-settings"
  require_in_file "upgrade-ios" "$EVIDENCE_ROOT/ios-03-after-reinstall-settings.hierarchy.txt"
}

run_android() {
  echo "[upgrade-migration $(date +%H:%M:%S)] seed Android profile before reinstall"
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ANDROID_ACTIVITY" >/dev/null
  sleep 2
  adb -s "$SERIAL" shell am start \
    -a "$ANDROID_CREATE_ACTION" \
    -n "$ANDROID_ACTIVITY" \
    --es group_name "UpgradeAndroid" \
    --ei threshold 2 \
    --ei count 3 \
    --es device_name "upgrade-android" \
    --es relay "ws://10.0.2.2:8194" \
    --ez auto_finish true >/dev/null
  sleep 8
  adb -s "$SERIAL" shell am start \
    -a "$ANDROID_SAVE_SETTINGS_ACTION" \
    -n "$ANDROID_ACTIVITY" \
    --ei sign_timeout_secs 45 \
    --es peer_selection_strategy random >/dev/null
  sleep 2
  android_snapshot "01-before-reinstall"
  require_in_file "upgrade-android" "$EVIDENCE_ROOT/android-01-before-reinstall.hierarchy.xml"

  echo "[upgrade-migration $(date +%H:%M:%S)] reinstall Android without clearing data"
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ANDROID_ACTIVITY" >/dev/null
  sleep 4
  android_snapshot "02-after-reinstall-hub"

  local flow="$EVIDENCE_ROOT/android-open-upgraded-profile.yaml"
  cat > "$flow" <<EOF
appId: $APP_ID
---
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "upgrade-android"
      - waitForAnimationToEnd
- assertVisible:
    text: "upgrade-android"
- scrollUntilVisible:
    element:
      text: "Settings"
    timeout: 30000
- tapOn:
    text: "Settings"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      text: "45"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    text: "45"
- scrollUntilVisible:
    element:
      text: "random"
    timeout: 30000
    visibilityPercentage: 50
- assertVisible:
    text: "random"
EOF
  maestro --device "$SERIAL" test "$flow" --debug-output "$EVIDENCE_ROOT/android-upgrade-maestro" > "$EVIDENCE_ROOT/android-upgrade-maestro.log" 2>&1
  android_snapshot "03-after-reinstall-settings"
  require_in_file "upgrade-android" "$EVIDENCE_ROOT/android-03-after-reinstall-settings.hierarchy.xml"
}

require_preflight
run_ios
run_android

cat > "$SUMMARY" <<EOF
ios_profile=upgrade-ios
android_profile=upgrade-android
settings_persisted=sign_timeout_45_peer_strategy_random
upgrade_model=reinstall_same_bundle_without_clear_state
result=pass
EOF

echo "[upgrade-migration RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
