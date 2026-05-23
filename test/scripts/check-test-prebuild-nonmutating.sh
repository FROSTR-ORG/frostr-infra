#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "${ROOT_DIR}/.tmp"

compare_wasm_dir() {
  local expected_dir="$1"
  local actual_dir="$2"
  local label="$3"

  if ! diff -qr -x .gitkeep "${expected_dir}" "${actual_dir}" >/dev/null; then
    echo "browser wasm artifacts are out of sync for ${label}" >&2
    diff -qr -x .gitkeep "${expected_dir}" "${actual_dir}" >&2 || true
    exit 1
  fi
}

compare_tracked_wasm_dir() {
  local tracked_dir="$1"
  local generated_dir="$2"
  local label="$3"

  if [[ "${FROSTR_BROWSER_WASM_STRICT_TRACKED:-0}" != "1" ]]; then
    return
  fi

  compare_wasm_dir "${tracked_dir}" "${generated_dir}" "${label}"
}

prebuild_dir="$(mktemp -d "${ROOT_DIR}/.tmp/test-prebuild-nonmutating-browser-wasm.XXXXXX")"
"${ROOT_DIR}/test/scripts/check-worktree-unchanged.sh" -- \
  env FROSTR_TEST_PREBUILD_DIR="${prebuild_dir}" \
  bash "${ROOT_DIR}/scripts/test-prebuild.sh" sync browser-wasm

scratch_root="${prebuild_dir}/browser-wasm"
scratch_shared="${scratch_root}/igloo-shared/public/wasm"
scratch_pwa="${scratch_root}/igloo-pwa/public/wasm"
scratch_chrome="${scratch_root}/igloo-chrome/public/wasm"

compare_wasm_dir "${scratch_shared}" "${scratch_pwa}" "igloo-pwa scratch sync"
compare_wasm_dir "${scratch_shared}" "${scratch_chrome}" "igloo-chrome scratch sync"
compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-shared/public/wasm" "${scratch_shared}" "igloo-shared"
compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-pwa/public/wasm" "${scratch_pwa}" "igloo-pwa"
compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-chrome/public/wasm" "${scratch_chrome}" "igloo-chrome"

echo "ok: test prebuild browser wasm paths are non-mutating"
