#!/usr/bin/env bash

set -euo pipefail

cd /app

if [ ! -f package.json ]; then
  echo "igloo-web source is not available at /app (missing package.json)"
  exit 1
fi

MODE="${IGLOO_WEB_MODE:-dev}"
LOCK_HASH_FILE="node_modules/.package-lock.sha256"

install_deps_if_needed() {
  if [ -f package-lock.json ]; then
    local current_hash
    local cached_hash=""
    current_hash="$(sha256sum package-lock.json | awk '{print $1}')"

    if [ ! -d node_modules ] || [ ! -x node_modules/.bin/vite ]; then
      npm ci
      mkdir -p node_modules
      printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
      return
    fi

    if [ -f "$LOCK_HASH_FILE" ]; then
      cached_hash="$(cat "$LOCK_HASH_FILE")"
      if [ "$current_hash" != "$cached_hash" ]; then
        npm ci
      fi
    fi

    mkdir -p node_modules
    printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
  else
    if [ ! -d node_modules ]; then
      npm install
    fi
  fi
}

if [ "$MODE" = "dev" ]; then
  install_deps_if_needed
  exec npm run dev -- --host 0.0.0.0 --port "${IGLOO_WEB_INTERNAL_PORT:-5173}"
fi

if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi

npm run build
exec npm run preview -- --host 0.0.0.0 --port "${IGLOO_WEB_INTERNAL_PORT:-5173}"
