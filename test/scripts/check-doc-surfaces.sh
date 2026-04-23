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

echo "ok: no retired doc paths or cross-repo manual links found"
