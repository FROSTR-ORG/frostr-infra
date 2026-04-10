#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="${ROOT_DIR}/test/igloo-home/run-e2e.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

run_sourced() {
  local script="$1"
  shift
  bash -lc "${script}" 2>&1
}

DIRECT_OUTPUT="$(run_sourced "
  set -euo pipefail
  source '${RUNNER}'
  run_playwright() { printf 'direct:%s\n' \"\$*\"; }
  export DISPLAY=':99'
  unset WAYLAND_DISPLAY
  main --grep hidden-window
")"
assert_eq "${DIRECT_OUTPUT}" "direct:--grep hidden-window"

XVFB_OUTPUT="$(run_sourced "
  set -euo pipefail
  source '${RUNNER}'
  has_display() { return 1; }
  has_xvfb() { return 0; }
  run_playwright_with_xvfb() { printf 'xvfb:%s\n' \"\$*\"; }
  main --workers=1
")"
assert_eq "${XVFB_OUTPUT}" "xvfb:--workers=1"

set +e
NO_DISPLAY_OUTPUT="$(run_sourced "
  set -euo pipefail
  source '${RUNNER}'
  has_display() { return 1; }
  has_xvfb() { return 1; }
  main
")"
NO_DISPLAY_STATUS=$?
set -e
if [[ ${NO_DISPLAY_STATUS} -eq 0 ]]; then
  echo "expected igloo-home run-e2e wrapper to fail without display or xvfb" >&2
  exit 1
fi
assert_eq "${NO_DISPLAY_OUTPUT}" "igloo-home E2E requires DISPLAY or WAYLAND_DISPLAY, or xvfb-run installed for headless execution"

echo "ok: igloo-home E2E wrapper selects direct, xvfb, and failure paths correctly"
