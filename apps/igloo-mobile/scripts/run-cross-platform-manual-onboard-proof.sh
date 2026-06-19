#!/usr/bin/env bash
# Bidirectional cross-platform manual package onboarding proof.
#
# Proves that native-created bfonboard1 packages can be consumed through the
# standard Connect form, not only the QR scanner fallback path:
#   1. iOS creates a bfonboard1 QR package; Android pastes it into Connect.
#   2. Android creates a bfonboard1 QR package; iOS pastes it into Connect.
#
# Evidence is written under:
#   apps/igloo-mobile/library/evidence/mobile-cross-platform-manual-onboard-*

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-manual-onboard-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
echo "[cross-manual-onboard $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

redact_text_file() {
  local input="$1"
  local output="$2"
  [ -f "$input" ] || return 0
  python3 - "$input" "$output" <<'PY'
import re
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, encoding="utf-8", errors="ignore").read()
data = re.sub(r'text="([^"]{50,})"', lambda m: f'text="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'content-desc="([^"]{50,})"', lambda m: f'content-desc="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'"(text|value|accessibilityText)" : "([A-Za-z0-9]{50,})"', lambda m: f'"{m.group(1)}" : "[REDACTED-{len(m.group(2))}chars]"', data)
open(dst, "w", encoding="utf-8").write(data)
PY
}

require_preflight() {
  [ -d "$APP_BUNDLE" ] || { echo "[cross-manual-onboard] missing $APP_BUNDLE; run just ios-full" >&2; exit 1; }
  [ -f "$APK" ] || { echo "[cross-manual-onboard] missing $APK; run just android-full" >&2; exit 1; }
  command -v zbarimg >/dev/null || { echo "[cross-manual-onboard] missing zbarimg; brew install zbar" >&2; exit 1; }
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
    || { echo "[cross-manual-onboard] relay 127.0.0.1:8194 unreachable" >&2; exit 1; }
  adb -s "$SERIAL" get-state >/dev/null 2>&1 \
    || { echo "[cross-manual-onboard] Android device $SERIAL not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "$UDID" \
    || { echo "[cross-manual-onboard] iOS simulator $UDID not booted" >&2; exit 1; }
}

run_maestro() {
  local device="$1"
  local flow="$2"
  local out="$3"
  shift 3
  mkdir -p "$out/maestro"
  echo "[cross-manual-onboard $(date +%H:%M:%S)] maestro: $(basename "$flow") on $device"
  set +e
  maestro --device "$device" test "$flow" --debug-output "$out/maestro" "$@" > "$out/maestro.log" 2>&1
  local code=$?
  set -e
  tail -80 "$out/maestro.log"
  return "$code"
}

ios_snapshot() {
  local dir="$1"
  local tag="$2"
  xcrun simctl io "$UDID" screenshot "$dir/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$dir/hierarchy-${tag}.txt" 2>&1 || true
  redact_text_file "$dir/hierarchy-${tag}.txt" "$dir/redacted-hierarchy-${tag}.txt"
}

android_snapshot() {
  local dir="$1"
  local tag="$2"
  adb -s "$SERIAL" shell screencap -p > "$dir/${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$dir/hierarchy-${tag}.xml" >/dev/null 2>&1 || true
  redact_text_file "$dir/hierarchy-${tag}.xml" "$dir/redacted-hierarchy-${tag}.xml"
}

decode_package_from_qr_evidence() {
  local evidence="$1"
  zbarimg --quiet --raw "$evidence/03-qr-modal.png" 2>/dev/null \
    | grep -E '^bfonboard1' \
    | head -1
}

password_from_qr_evidence() {
  local evidence="$1"
  local group_name run_tag
  group_name="$(awk -F= '/^group_name=/{print $2}' "$evidence/input.txt")"
  run_tag="${group_name##*-}"
  printf 'qrdisplay%s' "$run_tag"
}

write_package_input_summary() {
  local source_dir="$1"
  local recipient="$2"
  local relay="$3"
  local package="$4"
  local out="$5"
  {
    echo "source_evidence=$(basename "$source_dir")"
    echo "recipient=$recipient"
    echo "entry_path=manual_connect_form"
    echo "package_length=${#package}"
    printf '%s' "$package" | shasum -a 256 | awk '{ print "package_sha256=" $1 }'
    echo "relay=$relay"
  } > "$out/input.txt"
}

install_android_fresh() {
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
}

install_ios_fresh() {
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
}

write_ios_debug_onboard_creds() {
  local package="$1"
  local password="$2"
  local relay="$3"
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null || true)"
  [ -n "$container" ] || { echo "[cross-manual-onboard] iOS app container unavailable" >&2; return 1; }
  mkdir -p "$container/Documents"
  python3 - "$container/Documents/igloo_test_creds.json" "$package" "$password" "$relay" <<'PY'
import json
import sys

path, package, password, relay = sys.argv[1:5]
with open(path, "w", encoding="utf-8") as f:
    json.dump(
        {
            "package": package,
            "password": password,
            "relay": relay,
            "_focus": "mobile-cross-platform-manual-onboard",
        },
        f,
    )
    f.write("\n")
PY
}

