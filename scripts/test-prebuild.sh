#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"
PREBUILD_DIR="$(resolve_workspace_scratch_dir FROSTR_TEST_PREBUILD_DIR test-prebuild)"
TIMINGS_FILE="${PREBUILD_DIR}/timings.tsv"
STAMP_DIR="${PREBUILD_DIR}/stamps"

mkdir -p "${PREBUILD_DIR}" "${STAMP_DIR}"
printf 'step\telapsed_seconds\n' >"${TIMINGS_FILE}"

SELECTED=()

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

selected_add() {
  local target="$1"
  local selected
  for selected in "${SELECTED[@]+"${SELECTED[@]}"}"; do
    if [[ "${selected}" == "${target}" ]]; then
      return
    fi
  done
  SELECTED+=("${target}")
}

selected_has() {
  local target="$1"
  local selected
  for selected in "${SELECTED[@]+"${SELECTED[@]}"}"; do
    if [[ "${selected}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
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
    browser-wasm)
      selected_add "browser-wasm"
      ;;
    pwa|chrome)
      selected_add "ui"
      selected_add "browser-wasm"
      selected_add "${target}"
      ;;
    home)
      selected_add "ui"
      selected_add "${target}"
      ;;
    demo)
      selected_add "demo"
      selected_add "demo-binaries"
      ;;
    shared|ui|demo-binaries)
      selected_add "${target}"
      ;;
    *)
      echo "error: unknown prebuild target '${target}'" >&2
      exit 1
      ;;
  esac
}

