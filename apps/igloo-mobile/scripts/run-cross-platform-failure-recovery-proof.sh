#!/usr/bin/env bash
# Bidirectional native failure/recovery proof.
#
# Proves that a bad onboarding password surfaces a user-visible error and that
# the recipient can recover with a fresh valid package, reach Review, and save
# the profile to Dashboard on both iOS and Android.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"

ACTION_INJECT="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"
ACTION_SAVE_TO_DASHBOARD="com.frostr.igloo.DEBUG_TEST_SAVE_TO_DASHBOARD"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-failure-recovery-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
echo "[failure-recovery $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

trap 'rm -f /tmp/igloo_test_package.txt' EXIT

urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

redact_file() {
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
data = re.sub(r'(value|label|accessibilityText)"? ?: "?([A-Za-z0-9]{50,})"?', lambda m: f'{m.group(1)}: [REDACTED-{len(m.group(2))}chars]', data)
open(dst, "w", encoding="utf-8").write(data)
PY
}

require_preflight() {
  [ -d "$APP_BUNDLE" ] || { echo "[failure-recovery] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
  [ -f "$APK" ] || { echo "[failure-recovery] missing $APK; run just android-assemble" >&2; exit 1; }
  command -v zbarimg >/dev/null || { echo "[failure-recovery] missing zbarimg; brew install zbar" >&2; exit 1; }
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
    || { echo "[failure-recovery] relay 127.0.0.1:8194 unreachable; run make demo-start" >&2; exit 1; }
  adb -s "$SERIAL" get-state >/dev/null 2>&1 \
    || { echo "[failure-recovery] Android device $SERIAL not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "$UDID" \
    || { echo "[failure-recovery] iOS simulator $UDID not booted" >&2; exit 1; }
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

run_ios_source_qr() {
  local out="${1:-$EVIDENCE_ROOT/ios-source-qr}"
  echo "[failure-recovery $(date +%H:%M:%S)] source: iOS native QR package"
  EVIDENCE_DIR="$out" "$APPS/scripts/run-focus-ios-qr-display.sh"
}

run_android_source_qr() {
  local out="${1:-$EVIDENCE_ROOT/android-source-qr}"
  echo "[failure-recovery $(date +%H:%M:%S)] source: Android native QR package"
  EVIDENCE_DIR="$out" "$APPS/scripts/run-focus-android-qr-display.sh"
}

ios_snapshot() {
  local dir="$1"
  local tag="$2"
  xcrun simctl io "$UDID" screenshot "$dir/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$dir/hierarchy-${tag}.txt" 2>&1 || true
  redact_file "$dir/hierarchy-${tag}.txt" "$dir/redacted-hierarchy-${tag}.txt"
}

android_snapshot() {
  local dir="$1"
  local tag="$2"
  adb -s "$SERIAL" shell screencap -p > "$dir/${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$dir/hierarchy-${tag}.xml" >/dev/null 2>&1 || true
  redact_file "$dir/hierarchy-${tag}.xml" "$dir/redacted-hierarchy-${tag}.xml"
}

wait_ios_text() {
  local out="$1"
  local needle="$2"
  local timeout_secs="$3"
  local started
  started="$(date +%s)"
  while true; do
    maestro --device "$UDID" hierarchy > "$out/.wait-ios.txt" 2>&1 || true
    if grep -Fq "$needle" "$out/.wait-ios.txt"; then
      rm -f "$out/.wait-ios.txt"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[failure-recovery] iOS timed out waiting for: $needle" >&2
      ios_snapshot "$out" "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

wait_android_text() {
  local out="$1"
  local needle="$2"
  local timeout_secs="$3"
  local started
  started="$(date +%s)"
  while true; do
    adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
    adb -s "$SERIAL" pull /sdcard/window_dump.xml "$out/.wait-android.xml" >/dev/null 2>&1 || true
    if [ -f "$out/.wait-android.xml" ] && grep -Fq "$needle" "$out/.wait-android.xml"; then
      rm -f "$out/.wait-android.xml"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[failure-recovery] Android timed out waiting for: $needle" >&2
      android_snapshot "$out" "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

run_ios_maestro_flow() {
  local flow="$1"
  local out="$2"
  maestro --device "$UDID" test "$flow" \
    --debug-output "$out/maestro-$(basename "$flow" .yaml)"
}

write_ios_debug_onboard_creds() {
  local package="$1"
  local password="$2"
  local relay="$3"
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null || true)"
  [ -n "$container" ] || { echo "[failure-recovery] iOS app container unavailable" >&2; return 1; }
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
            "_focus": "mobile-cross-platform-failure-recovery",
        },
        f,
    )
    f.write("\n")
PY
}

write_ios_wrong_password_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: iOS wrong-password onboarding error
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
    id: "btn_paste_package"
- assertVisible:
    id: "btn_connect"
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
      id: "btn_connect"
    timeout: 10000
- tapOn:
    id: "btn_connect"
- waitForAnimationToEnd
- waitForAnimationToEnd
- waitForAnimationToEnd
EOF
}

write_ios_valid_retry_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: iOS valid onboarding retry recovery
---
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Onboard Device"
    commands:
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
- scrollUntilVisible:
    element:
      id: "btn_connect"
    timeout: 20000
- tapOn:
    id: "btn_connect"
- waitForAnimationToEnd
- waitForAnimationToEnd
- waitForAnimationToEnd
EOF
}

