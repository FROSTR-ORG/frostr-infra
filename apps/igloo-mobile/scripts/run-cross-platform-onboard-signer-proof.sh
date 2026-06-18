#!/usr/bin/env bash
# Bidirectional cross-platform onboarding + signer proof.
#
# Proves the highest-risk native-created path end-to-end:
#   1. iOS creates a bfonboard1 QR package.
#   2. Android consumes that package through the product QR fallback flow.
#   3. Android starts its onboarded signer and completes Test Sign + Test ECDH
#      against the still-running iOS source signer.
#   4. Repeat in reverse: Android source -> iOS recipient -> Test Sign/ECDH.
#
# Evidence is written under:
#   apps/igloo-mobile/library/evidence/mobile-cross-platform-onboard-signer-*

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

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-onboard-signer-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
echo "[cross-onboard-signer $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

require_preflight() {
  [ -d "$APP_BUNDLE" ] || { echo "[cross-onboard-signer] missing $APP_BUNDLE; run just ios-build" >&2; exit 1; }
  [ -f "$APK" ] || { echo "[cross-onboard-signer] missing $APK; run just android-assemble" >&2; exit 1; }
  command -v zbarimg >/dev/null || { echo "[cross-onboard-signer] missing zbarimg; brew install zbar" >&2; exit 1; }
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
    || { echo "[cross-onboard-signer] relay 127.0.0.1:8194 unreachable" >&2; exit 1; }
  adb -s "$SERIAL" get-state >/dev/null 2>&1 \
    || { echo "[cross-onboard-signer] Android device $SERIAL not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "$UDID" \
    || { echo "[cross-onboard-signer] iOS simulator $UDID not booted" >&2; exit 1; }
}

run_maestro() {
  local device="$1"
  local flow="$2"
  local out="$3"
  shift 3
  mkdir -p "$out/maestro"
  echo "[cross-onboard-signer $(date +%H:%M:%S)] maestro: $(basename "$flow") on $device"
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
data = re.sub(r'(value|label): ([A-Za-z0-9]{50,})', lambda m: f'{m.group(1)}: [REDACTED-{len(m.group(2))}chars]', data)
open(dst, "w", encoding="utf-8").write(data)
PY
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

android_recipient_onboard_qr() {
  local source_dir="$1"
  local out="$2"
  local package password
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  mkdir -p "$out"
  write_package_input_summary "$source_dir" "android" "ws://10.0.2.2:8194" "$package" "$out"
  install_android_fresh
  run_maestro "$SERIAL" "$APPS/flows/qr-scan-android.yaml" "$out" \
    -e ONBOARD_PACKAGE="$package" \
    -e ONBOARD_PASSWORD="$password" \
    -e RELAY_URL="ws://10.0.2.2:8194"
  android_snapshot "$out" "after-onboard"
}

ios_recipient_onboard_qr() {
  local source_dir="$1"
  local out="$2"
  local package password
  package="$(decode_package_from_qr_evidence "$source_dir")"
  password="$(password_from_qr_evidence "$source_dir")"
  mkdir -p "$out"
  write_package_input_summary "$source_dir" "ios" "ws://127.0.0.1:8194" "$package" "$out"
  printf '%s' "$package" > /tmp/igloo_test_package.txt
  install_ios_fresh
  set +e
  run_maestro "$UDID" "$APPS/flows/qr-scan-ios.yaml" "$out" \
    -e ONBOARD_PACKAGE="$package" \
    -e ONBOARD_PASSWORD="$password" \
    -e RELAY_URL="ws://127.0.0.1:8194"
  local code=$?
  set -e
  rm -f /tmp/igloo_test_package.txt
  ios_snapshot "$out" "after-onboard"
  return "$code"
}

write_android_signer_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: Android recipient Test Sign proof
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "Onboarded Device"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible: "qr-fallback"
    commands:
      - tapOn:
          text: "qr-fallback"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 30000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- assertVisible:
    text: "Sign Ready"
- scrollUntilVisible:
    element:
      id: "btn_test_sign"
    timeout: 30000
- tapOn:
    id: "btn_test_sign"
- scrollUntilVisible:
    element:
      id: "section_test_sign_result"
    timeout: 90000
    visibilityPercentage: 50
    centerElement: true
- scrollUntilVisible:
    element:
      id: "test_sign_request_id"
    timeout: 30000
- assertVisible:
    id: "test_sign_request_id"
- scrollUntilVisible:
    element:
      id: "test_sign_signature"
    timeout: 30000
- assertVisible:
    id: "test_sign_signature"
EOF
}

write_android_ecdh_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: Android recipient Test ECDH proof
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "Onboarded Device"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible: "qr-fallback"
    commands:
      - tapOn:
          text: "qr-fallback"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 30000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- assertVisible:
    text: "Sign Ready"
- scrollUntilVisible:
    element:
      id: "btn_test_ecdh"
    timeout: 30000
- tapOn:
    id: "btn_test_ecdh"
- extendedWaitUntil:
    notVisible:
      text: "ECDH..."
    timeout: 90000
- scrollUntilVisible:
    element:
      id: "section_test_ecdh_result"
    timeout: 30000
    visibilityPercentage: 50
    centerElement: true
- scrollUntilVisible:
    element:
      id: "test_ecdh_request_id"
    timeout: 30000
- assertVisible:
    id: "test_ecdh_request_id"
- scrollUntilVisible:
    element:
      id: "test_ecdh_shared_secret"
    timeout: 30000
- assertVisible:
    id: "test_ecdh_shared_secret"
EOF
}

