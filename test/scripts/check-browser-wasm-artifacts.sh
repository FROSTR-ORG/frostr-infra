#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

scope="${1:-all}"
case "${scope}" in
  all|pwa|igloo-pwa|chrome|igloo-chrome)
    "${ROOT_DIR}/scripts/prepare-browser-wasm.sh" check "${scope}"
    ;;
  *)
    echo "usage: test/scripts/check-browser-wasm-artifacts.sh [all|pwa|chrome]" >&2
    exit 1
    ;;
esac