launch_ios_with_onboard_diagnostics() {
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 4
}

write_android_manual_onboard_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: Android cross-platform manual Connect onboarding
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
- assertVisible:
    text: "Onboard Device"
- tapOn:
    text: "Onboard Device"
- scrollUntilVisible:
    element:
      id: "btn_connect_entry"
    timeout: 20000
- tapOn:
    id: "btn_connect_entry"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 20000
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "input_relay_url"
- assertVisible:
    id: "btn_connect"
- tapOn:
    id: "input_relay_url"
- eraseText: 64
- inputText:
    id: "input_relay_url"
    text: "${RELAY_URL}"
- tapOn:
    id: "input_package"
- setClipboard: "${ONBOARD_PACKAGE}"
- pasteText
- tapOn:
    id: "input_password"
- eraseText: 64
- setClipboard: "${ONBOARD_PASSWORD}"
- pasteText
- waitForAnimationToEnd
- tapOn:
    id: "btn_connect"
- waitForAnimationToEnd
- waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_save_device"
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "carol-Android"
- tapOn:
    id: "btn_save_device"
- waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      text: "carol-Android"
    timeout: 30000
- assertVisible:
    text: "carol-Android"
- pressKey: back
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
- scrollUntilVisible:
    element:
      text: "carol-Android"
    timeout: 10000
- assertVisible:
    text: "carol-Android"
EOF
}

android_recipient_manual_onboard() {
  local source_dir="$1"
  local out="$2"
  local package password
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  mkdir -p "$out"
  write_package_input_summary "$source_dir" "android" "ws://10.0.2.2:8194" "$package" "$out"
  install_android_fresh
  local flow="$out/android-manual-onboard.yaml"
  write_android_manual_onboard_flow "$flow"
  if ! run_maestro "$SERIAL" "$flow" "$out" \
    -e ONBOARD_PACKAGE="$package" \
    -e ONBOARD_PASSWORD="$password" \
    -e RELAY_URL="ws://10.0.2.2:8194"; then
    android_snapshot "$out" "after-manual-onboard-failure"
    return 1
  fi
  android_snapshot "$out" "after-manual-onboard"
}

write_ios_manual_onboard_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: iOS cross-platform manual Connect onboarding
---
- assertVisible:
    text: "Igloo"
- assertVisible:
    text: "Onboard Device"
- tapOn:
    text: "Onboard Device"
- scrollUntilVisible:
    element:
      id: "btn_connect_entry"
    timeout: 20000
- tapOn:
    id: "btn_connect_entry"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 20000
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "btn_paste_password"
- assertVisible:
    id: "input_relay_url"
- assertVisible:
    id: "btn_connect"
- tapOn:
    id: "input_relay_url"
- eraseText: 64
- inputText:
    id: "input_relay_url"
    text: "${RELAY_URL}"
