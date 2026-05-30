#!/usr/bin/env bash
set -euo pipefail

# igloo-ui does not depend on igloo-shared, so it carries byte-identical COPIES
# of the shared vitest base + jsdom localStorage shim. This guard fails if the
# copies drift from the canonical igloo-shared source.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

# canonical source : copy
pairs=(
  "repos/igloo-shared/src/testing/setup-dom.ts:repos/igloo-ui/src/test/setup-dom.ts"
  "repos/igloo-shared/src/testing/vitest-base.ts:repos/igloo-ui/src/test/vitest-base.ts"
)

status=0
for pair in "${pairs[@]}"; do
  src="${pair%%:*}"
  copy="${pair##*:}"
  if [[ ! -f "${src}" ]]; then
    echo "error: missing canonical shared test file: ${src}" >&2
    status=1
    continue
  fi
  if [[ ! -f "${copy}" ]]; then
    echo "error: missing igloo-ui copy: ${copy}" >&2
    status=1
    continue
  fi
  if ! diff -u "${src}" "${copy}" >/dev/null; then
    echo "error: ${copy} has drifted from ${src}" >&2
    echo "       run: cp ${src} ${copy}" >&2
    diff -u "${src}" "${copy}" >&2 || true
    status=1
  fi
done

if [[ "${status}" -eq 0 ]]; then
  echo "ok: igloo-ui shared test-setup copies match igloo-shared source"
fi
exit "${status}"
