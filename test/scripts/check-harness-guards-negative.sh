#!/usr/bin/env bash
set -euo pipefail

# Adversarial meta-test: prove the new harness guards FAIL when they should, so a
# future change can't silently defang them (mirrors
# check-pwa-visual-manifest-negative.sh). The persist-contract guard's negative
# test is the compiled fixture test/shared/persist-contract.expect-error.ts; this
# script covers the browser-WASM stamp drift guard.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

stamp="test/browser-wasm-source.stamp"
guard="test/scripts/check-browser-wasm-stamp.sh"

[[ -f "${stamp}" ]] || { echo "not ok: ${stamp} is missing" >&2; exit 1; }

# Precondition: the committed stamp verifies clean.
if ! bash "${guard}" >/dev/null 2>&1; then
  echo "not ok: stamp guard fails on the committed stamp (precondition)" >&2
  exit 1
fi

original="$(cat "${stamp}")"
restore() { printf '%s\n' "${original}" > "${stamp}"; }
trap restore EXIT

# Corrupt the stamp and confirm the guard catches the drift.
printf 'tampered-stale-stamp\n' > "${stamp}"
if bash "${guard}" >/dev/null 2>&1; then
  echo "not ok: stamp guard PASSED on a corrupted stamp — the drift check is defanged" >&2
  exit 1
fi

restore
trap - EXIT

# Sanity: the restored stamp verifies clean again.
if ! bash "${guard}" >/dev/null 2>&1; then
  echo "not ok: stamp did not restore cleanly" >&2
  exit 1
fi

echo "ok: harness guards reject drift (browser-WASM stamp drift detected)"
