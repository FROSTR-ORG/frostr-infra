#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AFFECTED_SH="${ROOT_DIR}/scripts/test-affected.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "expected output to contain: ${needle}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "expected output to omit: ${needle}" >&2
    exit 1
  fi
}

run_dry() {
  FROSTR_AFFECTED_DRY_RUN=1 FROSTR_AFFECTED_FILES="$1" "${AFFECTED_SH}"
}

NO_CHANGES="$(run_dry '')"
assert_contains "${NO_CHANGES}" "command: npm --prefix test run test:guards"
assert_not_contains "${NO_CHANGES}" "prep_targets:"
assert_not_contains "${NO_CHANGES}" "cargo test --manifest-path"

PARENT_ONLY="$(run_dry $'README.md\ntest/README.md')"
assert_contains "${PARENT_ONLY}" "command: npm --prefix test run test:guards"
assert_not_contains "${PARENT_ONLY}" "prep_targets:"
assert_not_contains "${PARENT_ONLY}" "test:e2e:igloo-pwa"

DEV_DOCS_ONLY="$(run_dry $'dev/docs/RELEASE.md\ndev/adrs/INDEX.md')"
assert_contains "${DEV_DOCS_ONLY}" "command: npm --prefix test run test:guards"
assert_not_contains "${DEV_DOCS_ONLY}" "prep_targets:"
assert_not_contains "${DEV_DOCS_ONLY}" "test:e2e:igloo-pwa"

BIFROST_ONLY="$(run_dry $'repos/bifrost-rs/Cargo.toml')"
assert_contains "${BIFROST_ONLY}" "cargo test --manifest-path ${ROOT_DIR}/repos/bifrost-rs/Cargo.toml --workspace --offline"
assert_not_contains "${BIFROST_ONLY}" "prep_targets:"
assert_not_contains "${BIFROST_ONLY}" "test:e2e:igloo-home"

UI_ONLY="$(run_dry $'repos/igloo-ui/src/index.ts')"
assert_contains "${UI_ONLY}" "prep_targets: pwa chrome demo home"
assert_contains "${UI_ONLY}" "command: npm --prefix ${ROOT_DIR}/repos/igloo-home test"
assert_contains "${UI_ONLY}" "command: npm --prefix ${ROOT_DIR}/repos/igloo-home run test:visual"
assert_contains "${UI_ONLY}" "command: FROSTR_TEST_PREPARED=1 IGLOO_HOME_TEST_SKIP_BUILD=1 IGLOO_HOME_TEST_BINARY=${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-home"
assert_contains "${UI_ONLY}" "command: FROSTR_TEST_PREPARED=1 npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-pwa"
assert_contains "${UI_ONLY}" "command: FROSTR_TEST_PREPARED=1 npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-chrome"

MIXED="$(run_dry $'README.md\nrepos/igloo-pwa/src/App.tsx\nrepos/igloo-home/src/App.tsx')"
assert_contains "${MIXED}" "command: npm --prefix test run test:guards"
assert_contains "${MIXED}" "prep_targets: pwa home demo"
assert_contains "${MIXED}" "command: FROSTR_TEST_PREPARED=1 npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-pwa"
assert_contains "${MIXED}" "command: npm --prefix ${ROOT_DIR}/repos/igloo-home test"
assert_contains "${MIXED}" "command: npm --prefix ${ROOT_DIR}/repos/igloo-home run test:visual"
assert_contains "${MIXED}" "command: FROSTR_TEST_PREPARED=1 IGLOO_HOME_TEST_SKIP_BUILD=1 IGLOO_HOME_TEST_BINARY=${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-home"
assert_not_contains "${MIXED}" "test:e2e:igloo-chrome"

echo "ok: affected test surface selection is stable"
