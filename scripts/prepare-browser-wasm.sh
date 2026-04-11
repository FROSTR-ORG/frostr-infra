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

sync_scope() {
  local scope="$1"

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
