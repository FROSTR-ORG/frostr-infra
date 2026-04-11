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
status "Preparing browser wasm artifacts for $APP_NAME"
"$ROOT_DIR/scripts/prepare-browser-wasm.sh" sync "$APP_NAME"
success "Browser wasm artifacts are ready for $APP_NAME"

status "Running npm script '$APP_ACTION' for $APP_NAME"
(
  cd "$APP_DIR"
  npm run "$APP_ACTION"
)
