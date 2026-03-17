#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="/workspace"
DEVTOOLS_DIR="${ROOT_DIR}/repos/bifrost-rs"
DEV_RELAY_PORT="${DEV_RELAY_PORT:-8194}"
DEV_RELAY_BIND_HOST="${DEV_RELAY_BIND_HOST:-0.0.0.0}"
BIFROST_DEVTOOLS_BIN="${DEVTOOLS_DIR}/target/debug/bifrost-devtools"

if [ ! -f "${DEVTOOLS_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${DEVTOOLS_DIR} (missing Cargo.toml)"
  exit 1
fi

if [ ! -x "${BIFROST_DEVTOOLS_BIN}" ]; then
  echo "missing required binary: ${BIFROST_DEVTOOLS_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p bifrost-devtools --bin bifrost-devtools"
  exit 1
fi

echo "==> Starting dev relay on ws://${DEV_RELAY_BIND_HOST}:${DEV_RELAY_PORT}"
exec "${BIFROST_DEVTOOLS_BIN}" relay --host "${DEV_RELAY_BIND_HOST}" --port "${DEV_RELAY_PORT}"
