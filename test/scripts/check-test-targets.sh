#!/usr/bin/env bash
set -euo pipefail

# Keeps test/shared/test-targets.json the single source of truth for client ->
# prebuild-target maps: the manifest must cover every client lane, the per-client
# global-setups must read it via targetsForClient, and test-affected.sh must read
# it via the lib-test-targets helper (no hardcoded prebuild lists).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

manifest="test/shared/test-targets.json"
status=0

if ! node -e '
  const fs = require("fs");
  const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const c of ["pwa", "chrome", "home"]) {
    const e = m.clients && m.clients[c];
    if (!e || !Array.isArray(e.prebuild) || e.prebuild.length === 0) {
      console.error("test-targets manifest missing/empty prebuild for client: " + c);
      process.exit(1);
    }
    if (!Array.isArray(e.paths) || e.paths.length === 0) {
      console.error("test-targets manifest missing/empty paths for client: " + c);
      process.exit(1);
    }
  }
' "${manifest}"; then
  status=1
fi

for client in pwa chrome home; do
  setup="test/igloo-${client}/global-setup.ts"
  if ! rg -q "targetsForClient\\('${client}'\\)" "${setup}"; then
    echo "error: ${setup} must call targetsForClient('${client}') (no hardcoded prebuild list)" >&2
    status=1
  fi
done

if ! rg -q "test_targets_for_client" scripts/test-affected.sh; then
  echo "error: scripts/test-affected.sh must derive prebuild targets via test_targets_for_client" >&2
  status=1
fi

if ! rg -q "test_client_for_path" scripts/test-affected.sh; then
  echo "error: scripts/test-affected.sh must derive the path -> client mapping via test_client_for_path (no hardcoded repos/igloo-{pwa,chrome,home} globs)" >&2
  status=1
fi

# Belt-and-suspenders: the per-client repo path must not be re-hardcoded as a case
# arm in test-affected.sh now that the manifest owns the mapping.
for client in pwa chrome home; do
  if rg -q "repos/igloo-${client}/\\*\\)" scripts/test-affected.sh; then
    echo "error: scripts/test-affected.sh hardcodes a repos/igloo-${client}/* case; use test_client_for_path instead" >&2
    status=1
  fi
done

if [[ "${status}" -eq 0 ]]; then
  echo "ok: test-target manifest is the single source of truth"
fi
exit "${status}"
