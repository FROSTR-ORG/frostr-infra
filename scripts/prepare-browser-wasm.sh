#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
usage: scripts/prepare-browser-wasm.sh <sync|check> [all|igloo-chrome|igloo-pwa]
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

check_scope() {
  local scope="$1"
  sync_scope "${scope}"

  local -a diff_paths=("${ROOT_DIR}/repos/igloo-shared/public/wasm")
  case "${scope}" in
    all)
      diff_paths+=(
        "${ROOT_DIR}/repos/igloo-chrome/public/wasm"
        "${ROOT_DIR}/repos/igloo-pwa/public/wasm"
      )
      ;;
    igloo-chrome|igloo-pwa)
      diff_paths+=("${ROOT_DIR}/repos/${scope}/public/wasm")
      ;;
  esac

  if ! git -C "${ROOT_DIR}" diff --quiet -- "${diff_paths[@]}"; then
    echo "browser wasm artifacts are out of sync with source" >&2
    git -C "${ROOT_DIR}" diff -- "${diff_paths[@]}"
    exit 1
  fi

  echo "ok: browser wasm artifacts are in sync"
}

main() {
  local mode="${1:-}"
  local scope
  scope="$(normalize_scope "${2:-all}")"

  case "${mode}" in
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