android_inject() {
  local package="$1"
  local password="$2"
  local relay="$3"
  local device_name="$4"
  adb -s "$SERIAL" shell am start \
    -a "$ACTION_INJECT" \
    -n "$ACTIVITY" \
    --es package "$package" \
    --es password "$password" \
    --es relay "$relay" \
    --es device_name "$device_name" \
    --ez connect true >/dev/null
}

run_ios_failure_recovery() {
  local source_dir="$1"
  local out="$EVIDENCE_ROOT/ios"
  local package password wrong_password device_name relay valid_source_dir valid_package valid_password
  mkdir -p "$out"
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  [ -n "$package" ] || { echo "[failure-recovery] missing decoded Android source package" >&2; return 1; }
  [ -n "$password" ] || { echo "[failure-recovery] missing Android source package password" >&2; return 1; }
  wrong_password="wrong-${password}"
  device_name="failure-ios"
  relay="ws://127.0.0.1:8194"

  {
    echo "platform=ios"
    echo "wrong_source_evidence=$(basename "$source_dir")"
    echo "source_platform=android"
    echo "wrong_package_length=${#package}"
    printf '%s' "$package" | shasum -a 256 | awk '{ print "wrong_package_sha256=" $1 }'
    echo "wrong_source_password_length=${#password}"
    echo "wrong_password_length=${#wrong_password}"
    echo "relay=$relay"
  } > "$out/input.txt"

  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  rm -f /tmp/igloo_test_package.txt
  xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
  printf '%s' "$package" > /tmp/igloo_test_package.txt
  write_ios_debug_onboard_creds "$package" "$wrong_password" "$relay"
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 4
  ios_snapshot "$out" "01-launch"

  local wrong_flow="$out/ios-wrong-password.yaml"
  write_ios_wrong_password_flow "$wrong_flow"
  run_ios_maestro_flow "$wrong_flow" "$out"
  wait_ios_text "$out" "Wrong password. Check the password that came with your package." 180
  ios_snapshot "$out" "02-wrong-password"

  valid_source_dir="$EVIDENCE_ROOT/android-source-qr-valid"
  run_android_source_qr "$valid_source_dir"
  valid_package="$(decode_package_from_qr_evidence "$valid_source_dir")"
  valid_password="$(password_from_qr_evidence "$valid_source_dir")"
  [ -n "$valid_package" ] || { echo "[failure-recovery] missing valid Android source package" >&2; return 1; }
  [ -n "$valid_password" ] || { echo "[failure-recovery] missing valid Android source package password" >&2; return 1; }
  {
    echo "valid_source_evidence=$(basename "$valid_source_dir")"
    echo "valid_package_length=${#valid_package}"
    printf '%s' "$valid_package" | shasum -a 256 | awk '{ print "valid_package_sha256=" $1 }'
    echo "valid_password_length=${#valid_password}"
  } >> "$out/input.txt"

  printf '%s' "$valid_package" > /tmp/igloo_test_package.txt
  write_ios_debug_onboard_creds "$valid_package" "$valid_password" "$relay"
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 4
  local retry_flow="$out/ios-valid-retry.yaml"
  write_ios_valid_retry_flow "$retry_flow"
  run_ios_maestro_flow "$retry_flow" "$out"
  wait_ios_text "$out" "input_device_name" 180
  ios_snapshot "$out" "03-recovered-review"

  xcrun simctl openurl "$UDID" "igloo://test-save-to-dashboard?device_name=$(urlencode "$device_name")" >/dev/null
  wait_ios_text "$out" "Signer Stopped" 60
  wait_ios_text "$out" "$device_name" 60
  ios_snapshot "$out" "04-recovered-dashboard"
  rm -f /tmp/igloo_test_package.txt

  {
    cat "$out/input.txt"
    echo "wrong_password_error=pass"
    echo "valid_retry_dashboard=pass"
    echo "result=pass"
  } > "$out/summary.txt"
}

