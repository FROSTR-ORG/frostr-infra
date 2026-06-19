#!/usr/bin/env bash
# Orchestrated runtime error proof.
#
# Maestro 2.6 runScript evaluates JavaScript in a restricted engine, so Docker
# service mutations are driven from this shell script between small Maestro
# flows instead of from inside a monolithic flow.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"

APP_ID="com.frostr.igloo.dev"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-runtime-errors-$(date +%Y-%m-%d-%H%M%S)}"
RELAY_PORT="${DEV_RELAY_PORT:-8194}"

mkdir -p "$EVIDENCE_ROOT"
echo "[runtime-errors $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

run_maestro() {
  local device="$1"
  local flow="$2"
  local out="$3"
  mkdir -p "$out"
  echo "[runtime-errors $(date +%H:%M:%S)] maestro: $(basename "$flow") on $device"
  maestro --device "$device" test "$flow" --debug-output "$out/maestro" 2>&1 | tee "$out/maestro.log"
}

write_common_start_flow() {
  local flow="$1"
  local profile="$2"
  local screenshot_prefix="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime common start $profile
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        id: "tab_signer"
    commands:
      - tapOn:
          id: "btn_back_dashboard"
      - waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
- scrollUntilVisible:
    element:
      text: "$profile"
    timeout: 10000
- tapOn:
    text: "$profile"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 10000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- takeScreenshot:
    path: "${screenshot_prefix}-sign-ready.png"
EOF
}

write_assert_sign_ready_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime assert sign ready
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 30000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_resume_recovery_flow() {
  local flow="$1"
  local before_screenshot="$2"
  local after_screenshot="$3"
  local profile="$4"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime resume recovery
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- takeScreenshot:
    path: "$before_screenshot"
- runFlow:
    when:
      visible:
        text: "Signer Stopped"
    commands:
      - scrollUntilVisible:
          element:
            id: "btn_start_signer"
          timeout: 10000
      - tapOn:
          id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 90000
- takeScreenshot:
    path: "$after_screenshot"
EOF
}

write_relay_disconnected_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime relay loss stops signer
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Stopped"
    timeout: 150000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_relay_down_start_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime relay down start
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- scrollUntilVisible:
    element:
      id: "signer_status_card"
    timeout: 10000
- runFlow:
    when:
      visible:
        id: "btn_stop_signer"
    commands:
      - tapOn:
          id: "btn_stop_signer"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 10000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Running (Degraded)"
    timeout: 30000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_alice_down_start_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime alice down start
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 10000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Running (Degraded)"
    timeout: 30000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_stop_signer_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime force stop signer
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- runFlow:
    when:
      visible:
        id: "btn_stop_signer"
    commands:
      - tapOn:
          id: "btn_stop_signer"
      - waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      text: "Signer Stopped"
    timeout: 30000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_sign_unavailable_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime sign unavailable
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 10000
- tapOn:
    id: "tab_signer"
- scrollUntilVisible:
    element:
      id: "btn_test_sign"
    timeout: 10000
- scrollUntilVisible:
    element:
      text: "No peers detected"
    timeout: 10000
- scrollUntilVisible:
    element:
      id: "pending_ops_empty"
    timeout: 10000
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_settings_locked_flow() {
  local flow="$1"
  local screenshot="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime settings locked
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 10000
- tapOn:
    id: "tab_settings"
- scrollUntilVisible:
    element:
      id: "btn_save_settings"
    timeout: 10000
    visibilityPercentage: 50
- takeScreenshot:
    path: "$screenshot"
EOF
}

write_set_timeout_flow() {
  local flow="$1"
  local value="$2"
  local profile="$3"
  cat > "$flow" <<EOF
appId: $APP_ID
name: runtime set timeout $value
---
- launchApp:
    appId: $APP_ID
    clearState: false
    clearKeychain: false
- waitForAnimationToEnd
- runFlow:
    when:
      visible:
        text: "Create / Rotate Keyset"
    commands:
      - scrollUntilVisible:
          element:
            text: "$profile"
          timeout: 10000
      - tapOn:
          text: "$profile"
      - waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 10000
- tapOn:
    id: "tab_settings"
- scrollUntilVisible:
    element:
      id: "input_sign_timeout"
    timeout: 10000
- tapOn:
    id: "input_sign_timeout"
- eraseText: 10
- inputText: "$value"
- scrollUntilVisible:
    element:
      id: "btn_save_settings"
    timeout: 10000
- tapOn:
    id: "btn_save_settings"
- waitForAnimationToEnd
EOF
}

background_foreground_cycle() {
  local device_kind="$1"
  "$SCRIPT_DIR/runtime-background-app.sh"
  sleep 2
  "$SCRIPT_DIR/runtime-foreground-app.sh"
  sleep 2
  if [ "$device_kind" = "ios" ]; then
    write_resume_recovery_flow "$EVIDENCE_ROOT/ios-resume-recovery.yaml" "ios-val-err-005-resume-state.png" "ios-val-err-005-recovered.png" "bob"
    run_maestro "$UDID" "$EVIDENCE_ROOT/ios-resume-recovery.yaml" "$EVIDENCE_ROOT/ios-background"
  else
    write_resume_recovery_flow "$EVIDENCE_ROOT/android-resume-recovery.yaml" "android-val-err-005-resume-state.png" "android-val-err-005-recovered.png" "carol"
    run_maestro "$SERIAL" "$EVIDENCE_ROOT/android-resume-recovery.yaml" "$EVIDENCE_ROOT/android-background"
  fi
}

