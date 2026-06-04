#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for doc surface checks" >&2
  exit 1
fi

if rg -n \
  -e 'docs/STRUCTURE\.md' \
  -e 'test/DEMO_STRATEGY\.md' \
  -e 'E2E-DEMO-STRATEGY' \
  -e '\(\./RELEASE\.md\)' \
  -e '\(\.\./RELEASE\.md\)' \
  -e 'design/adrs/' \
  -e 'design/policies/' \
  README.md CONTRIBUTING.md docs dev test \
  --glob '!test/scripts/check-doc-surfaces.sh'
then
  echo "retired parent doc paths are still referenced" >&2
  exit 1
fi

if rg -n \
  -e 'igloo-web' \
  -e 'igloo-server' \
  -e 'igloo-cli' \
  -e 'igloo-shell-tui' \
  -e 'IGLOO_SERVER_' \
  -e 'IGLOO_WEB_' \
  -e 'IGLOO_CLI_' \
  -e 'VITE_IGLOO_SERVER_URL' \
  -e 'data/test-harness' \
  -e '/tmp/frostr-test-prebuild-' \
  -e 'setup-dev\.sh' \
  .env.example Makefile scripts .github test README.md CONTRIBUTING.md docs dev \
  --glob '!test/scripts/check-doc-surfaces.sh' \
  --glob '!dev/done/**' \
  --glob '!dev/reports/**' \
  --glob '!dev/audit/**' \
  --glob '!dev/plans/**'
then
  echo "retired parent surfaces are still referenced" >&2
  exit 1
fi

# Reject any tracked path under data/. The data/ directory was retired;
# scratch artifacts belong under .tmp/ per the workspace scratch-discipline
# policy. Untracked data/ directories on disk are fine — this only guards
# the index.
tracked_data_paths="$(git ls-files data/ 2>/dev/null || true)"
if [ -n "${tracked_data_paths}" ]; then
  echo "tracked data/ paths are not permitted (see CONTRIBUTING.md scratch policy):" >&2
  echo "${tracked_data_paths}" >&2
  exit 1
fi

# Reject any re-introduction of data/* carve-outs in .gitignore. If a
# data/ ignore rule shows up again, the data/ tree is about to be
# tracked via .gitkeep-style fossils.
if rg -n '^!?data/' .gitignore
then
  echo ".gitignore must not re-introduce data/ carve-outs" >&2
  exit 1
fi

if rg -n \
  -e '\.\./docs/' \
  -e '\.\./\.\./docs/' \
  -e 'repos/[^/]+/' \
  repos/*/README.md repos/*/TESTING.md repos/*/CONTRIBUTING.md repos/*/RELEASE.md
then
  echo "submodule manuals still contain cross-repo file references" >&2
  exit 1
fi

# --- Doc-vs-code constant drift fence (R3 Bucket J.1) ---
# Each pair asserts that the code defines a constant at the documented value AND
# that the spec doc quotes that value. If the constant changes in code, the
# code-side assertion fails until the value and its doc are updated together; if
# a doc drops the value, the doc-side assertion fails. This keeps the shared
# specs honest against bifrost-rs instead of silently drifting.
assert_doc_matches_code() {
  # $1 label  $2 code_file  $3 code_pattern  $4 doc_file  $5 doc_pattern
  local label="$1" code_file="$2" code_pattern="$3" doc_file="$4" doc_pattern="$5"
  if ! rg -nq -e "${code_pattern}" "${code_file}"; then
    echo "doc-surface: code constant for '${label}' not found at the documented value in ${code_file}" >&2
    echo "  (expected pattern: ${code_pattern}) — update the constant AND its doc together" >&2
    exit 1
  fi
  if ! rg -nq -e "${doc_pattern}" "${doc_file}"; then
    echo "doc-surface: ${doc_file} must document '${label}' (expected pattern: ${doc_pattern})" >&2
    exit 1
  fi
}

CODEC_BRIDGE="repos/bifrost-rs/crates/bifrost-codec/src/bridge.rs"
ARGON_PROFILE="repos/bifrost-rs/crates/bifrost-profile/src/argon2_params.rs"
ARGON_UTILS="repos/bifrost-rs/crates/frostr-utils/src/argon2_params.rs"
PKG="repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs"

assert_doc_matches_code "MAX_BRIDGE_ENVELOPE_BYTES" \
  "${CODEC_BRIDGE}" 'MAX_BRIDGE_ENVELOPE_BYTES: usize = 65_536' \
  docs/WIRE.md 'MAX_BRIDGE_ENVELOPE_BYTES = 65536'
assert_doc_matches_code "MAX_IDENTIFIER_FIELD_BYTES" \
  "${CODEC_BRIDGE}" 'MAX_IDENTIFIER_FIELD_BYTES: usize = 1024' \
  docs/WIRE.md 'MAX_IDENTIFIER_FIELD_BYTES = 1024'
assert_doc_matches_code "MAX_CONTENT_FIELD_BYTES" \
  "${CODEC_BRIDGE}" 'MAX_CONTENT_FIELD_BYTES: usize = 32 \* 1024' \
  docs/WIRE.md 'MAX_CONTENT_FIELD_BYTES = 32768'
assert_doc_matches_code "Argon2id default m_cost (bifrost-profile)" \
  "${ARGON_PROFILE}" '262_144' \
  docs/CRYPTOGRAPHY.md '262144'
assert_doc_matches_code "Argon2id KDF (frostr-utils)" \
  "${ARGON_UTILS}" '262_144' \
  docs/CRYPTOGRAPHY.md 'Argon2id'
assert_doc_matches_code "BF_PACKAGE_VERSION" \
  "${PKG}" 'BF_PACKAGE_VERSION: u8 = 2' \
  docs/BACKUP.md 'BF_PACKAGE_VERSION = 2'
assert_doc_matches_code "bfshare HRP" \
  "${PKG}" 'PREFIX_BFSHARE: &str = "bfshare"' \
  docs/BACKUP.md 'bfshare'

echo "ok: doc-vs-code constant fences match"

echo "ok: no retired doc paths or cross-repo manual links found"
