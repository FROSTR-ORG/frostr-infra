#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="/workspace"
BIFROST_RS_DIR="${ROOT_DIR}/repos/bifrost-rs"
DEV_RELAY_PORT="${DEV_RELAY_PORT:-8194}"
BIFROST_RELAY_HOST="${BIFROST_RELAY_HOST:-0.0.0.0}"
BIFROST_DEVTOOLS_BIN="${BIFROST_RS_DIR}/target/debug/bifrost-devtools"

if [ ! -f "${BIFROST_RS_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${BIFROST_RS_DIR} (missing Cargo.toml)"
  exit 1
fi

if [ ! -x "${BIFROST_DEVTOOLS_BIN}" ]; then
  echo "missing required binary: ${BIFROST_DEVTOOLS_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p bifrost-dev --bin bifrost-devtools"
  exit 1
fi

echo "==> Starting dev relay on ws://${BIFROST_RELAY_HOST}:${DEV_RELAY_PORT}"
exec "${BIFROST_DEVTOOLS_BIN}" relay --host "${BIFROST_RELAY_HOST}" --port "${DEV_RELAY_PORT}"