stop_ios_peer_for_android_negative() {
  if xcrun simctl list devices booted | grep -q "$UDID"; then
    echo "[runtime-errors $(date +%H:%M:%S)] stopping iOS peer before Android no-peer negative guard"
    xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
    sleep 2
  fi
}

run_platform() {
  local device_kind="$1"
  local device="$2"
  local profile="$3"
  local prefix="$4"
  local target_dir="$EVIDENCE_ROOT/$device_kind"
  mkdir -p "$target_dir"

  write_common_start_flow "$target_dir/01-start.yaml" "$profile" "$prefix-val-err-004-005"
  run_maestro "$device" "$target_dir/01-start.yaml" "$target_dir/01-start"

  background_foreground_cycle "$device_kind"

  "$SCRIPT_DIR/service-control.sh" stop relay
  write_relay_disconnected_flow "$target_dir/02-relay-disconnected.yaml" "$prefix-val-err-002-disconnected.png" "$profile"
  run_maestro "$device" "$target_dir/02-relay-disconnected.yaml" "$target_dir/02-relay-disconnected"
  "$SCRIPT_DIR/service-control.sh" start relay
  write_resume_recovery_flow "$target_dir/03-relay-recovered.yaml" "$prefix-val-err-002-recovery-state.png" "$prefix-val-err-002-recovered.png" "$profile"
  run_maestro "$device" "$target_dir/03-relay-recovered.yaml" "$target_dir/03-relay-recovered"

  "$SCRIPT_DIR/service-control.sh" stop relay
  write_relay_down_start_flow "$target_dir/04-relay-down-start.yaml" "$prefix-val-err-001-error.png" "$profile"
  run_maestro "$device" "$target_dir/04-relay-down-start.yaml" "$target_dir/04-relay-down-start"
  "$SCRIPT_DIR/service-control.sh" start relay
  write_resume_recovery_flow "$target_dir/05-relay-down-recovered.yaml" "$prefix-val-err-001-recovery-state.png" "$prefix-val-err-001-recovered.png" "$profile"
  run_maestro "$device" "$target_dir/05-relay-down-recovered.yaml" "$target_dir/05-relay-down-recovered"

  write_stop_signer_flow "$target_dir/06-stop-before-alice-down.yaml" "$prefix-val-err-006-precondition-stopped.png" "$profile"
  run_maestro "$device" "$target_dir/06-stop-before-alice-down.yaml" "$target_dir/06-stop-before-alice-down"
  if [ "$device_kind" = "android" ]; then
    stop_ios_peer_for_android_negative
  fi
  "$SCRIPT_DIR/service-control.sh" stop alice
  write_alice_down_start_flow "$target_dir/07-alice-down-start.yaml" "$prefix-val-err-006-no-false-ready.png" "$profile"
  run_maestro "$device" "$target_dir/07-alice-down-start.yaml" "$target_dir/07-alice-down-start"
  RUNTIME_ABSENCE_TARGET="$device_kind" "$SCRIPT_DIR/runtime-wait-sign-ready-absent.sh"
  write_sign_unavailable_flow "$target_dir/08-alice-down-sign-failure.yaml" "$prefix-val-err-003-failure.png" "$profile"
  run_maestro "$device" "$target_dir/08-alice-down-sign-failure.yaml" "$target_dir/08-alice-down-sign-failure"
  write_settings_locked_flow "$target_dir/09-settings-locked.yaml" "$prefix-val-err-007-settings-locked.png" "$profile"
  run_maestro "$device" "$target_dir/09-settings-locked.yaml" "$target_dir/09-settings-locked"
  "$SCRIPT_DIR/service-control.sh" start alice
  write_resume_recovery_flow "$target_dir/11-alice-recovered.yaml" "$prefix-val-err-006-recovery-state.png" "$prefix-val-err-006-recovered.png" "$profile"
  run_maestro "$device" "$target_dir/11-alice-recovered.yaml" "$target_dir/11-alice-recovered"
}

cleanup() {
  "$SCRIPT_DIR/service-control.sh" start relay >/dev/null 2>&1 || true
  "$SCRIPT_DIR/service-control.sh" start alice >/dev/null 2>&1 || true
}
trap cleanup EXIT

python3 - "$RELAY_PORT" <<'PY' \
  || { echo "[runtime-errors] relay 127.0.0.1:${RELAY_PORT} unreachable" >&2; exit 1; }
import socket
import sys

port = int(sys.argv[1])
s = socket.create_connection(("127.0.0.1", port), 2)
s.close()
PY

run_platform ios "$UDID" bob "ios"
run_platform android "$SERIAL" carol "android"

{
  echo "ios=pass"
  echo "android=pass"
  echo "result=pass"
} > "$EVIDENCE_ROOT/summary.txt"

echo "[runtime-errors RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
