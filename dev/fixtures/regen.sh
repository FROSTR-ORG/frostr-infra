#!/usr/bin/env bash
#
# Regenerate the committed dev fixtures used by `make dev` (the fast native dev
# loop). ALPHA / THROWAWAY: these are devnet keys for a local relay, committed on
# purpose so the dev loop never has to keygen or onboard. Never reuse them for
# anything real.
#
# Produces, under dev/fixtures/:
#   dev-keyset/            a fixed 2-of-2 keyset (alice = co-signer, bob = PWA device)
#   dev-device.bfprofile   bob exported as an importable device backup (password below)
#   dev-device.bfshare     bob's encrypted share artifact (for the future auto-seed)
#
# Usage: dev/fixtures/regen.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES_DIR="${ROOT_DIR}/dev/fixtures"

# The single dev relay every fixture is wired to. Keep in sync with scripts/dev.sh.
DEV_RELAY_URL="ws://127.0.0.1:8194"
# The dev passphrase for the device profile / share package. Intentionally trivial.
DEV_PASSPHRASE="devpass"

DEVTOOLS_BIN="${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
SHELL_BIN="${ROOT_DIR}/build/igloo-shell-target/debug/igloo-shell"

if [[ ! -x "${DEVTOOLS_BIN}" || ! -x "${SHELL_BIN}" ]]; then
  echo "==> Building native bifrost-devtools + igloo-shell" >&2
  bash "${ROOT_DIR}/scripts/test-prebuild.sh" sync shared >&2
fi

KS_DIR="${FIXTURES_DIR}/dev-keyset"
rm -rf "${KS_DIR}"
mkdir -p "${KS_DIR}"

echo "==> Generating the fixed 2-of-2 dev keyset (alice = co-signer, bob = device)"
"${DEVTOOLS_BIN}" keygen \
  --out-dir "${KS_DIR}" \
  --threshold 2 \
  --count 2 \
  --relay "${DEV_RELAY_URL}" >/dev/null

# Export bob (the device share) as a bfprofile + bfshare, using a throwaway
# igloo-shell home so nothing touches the dev signer state.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dev-fixture-regen.XXXXXX")"
export XDG_CONFIG_HOME="${WORK}/c" XDG_DATA_HOME="${WORK}/d" XDG_STATE_HOME="${WORK}/s" XDG_RUNTIME_DIR="${WORK}"
trap 'rm -rf "${WORK}"' EXIT

echo "==> Exporting bob as an importable device backup"
PID="$("${SHELL_BIN}" import \
  --group "${KS_DIR}/group.json" \
  --share "${KS_DIR}/share-bob.json" \
  --relay "${DEV_RELAY_URL}" \
  --label "Dev Device" \
  --passphrase "${DEV_PASSPHRASE}" \
  --json | python3 -c "import json,sys;print(json.load(sys.stdin)['import']['profile']['id'])")"

export IGLOO_SHELL_PROFILE_PASSPHRASE="${DEV_PASSPHRASE}"
export IGLOO_SHELL_PACKAGE_PASSWORD="${DEV_PASSPHRASE}"
for fmt in bfprofile bfshare; do
  "${SHELL_BIN}" export "${PID}" \
    --out "${FIXTURES_DIR}/dev-device.${fmt}" \
    --format "${fmt}" \
    --passphrase-env IGLOO_SHELL_PROFILE_PASSPHRASE \
    --package-password-env IGLOO_SHELL_PACKAGE_PASSWORD >/dev/null
done

echo "==> Done. Fixtures under ${FIXTURES_DIR} (relay ${DEV_RELAY_URL}, password ${DEV_PASSPHRASE})"
