#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${IGLOO_HOME_PACKAGE_HOME_DIR:-${ROOT_DIR}/repos/igloo-home}"
BUNDLE_DIR="${IGLOO_HOME_PACKAGE_BUNDLE_DIR:-${HOME_DIR}/src-tauri/target/release/bundle}"
STAGE_ROOT="${IGLOO_HOME_PACKAGE_STAGE_ROOT:-${ROOT_DIR}/.tmp/release/igloo-home}"
OS_NAME="${IGLOO_HOME_PACKAGE_OS:-$(uname -s)}"
SKIP_BUILD="${IGLOO_HOME_PACKAGE_SKIP_BUILD:-0}"
GENERATED_AT="${IGLOO_HOME_PACKAGE_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing required file: ${path}"
}

read_json_string() {
  local file="$1"
  local filter="$2"
  jq -er "${filter}" "${file}"
}

home_version() {
  local package_json="${HOME_DIR}/package.json"
  local tauri_conf="${HOME_DIR}/src-tauri/tauri.conf.json"
  require_file "${package_json}"
  require_file "${tauri_conf}"

  local package_version
  local tauri_version
  package_version="$(read_json_string "${package_json}" '.version')"
  tauri_version="$(read_json_string "${tauri_conf}" '.version')"

  if [[ "${package_version}" != "${tauri_version}" ]]; then
    fail "version mismatch: package.json=${package_version} tauri.conf.json=${tauri_version}"
  fi

  printf '%s\n' "${package_version}"
}

git_commit_or_override() {
  local override="$1"
  local dir="$2"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
  else
    git -C "${dir}" rev-parse --short=12 HEAD
  fi
}

platform_info() {
  case "${OS_NAME}" in
    Darwin)
      printf '%s\t%s\t%s\n' "macos" "dmg" "${BUNDLE_DIR}/dmg/*.dmg"
      ;;
    Linux)
      printf '%s\t%s\t%s\n' "linux" "appimage" "${BUNDLE_DIR}/appimage/*.AppImage"
      ;;
    *)
      fail "unsupported igloo-home release OS: ${OS_NAME}"
      ;;
  esac
}

select_one_artifact() {
  local glob_pattern="$1"
  local label="$2"
  local matches=()
  shopt -s nullglob
  matches=(${glob_pattern})
  shopt -u nullglob

  if [[ ${#matches[@]} -ne 1 ]]; then
    fail "expected exactly one ${label} artifact matching ${glob_pattern}, found ${#matches[@]}"
  fi

  printf '%s\n' "${matches[0]}"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    fail "neither sha256sum nor shasum is available"
  fi
}

run_build() {
  if [[ "${SKIP_BUILD}" == "1" ]]; then
    return 0
  fi
  npm --prefix "${HOME_DIR}" run tauri -- build
}

write_outputs() {
  local version="$1"
  local platform="$2"
  local target_family="$3"
  local artifact_path="$4"
  local stage_dir="$5"

  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  local artifact_name
  artifact_name="$(basename "${artifact_path}")"
  cp "${artifact_path}" "${stage_dir}/${artifact_name}"

  local digest
  digest="$(sha256_file "${stage_dir}/${artifact_name}")"
  printf '%s  %s\n' "${digest}" "${artifact_name}" >"${stage_dir}/SHA256SUMS"

  local parent_commit
  local home_commit
  parent_commit="$(git_commit_or_override "${IGLOO_HOME_PACKAGE_PARENT_COMMIT:-}" "${ROOT_DIR}")"
  home_commit="$(git_commit_or_override "${IGLOO_HOME_PACKAGE_HOME_COMMIT:-}" "${HOME_DIR}")"

  jq -n \
    --arg client "igloo-home" \
    --arg version "${version}" \
    --arg platform "${platform}" \
    --arg targetFamily "${target_family}" \
    --arg parentCommit "${parent_commit}" \
    --arg homeCommit "${home_commit}" \
    --arg generatedAt "${GENERATED_AT}" \
    --arg file "${artifact_name}" \
    --arg sha256 "${digest}" \
    '{
      client: $client,
      version: $version,
      platform: $platform,
      targetFamily: $targetFamily,
      parentCommit: $parentCommit,
      homeCommit: $homeCommit,
      generatedAt: $generatedAt,
      artifacts: [{file: $file, sha256: $sha256}]
    }' >"${stage_dir}/manifest.json"

  printf '%s\n' "${stage_dir}"
}

main() {
  local version
  version="$(home_version)"

  run_build

  local platform
  local target_family
  local glob_pattern
  IFS=$'\t' read -r platform target_family glob_pattern < <(platform_info)

  local label
  case "${target_family}" in
    dmg) label="DMG" ;;
    appimage) label="AppImage" ;;
    *) label="${target_family}" ;;
  esac

  local artifact_path
  artifact_path="$(select_one_artifact "${glob_pattern}" "${label}")"
  write_outputs "${version}" "${platform}" "${target_family}" "${artifact_path}" "${STAGE_ROOT}/${version}"
}

main "$@"
