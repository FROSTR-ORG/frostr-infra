#!/usr/bin/env bash
# Cross-platform E2E hardening lanes 6-10.
#
# 6. Visual screenshot + accessibility/layout proof.
# 7. Upgrade/reinstall migration proof.
# 8. Release diagnostic-surface guard.
# 9. QR display + scan fallback proof.
# 10. Runtime error resilience on both shells.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-$APPS/library/evidence/mobile-cross-platform-e2e-6-10-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_ROOT"
SUMMARY="$EVIDENCE_ROOT/summary.txt"
: > "$SUMMARY"
RUNTIME_HARNESS_DIR="${RUNTIME_HARNESS_DIR:-$ROOT/.tmp/mobile-runtime-harness}"
RUNTIME_RELAY_START_PORT="${RUNTIME_RELAY_PORT:-8195}"

echo "[e2e-6-10 $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"

record() {
  printf '%s=%s\n' "$1" "$2" >> "$SUMMARY"
}

latest_dir() {
  local glob="$1"
  local dirs=("$APPS"/library/evidence/$glob)
  [ -d "${dirs[0]}" ] || return 1
  ls -td "${dirs[@]}" | head -1
}

run_step() {
  local label="$1"
  shift
  local log="$EVIDENCE_ROOT/${label}.log"
  echo "[e2e-6-10 $(date +%H:%M:%S)] start: $label"
  (
    cd "$APPS"
    "$@"
  ) 2>&1 | tee "$log"
  echo "[e2e-6-10 $(date +%H:%M:%S)] pass: $label"
}

ensure_relay_service() {
  local log="$EVIDENCE_ROOT/00-ensure-relay.log"
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" >/dev/null 2>&1; then
    echo "[e2e-6-10 $(date +%H:%M:%S)] reuse existing relay: 127.0.0.1:8194" | tee "$log"
    return
  fi
  (
    cd "$ROOT"
    TIMEOUT_SECS="${TIMEOUT_SECS:-180}" make demo-start
  ) 2>&1 | tee "$log"
}

require_preflight() {
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
    || { echo "[e2e-6-10] relay 127.0.0.1:8194 unreachable" >&2; exit 1; }
  adb -s "${ANDROID_SERIAL:-emulator-5554}" get-state >/dev/null 2>&1 \
    || { echo "[e2e-6-10] Android emulator not ready" >&2; exit 1; }
  xcrun simctl list devices booted | grep -q "${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}" \
    || { echo "[e2e-6-10] iOS simulator not booted" >&2; exit 1; }
}

pick_runtime_relay_port() {
  python3 - "$RUNTIME_RELAY_START_PORT" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, start + 100):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
    print(port)
    break
else:
    raise SystemExit(f"no free runtime relay port in {start}-{start + 99}")
PY
}

prepare_runtime_demo() {
  local port="$1"
  local log="$EVIDENCE_ROOT/10-runtime-demo-start.log"
  mkdir -p "$RUNTIME_HARNESS_DIR"
  echo "[e2e-6-10 $(date +%H:%M:%S)] start runtime demo: port=$port harness=$RUNTIME_HARNESS_DIR"
  (
    cd "$ROOT"
    FROSTR_TEST_HARNESS_DIR="$RUNTIME_HARNESS_DIR" \
      TIMEOUT_SECS="${TIMEOUT_SECS:-180}" \
      make demo-start PORT="$port"
  ) 2>&1 | tee "$log"
  echo "[e2e-6-10 $(date +%H:%M:%S)] pass: runtime demo"
}

ensure_relay_service
require_preflight

run_step "00-ios-build" just ios-build
run_step "00-android-assemble" just android-assemble

run_step "06-visual-a11y" just focus-cross-platform-visual-a11y
record "lane_6_visual_a11y" "$(latest_dir 'mobile-cross-platform-visual-a11y-*')"

run_step "07-upgrade-migration" just focus-cross-platform-upgrade-migration
record "lane_7_upgrade_migration" "$(latest_dir 'mobile-cross-platform-upgrade-migration-*')"

run_step "08-release-diagnostic-guard" just focus-cross-platform-release-diagnostic-guard
record "lane_8_release_diagnostic_guard" "$(latest_dir 'mobile-cross-platform-release-diagnostic-guard-*')"

run_step "09-qr-permission-fallback" just focus-cross-platform-qr-permission-fallback
record "lane_9_qr_permission_fallback" "$(latest_dir 'mobile-cross-platform-qr-permission-fallback-*')"

RUNTIME_RELAY_PORT="$(pick_runtime_relay_port)"
record "lane_10_runtime_relay" "ws://127.0.0.1:$RUNTIME_RELAY_PORT"
record "lane_10_runtime_harness" "$RUNTIME_HARNESS_DIR"
prepare_runtime_demo "$RUNTIME_RELAY_PORT"

run_step "10-runtime-profile-seed" env \
  DEV_RELAY_PORT="$RUNTIME_RELAY_PORT" \
  FROSTR_TEST_HARNESS_DIR="$RUNTIME_HARNESS_DIR" \
  bash scripts/seed-runtime-error-profiles.sh
record "lane_10_runtime_profile_seed" "$(latest_dir 'mobile-runtime-profile-seed-*')"

run_step "10-runtime-errors" env \
  DEV_RELAY_PORT="$RUNTIME_RELAY_PORT" \
  FROSTR_TEST_HARNESS_DIR="$RUNTIME_HARNESS_DIR" \
  bash scripts/run-cross-platform-runtime-errors-proof.sh
record "lane_10_runtime_errors" "$(latest_dir 'mobile-cross-platform-runtime-errors-*')"

record "result" "pass"

echo "[e2e-6-10 RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_ROOT"
cat "$SUMMARY"
