#!/usr/bin/env bash

set -euo pipefail

cd /app

if [ ! -f package.json ]; then
  echo "igloo-server source is not available at /app (missing package.json)"
  exit 1
fi

MODE="${IGLOO_SERVER_MODE:-dev}"
LOCK_HASH_FILE="node_modules/.deps.sha256"

install_deps_if_needed() {
  local current_hash
  local cached_hash=""

  if [ -f bun.lock ]; then
    current_hash="$(sha256sum bun.lock | awk '{print $1}')"
  else
    current_hash="$(sha256sum package.json | awk '{print $1}')"
  fi

  if [ ! -d node_modules ] || [ ! -x node_modules/.bin/esbuild ]; then
    bun install
    mkdir -p node_modules
    printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
    return
  fi

  if [ -f "$LOCK_HASH_FILE" ]; then
    cached_hash="$(cat "$LOCK_HASH_FILE")"
    if [ "$current_hash" != "$cached_hash" ]; then
      bun install
    fi
  fi

  mkdir -p node_modules
  printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
}

if [ "$MODE" = "dev" ]; then
  install_deps_if_needed
  bun run build
  exec bun run start
fi

bun install --frozen-lockfile
bun run build
exec bun run start
