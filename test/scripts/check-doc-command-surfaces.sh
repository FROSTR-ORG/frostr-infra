#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"
README_FILE="${ROOT_DIR}/README.md"
TEST_README_FILE="${ROOT_DIR}/test/README.md"
DEV_README_FILE="${ROOT_DIR}/dev/README.md"
DEV_WORKFLOWS_FILE="${ROOT_DIR}/dev/docs/WORKFLOWS.md"
TEST_WORKFLOWS_FILE="${ROOT_DIR}/test/docs/WORKFLOWS.md"
RELEASE_DOC_FILE="${ROOT_DIR}/dev/docs/RELEASE.md"
CONTRIBUTING_FILE="${ROOT_DIR}/CONTRIBUTING.md"
AGENTS_FILE="${ROOT_DIR}/AGENTS.md"
TEST_PACKAGE_FILE="${ROOT_DIR}/test/package.json"

assert_text_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "${label}: expected text to contain '${needle}'" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${file}"; then
    echo "${file}: expected to contain '${needle}'" >&2
    exit 1
  fi
}

assert_package_has_script() {
  local script_name="$1"
  if ! grep -Fq "\"${script_name}\":" "${TEST_PACKAGE_FILE}"; then
    echo "${TEST_PACKAGE_FILE}: expected npm script '${script_name}'" >&2
    exit 1
  fi
}

HELP_OUTPUT="$(make -s -f "${MAKEFILE}" help)"

root_commands=(
  "make repo-init"
  "make repo-check"
  "make repo-reset"
  "make demo-start"
  "make demo-foreground"
  "make demo-onboard"
  "make demo-smoke"
  "make test-smoke"
  "make test-fast"
  "make test-live"
  "make test-demo"
  "make test-prep"
  "make test-affected"
  "make test-release"
  "make browser-wasm-refresh"
  "make browser-wasm-sync"
  "make browser-wasm-check"
  "make wasm-toolchain-check"
  "make igloo-chrome-build"
  "make igloo-pwa-dev"
  "make igloo-home-package-release"
  "make igloo-home-tauri-dev"
  "make igloo-paper-sync"
  "make igloo-paper-verify"
  "make igloo-ui-paper-token-sync"
  "make igloo-ui-paper-token-check"
)

for command in "${root_commands[@]}"; do
  assert_text_contains "${HELP_OUTPUT}" "${command}" "make help"
done

for command in \
  "make repo-init" \
  "make repo-check" \
  "make repo-reset" \
  "make demo-start" \
  "make demo-onboard" \
  "make demo-smoke" \
  "make test-smoke" \
  "make test-fast" \
  "make test-live" \
  "make test-demo" \
  "make test-prep" \
  "make test-affected" \
  "make test-release" \
  "make browser-wasm-refresh" \
  "make browser-wasm-check" \
  "make wasm-toolchain-check" \
  "make igloo-paper-sync" \
  "make igloo-paper-verify" \
  "make igloo-ui-paper-token-sync" \
  "make igloo-ui-paper-token-check" \
  "make igloo-chrome-build" \
  "make igloo-home-package-release"; do
  assert_file_contains "${README_FILE}" "${command}"
done

for command in \
  "make repo-init" \
  "make repo-check" \
  "make demo-start" \
  "make test-prep" \
  "make test-affected" \
  "make test-release" \
  "make repo-reset"; do
  assert_file_contains "${AGENTS_FILE}" "${command}"
done