- tapOn:
    id: "input_package"
- setClipboard: "${ONBOARD_PACKAGE}"
- tapOn:
    id: "btn_paste_package"
- runFlow:
    when:
      visible:
        text: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Allow"
    commands:
      - tapOn: "Allow"
      - waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_password"
    timeout: 10000
- setClipboard: "${ONBOARD_PASSWORD}"
- tapOn:
    id: "btn_paste_password"
- runFlow:
    when:
      visible:
        text: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Allow"
    commands:
      - tapOn: "Allow"
      - waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_connect"
    timeout: 10000
- tapOn:
    id: "btn_connect"
- waitForAnimationToEnd
- waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_save_device"
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "bobios"
- pressKey: Enter
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_save_device"
    timeout: 10000
- tapOn:
    id: "btn_save_device"
- waitForAnimationToEnd
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      text: "Signer"
    timeout: 30000
- assertVisible:
    text: "Signer"
- assertVisible:
    text: "Permissions"
- assertVisible:
    text: "Settings"
EOF
}

ios_recipient_manual_onboard() {
  local source_dir="$1"
  local out="$2"
  local package password
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  mkdir -p "$out"
  write_package_input_summary "$source_dir" "ios" "ws://127.0.0.1:8194" "$package" "$out"
  install_ios_fresh
  local flow="$out/ios-manual-onboard.yaml"
  write_ios_manual_onboard_flow "$flow"
  printf '%s' "$package" > /tmp/igloo_test_package.txt
  write_ios_debug_onboard_creds "$package" "$password" "ws://127.0.0.1:8194"
  launch_ios_with_onboard_diagnostics
  set +e
  run_maestro "$UDID" "$flow" "$out" \
    -e ONBOARD_PACKAGE="$package" \
    -e ONBOARD_PASSWORD="$password" \
    -e RELAY_URL="ws://127.0.0.1:8194"
  local code=$?
  set -e
  rm -f /tmp/igloo_test_package.txt
  if [ "$code" -ne 0 ]; then
    ios_snapshot "$out" "after-manual-onboard-failure"
    return "$code"
  fi
  ios_snapshot "$out" "after-manual-onboard"
}

run_ios_to_android() {
  local source_dir="$EVIDENCE_ROOT/ios-source-qr"
  local lane_dir="$EVIDENCE_ROOT/ios-to-android-manual"
  echo "[cross-manual-onboard $(date +%H:%M:%S)] lane: iOS source -> Android manual recipient"
  EVIDENCE_DIR="$source_dir" "$APPS/scripts/run-focus-ios-qr-display.sh"
  android_recipient_manual_onboard "$source_dir" "$lane_dir"
  {
    cat "$lane_dir/input.txt"
    echo "result=pass"
  } > "$lane_dir/summary.txt"
}

run_android_to_ios() {
  local source_dir="$EVIDENCE_ROOT/android-source-qr"
  local lane_dir="$EVIDENCE_ROOT/android-to-ios-manual"
  echo "[cross-manual-onboard $(date +%H:%M:%S)] lane: Android source -> iOS manual recipient"
  EVIDENCE_DIR="$source_dir" "$APPS/scripts/run-focus-android-qr-display.sh"
  ios_recipient_manual_onboard "$source_dir" "$lane_dir"
  {
    cat "$lane_dir/input.txt"
    echo "result=pass"
  } > "$lane_dir/summary.txt"
}

require_preflight
run_ios_to_android
run_android_to_ios

cat > "$EVIDENCE_ROOT/summary.txt" <<EOF
ios_to_android_manual=$(cat "$EVIDENCE_ROOT/ios-to-android-manual/summary.txt" | tr '\n' ';')
android_to_ios_manual=$(cat "$EVIDENCE_ROOT/android-to-ios-manual/summary.txt" | tr '\n' ';')
result=pass
EOF

echo "[cross-manual-onboard RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$EVIDENCE_ROOT/summary.txt"
