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

stopped=0
stop_demo() {
  [[ "${stopped}" == "1" ]] && return 0
  stopped=1
  printf '\n==> Stopping demo stack (relay + co-signer)\n' >&2
  "${ROOT_DIR}/scripts/demo.sh" stop || true
}
trap stop_demo EXIT INT TERM

# 1. Relay + demo co-signer, backgrounded. Blocks until the onboarding artifacts
#    are written, then prints the package/password/relay URL and returns.
BG=1 "${ROOT_DIR}/scripts/demo.sh" start "${PORT}"

printf '\n────────────────────────────────────────────────────────────────────\n' >&2
printf '==> Demo stack is up. Starting the igloo-pwa dev server (Ctrl-C stops both).\n' >&2
printf '==> Open http://localhost:1430 -> "Onboard New Device" and paste the\n' >&2
printf '    onboarding package + password printed above.\n' >&2
printf '────────────────────────────────────────────────────────────────────\n\n' >&2

# 2. PWA dev server in the foreground. RELAY=0: the onboarding package already
#    carries the demo relay URL, so the app does not start a relay of its own.
RELAY=0 "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"
