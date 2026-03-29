#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=false
TMP_ROOT="${ROOT_DIR}/.tmp"
BUILD_ROOT="${ROOT_DIR}/build/igloo-shell-target"

if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
  FORCE=true
fi

if [ "$FORCE" = false ]; then
  echo "This will remove root scratch data under ./.tmp and build scratch under ./build/igloo-shell-target."
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Stopping demo compose services..."
docker compose -f "$ROOT_DIR/compose.test.yml" down || true

echo "Resetting root scratch directories..."
rm -rf "${TMP_ROOT:?}"/*
rm -rf "${BUILD_ROOT}"

echo "Reset complete."
