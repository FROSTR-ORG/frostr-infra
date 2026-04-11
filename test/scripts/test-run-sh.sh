#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_SH="${ROOT_DIR}/run.sh"
TRACE_DIR="$(mktemp -d)"
TRACE_BIN_DIR="${TRACE_DIR}/bin"
TRACE_FILE="${TRACE_DIR}/command-trace.log"
TRACE_HARNESS_DIR="${TRACE_DIR}/harness"

cleanup() {
  rm -rf "${TRACE_DIR}"
}

trap cleanup EXIT

mkdir -p "${TRACE_BIN_DIR}" "${TRACE_HARNESS_DIR}"

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

write_stub "ss" '#!/usr/bin/env bash
printf "ss|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

run_with_trace() {
  TRACE_FILE="${TRACE_FILE}" PATH="${TRACE_BIN_DIR}:${PATH}" "$@" >/dev/null
}

HELP_OUTPUT="$("${RUN_SH}" help)"
assert_contains "${HELP_OUTPUT}" "./run.sh repo check"
assert_contains "${HELP_OUTPUT}" "./run.sh demo start [--port <port>]"
assert_contains "${HELP_OUTPUT}" "BG=1 ./run.sh demo start"
assert_contains "${HELP_OUTPUT}" "./run.sh test prep"
assert_contains "${HELP_OUTPUT}" "./run.sh test affected"
assert_contains "${HELP_OUTPUT}" "./run.sh test release"

REPO_HELP="$("${RUN_SH}" repo help)"
assert_contains "${REPO_HELP}" "./run.sh repo reset"

DEMO_HELP="$("${RUN_SH}" demo help)"
assert_contains "${DEMO_HELP}" "./run.sh demo smoke [--port <port>]"
assert_contains "${DEMO_HELP}" "BG=1 ./run.sh demo start"

TEST_HELP="$("${RUN_SH}" test help)"
assert_contains "${TEST_HELP}" "./run.sh test e2e"
assert_contains "${TEST_HELP}" "./run.sh test prep"
assert_contains "${TEST_HELP}" "./run.sh test affected"
assert_contains "${TEST_HELP}" "./run.sh test release"

COMPOSE_HELP="$("${RUN_SH}" compose help)"
assert_contains "${COMPOSE_HELP}" "./run.sh compose logs <service> [service...]"
assert_contains "${COMPOSE_HELP}" "dev-relay"

BROWSER_HELP="$("${RUN_SH}" browser help)"
assert_contains "${BROWSER_HELP}" "./run.sh browser <igloo-pwa|igloo-chrome>"

expect_fail_contains "unknown command namespace" "${RUN_SH}" nope
expect_fail_contains "infra namespace has been retired" "${RUN_SH}" infra nope
expect_fail_contains "compose start requires at least one service" "${RUN_SH}" compose start
expect_fail_contains "browser requires <app> and <action>" "${RUN_SH}" browser igloo-chrome

reset_trace
run_with_trace "${RUN_SH}" browser igloo-chrome build
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}/repos/igloo-chrome|args=run build"

reset_trace
run_with_trace "${RUN_SH}" browser igloo-pwa build
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}/repos/igloo-pwa|args=run build"

reset_trace
run_with_trace "${RUN_SH}" test prep
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
run_with_trace env BG=1 FROSTR_TEST_HARNESS_DIR="${TRACE_HARNESS_DIR}" "${RUN_SH}" demo start --port 8394
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_contains "docker|cwd=${ROOT_DIR}|args=compose -f ${ROOT_DIR}/compose.test.yml up -d --build --remove-orphans dev-relay igloo-demo"

"${RUN_SH}" repo check >/dev/null

echo "ok: run.sh command router smoke tests passed"