run_android_failure_recovery() {
  local source_dir="$1"
  local out="$EVIDENCE_ROOT/android"
  local package password wrong_password device_name relay valid_source_dir valid_package valid_password
  mkdir -p "$out"
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  [ -n "$package" ] || { echo "[failure-recovery] missing decoded iOS source package" >&2; return 1; }
  [ -n "$password" ] || { echo "[failure-recovery] missing iOS source package password" >&2; return 1; }
  wrong_password="wrong-${password}"
  device_name="failure-android"
  relay="ws://10.0.2.2:8194"

  {
    echo "platform=android"
    echo "wrong_source_evidence=$(basename "$source_dir")"
    echo "source_platform=ios"
    echo "wrong_package_length=${#package}"
    printf '%s' "$package" | shasum -a 256 | awk '{ print "wrong_package_sha256=" $1 }'
    echo "wrong_source_password_length=${#password}"
    echo "wrong_password_length=${#wrong_password}"
    echo "relay=$relay"
  } > "$out/input.txt"

  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
  sleep 3
  android_snapshot "$out" "01-launch"

  android_inject "$package" "$wrong_password" "$relay" "$device_name"
  wait_android_text "$out" "Wrong password" 180
  android_snapshot "$out" "02-wrong-password"

  valid_source_dir="$EVIDENCE_ROOT/ios-source-qr-valid"
  run_ios_source_qr "$valid_source_dir"
  valid_package="$(decode_package_from_qr_evidence "$valid_source_dir")"
  valid_password="$(password_from_qr_evidence "$valid_source_dir")"
  [ -n "$valid_package" ] || { echo "[failure-recovery] missing valid iOS source package" >&2; return 1; }
  [ -n "$valid_password" ] || { echo "[failure-recovery] missing valid iOS source package password" >&2; return 1; }
  {
    echo "valid_source_evidence=$(basename "$valid_source_dir")"
    echo "valid_package_length=${#valid_package}"
    printf '%s' "$valid_package" | shasum -a 256 | awk '{ print "valid_package_sha256=" $1 }'
    echo "valid_password_length=${#valid_password}"
  } >> "$out/input.txt"

  android_inject "$valid_package" "$valid_password" "$relay" "$device_name"
  wait_android_text "$out" "$device_name" 180
  android_snapshot "$out" "03-recovered-review"

  adb -s "$SERIAL" shell am start \
    -a "$ACTION_SAVE_TO_DASHBOARD" \
    -n "$ACTIVITY" \
    --es device_name "$device_name" >/dev/null
  wait_android_text "$out" "Signer Stopped" 60
  wait_android_text "$out" "$device_name" 60
  android_snapshot "$out" "04-recovered-dashboard"

  {
    cat "$out/input.txt"
    echo "wrong_password_error=pass"
    echo "valid_retry_dashboard=pass"
    echo "result=pass"
  } > "$out/summary.txt"
}

require_preflight
run_android_source_qr "$EVIDENCE_ROOT/android-source-qr-wrong"
run_ios_failure_recovery "$EVIDENCE_ROOT/android-source-qr-wrong"
run_ios_source_qr "$EVIDENCE_ROOT/ios-source-qr-wrong"
run_android_failure_recovery "$EVIDENCE_ROOT/ios-source-qr-wrong"

cat > "$EVIDENCE_ROOT/summary.txt" <<EOF
ios=$(tr '\n' ';' < "$EVIDENCE_ROOT/ios/summary.txt")
android=$(tr '\n' ';' < "$EVIDENCE_ROOT/android/summary.txt")
result=pass
EOF

echo "[failure-recovery RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$EVIDENCE_ROOT/summary.txt"