write_ios_signer_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: iOS recipient Test Sign proof
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "Onboarded Device"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible: "qr-fallback"
    commands:
      - tapOn:
          text: "qr-fallback"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 30000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- assertVisible:
    text: "Sign Ready"
- scrollUntilVisible:
    element:
      id: "btn_test_sign"
    timeout: 30000
- tapOn:
    id: "btn_test_sign"
- scrollUntilVisible:
    element:
      id: "test_sign_result_section"
    timeout: 90000
    visibilityPercentage: 50
    centerElement: true
- scrollUntilVisible:
    element:
      id: "test_sign_request_id"
    timeout: 30000
- assertVisible:
    id: "test_sign_request_id"
- scrollUntilVisible:
    element:
      id: "test_sign_signature"
    timeout: 30000
- assertVisible:
    id: "test_sign_signature"
EOF
}

write_ios_ecdh_flow() {
  local flow="$1"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: iOS recipient Test ECDH proof
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible: "Stored Profiles"
    commands:
      - tapOn:
          text: "Onboarded Device"
      - waitForAnimationToEnd
- runFlow:
    when:
      visible: "qr-fallback"
    commands:
      - tapOn:
          text: "qr-fallback"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 30000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- assertVisible:
    text: "Sign Ready"
- scrollUntilVisible:
    element:
      id: "btn_test_ecdh"
    timeout: 30000
- tapOn:
    id: "btn_test_ecdh"
- scrollUntilVisible:
    element:
      id: "test_ecdh_result_section"
    timeout: 90000
    visibilityPercentage: 50
    centerElement: true
- assertVisible:
    id: "test_ecdh_result_section"
- assertVisible:
    text: "Request ID"
- assertVisible:
    text: "Target Pubkey"
- assertVisible:
    text: "Shared Secret"
EOF
}

