#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "${ROOT_DIR}/.tmp"
TMP_DIR="$(mktemp -d "${ROOT_DIR}/.tmp/pwa-visual-manifest-negative.XXXXXX")"
MANIFEST_PATH="${TMP_DIR}/visual-manifest.json"
OUTPUT_PATH="${TMP_DIR}/output.txt"

cleanup() {
  local status="$?"
  if [[ "${status}" -eq 0 ]]; then
    rm -rf "${TMP_DIR}"
  else
    echo "preserving failed PWA visual manifest negative scratch directory: ${TMP_DIR}" >&2
  fi
  exit "${status}"
}

trap cleanup EXIT

cat >"${MANIFEST_PATH}" <<'EOF'
{
  "suite": "igloo-pwa-paper-visuals",
  "screens": [
    {
      "name": "missing-paper-reference",
      "viewport": "1440x1080",
      "output": ".tmp/visual/igloo-pwa/missing-paper-reference.png",
      "paperReference": "repos/igloo-paper/screens/missing-fixture/screenshot.png",
      "status": "needs-work"
    }
  ]
}
EOF

set +e
FROSTR_PWA_VISUAL_MANIFEST_PATH="${MANIFEST_PATH}" \
  FROSTR_PWA_VISUAL_REQUIRE_PAPER=1 \
  node "${ROOT_DIR}/test/scripts/check-pwa-visual-manifest.mjs" >"${OUTPUT_PATH}" 2>&1
status="$?"
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected visual manifest checker to fail for a missing Paper reference" >&2
  cat "${OUTPUT_PATH}" >&2
  exit 1
fi

if ! grep -Fq "paperReference does not exist: repos/igloo-paper/screens/missing-fixture/screenshot.png" "${OUTPUT_PATH}"; then
  echo "expected missing Paper reference failure message" >&2
  cat "${OUTPUT_PATH}" >&2
  exit 1
fi

cat >"${MANIFEST_PATH}" <<'EOF'
{
  "suite": "igloo-pwa-paper-visuals",
  "screens": [
    {
      "name": "aligned-missing-capture",
      "viewport": "1440x1080",
      "output": ".tmp/visual/igloo-pwa/missing/aligned-missing-capture.png",
      "paperReference": "repos/igloo-paper/design/components/settings-sidebar/screenshot.png",
      "status": "aligned"
    }
  ]
}
EOF

set +e
FROSTR_PWA_VISUAL_MANIFEST_PATH="${MANIFEST_PATH}" \
  FROSTR_PWA_VISUAL_REQUIRE_ALIGNED_OUTPUTS=1 \
  node "${ROOT_DIR}/test/scripts/check-pwa-visual-manifest.mjs" >"${OUTPUT_PATH}" 2>&1
status="$?"
set -e

if [[ "${status}" -eq 0 ]]; then
  echo "expected visual manifest checker to fail for a missing aligned PWA capture" >&2
  cat "${OUTPUT_PATH}" >&2
  exit 1
fi

if ! grep -Fq "output does not exist for aligned screen aligned-missing-capture" "${OUTPUT_PATH}"; then
  echo "expected missing aligned PWA capture failure message" >&2
  cat "${OUTPUT_PATH}" >&2
  exit 1
fi

echo "ok: visual manifest checker rejects missing Paper references and missing aligned PWA captures"
