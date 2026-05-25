#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"

if ! command -v rustc >/dev/null 2>&1 && [[ -n "${HOME:-}" && -x "${HOME}/.cargo/bin/rustc" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

usage() {
  cat <<'EOF'
usage: scripts/prepare-browser-wasm.sh <prepare|sync|check> [all|igloo-chrome|igloo-pwa]
EOF
}

normalize_scope() {
  local scope="${1:-all}"
  case "${scope}" in
    all|"")
      printf '%s\n' "all"
      ;;
    chrome|igloo-chrome)
      printf '%s\n' "igloo-chrome"
      ;;
    pwa|igloo-pwa)
      printf '%s\n' "igloo-pwa"
      ;;
    *)
      echo "error: unknown browser wasm scope '${scope}'" >&2
      exit 1
      ;;
  esac
}

ensure_wasm_target() {
  if [[ "${FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK:-0}" == "1" ]]; then
    return
  fi

  local target_libdir
  target_libdir="$(rustc --print target-libdir --target wasm32-unknown-unknown 2>/dev/null || true)"
  if [[ -n "${target_libdir}" && -d "${target_libdir}" ]]; then
    return
  fi

  echo "error: wasm32-unknown-unknown Rust target is not available for $(command -v rustc)" >&2
  echo "hint: remove or unlink Homebrew Rust, put ~/.cargo/bin ahead of /opt/homebrew/bin, then run 'rustup target add wasm32-unknown-unknown'." >&2
  exit 1
}

clang_supports_wasm() {
  local clang_bin="$1"
  printf 'int main(void){return 0;}' \
    | "${clang_bin}" --target=wasm32-unknown-unknown -x c -c - -o /dev/null >/dev/null 2>&1
}

select_wasm_clang() {
  local candidate
  for candidate in \
    "${CC_wasm32_unknown_unknown:-}" \
    "${WASM_CC:-}" \
    "/opt/homebrew/opt/llvm/bin/clang" \
    "clang"; do
    if [[ -z "${candidate}" ]]; then
      continue
    fi
    if command -v "${candidate}" >/dev/null 2>&1 && clang_supports_wasm "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

ensure_wasm_clang() {
  local wasm_clang
  if wasm_clang="$(select_wasm_clang)"; then
    export CC_wasm32_unknown_unknown="${wasm_clang}"
    export TARGET_CC="${wasm_clang}"
    return
  fi

  echo "error: no clang with wasm32-unknown-unknown target support found" >&2
  echo "hint: install LLVM (for example: brew install llvm) or set WASM_CC/CC_wasm32_unknown_unknown to a wasm-capable clang." >&2
  exit 1
}

sync_scope() {
  local scope="$1"

  ensure_wasm_target
  ensure_wasm_clang

  echo "==> Rebuild shared browser wasm artifacts"
  npm --prefix "${ROOT_DIR}/repos/igloo-shared" run build:browser-wasm

  case "${scope}" in
    all)
      echo "==> Sync browser wasm into igloo-pwa"
      npm --prefix "${ROOT_DIR}/repos/igloo-pwa" run build:browser-wasm
      echo "==> Sync browser wasm into igloo-chrome"
      npm --prefix "${ROOT_DIR}/repos/igloo-chrome" run build:browser-wasm
      ;;
    igloo-pwa|igloo-chrome)
      echo "==> Sync browser wasm into ${scope}"
      npm --prefix "${ROOT_DIR}/repos/${scope}" run build:browser-wasm
      ;;
  esac
}

build_shared_wasm() {
  local out_dir="$1"
  echo "==> Rebuild shared browser wasm artifacts"
  IGLOO_SHARED_BROWSER_WASM_OUT_DIR="${out_dir}" \
    npm --prefix "${ROOT_DIR}/repos/igloo-shared" run build:browser-wasm
}

write_wasm_module_package() {
  local out_dir="$1"
  mkdir -p "${out_dir}"
  printf '{"type":"module"}\n' >"${out_dir}/package.json"
}

sync_client_wasm() {
  local scope="$1"
  local source_dir="$2"
  local target_dir="$3"

  echo "==> Sync browser wasm into ${scope}"
  IGLOO_BROWSER_WASM_SOURCE_DIR="${source_dir}" \
    IGLOO_BROWSER_WASM_TARGET_DIR="${target_dir}" \
    npm --prefix "${ROOT_DIR}/repos/${scope}" run build:browser-wasm
}

