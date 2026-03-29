#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"
PREBUILD_DIR="$(resolve_workspace_scratch_dir FROSTR_TEST_PREBUILD_DIR test-prebuild)"

TIMINGS_FILE="${PREBUILD_DIR}/timings.tsv"

mkdir -p "${PREBUILD_DIR}"
printf 'step\telapsed_seconds\n' >"${TIMINGS_FILE}"

declare -A SELECTED=()

record_timing() {
  local step="$1"
  local started_at="$2"
  local finished_at
  finished_at="$(date +%s)"
  printf '%s\t%s\n' "${step}" "$((finished_at - started_at))" >>"${TIMINGS_FILE}"
}

run_step() {
  local step="$1"
  shift
  local started_at
  started_at="$(date +%s)"
  echo "==> ${step}"
  "$@"
  record_timing "${step}" "${started_at}"
}

select_target() {
  local target="$1"
  case "${target}" in
    release)
      select_target shared
      select_target pwa
      select_target chrome
      select_target home
      select_target demo
      ;;
    pwa|chrome|home)
      SELECTED["ui"]=1
      SELECTED["${target}"]=1
      ;;
    shared|ui|demo)
      SELECTED["${target}"]=1
      ;;
    *)
      echo "error: unknown prebuild target '${target}'" >&2
      exit 1
      ;;
  esac
}

if [[ "$#" -eq 0 ]]; then
  select_target release
else
  for target in "$@"; do
    select_target "${target}"
  done
fi

if [[ -n "${SELECTED[shared]:-}" ]]; then
  run_step "Build bifrost-devtools" cargo build --manifest-path "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml" --offline --locked -p bifrost-devtools --bin bifrost-devtools
  run_step "Build igloo-shell CLI" env CARGO_TARGET_DIR="${ROOT_DIR}/build/igloo-shell-target" cargo build --manifest-path "${ROOT_DIR}/repos/igloo-shell/Cargo.toml" --offline -p igloo-shell-cli --bin igloo-shell
  run_step "Sync bridge wasm assets" npm --prefix "${ROOT_DIR}/repos/igloo-chrome" run build:bridge-wasm
fi

if [[ -n "${SELECTED[ui]:-}" ]]; then
  run_step "Build igloo-ui shared assets" npm --prefix "${ROOT_DIR}/repos/igloo-ui" run build
fi

if [[ -n "${SELECTED[pwa]:-}" ]]; then
  run_step "Build igloo-pwa app assets" npm --prefix "${ROOT_DIR}/repos/igloo-pwa" run build:app
fi

if [[ -n "${SELECTED[chrome]:-}" ]]; then
  run_step "Build igloo-chrome extension" npm --prefix "${ROOT_DIR}/repos/igloo-chrome" run build:app
fi

if [[ -n "${SELECTED[home]:-}" ]]; then
  run_step "Build igloo-home web assets" npm --prefix "${ROOT_DIR}/repos/igloo-home" run build:app
  run_step "Build igloo-home desktop binary" cargo build --manifest-path "${ROOT_DIR}/repos/igloo-home/src-tauri/Cargo.toml" --offline
fi

if [[ -n "${SELECTED[demo]:-}" ]]; then
  run_step "Build demo-harness images" docker compose -f "${ROOT_DIR}/compose.test.yml" build dev-relay igloo-demo
fi

echo "ok: test prebuild complete"
echo "timings: ${TIMINGS_FILE}"
