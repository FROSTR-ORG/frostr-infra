#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIFROST_DIR="${ROOT_DIR}/repos/bifrost-rs"
IGLOO_SHELL_DIR="${ROOT_DIR}/repos/igloo-shell"

if [ ! -f "${BIFROST_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${BIFROST_DIR} (missing Cargo.toml)" >&2
  exit 1
fi

if [ ! -f "${IGLOO_SHELL_DIR}/Cargo.toml" ]; then
  echo "igloo-shell source is not available at ${IGLOO_SHELL_DIR} (missing Cargo.toml)" >&2
  exit 1
fi

echo "==> Building demo harness binaries on host"
(
  cd "${BIFROST_DIR}"
  cargo build --locked -p bifrost-devtools --bin bifrost-devtools
)
(
  cd "${IGLOO_SHELL_DIR}"
  cargo build --locked -p igloo-shell-cli --bin igloo-shell
)
