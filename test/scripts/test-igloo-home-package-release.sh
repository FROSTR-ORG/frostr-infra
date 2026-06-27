#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/igloo-home-package-release.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

fail() {
  echo "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}', got: ${haystack}"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

write_home_fixture() {
  local root="$1"
  local package_version="$2"
  local tauri_version="$3"
  mkdir -p "${root}/src-tauri"
  jq -n --arg version "${package_version}" '{name:"igloo-home",version:$version}' >"${root}/package.json"
  jq -n --arg version "${tauri_version}" '{productName:"Igloo Home",version:$version}' >"${root}/src-tauri/tauri.conf.json"
}

run_package_script() {
  local home_dir="$1"
  local bundle_dir="$2"
  local stage_root="$3"
  local os_name="$4"
  shift 4
  IGLOO_HOME_PACKAGE_HOME_DIR="${home_dir}" \
    IGLOO_HOME_PACKAGE_BUNDLE_DIR="${bundle_dir}" \
    IGLOO_HOME_PACKAGE_STAGE_ROOT="${stage_root}" \
    IGLOO_HOME_PACKAGE_OS="${os_name}" \
    IGLOO_HOME_PACKAGE_SKIP_BUILD=1 \
    IGLOO_HOME_PACKAGE_TIMESTAMP="2026-06-27T00:00:00Z" \
    IGLOO_HOME_PACKAGE_PARENT_COMMIT="parent-fixture" \
    IGLOO_HOME_PACKAGE_HOME_COMMIT="home-fixture" \
    "${SCRIPT}" "$@"
}

expect_fail_contains() {
  local expected="$1"
  shift
  set +e
  local output
  output="$("$@" 2>&1)"
  local status=$?
  set -e
  if [[ ${status} -eq 0 ]]; then
    fail "expected command to fail: $*"
  fi
  assert_contains "${output}" "${expected}"
}

portable_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

test_version_mismatch_fails() {
  local home="${TMP_DIR}/version-mismatch/home"
  local bundle="${TMP_DIR}/version-mismatch/bundle"
  local stage="${TMP_DIR}/version-mismatch/stage"
  write_home_fixture "${home}" "0.2.0" "0.3.0"
  mkdir -p "${bundle}/appimage"
  printf 'appimage' >"${bundle}/appimage/Igloo Home_0.2.0_amd64.AppImage"
  expect_fail_contains "version mismatch: package.json=0.2.0 tauri.conf.json=0.3.0" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_unsupported_os_fails() {
  local home="${TMP_DIR}/unsupported/home"
  local bundle="${TMP_DIR}/unsupported/bundle"
  local stage="${TMP_DIR}/unsupported/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'appimage' >"${bundle}/appimage/Igloo Home_0.2.0_amd64.AppImage"
  expect_fail_contains "unsupported igloo-home release OS: Plan9" \
    run_package_script "${home}" "${bundle}" "${stage}" "Plan9"
}

test_missing_appimage_fails() {
  local home="${TMP_DIR}/missing/home"
  local bundle="${TMP_DIR}/missing/bundle"
  local stage="${TMP_DIR}/missing/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  expect_fail_contains "expected exactly one AppImage artifact" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_ambiguous_appimage_fails() {
  local home="${TMP_DIR}/ambiguous/home"
  local bundle="${TMP_DIR}/ambiguous/bundle"
  local stage="${TMP_DIR}/ambiguous/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'one' >"${bundle}/appimage/one.AppImage"
  printf 'two' >"${bundle}/appimage/two.AppImage"
  expect_fail_contains "expected exactly one AppImage artifact" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_linux_appimage_stages_manifest_and_checksum() {
  local home="${TMP_DIR}/linux/home"
  local bundle="${TMP_DIR}/linux/bundle"
  local stage="${TMP_DIR}/linux/stage"
  local artifact="Igloo Home_0.2.0_amd64.AppImage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'linux-appimage-fixture' >"${bundle}/appimage/${artifact}"

  local output
  output="$(run_package_script "${home}" "${bundle}" "${stage}" "Linux")"
  local staged_dir="${stage}/0.2.0"
  assert_contains "${output}" "${staged_dir}"
  assert_file_exists "${staged_dir}/${artifact}"
  assert_file_exists "${staged_dir}/SHA256SUMS"
  assert_file_exists "${staged_dir}/manifest.json"

  local digest
  digest="$(portable_sha256 "${staged_dir}/${artifact}")"
  assert_contains "$(cat "${staged_dir}/SHA256SUMS")" "${digest}  ${artifact}"
  [[ "$(jq -r '.client' "${staged_dir}/manifest.json")" == "igloo-home" ]] || fail "manifest client mismatch"
  [[ "$(jq -r '.version' "${staged_dir}/manifest.json")" == "0.2.0" ]] || fail "manifest version mismatch"
  [[ "$(jq -r '.platform' "${staged_dir}/manifest.json")" == "linux" ]] || fail "manifest platform mismatch"
  [[ "$(jq -r '.targetFamily' "${staged_dir}/manifest.json")" == "appimage" ]] || fail "manifest targetFamily mismatch"
  [[ "$(jq -r '.artifacts[0].file' "${staged_dir}/manifest.json")" == "${artifact}" ]] || fail "manifest artifact mismatch"
  [[ "$(jq -r '.artifacts[0].sha256' "${staged_dir}/manifest.json")" == "${digest}" ]] || fail "manifest digest mismatch"
}

test_darwin_dmg_stages_manifest_and_checksum() {
  local home="${TMP_DIR}/darwin/home"
  local bundle="${TMP_DIR}/darwin/bundle"
  local stage="${TMP_DIR}/darwin/stage"
  local artifact="Igloo Home_0.2.0_aarch64.dmg"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/dmg"
  printf 'darwin-dmg-fixture' >"${bundle}/dmg/${artifact}"

  run_package_script "${home}" "${bundle}" "${stage}" "Darwin" >/dev/null
  local staged_dir="${stage}/0.2.0"
  assert_file_exists "${staged_dir}/${artifact}"
  [[ "$(jq -r '.platform' "${staged_dir}/manifest.json")" == "macos" ]] || fail "manifest platform mismatch"
  [[ "$(jq -r '.targetFamily' "${staged_dir}/manifest.json")" == "dmg" ]] || fail "manifest targetFamily mismatch"
}

test_version_mismatch_fails
test_unsupported_os_fails
test_missing_appimage_fails
test_ambiguous_appimage_fails
test_linux_appimage_stages_manifest_and_checksum
test_darwin_dmg_stages_manifest_and_checksum

echo "ok: igloo-home package release primitive"
