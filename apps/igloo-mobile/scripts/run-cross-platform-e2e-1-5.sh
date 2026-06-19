#!/usr/bin/env bash
# Cross-platform E2E lanes 1-5.
#
# 1. Bidirectional export/import/recover artifacts.
# 2. iOS + Android rotate-share replacement.
# 3. Bidirectional native onboard + live signer Test Sign/ECDH.
# 4. Wrong-password failure followed by valid retry recovery.
# 5. iOS + Android cross-flow persistence.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-e2e-1-5-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"

echo "[e2e-1-5 $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

if [ -z "${CROSS_PLATFORM_RELAY:-}" ]; then
  CROSS_HOST_IP="${CROSS_HOST_IP:-$(ipconfig getifaddr en0 2>/dev/null || true)}"
  [ -n "$CROSS_HOST_IP" ] \
    || { echo "[e2e-1-5] unable to derive CROSS_HOST_IP; pass CROSS_PLATFORM_RELAY" >&2; exit 1; }
  CROSS_PLATFORM_RELAY="ws://${CROSS_HOST_IP}:8194"
fi

latest_dir() {
  local glob="$1"
  local dirs=("$APPS"/library/evidence/$glob)
  [ -d "${dirs[0]}" ] || return 1
  ls -td "${dirs[@]}" | head -1
}

record() {
  local key="$1"
  local value="$2"
  printf '%s=%s\n' "$key" "$value" >> "$SUMMARY"
}

run_step() {
  local label="$1"
  shift
  local log="$EVIDENCE_ROOT/${label}.log"
  echo "[e2e-1-5 $(date +%H:%M:%S)] start: $label"
  (
    cd "$APPS"
    "$@"
  ) 2>&1 | tee "$log"
  echo "[e2e-1-5 $(date +%H:%M:%S)] pass: $label"
}

refresh_demo_packages() {
  local label="$1"
  local log="$EVIDENCE_ROOT/${label}.log"
  echo "[e2e-1-5 $(date +%H:%M:%S)] refresh demo packages: $label"
  (
    cd "$ROOT"
    TIMEOUT_SECS="${TIMEOUT_SECS:-180}" make demo-start
  ) 2>&1 | tee "$log"
}

require_preflight() {
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
    || { echo "[e2e-1-5] relay 127.0.0.1:8194 unreachable; run make demo-start" >&2; exit 1; }
  [ -f "$ROOT/.tmp/test-harness/onboard-bob.txt" ] \
    || { echo "[e2e-1-5] missing bob demo package; run make demo-onboard" >&2; exit 1; }
  [ -f "$ROOT/.tmp/test-harness/onboard-carol.txt" ] \
    || { echo "[e2e-1-5] missing carol demo package; run make demo-onboard" >&2; exit 1; }
  adb -s "${ANDROID_SERIAL:-emulator-5554}" get-state >/dev/null 2>&1 \
    || { echo "[e2e-1-5] Android emulator not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}" \
    || { echo "[e2e-1-5] iOS simulator not booted" >&2; exit 1; }
}

refresh_demo_packages "00-refresh-demo-preflight"
require_preflight

run_step "00-ios-build" just ios-build
run_step "00-android-assemble" just android-assemble

# 1. Export on each platform, then import/recover the opposite platform's
# artifacts. The load validators accept EXPORT_DIR specifically for this
# cross-platform artifact contract.
record "lane_1_cross_platform_relay" "$CROSS_PLATFORM_RELAY"
run_step "01-ios-export" env KEYSET_RELAY="$CROSS_PLATFORM_RELAY" just focus-ios-export
IOS_EXPORT="$(latest_dir 'mobile-export-artifact-validation-ios-*')"
record "lane_1_ios_export" "$IOS_EXPORT"

run_step "01-android-export" env KEYSET_RELAY="$CROSS_PLATFORM_RELAY" just focus-android-export
ANDROID_EXPORT="$(latest_dir 'mobile-export-artifact-validation-android-*')"
record "lane_1_android_export" "$ANDROID_EXPORT"

run_step "01-ios-load-android-export" env EXPORT_DIR="$ANDROID_EXPORT" just focus-ios-load-artifacts
IOS_LOAD_ANDROID_EXPORT="$(latest_dir 'mobile-load-profile-artifacts-ios-*')"
record "lane_1_ios_load_android_export" "$IOS_LOAD_ANDROID_EXPORT"

run_step "01-android-load-ios-export" env EXPORT_DIR="$IOS_EXPORT" just focus-android-load-artifacts
ANDROID_LOAD_IOS_EXPORT="$(latest_dir 'mobile-load-profile-artifacts-android-*')"
record "lane_1_android_load_ios_export" "$ANDROID_LOAD_IOS_EXPORT"

# 2. Rotate-share replacement on both shells.
refresh_demo_packages "02-refresh-demo-ios-rotate-share"
run_step "02-ios-rotate-share" just focus-ios-rotate-share
record "lane_2_ios_rotate_share" "$(latest_dir 'mobile-ios-rotate-share-*')"

refresh_demo_packages "02-refresh-demo-android-rotate-share"
run_step "02-android-rotate-share" just focus-android-rotate-share
record "lane_2_android_rotate_share" "$(latest_dir 'mobile-android-rotate-share-*')"

# 3. Bidirectional native onboarding plus live signer Test Sign/ECDH.
run_step "03-cross-platform-onboard-signer" just focus-cross-platform-onboard-signer
record "lane_3_cross_platform_onboard_signer" "$(latest_dir 'mobile-cross-platform-onboard-signer-*')"

# 4. Visible wrong-password failure followed by valid retry recovery.
run_step "04-cross-platform-failure-recovery" just focus-cross-platform-failure-recovery
record "lane_4_cross_platform_failure_recovery" "$(latest_dir 'mobile-cross-platform-failure-recovery-*')"

# 5. Durable cross-flow persistence on both shells.
refresh_demo_packages "05-refresh-demo-ios-cross-flow-persistence"
run_step "05-ios-cross-flow-persistence" just focus-cross-flow-ios
record "lane_5_ios_cross_flow_persistence" "$(latest_dir 'mobile-cross-flow-persistence-ios-*')"

refresh_demo_packages "05-refresh-demo-android-cross-flow-persistence"
run_step "05-android-cross-flow-persistence" just focus-cross-flow-android
record "lane_5_android_cross_flow_persistence" "$(latest_dir 'mobile-cross-flow-persistence-android-*')"

record "result" "pass"

echo "[e2e-1-5 RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
