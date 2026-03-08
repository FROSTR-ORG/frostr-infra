#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIFROST_RS_DIR="${ROOT_DIR}/repos/bifrost-rs"

if [ ! -f "${BIFROST_RS_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${BIFROST_RS_DIR} (missing Cargo.toml)" >&2
  exit 1
fi

cd "${BIFROST_RS_DIR}"

echo "==> Building demo harness binaries on host"
cargo build --locked -p bifrost-dev --bin bifrost-devtools -p bifrost-app --bin bifrost
