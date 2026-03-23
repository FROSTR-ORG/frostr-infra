#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${1:-}"
APP_ACTION="${2:-dev}"

status() {
  printf '\033[0;34m%s\033[0m\n' "$1"
}

success() {
  printf '\033[0;32m%s\033[0m\n' "$1"
}

warn() {
  printf '\033[1;33m%s\033[0m\n' "$1"
}

error() {
  printf '\033[0;31m%s\033[0m\n' "$1" >&2
}

case "$APP_NAME" in
  igloo-pwa|igloo-chrome)
    ;;
  *)
    error "usage: scripts/run-browser-app.sh <igloo-pwa|igloo-chrome> [dev|build|test:unit|test:e2e]"
    exit 1
    ;;
esac

APP_DIR="$ROOT_DIR/repos/$APP_NAME"
SHARED_DIR="$ROOT_DIR/repos/igloo-shared"
WASM_DIR="$SHARED_DIR/public/wasm"
WASM_STAMP="$WASM_DIR/bifrost_bridge_wasm_bg.wasm"
BIFROST_DIR="$ROOT_DIR/repos/bifrost-rs"

needs_bridge_rebuild() {
  if [[ ! -f "$WASM_STAMP" ]]; then
    return 0
  fi

  if find \
    "$BIFROST_DIR/crates/bifrost-bridge-wasm" \
    "$BIFROST_DIR/crates/frostr-utils" \
    "$BIFROST_DIR/Cargo.lock" \
    "$SHARED_DIR/scripts/build-bridge-wasm.sh" \
    -type f \
    -newer "$WASM_STAMP" \
    -print \
    -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  return 1
}

status "Preparing browser bridge artifacts for $APP_NAME"
if needs_bridge_rebuild; then
  warn "Detected newer bifrost-rs or missing artifacts; rebuilding bridge wasm in igloo-shared"
  (
    cd "$SHARED_DIR"
    npm run build:bridge-wasm
  )
else
  success "Shared bridge wasm artifacts are up to date"
fi

status "Syncing bridge wasm into $APP_NAME"
(
  cd "$APP_DIR"
  npm run build:bridge-wasm
)

status "Running npm script '$APP_ACTION' for $APP_NAME"
(
  cd "$APP_DIR"
  npm run "$APP_ACTION"
)
