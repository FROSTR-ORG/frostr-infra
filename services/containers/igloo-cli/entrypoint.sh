#!/usr/bin/env bash

set -euo pipefail

cd /app

if [ ! -f package.json ]; then
  echo "igloo-cli source is not available at /app (missing package.json)"
  exit 1
fi

MODE="${IGLOO_CLI_MODE:-dev}"
LOCK_HASH_FILE="node_modules/.deps.sha256"

install_deps_if_needed() {
  local current_hash
  local cached_hash=""

  if [ -f package-lock.json ]; then
    current_hash="$(sha256sum package-lock.json | awk '{print $1}')"
  else
    current_hash="$(sha256sum package.json | awk '{print $1}')"
  fi

  if [ ! -d node_modules ] || [ ! -x node_modules/.bin/tsx ]; then
    if [ -f package-lock.json ]; then
      npm ci
    else
      npm install
    fi
    mkdir -p node_modules
    printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
    return
  fi

  if [ -f "$LOCK_HASH_FILE" ]; then
    cached_hash="$(cat "$LOCK_HASH_FILE")"
    if [ "$current_hash" != "$cached_hash" ]; then
      if [ -f package-lock.json ]; then
        npm ci
      else
        npm install
      fi
    fi
  fi

  mkdir -p node_modules
  printf '%s\n' "$current_hash" > "$LOCK_HASH_FILE"
}

if [ "$MODE" = "dev" ]; then
  install_deps_if_needed
  exec tail -f /dev/null
fi

if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi

npm run build
exec npm run start
