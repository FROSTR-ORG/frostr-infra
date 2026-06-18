# shellcheck shell=bash
# Helper for reading test/shared/test-targets.json (the client -> prebuild-target
# manifest) from bash. Source this, then call test_targets_for_client. Requires
# node (already a workspace dependency). Single source of truth shared with
# test/shared/test-prebuild.ts (targetsForClient).

_lib_test_targets_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TARGETS_MANIFEST="${TEST_TARGETS_MANIFEST:-${_lib_test_targets_root}/test/shared/test-targets.json}"

# Echo the space-separated prebuild targets for a client (pwa|chrome|home).
test_targets_for_client() {
  local client="$1"
  node -e '
    const fs = require("fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const entry = manifest.clients[process.argv[2]];
    if (!entry) { console.error("unknown test-targets client: " + process.argv[2]); process.exit(3); }
    process.stdout.write(entry.prebuild.join(" "));
  ' "${TEST_TARGETS_MANIFEST}" "${client}"
}

# Echo the client (pwa|chrome|home) that owns a changed path, or nothing if the
# path is outside every client's `paths` prefix. The manifest's `paths` are the
# single source of truth for the path -> client mapping (no hardcoded repo globs
# in test-affected.sh).
test_client_for_path() {
  local path="$1"
  node -e '
    const fs = require("fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const path = process.argv[2];
    let found = "";
    outer: for (const [client, entry] of Object.entries(manifest.clients || {})) {
      for (const prefix of entry.paths || []) {
        if (path === prefix || path.startsWith(prefix)) { found = client; break outer; }
      }
    }
    process.stdout.write(found);
  ' "${TEST_TARGETS_MANIFEST}" "${path}"
}
