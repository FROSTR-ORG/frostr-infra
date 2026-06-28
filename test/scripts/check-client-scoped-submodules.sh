#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/client-scoped-validation.yml"

require_line() {
  local expected="$1"
  if ! grep -F --quiet -- "${expected}" "${WORKFLOW}"; then
    echo "client-scoped workflow is missing expected submodule line:" >&2
    echo "${expected}" >&2
    exit 1
  fi
}

require_line "git submodule update --init repos/bifrost-rs repos/igloo-shared repos/igloo-ui repos/igloo-pwa"
require_line "git submodule update --init repos/bifrost-rs repos/igloo-shared repos/igloo-ui repos/igloo-chrome repos/igloo-shell"
require_line "git submodule update --init repos/igloo-shared repos/igloo-ui repos/igloo-home"

echo "ok: client-scoped workflow initializes only lane dependencies"
