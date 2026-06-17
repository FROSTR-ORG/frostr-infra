#!/usr/bin/env bash
#
# Fast native dev loop: one relay + one igloo-shell co-signer + the igloo-pwa dev
# server, all native (no Docker). Provisioned from the committed dev keyset
# (dev/fixtures/) so it never keygens, onboards, or exports — bring-up is a few
# seconds. The PWA device lives in the browser's localStorage and persists across
# restarts; the co-signer is recreated cheaply each run from the fixed keyset, so
# the two always belong to the same 2-of-2 group and can co-sign.
#
# First run only: in the PWA choose "Import Existing Device", load
# dev/fixtures/dev-device.bfprofile, password "devpass". Then unlock + Start
# Signer to see the running dashboard (the co-signer shows up as a peer).
#
# Usage: make dev [PORT=<relay-port>]      (preferred)
#        scripts/dev.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8194}"
RELAY_URL="ws://127.0.0.1:${PORT}"
DEV_PASSPHRASE="devpass"
KS_DIR="${ROOT_DIR}/dev/fixtures/dev-keyset"
DEVTOOLS_BIN="${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
SHELL_BIN="${ROOT_DIR}/build/igloo-shell-target/debug/igloo-shell"

if [[ ! -d "${KS_DIR}" ]]; then
  echo "error: missing dev keyset at ${KS_DIR}. Run dev/fixtures/regen.sh first." >&2
  exit 1
fi

if [[ ! -x "${DEVTOOLS_BIN}" || ! -x "${SHELL_BIN}" ]]; then
  echo "==> Building native bifrost-devtools + igloo-shell (first run)" >&2
  bash "${ROOT_DIR}/scripts/test-prebuild.sh" sync shared >&2
fi

# Ephemeral co-signer home. XDG_RUNTIME_DIR (the daemon control socket) must be a
# short path to fit the unix-socket sun_path limit on macOS — keep WORK_DIR shallow.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/frostr-dev.XXXXXX")"
export XDG_CONFIG_HOME="${WORK_DIR}/c" XDG_DATA_HOME="${WORK_DIR}/d" XDG_STATE_HOME="${WORK_DIR}/s" XDG_RUNTIME_DIR="${WORK_DIR}"

RELAY_PID=""
PROFILE_ID=""
cleanup() {
  if [[ -n "${PROFILE_ID}" ]]; then
    "${SHELL_BIN}" daemon stop --profile "${PROFILE_ID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${RELAY_PID}" ]]; then
    kill "${RELAY_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "==> Starting dev relay at ${RELAY_URL}" >&2
"${DEVTOOLS_BIN}" relay --host 127.0.0.1 --port "${PORT}" >"${WORK_DIR}/relay.log" 2>&1 &
RELAY_PID="$!"

# Wait briefly for the relay to accept connections (no foreground sleep loop hangs).
for _ in $(seq 1 50); do
  if nc -z 127.0.0.1 "${PORT}" 2>/dev/null; then break; fi
  if ! kill -0 "${RELAY_PID}" 2>/dev/null; then
    echo "error: dev relay exited on startup:" >&2
    tail -5 "${WORK_DIR}/relay.log" >&2 || true
    exit 1
  fi
done

echo "==> Loading the co-signer from the dev keyset" >&2
PROFILE_ID="$("${SHELL_BIN}" import \
  --group "${KS_DIR}/group.json" \
  --share "${KS_DIR}/share-alice.json" \
  --relay "${RELAY_URL}" \
  --label "Dev Co-signer" \
  --passphrase "${DEV_PASSPHRASE}" \
  --json | python3 -c "import json,sys;print(json.load(sys.stdin)['import']['profile']['id'])")"
"${SHELL_BIN}" daemon start --profile "${PROFILE_ID}" --passphrase "${DEV_PASSPHRASE}" >/dev/null

cat >&2 <<EOF

────────────────────────────────────────────────────────────────────
 READY http://localhost:1430
 Dev relay + co-signer are up. Starting the igloo-pwa dev server
 (Ctrl-C stops everything).

 First run only: in the PWA, "Import Existing Device" ->
   file:     dev/fixtures/dev-device.bfprofile
   password: ${DEV_PASSPHRASE}
 Then Unlock + Start Signer. The browser keeps the device across
 restarts, so later runs are just relay + co-signer + vite.
────────────────────────────────────────────────────────────────────

EOF

# Foreground vite. RELAY=0 (we run our own relay above); the device profile
# already carries ${RELAY_URL}, so the PWA signer joins the same relay.
RELAY=0 FROSTR_NONINTERACTIVE=1 VITE_DEFAULT_RELAYS="${RELAY_URL}" "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"
