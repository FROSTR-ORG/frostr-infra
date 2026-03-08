#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=false

if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
  FORCE=true
fi

if [ "$FORCE" = false ]; then
  echo "This will remove data in ./data and dependency caches in service submodules."
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Stopping compose services..."
docker compose -f "$ROOT_DIR/compose.yml" down || true

echo "Resetting data directories..."
rm -rf "$ROOT_DIR/data/igloo-web"/*

echo "Removing app node_modules if present..."
for svc in igloo-web; do
  if [ -d "$ROOT_DIR/repos/$svc/node_modules" ]; then
    rm -rf "$ROOT_DIR/repos/$svc/node_modules"
    echo "  - removed repos/$svc/node_modules"
  fi
done

echo "Reset complete."
