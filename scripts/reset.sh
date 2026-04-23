#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${ROOT_DIR}/.tmp"
BUILD_ROOT="${ROOT_DIR}/build"

if [ "${1:-}" != "--force" ] && [ "${1:-}" != "-f" ]; then
  echo "reset.sh requires --force (invoked via 'make repo-reset')." >&2
  echo "This will remove all workspace scratch under .tmp/ and build artifacts under build/." >&2
  exit 1
fi

echo "Stopping demo compose services..."
bash "${ROOT_DIR}/scripts/demo.sh" stop || true

echo "Resetting root scratch directories..."
if [[ -e "${TMP_ROOT}" && ! -w "${TMP_ROOT}" ]]; then
  stale_root="${ROOT_DIR}/.tmp.stale.$(date +%s)"
  echo "Workspace scratch root is not writable; moving it to ${stale_root}"
  mv "${TMP_ROOT}" "${stale_root}"
fi
rm -rf "${TMP_ROOT}"
rm -rf "${BUILD_ROOT}"
mkdir -p "${TMP_ROOT}"
mkdir -p "${BUILD_ROOT}"

echo "Reset complete."
