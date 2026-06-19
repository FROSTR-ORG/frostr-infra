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
SHELL_BIN="${ROOT_DIR}/build/igloo-shell-target/release/igloo-shell"
PWA_URL="http://localhost:1430"
AGENT_DIR="${ROOT_DIR}/.tmp/agent"
DEV_STATUS="${AGENT_DIR}/dev.json"

if [[ ! -d "${KS_DIR}" ]]; then
  echo "error: missing dev keyset at ${KS_DIR}. Run dev/fixtures/regen.sh first." >&2
  exit 1
fi

# Build the native binaries directly. cargo's own freshness check is the
# change-detector: a near-instant no-op when nothing changed, an incremental
# rebuild when sources change. The relay does no KDF, so it stays debug; the
# co-signer runs the Argon2id KDF on import + daemon start, so it must be a
# release build or bring-up is ~10x slower.
echo "==> Ensuring native relay (debug) + co-signer (release) are current" >&2
cargo build --manifest-path "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml" \
  --offline --locked -p bifrost-devtools --bin bifrost-devtools >&2
env CARGO_TARGET_DIR="${ROOT_DIR}/build/igloo-shell-target" \
  cargo build --release --manifest-path "${ROOT_DIR}/repos/igloo-shell/Cargo.toml" \
  --offline -p igloo-shell-cli --bin igloo-shell >&2

# Ephemeral co-signer home. The daemon binds its control socket at
# $XDG_RUNTIME_DIR/igloo-shell-<hash>.sock (~30 chars), which must fit the unix
# `sun_path` limit (104 on macOS). Use TMPDIR (a user-owned dir — /var/folders on
# macOS, not world-writable /tmp) with a short prefix, then fail loud if the path
# budget is too tight rather than letting the daemon die with a cryptic bind error.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fd.XXXXXX")"
SOCK_BUDGET=$(( ${#WORK_DIR} + 30 ))
if [[ "${SOCK_BUDGET}" -gt 104 ]]; then
  echo "error: TMPDIR is too deep for the daemon control socket (would be ~${SOCK_BUDGET}/104 bytes)." >&2
  echo "       Set a shorter TMPDIR, e.g.  TMPDIR=/tmp make dev" >&2
  exit 1
fi
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
  # Drop the readiness marker so a polling agent never sees a stale "ready".
  rm -f "${DEV_STATUS}" >/dev/null 2>&1 || true
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

# Machine-readable readiness marker for agents that background `make dev` and
# poll instead of scraping logs. Written once the relay + co-signer are up, just
# before the foreground vite hands off; removed on teardown by cleanup().
mkdir -p "${AGENT_DIR}"
printf '{"ready":true,"pwaUrl":"%s","relayUrl":"%s"}\n' "${PWA_URL}" "${RELAY_URL}" >"${DEV_STATUS}"

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
