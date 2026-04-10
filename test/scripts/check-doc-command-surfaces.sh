#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_SH="${ROOT_DIR}/run.sh"
README_FILE="${ROOT_DIR}/README.md"
TEST_README_FILE="${ROOT_DIR}/test/README.md"
DEV_README_FILE="${ROOT_DIR}/dev/README.md"
RELEASE_DOC_FILE="${ROOT_DIR}/dev/docs/RELEASE.md"
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

ROOT_HELP="$("${RUN_SH}" help)"
DEMO_HELP="$("${RUN_SH}" demo help)"
TEST_HELP="$("${RUN_SH}" test help)"
BROWSER_HELP="$("${RUN_SH}" browser help)"

readme_root_commands=(
  "./run.sh repo init"
  "./run.sh repo check"
  "./run.sh repo reset"
  "./run.sh demo start"
  "./run.sh demo onboard"
  "./run.sh demo smoke"
  "./run.sh test smoke"
  "./run.sh test fast"
  "./run.sh test live"
  "./run.sh test prep"
  "./run.sh test affected"
  "./run.sh test release"
  "./run.sh browser igloo-chrome build"
)

for command in "${readme_root_commands[@]}"; do
  assert_text_contains "${ROOT_HELP}" "${command}" "run.sh help"
  assert_file_contains "${README_FILE}" "${command}"
done

test_readme_npm_commands=(
  "npm run test:e2e"
  "npm run test:e2e:smoke"
  "npm run test:e2e:fast"
  "npm run test:e2e:live"
  "npm run test:e2e:demo"
  "npm run test:e2e:igloo-home"
  "npm run test:e2e:igloo-pwa"
  "npm run test:e2e:igloo-chrome"
  "npm run test:e2e:igloo-chrome:fast"
  "npm run test:e2e:igloo-chrome:live"
)

for command in "${test_readme_npm_commands[@]}"; do
  script_name="${command#npm run }"
  assert_package_has_script "${script_name}"
  assert_file_contains "${TEST_README_FILE}" "${command}"
done

test_readme_root_commands=(
  "./run.sh test smoke"
  "./run.sh test fast"
  "./run.sh test live"
  "./run.sh test demo"
  "./run.sh test e2e"
  "./run.sh test prep"
  "./run.sh test affected"
  "./run.sh test release"
)

for command in "${test_readme_root_commands[@]}"; do
  assert_text_contains "${TEST_HELP}" "${command}" "run.sh test help"
  assert_file_contains "${TEST_README_FILE}" "${command}"
done

test_readme_demo_commands=(
  "./run.sh demo start"
  "./run.sh demo onboard"
  "./run.sh demo logs"
  "./run.sh demo stop"
)

for command in "${test_readme_demo_commands[@]}"; do
  assert_text_contains "${DEMO_HELP}" "${command}" "run.sh demo help"
  assert_file_contains "${TEST_README_FILE}" "${command}"
done

assert_text_contains "${BROWSER_HELP}" "./run.sh browser <igloo-pwa|igloo-chrome> <dev|build|test:unit|test:e2e>" "run.sh browser help"
assert_file_contains "${TEST_README_FILE}" "./run.sh browser igloo-pwa dev"

release_doc_root_commands=(
  "./run.sh test prep"
  "./run.sh test release"
  "./run.sh test smoke"
  "./run.sh test fast"
  "./run.sh test live"
  "./run.sh test demo"
  "./run.sh test e2e"
)

for command in "${release_doc_root_commands[@]}"; do
  assert_text_contains "${TEST_HELP}" "${command}" "run.sh test help"
  assert_file_contains "${RELEASE_DOC_FILE}" "${command}"
done

release_doc_npm_commands=(
  "test:e2e:igloo-home"
  "test:e2e:igloo-pwa"
  "test:e2e:igloo-chrome"
)

for script_name in "${release_doc_npm_commands[@]}"; do
  assert_package_has_script "${script_name}"
  assert_file_contains "${RELEASE_DOC_FILE}" "npm --prefix test run ${script_name}"
done

assert_file_contains "${README_FILE}" "./dev/README.md"
assert_file_contains "${DEV_README_FILE}" "./docs/RELEASE.md"
assert_file_contains "${DEV_README_FILE}" "../docs/INDEX.md"
assert_file_contains "${DEV_README_FILE}" "../test/README.md"

echo "ok: documented command surfaces match run.sh help and test package scripts"
