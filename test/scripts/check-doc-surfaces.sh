#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if rg -n \
  -e 'docs/STRUCTURE\.md' \
  -e 'test/DEMO_STRATEGY\.md' \
  -e 'E2E-DEMO-STRATEGY' \
  README.md CONTRIBUTING.md RELEASE.md docs test \
  --glob '!test/scripts/check-doc-surfaces.sh'
then
  echo "retired parent doc paths are still referenced" >&2
  exit 1
fi

if rg -n \
  -e 'igloo-web' \
  -e 'igloo-shell-tui' \
  -e 'data/test-harness' \
  -e '/tmp/frostr-test-prebuild-' \
  -e 'setup-dev\.sh' \
  run.sh scripts .github test README.md CONTRIBUTING.md RELEASE.md docs \
  --glob '!test/scripts/check-doc-surfaces.sh'
then
  echo "retired parent surfaces are still referenced" >&2
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
