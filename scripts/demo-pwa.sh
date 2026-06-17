#!/usr/bin/env bash
#
# Manual demo: the Docker demo stack (relay + demo co-signer) plus the igloo-pwa
# dev server, in one command. Brings the demo stack up in the background —
# printing the onboarding package, password, and relay URL — then runs the PWA
# dev server in the foreground. Stopping the dev server (Ctrl-C) also tears the
# demo stack down.
#
# Onboard a browser device from http://localhost:1430 -> "Onboard New Device" by
# pasting the printed package + password. The package already carries the demo
# relay URL, so the app needs no relay configuration of its own.
#
# Usage:  make demo-pwa [PORT=<relay-port>]      (preferred)
#         scripts/demo-pwa.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8194}"
HARNESS_DIR="${FROSTR_TEST_HARNESS_DIR:-${ROOT_DIR}/.tmp/test-harness}"

# This launcher onboards a single browser device, so generate just one onboard
# package. Each package is a relay-coordinated export (~12s in the signing core),
# so dropping the second member (the default is bob,carol) roughly halves the
# package-export time. Override by exporting IGLOO_SHELL_DEMO_INVITE_MEMBERS.
export IGLOO_SHELL_DEMO_INVITE_MEMBERS="${IGLOO_SHELL_DEMO_INVITE_MEMBERS:-bob}"

stopped=0
stop_demo() {
  [[ "${stopped}" == "1" ]] && return 0
  stopped=1
  printf '\n==> Stopping demo stack (relay + co-signer)\n' >&2
  "${ROOT_DIR}/scripts/demo.sh" stop || true
}
trap stop_demo EXIT INT TERM

# 1. Start from a clean demo scratch. The demo signer reuses an existing keyset
#    under .tmp/test-harness if present (generate_demo_material_if_needed); a
#    stale one from a prior run can destabilize the signer, and its
#    restart-on-failure wipes a freshly-written onboard package mid-read — which
#    surfaces on the host as `cat: onboard-<member>.txt: No such file`. Reset the
#    scratch so every launch regenerates a fresh, consistent keyset + packages.
"${ROOT_DIR}/scripts/demo.sh" stop >/dev/null 2>&1 || true
if [[ -d "${HARNESS_DIR}" ]]; then
  printf '==> Clearing demo scratch for a fresh keyset (%s)\n' "${HARNESS_DIR}" >&2
  rm -rf "${HARNESS_DIR:?}/"* 2>/dev/null || true
fi

# 2. Relay + demo co-signer, backgrounded. Blocks until the onboarding artifacts
#    are written, then prints the package/password/relay URL and returns.
BG=1 "${ROOT_DIR}/scripts/demo.sh" start "${PORT}"

printf '\n────────────────────────────────────────────────────────────────────\n' >&2
printf '==> Demo stack is up. Starting the igloo-pwa dev server (Ctrl-C stops both).\n' >&2
printf '==> Open http://localhost:1430 -> "Onboard New Device" and paste the\n' >&2
printf '    onboarding package + password printed above.\n' >&2
printf '────────────────────────────────────────────────────────────────────\n\n' >&2

# 3. PWA dev server in the foreground. RELAY=0: the onboarding package already
#    carries the demo relay URL, so the app does not start a relay of its own.
RELAY=0 "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"
