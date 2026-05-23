#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for workflow action checks" >&2
  exit 1
fi

if rg -n \
  -e 'actions/checkout@v[1-4]\b' \
  -e 'actions/setup-node@v[1-4]\b' \
  -e 'actions/upload-artifact@v[1-5]\b' \
  "${ROOT_DIR}/.github/workflows"; then
  echo "workflow uses a GitHub action major that does not satisfy the Node 24 hard cut" >&2
  exit 1
fi

echo "ok: workflow GitHub actions use Node 24-compatible majors"
