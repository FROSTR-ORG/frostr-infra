#!/usr/bin/env bash
# Cross-platform QR permission/fallback E2E proof.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-qr-permission-fallback-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[qr-permission-fallback $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

run_step() {
  local label="$1"
  shift
  local out="$EVIDENCE_ROOT/$label"
  mkdir -p "$out"
  echo "[qr-permission-fallback $(date +%H:%M:%S)] start: $label"
  (
    cd "$APPS"
    EVIDENCE_ROOT="$out" "$@"
  ) 2>&1 | tee "$EVIDENCE_ROOT/${label}.log"
  echo "[qr-permission-fallback $(date +%H:%M:%S)] pass: $label"
}

latest_dir() {
  local glob="$1"
  local dirs=("$APPS"/library/evidence/$glob)
  [ -d "${dirs[0]}" ] || return 1
  ls -td "${dirs[@]}" | head -1
}

record() {
  printf '%s=%s\n' "$1" "$2" >> "$SUMMARY"
}

run_ios_fallback_controls() {
  local out="$EVIDENCE_ROOT/03-ios-fallback-controls"
  local flow="$out/qr-fallback-controls-ios.yaml"
  mkdir -p "$out"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: QR fallback controls - iOS
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: true
    clearKeychain: true
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
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
      id: "btn_scan_qr"
    timeout: 20000
- tapOn:
    id: "btn_scan_qr"
- assertVisible:
    id: "qr_scan_camera_unavailable_title"
- assertVisible:
    id: "input_qr_fallback_package"
- assertVisible:
    id: "btn_qr_paste_clipboard"
- assertVisible:
    id: "btn_qr_scan_back"
- setClipboard: "bfonboard1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
- tapOn:
    id: "btn_qr_paste_clipboard"
- runFlow:
    when:
      visible:
        text: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
- runFlow:
    when:
      visible:
        text: "Allow"
    commands:
      - tapOn: "Allow"
- tapOn:
    id: "btn_qr_fallback_use"
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "btn_connect"
EOF
  echo "[qr-permission-fallback $(date +%H:%M:%S)] start: 03-ios-fallback-controls"
  maestro --device "${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}" test "$flow" \
    --debug-output "$out/maestro" 2>&1 | tee "$out/maestro.log"
  record "ios_qr_fallback_controls" "$out"
  echo "[qr-permission-fallback $(date +%H:%M:%S)] pass: 03-ios-fallback-controls"
}

run_android_fallback_controls() {
  local out="$EVIDENCE_ROOT/04-android-fallback-controls"
  local flow="$out/qr-fallback-controls-android.yaml"
  mkdir -p "$out"
  cat > "$flow" <<'EOF'
appId: com.frostr.igloo.dev
name: QR fallback controls - Android
---
- launchApp:
    appId: com.frostr.igloo.dev
    clearState: true
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
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
      id: "btn_scan_qr"
    timeout: 20000
- tapOn:
    id: "btn_scan_qr"
- assertVisible:
    id: "qr_scan_camera_unavailable_title"
- assertVisible:
    id: "input_qr_fallback_package"
- assertVisible:
    id: "btn_qr_paste_clipboard"
- assertVisible:
    id: "btn_qr_scan_back"
- tapOn:
    id: "input_qr_fallback_package"
- setClipboard: "bfonboard1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
- pasteText
- tapOn:
    id: "btn_qr_fallback_use"
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "btn_connect"
EOF
  echo "[qr-permission-fallback $(date +%H:%M:%S)] start: 04-android-fallback-controls"
  maestro --device "${ANDROID_SERIAL:-emulator-5554}" test "$flow" \
    --debug-output "$out/maestro" 2>&1 | tee "$out/maestro.log"
  record "android_qr_fallback_controls" "$out"
  echo "[qr-permission-fallback $(date +%H:%M:%S)] pass: 04-android-fallback-controls"
}

run_step "01-ios-qr-display" just focus-ios-qr-display
record "ios_qr_display" "$(latest_dir 'mobile-ios-qr-display-*')"

run_step "02-android-qr-display" just focus-android-qr-display
record "android_qr_display" "$(latest_dir 'mobile-android-qr-display-*')"

run_ios_fallback_controls
run_android_fallback_controls

record "result" "pass"
echo "[qr-permission-fallback RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