test_readme_npm_commands=(
  "npm run test:e2e"
  "npm run test:e2e:smoke"
  "npm run test:e2e:fast"
  "npm run test:e2e:live"
  "npm run test:e2e:demo"
  "npm run test:e2e:igloo-home"
  "npm run test:e2e:igloo-pwa"
  "npm run test:e2e:igloo-pwa:visual"
  "npm run test:e2e:igloo-pwa:cross"
  "npm run test:e2e:igloo-chrome"
  "npm run test:e2e:igloo-chrome:fast"
  "npm run test:e2e:igloo-chrome:live"
  "npm run test:guards:pwa"
  "npm run test:guards:chrome"
  "npm run test:guards:home"
  "npm run test:guards:wasm"
  "npm run test:guards:wasm:strict"
  "npm run test:guards:visual"
  "npm run test:typecheck:pwa"
  "npm run test:typecheck:chrome"
  "npm run test:typecheck:home"
  "npm run test:typecheck:strict-support"
  "npm run test:typecheck:strict-helpers"
  "npm run test:typecheck:strict-visual-specs"
)

for command in "${test_readme_npm_commands[@]}"; do
  script_name="${command#npm run }"
  assert_package_has_script "${script_name}"
  assert_file_contains "${TEST_README_FILE}" "${command}"
done

for command in \
  "make test-smoke" \
  "make test-fast" \
  "make test-live" \
  "make test-demo" \
  "make test-e2e" \
  "make test-prep" \
  "make test-affected" \
  "make test-release" \
  "make demo-start" \
  "make demo-onboard" \
  "make demo-logs" \
  "make demo-stop" \
  "make igloo-pwa-dev" \
  "make igloo-home-tauri-dev"; do
  assert_file_contains "${TEST_README_FILE}" "${command}"
done

for command in \
  "make test-prep" \
  "make test-release" \
  "make test-smoke" \
  "make test-fast" \
  "make test-live" \
  "make test-demo" \
  "make test-e2e"; do
  assert_file_contains "${RELEASE_DOC_FILE}" "${command}"
done

for script_name in \
  "test:e2e:igloo-home" \
  "test:e2e:igloo-pwa" \
  "test:e2e:igloo-pwa:visual" \
  "test:e2e:igloo-pwa:cross" \
  "test:e2e:igloo-chrome"; do
  assert_package_has_script "${script_name}"
  assert_file_contains "${RELEASE_DOC_FILE}" "npm --prefix test run ${script_name}"
done

assert_file_contains "${README_FILE}" "./dev/README.md"
assert_file_contains "${DEV_README_FILE}" "./docs/RELEASE.md"
assert_file_contains "${DEV_README_FILE}" "./docs/WORKFLOWS.md"
assert_file_contains "${DEV_README_FILE}" "../docs/INDEX.md"
assert_file_contains "${DEV_README_FILE}" "../test/README.md"
assert_file_contains "${DEV_README_FILE}" "../test/docs/WORKFLOWS.md"
assert_file_contains "${TEST_README_FILE}" "./docs/WORKFLOWS.md"
assert_file_contains "${AGENTS_FILE}" "dev/docs/WORKFLOWS.md"
assert_file_contains "${AGENTS_FILE}" "test/docs/WORKFLOWS.md"
assert_file_contains "${AGENTS_FILE}" "dev/docs/DESIGN.md"
assert_file_contains "${AGENTS_FILE}" "dev/docs/RELEASE.md"
assert_file_contains "${DEV_WORKFLOWS_FILE}" "Documentation Drift"
assert_file_contains "${DEV_WORKFLOWS_FILE}" "Follow-Up Harvest"
assert_file_contains "${TEST_WORKFLOWS_FILE}" "Client-Scoped Validation"
assert_file_contains "${TEST_WORKFLOWS_FILE}" "Browser WASM"
assert_file_contains "${TEST_WORKFLOWS_FILE}" "test:guards:visual"
assert_file_contains "${TEST_WORKFLOWS_FILE}" "test:guards:wasm:strict"
assert_file_contains "${RELEASE_DOC_FILE}" "npm --prefix test run test:guards:wasm:strict"
assert_file_contains "${TEST_README_FILE}" "FROSTR_TEST_SKIP_STRICT_WASM=1"
assert_file_contains "${CONTRIBUTING_FILE}" "Makefile"
assert_file_contains "${AGENTS_FILE}" "make"

echo "ok: documented command surfaces match Makefile help and test package scripts"