selected_targets() {
  if [[ ${#SELECTED[@]} -eq 0 ]]; then
    return
  fi
  printf '%s\n' "${SELECTED[@]}" | sort
}

selected_key() {
  local key
  key="$(selected_targets | paste -sd '__' -)"
  printf '%s\n' "${key:-release}"
}

browser_wasm_scope() {
  if selected_has pwa && ! selected_has chrome && ! selected_has shared; then
    printf '%s\n' "pwa"
    return
  fi
  if selected_has chrome && ! selected_has pwa && ! selected_has shared; then
    printf '%s\n' "chrome"
    return
  fi
  printf '%s\n' "all"
}

require_submodule_path() {
  local target="$1"
  local submodule="$2"
  local sentinel="$3"
  if [[ -e "${ROOT_DIR}/${sentinel}" ]]; then
    return
  fi
  echo "error: prebuild target '${target}' requires initialized submodule ${submodule} (missing ${sentinel})." >&2
  echo "hint: git submodule update --init ${submodule}" >&2
  return 1
}

check_required_submodules() {
  if [[ "${FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK:-0}" == "1" ]]; then
    return
  fi

  local missing=0
  if selected_has shared || selected_has browser-wasm || selected_has demo-binaries; then
    require_submodule_path "browser-wasm" "repos/bifrost-rs" "repos/bifrost-rs/Cargo.toml" || missing=1
    require_submodule_path "browser-wasm" "repos/igloo-shared" "repos/igloo-shared/package.json" || missing=1
  fi
  if selected_has shared || selected_has demo-binaries; then
    require_submodule_path "shared" "repos/igloo-shell" "repos/igloo-shell/Cargo.toml" || missing=1
  fi
  if selected_has ui; then
    require_submodule_path "ui" "repos/igloo-ui" "repos/igloo-ui/package.json" || missing=1
  fi
  if selected_has pwa; then
    require_submodule_path "pwa" "repos/igloo-pwa" "repos/igloo-pwa/package.json" || missing=1
  fi
  if selected_has chrome; then
    require_submodule_path "chrome" "repos/igloo-chrome" "repos/igloo-chrome/package.json" || missing=1
  fi
  if selected_has home; then
    require_submodule_path "home" "repos/igloo-home" "repos/igloo-home/package.json" || missing=1
    require_submodule_path "home" "repos/igloo-home" "repos/igloo-home/src-tauri/Cargo.toml" || missing=1
  fi
  if [[ "${missing}" -eq 1 ]]; then
    exit 1
  fi
}

append_file_state() {
  local path="$1"
  local rel="${path#${ROOT_DIR}/}"
  if [[ -f "${path}" ]]; then
    printf 'file\t%s\t%s\n' "${rel}" "$(sha256sum "${path}" 2>/dev/null | awk '{print $1}')"
  else
    printf 'missing_file\t%s\n' "${rel}"
  fi
}

append_dir_state() {
  local path="$1"
  local rel="${path#${ROOT_DIR}/}"
  if [[ ! -d "${path}" ]]; then
    printf 'missing_dir\t%s\n' "${rel}"
    return
  fi

  while IFS= read -r -d '' file; do
    if [[ -f "${file}" ]]; then
      printf 'file\t%s\t%s\n' "${file#${ROOT_DIR}/}" "$(sha256sum "${file}" 2>/dev/null | awk '{print $1}')"
    fi
  done < <(find "${path}" -type f -print0 | sort -z)
}

append_image_state() {
  local image="$1"
  local image_id
  if image_id="$(docker image inspect --format '{{.Id}}' "${image}" 2>/dev/null)"; then
    printf 'image\t%s\t%s\n' "${image}" "${image_id}"
  else
    printf 'missing_image\t%s\n' "${image}"
  fi
}

collect_input_paths() {
  local -a entries_ref=()

  entries_ref+=("${ROOT_DIR}/scripts/test-prebuild.sh")
  entries_ref+=("${ROOT_DIR}/scripts/prepare-browser-wasm.sh")

  if selected_has shared || selected_has browser-wasm; then
    entries_ref+=(
      "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml"
      "${ROOT_DIR}/repos/bifrost-rs/Cargo.lock"
      "${ROOT_DIR}/repos/bifrost-rs/crates/bifrost-bridge-wasm"
      "${ROOT_DIR}/repos/bifrost-rs/crates/bifrost-devtools"
      "${ROOT_DIR}/repos/bifrost-rs/crates/bifrost-profile-wasm"
      "${ROOT_DIR}/repos/igloo-shared/package.json"
      "${ROOT_DIR}/repos/igloo-shared/package-lock.json"
      "${ROOT_DIR}/repos/igloo-shared/scripts/build-bridge-wasm.sh"
      "${ROOT_DIR}/repos/igloo-shared/src/wasm"
    )
  fi

  if selected_has shared; then
    entries_ref+=(
      "${ROOT_DIR}/repos/igloo-shell/Cargo.toml"
      "${ROOT_DIR}/repos/igloo-shell/Cargo.lock"
      "${ROOT_DIR}/repos/igloo-shell/crates/igloo-shell-cli"
    )
  fi

  if selected_has ui; then
    entries_ref+=(
      "${ROOT_DIR}/repos/igloo-ui/package.json"
      "${ROOT_DIR}/repos/igloo-ui/package-lock.json"
      "${ROOT_DIR}/repos/igloo-ui/scripts/build.mjs"
      "${ROOT_DIR}/repos/igloo-ui/tailwind.config.js"
      "${ROOT_DIR}/repos/igloo-ui/tsconfig.json"
      "${ROOT_DIR}/repos/igloo-ui/src"
    )
  fi

  if selected_has pwa; then
    entries_ref+=(
      "${ROOT_DIR}/repos/igloo-pwa/package.json"
      "${ROOT_DIR}/repos/igloo-pwa/package-lock.json"
      "${ROOT_DIR}/repos/igloo-pwa/scripts"
      "${ROOT_DIR}/repos/igloo-pwa/src"
      "${ROOT_DIR}/repos/igloo-pwa/public"
      "${ROOT_DIR}/repos/igloo-pwa/tsconfig.json"
      "${ROOT_DIR}/repos/igloo-pwa/vite.config.ts"
    )
  fi

  if selected_has chrome; then
    entries_ref+=(
      "${ROOT_DIR}/repos/igloo-chrome/package.json"
      "${ROOT_DIR}/repos/igloo-chrome/package-lock.json"
      "${ROOT_DIR}/repos/igloo-chrome/scripts"
      "${ROOT_DIR}/repos/igloo-chrome/src"
      "${ROOT_DIR}/repos/igloo-chrome/public"
      "${ROOT_DIR}/repos/igloo-chrome/tsconfig.json"
      "${ROOT_DIR}/repos/igloo-chrome/vite.config.ts"
    )
  fi

  if selected_has home; then
    entries_ref+=(
      "${ROOT_DIR}/repos/igloo-home/package.json"
      "${ROOT_DIR}/repos/igloo-home/package-lock.json"
      "${ROOT_DIR}/repos/igloo-home/scripts"
      "${ROOT_DIR}/repos/igloo-home/src"
      "${ROOT_DIR}/repos/igloo-home/tsconfig.json"
      "${ROOT_DIR}/repos/igloo-home/vite.config.ts"
      "${ROOT_DIR}/repos/igloo-home/src-tauri/Cargo.toml"
      "${ROOT_DIR}/repos/igloo-home/src-tauri/Cargo.lock"
      "${ROOT_DIR}/repos/igloo-home/src-tauri/build.rs"
      "${ROOT_DIR}/repos/igloo-home/src-tauri/tauri.conf.json"
      "${ROOT_DIR}/repos/igloo-home/src-tauri/src"
    )
  fi

  if selected_has demo-binaries; then
    entries_ref+=(
      "${ROOT_DIR}/scripts/demo.sh"
      "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml"
      "${ROOT_DIR}/repos/bifrost-rs/Cargo.lock"
      "${ROOT_DIR}/repos/igloo-shell/Cargo.toml"
      "${ROOT_DIR}/repos/igloo-shell/Cargo.lock"
      "${ROOT_DIR}/repos/igloo-shell/crates/igloo-shell-cli"
    )
  fi

  if selected_has demo; then
    entries_ref+=(
      "${ROOT_DIR}/compose.test.yml"
      "${ROOT_DIR}/services/dev-relay"
      "${ROOT_DIR}/services/igloo-demo"
    )
  fi

  printf '%s\n' "${entries_ref[@]}"
}

render_input_fingerprint() {
  {
    local path
    while IFS= read -r path; do
      if [[ -d "${path}" ]]; then
        append_dir_state "${path}"
      else
        append_file_state "${path}"
      fi
    done < <(collect_input_paths)
  } | sha256sum | awk '{print $1}'
}

render_output_state() {
  if selected_has shared; then
    append_file_state "${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
    append_file_state "${ROOT_DIR}/build/igloo-shell-target/debug/igloo-shell"
  fi

  if selected_has browser-wasm || selected_has shared; then
    append_dir_state "${ROOT_DIR}/repos/igloo-shared/public/wasm"
    if selected_has pwa || selected_has shared || { ! selected_has pwa && ! selected_has chrome; }; then
      append_dir_state "${ROOT_DIR}/repos/igloo-pwa/public/wasm"
    fi
    if selected_has chrome || selected_has shared || { ! selected_has pwa && ! selected_has chrome; }; then
      append_dir_state "${ROOT_DIR}/repos/igloo-chrome/public/wasm"
    fi
  fi

  if selected_has ui; then
    append_dir_state "${ROOT_DIR}/repos/igloo-ui/dist"
  fi

  if selected_has pwa; then
    append_dir_state "${ROOT_DIR}/repos/igloo-pwa/dist"
  fi

  if selected_has chrome; then
    append_dir_state "${ROOT_DIR}/repos/igloo-chrome/dist"
  fi

  if selected_has home; then
    append_dir_state "${ROOT_DIR}/repos/igloo-home/dist"
    append_file_state "${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home"
  fi

  if selected_has demo-binaries; then
    append_file_state "${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
    append_file_state "${ROOT_DIR}/repos/igloo-shell/target/debug/igloo-shell"
  fi

  if selected_has demo; then
    append_image_state "bifrost-infra-dev-relay:dev"
    append_image_state "bifrost-infra-igloo-demo:dev"
  fi
}

render_state_stamp() {
  local input_fingerprint
  input_fingerprint="$(render_input_fingerprint)"
  printf 'input_fingerprint\t%s\n' "${input_fingerprint}"
  render_output_state
}

stamp_file() {
  printf '%s/%s.state\n' "${STAMP_DIR}" "$(selected_key)"
}

check_stamp() {
  local current_stamp saved_stamp
  saved_stamp="$(stamp_file)"
  if [[ ! -f "${saved_stamp}" ]]; then
    echo "missing prebuild stamp for $(selected_key)" >&2
    return 1
  fi

  current_stamp="$(mktemp)"
  render_state_stamp >"${current_stamp}"
  if ! cmp -s "${saved_stamp}" "${current_stamp}"; then
    echo "prebuild outputs are stale for $(selected_key)" >&2
    rm -f "${current_stamp}"
    return 1
  fi

  rm -f "${current_stamp}"
  echo "ok: test prebuild outputs are current for $(selected_key)"
}

write_stamp() {
  render_state_stamp >"$(stamp_file)"
}

MODE="sync"
if [[ "${1:-}" == "sync" || "${1:-}" == "check" || "${1:-}" == "ensure" ]]; then
  MODE="$1"
  shift
fi

if [[ "$#" -eq 0 ]]; then
  select_target release
else
  for target in "$@"; do
    select_target "${target}"
  done
fi

check_required_submodules

if [[ "${MODE}" == "check" ]]; then
  check_stamp
  exit 0
fi

if [[ "${MODE}" == "ensure" ]]; then
  if check_stamp; then
    exit 0
  fi
  MODE="sync"
fi

if selected_has shared; then
  run_step "Build bifrost-devtools" cargo build --manifest-path "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml" --offline --locked -p bifrost-devtools --bin bifrost-devtools
  run_step "Build igloo-shell CLI" env CARGO_TARGET_DIR="${ROOT_DIR}/build/igloo-shell-target" cargo build --manifest-path "${ROOT_DIR}/repos/igloo-shell/Cargo.toml" --offline -p igloo-shell-cli --bin igloo-shell
fi

if selected_has browser-wasm || selected_has shared; then
  run_step "Prepare browser wasm artifacts" "${ROOT_DIR}/scripts/prepare-browser-wasm.sh" sync "$(browser_wasm_scope)"
fi

if selected_has ui; then
  run_step "Build igloo-ui shared assets" npm --prefix "${ROOT_DIR}/repos/igloo-ui" run build
fi

if selected_has pwa; then
  run_step "Build igloo-pwa app assets" npm --prefix "${ROOT_DIR}/repos/igloo-pwa" run build:app
fi

if selected_has chrome; then
  run_step "Build igloo-chrome extension" npm --prefix "${ROOT_DIR}/repos/igloo-chrome" run build:app
fi

if selected_has home; then
  run_step "Build igloo-home web assets" npm --prefix "${ROOT_DIR}/repos/igloo-home" run build:app
  run_step "Build igloo-home desktop binary" cargo build --manifest-path "${ROOT_DIR}/repos/igloo-home/src-tauri/Cargo.toml" --offline
fi

if selected_has demo-binaries; then
  run_step "Build demo-harness binaries" bash -c "cd '${ROOT_DIR}/repos/bifrost-rs' && cargo build --offline --locked -p bifrost-devtools --bin bifrost-devtools"
  run_step "Build demo-harness shell" bash -c "cd '${ROOT_DIR}/repos/igloo-shell' && cargo build --offline --locked -p igloo-shell-cli --bin igloo-shell"
fi

if selected_has demo; then
  run_step "Build demo-harness images" docker compose -f "${ROOT_DIR}/compose.test.yml" build dev-relay igloo-demo
fi

write_stamp

echo "ok: test prebuild complete"
echo "timings: ${TIMINGS_FILE}"
