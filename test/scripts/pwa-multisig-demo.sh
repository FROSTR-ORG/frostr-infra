#!/usr/bin/env bash
#
# Manual demo: multiple igloo-pwa tabs coordinating a real threshold signature.
#
# The igloo-pwa runtime is responder-only (no in-app "sign this" surface), so a
# headless igloo-shell co-signer holds one share and INITIATES the signature;
# two browser tabs each hold a share and contribute their partials. With a 3-of-3
# keyset every participant is required, so a completed signature proves both tabs
# coordinated. This script does the non-browser scaffolding (relay, keyset, the
# igloo-shell initiator, the onboarding packages) and drives the sign on demand;
# you drive the two browser tabs.
#
# Usage:  make pwa-multisig-demo            (preferred)
#         test/scripts/pwa-multisig-demo.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEVTOOLS_BIN="${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
SHELL_BIN="${ROOT_DIR}/build/igloo-shell-target/debug/igloo-shell"

RELAY_PORT="${RELAY_PORT:-7848}"
RELAY_URL="ws://127.0.0.1:${RELAY_PORT}"
LOCAL_PASSPHRASE="multisig-demo-passphrase"
ONBOARD_PASSWORD="multisig-demo-onboard"
SIGN_MESSAGE="$(printf 'cd%.0s' {1..32})" # 32-byte message (64 hex chars)

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pwa-multisig-demo.XXXXXX")"
export XDG_CONFIG_HOME="${WORK_DIR}/xdg/config"
export XDG_DATA_HOME="${WORK_DIR}/xdg/data"
export XDG_STATE_HOME="${WORK_DIR}/xdg/state"
# Keep the daemon socket path short (macOS sun_path 104-byte limit).
export XDG_RUNTIME_DIR="${WORK_DIR}"
export CARGO_TARGET_DIR="${ROOT_DIR}/build/igloo-shell-target"

RELAY_PID=""
SHELL_PROFILE_ID=""

cleanup() {
  if [[ -n "${SHELL_PROFILE_ID}" ]]; then
    "${SHELL_BIN}" daemon stop --profile "${SHELL_PROFILE_ID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${RELAY_PID}" ]]; then
    kill "${RELAY_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building bifrost-devtools + igloo-shell (shared prebuild target)"
bash "${ROOT_DIR}/scripts/test-prebuild.sh" sync shared >/dev/null

echo "==> Starting local relay on ${RELAY_URL}"
"${DEVTOOLS_BIN}" relay --host 127.0.0.1 --port "${RELAY_PORT}" >"${WORK_DIR}/relay.log" 2>&1 &
RELAY_PID="$!"
sleep 1

echo "==> Generating a 3-of-3 keyset"
"${DEVTOOLS_BIN}" keygen --out-dir "${WORK_DIR}/keyset" --threshold 3 --count 3 --relay "${RELAY_URL}" >/dev/null

echo "==> Importing the coordinator share into igloo-shell"
"${SHELL_BIN}" relays set local "${RELAY_URL}" >/dev/null
IMPORT_JSON="$(
  "${SHELL_BIN}" import \
    --group "${WORK_DIR}/keyset/group.json" \
    --share "${WORK_DIR}/keyset/share-carol.json" \
    --label "Multisig Demo Coordinator" \
    --passphrase "${LOCAL_PASSPHRASE}" \
    --relay-profile local \
    --json
)"
SHELL_PROFILE_ID="$(printf '%s' "${IMPORT_JSON}" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
if [[ -z "${SHELL_PROFILE_ID}" ]]; then
  echo "error: could not read the imported profile id from igloo-shell import output" >&2
  echo "${IMPORT_JSON}" >&2
  exit 1
fi

echo "==> Exporting onboarding packages for the two browser tabs"
for member in alice:tab-1 bob:tab-2; do
  share="${member%%:*}"
  label="${member##*:}"
  IGLOO_SHELL_DEMO_PASSPHRASE="${LOCAL_PASSPHRASE}" LIVE_ONBOARD_PASSWORD="${ONBOARD_PASSWORD}" \
    "${SHELL_BIN}" export "${SHELL_PROFILE_ID}" \
      --format bfonboard \
      --out "${WORK_DIR}/${label}.bfonboard" \
      --recipient-share "${WORK_DIR}/keyset/share-${share}.json" \
      --passphrase-env IGLOO_SHELL_DEMO_PASSPHRASE \
      --package-password-env LIVE_ONBOARD_PASSWORD >/dev/null
done

echo "==> Starting the igloo-shell coordinator daemon"
"${SHELL_BIN}" daemon start --profile "${SHELL_PROFILE_ID}" --passphrase "${LOCAL_PASSPHRASE}" >/dev/null

cat <<INSTRUCTIONS

────────────────────────────────────────────────────────────────────────────
 igloo-pwa multi-tab signing demo is ready.

 1. In another terminal, start the PWA dev server:
        make igloo-pwa-dev

 2. Open TWO browser tabs at the dev server URL. In EACH tab choose
    "Onboard New Device", paste the matching package below, and use the
    onboarding password:  ${ONBOARD_PASSWORD}
    Give each a profile password of your choice and launch the signer.

    ── Tab 1 onboarding package (${WORK_DIR}/tab-1.bfonboard):
$(cat "${WORK_DIR}/tab-1.bfonboard")

    ── Tab 2 onboarding package (${WORK_DIR}/tab-2.bfonboard):
$(cat "${WORK_DIR}/tab-2.bfonboard")

 3. Wait until BOTH tab dashboards show the signer running and peers connected.

 4. Press ENTER here to initiate a 3-of-3 signature from the coordinator. Watch
    both tabs' event logs show the sign request + their partial responses.
────────────────────────────────────────────────────────────────────────────

INSTRUCTIONS

read -r -p "Press ENTER to initiate the signature... " _

echo "==> Initiating signature over message ${SIGN_MESSAGE}"
"${SHELL_BIN}" runtime sign --profile "${SHELL_PROFILE_ID}" "${SIGN_MESSAGE}"

echo
echo "==> If a signatures_hex array printed above, all three signers (both tabs +"
echo "    the coordinator) coordinated a valid threshold signature. Done."