prepare_scope() {
  local scope="$1"

  ensure_wasm_target
  ensure_wasm_clang

  local scratch_root
  scratch_root="$(resolve_workspace_scratch_dir FROSTR_BROWSER_WASM_PREPARE_DIR "test-prebuild/browser-wasm")"
  local scratch_shared="${scratch_root}/igloo-shared/public/wasm"
  local scratch_pwa="${scratch_root}/igloo-pwa/public/wasm"
  local scratch_chrome="${scratch_root}/igloo-chrome/public/wasm"

  rm -rf "${scratch_root}/igloo-shared" "${scratch_root}/igloo-pwa" "${scratch_root}/igloo-chrome"

  build_shared_wasm "${scratch_shared}"
  write_wasm_module_package "${scratch_shared}"

  case "${scope}" in
    all)
      sync_client_wasm "igloo-pwa" "${scratch_shared}" "${scratch_pwa}"
      sync_client_wasm "igloo-chrome" "${scratch_shared}" "${scratch_chrome}"
      ;;
    igloo-pwa)
      sync_client_wasm "igloo-pwa" "${scratch_shared}" "${scratch_pwa}"
      ;;
    igloo-chrome)
      sync_client_wasm "igloo-chrome" "${scratch_shared}" "${scratch_chrome}"
      ;;
  esac

  echo "ok: browser wasm artifacts prepared under ${scratch_root}"
}

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

check_scope() {
  local scope="$1"

  ensure_wasm_target
  ensure_wasm_clang

  local scratch_root
  scratch_root="$(resolve_workspace_scratch_dir FROSTR_BROWSER_WASM_CHECK_DIR browser-wasm-check)"
  local scratch_shared="${scratch_root}/igloo-shared/public/wasm"
  local scratch_pwa="${scratch_root}/igloo-pwa/public/wasm"
  local scratch_chrome="${scratch_root}/igloo-chrome/public/wasm"

  rm -rf "${scratch_root}/igloo-shared" "${scratch_root}/igloo-pwa" "${scratch_root}/igloo-chrome"

  build_shared_wasm "${scratch_shared}"
  compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-shared/public/wasm" "${scratch_shared}" "igloo-shared"

  case "${scope}" in
    all)
      sync_client_wasm "igloo-pwa" "${scratch_shared}" "${scratch_pwa}"
      sync_client_wasm "igloo-chrome" "${scratch_shared}" "${scratch_chrome}"
      compare_wasm_dir "${scratch_shared}" "${scratch_pwa}" "igloo-pwa scratch sync"
      compare_wasm_dir "${scratch_shared}" "${scratch_chrome}" "igloo-chrome scratch sync"
      compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-pwa/public/wasm" "${scratch_pwa}" "igloo-pwa"
      compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-chrome/public/wasm" "${scratch_chrome}" "igloo-chrome"
      ;;
    igloo-pwa)
      sync_client_wasm "igloo-pwa" "${scratch_shared}" "${scratch_pwa}"
      compare_wasm_dir "${scratch_shared}" "${scratch_pwa}" "igloo-pwa scratch sync"
      compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-pwa/public/wasm" "${scratch_pwa}" "igloo-pwa"
      ;;
    igloo-chrome)
      sync_client_wasm "igloo-chrome" "${scratch_shared}" "${scratch_chrome}"
      compare_wasm_dir "${scratch_shared}" "${scratch_chrome}" "igloo-chrome scratch sync"
      compare_tracked_wasm_dir "${ROOT_DIR}/repos/igloo-chrome/public/wasm" "${scratch_chrome}" "igloo-chrome"
      ;;
  esac

  echo "ok: browser wasm artifacts build and sync from scratch"
}

main() {
  local mode="${1:-}"
  local scope
  scope="$(normalize_scope "${2:-all}")"

  case "${mode}" in
    prepare)
      prepare_scope "${scope}"
      ;;
    sync)
      sync_scope "${scope}"
      ;;
    check)
      check_scope "${scope}"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
