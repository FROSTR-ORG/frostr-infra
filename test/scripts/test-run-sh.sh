#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"
TRACE_DIR="$(mktemp -d)"
TRACE_BIN_DIR="${TRACE_DIR}/bin"
TRACE_FILE="${TRACE_DIR}/command-trace.log"
TRACE_HARNESS_DIR="${TRACE_DIR}/harness"
TRACE_PREBUILD_DIR="${TRACE_DIR}/prebuild"

cleanup() {
  rm -rf "${TRACE_DIR}"
}

trap cleanup EXIT

mkdir -p "${TRACE_BIN_DIR}" "${TRACE_HARNESS_DIR}" "${TRACE_PREBUILD_DIR}"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "expected output to contain: ${needle}" >&2
    exit 1
  fi
}

expect_fail_contains() {
  local needle="$1"
  shift
  set +e
  local output
  output="$("$@" 2>&1)"
  local status=$?
  set -e
  if [[ ${status} -eq 0 ]]; then
    echo "expected failure from: $*" >&2
    exit 1
  fi
  assert_contains "${output}" "${needle}"
}

assert_trace_contains() {
  local needle="$1"
  if ! grep -F --quiet -- "${needle}" "${TRACE_FILE}"; then
    echo "expected trace to contain: ${needle}" >&2
    cat "${TRACE_FILE}" >&2
    exit 1
  fi
}

reset_trace() {
  : >"${TRACE_FILE}"
}

write_stub() {
  local name="$1"
  local body="$2"
  printf '%s\n' "${body}" >"${TRACE_BIN_DIR}/${name}"
  chmod +x "${TRACE_BIN_DIR}/${name}"
}

write_stub "npm" '#!/usr/bin/env bash
printf "npm|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "cargo" '#!/usr/bin/env bash
printf "cargo|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "docker" '#!/usr/bin/env bash
printf "docker|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "python3" '#!/usr/bin/env bash
printf "python3|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "ss" '#!/usr/bin/env bash
printf "ss|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

run_with_trace() {
  TRACE_FILE="${TRACE_FILE}" PATH="${TRACE_BIN_DIR}:${PATH}" make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" "$@" >/dev/null
}

run_with_fresh_prebuild_trace() {
  local prebuild_dir
  prebuild_dir="$(mktemp -d "${TRACE_PREBUILD_DIR}/prebuild.XXXXXX")"
  TRACE_FILE="${TRACE_FILE}" \
    PATH="${TRACE_BIN_DIR}:${PATH}" \
    FROSTR_TEST_PREBUILD_DIR="${prebuild_dir}" \
    make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" "$@" >/dev/null
}

HELP_OUTPUT="$(make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" help)"
assert_contains "${HELP_OUTPUT}" "make repo-check"
assert_contains "${HELP_OUTPUT}" "make demo-start [PORT=<port>]"
assert_contains "${HELP_OUTPUT}" "make demo-foreground [PORT=<port>]"
assert_contains "${HELP_OUTPUT}" "make test-prep"
assert_contains "${HELP_OUTPUT}" "make test-affected"
assert_contains "${HELP_OUTPUT}" "make test-release"
assert_contains "${HELP_OUTPUT}" "make igloo-paper-verify [STRICT=1]"
assert_contains "${HELP_OUTPUT}" "make compose-logs SERVICES=\"<service> [service...]\""
assert_contains "${HELP_OUTPUT}" "make igloo-chrome-build"
assert_contains "${HELP_OUTPUT}" "make igloo-pwa-dev"
assert_contains "${HELP_OUTPUT}" "make igloo-home-tauri-dev"

expect_fail_contains "compose-start requires SERVICES" make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" compose-start
expect_fail_contains "compose-logs requires SERVICES" make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" compose-logs

reset_trace
run_with_trace igloo-chrome-build
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build"

reset_trace
run_with_trace igloo-pwa-build
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build"

reset_trace
run_with_trace igloo-home-test-unit
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-home run test:unit"

reset_trace
run_with_trace igloo-paper-verify
assert_trace_contains "python3|cwd=${ROOT_DIR}|args=${ROOT_DIR}/repos/igloo-paper/scripts/verify.py"

reset_trace
run_with_trace igloo-paper-verify STRICT=1
assert_trace_contains "python3|cwd=${ROOT_DIR}|args=${ROOT_DIR}/repos/igloo-paper/scripts/verify.py --strict-drift"

reset_trace
run_with_fresh_prebuild_trace test-prep
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"

cat >"${TRACE_HARNESS_DIR}/onboard-bob.txt" <<'EOF'
bfonboard1bob-demo
EOF
cat >"${TRACE_HARNESS_DIR}/onboard-bob.password.txt" <<'EOF'
bob-password
EOF
cat >"${TRACE_HARNESS_DIR}/onboard-carol.txt" <<'EOF'
bfonboard1carol-demo
EOF
cat >"${TRACE_HARNESS_DIR}/onboard-carol.password.txt" <<'EOF'
carol-password
EOF

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_HARNESS_DIR="${TRACE_HARNESS_DIR}" \
  FROSTR_TEST_PREBUILD_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/demo.XXXXXX")" \
  make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" demo-start PORT=8394 >/dev/null
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_contains "cargo|cwd=${ROOT_DIR}/repos/bifrost-rs|args=build --offline --locked -p bifrost-devtools --bin bifrost-devtools"
assert_trace_contains "cargo|cwd=${ROOT_DIR}/repos/igloo-shell|args=build --offline --locked -p igloo-shell-cli --bin igloo-shell"
assert_trace_contains "docker|cwd=${ROOT_DIR}|args=compose -f ${ROOT_DIR}/compose.test.yml up -d --build --remove-orphans dev-relay igloo-demo"

make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" repo-check >/dev/null

echo "ok: make command surface smoke tests passed"