ios_verify_ecdh_result_values() {
  local out="$1"
  local hierarchy="$out/hierarchy-after-ecdh-proof.txt"
  local marker="$out/signer-proof/ecdh/result.txt"
  mkdir -p "$(dirname "$marker")"
  python3 - "$hierarchy" "$marker" <<'PY'
import json
import re
import sys

hierarchy_path, marker_path = sys.argv[1], sys.argv[2]
with open(hierarchy_path, encoding="utf-8", errors="ignore") as f:
    tree = json.load(f)

texts = []

def walk(node):
    attrs = node.get("attributes", {})
    for key in ("accessibilityText", "text", "value"):
        value = attrs.get(key)
        if value:
            texts.append(value)
    for child in node.get("children", []):
        walk(child)

walk(tree)
labels = {"Test ECDH Result", "Request ID", "Target Pubkey", "Shared Secret"}
missing = sorted(label for label in labels if label not in texts)
hex_values = [value for value in texts if re.fullmatch(r"[0-9a-f]{32}|[0-9a-f]{64}", value)]
has_request_id = any(len(value) == 32 for value in hex_values)
has_two_64_char_values = sum(1 for value in hex_values if len(value) == 64) >= 2

with open(marker_path, "w", encoding="utf-8") as marker:
    marker.write(f"ios_ecdh_labels_present={not missing}\n")
    marker.write(f"ios_ecdh_hex_value_count={len(hex_values)}\n")
    marker.write(f"ios_ecdh_has_request_id={has_request_id}\n")
    marker.write(f"ios_ecdh_has_target_and_shared_secret={has_two_64_char_values}\n")

if missing or not has_request_id or not has_two_64_char_values:
    print(open(marker_path, encoding="utf-8").read(), file=sys.stderr)
    sys.exit(1)
PY
}

android_signer_proof() {
  local out="$1"
  local sign_flow="$out/android-sign-proof.yaml"
  local ecdh_flow="$out/android-ecdh-proof.yaml"
  write_android_signer_flow "$sign_flow"
  write_android_ecdh_flow "$ecdh_flow"
  run_maestro "$SERIAL" "$sign_flow" "$out/signer-proof/sign"
  android_snapshot "$out" "after-sign-proof"
  run_maestro "$SERIAL" "$ecdh_flow" "$out/signer-proof/ecdh"
  android_snapshot "$out" "after-ecdh-proof"
}

ios_signer_proof() {
  local out="$1"
  local sign_flow="$out/ios-sign-proof.yaml"
  local ecdh_flow="$out/ios-ecdh-proof.yaml"
  write_ios_signer_flow "$sign_flow"
  write_ios_ecdh_flow "$ecdh_flow"
  run_maestro "$UDID" "$sign_flow" "$out/signer-proof/sign"
  ios_snapshot "$out" "after-sign-proof"
  run_maestro "$UDID" "$ecdh_flow" "$out/signer-proof/ecdh"
  ios_snapshot "$out" "after-ecdh-proof"
  ios_verify_ecdh_result_values "$out"
}

run_ios_to_android() {
  local source_dir="$EVIDENCE_ROOT/ios-source-qr"
  local lane_dir="$EVIDENCE_ROOT/ios-to-android"
  echo "[cross-onboard-signer $(date +%H:%M:%S)] lane: iOS source -> Android recipient"
  EVIDENCE_DIR="$source_dir" "$APPS/scripts/run-focus-ios-qr-display.sh"
  android_recipient_onboard_qr "$source_dir" "$lane_dir"
  android_signer_proof "$lane_dir"
  {
    cat "$lane_dir/input.txt"
    echo "signer_test_sign=pass"
    echo "signer_test_ecdh=pass"
    echo "result=pass"
  } > "$lane_dir/summary.txt"
}

run_android_to_ios() {
  local source_dir="$EVIDENCE_ROOT/android-source-qr"
  local lane_dir="$EVIDENCE_ROOT/android-to-ios"
  echo "[cross-onboard-signer $(date +%H:%M:%S)] lane: Android source -> iOS recipient"
  EVIDENCE_DIR="$source_dir" "$APPS/scripts/run-focus-android-qr-display.sh"
  ios_recipient_onboard_qr "$source_dir" "$lane_dir"
  ios_signer_proof "$lane_dir"
  {
    cat "$lane_dir/input.txt"
    echo "signer_test_sign=pass"
    echo "signer_test_ecdh=pass"
    echo "result=pass"
  } > "$lane_dir/summary.txt"
}

require_preflight
run_ios_to_android
run_android_to_ios

cat > "$EVIDENCE_ROOT/summary.txt" <<EOF
ios_to_android=$(cat "$EVIDENCE_ROOT/ios-to-android/summary.txt" | tr '\n' ';')
android_to_ios=$(cat "$EVIDENCE_ROOT/android-to-ios/summary.txt" | tr '\n' ';')
result=pass
EOF

echo "[cross-onboard-signer RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$EVIDENCE_ROOT/summary.txt"
