#!/usr/bin/env bash

set -euo pipefail

# The bifrost-devtools binary is compiled into the image (see services/demo/Dockerfile)
# and installed on PATH; no host bind-mount or source tree is required.
BIFROST_DEVTOOLS_BIN="${BIFROST_DEVTOOLS_BIN:-bifrost-devtools}"
DEV_RELAY_PORT="${DEV_RELAY_PORT:-8194}"
DEV_RELAY_BIND_HOST="${DEV_RELAY_BIND_HOST:-0.0.0.0}"

if ! command -v "${BIFROST_DEVTOOLS_BIN}" >/dev/null 2>&1; then
  echo "missing required binary: ${BIFROST_DEVTOOLS_BIN} (expected on PATH; rebuild the image)"
  exit 1
fi

echo "==> Starting dev relay on ws://${DEV_RELAY_BIND_HOST}:${DEV_RELAY_PORT}"
exec "${BIFROST_DEVTOOLS_BIN}" relay --host "${DEV_RELAY_BIND_HOST}" --port "${DEV_RELAY_PORT}"
