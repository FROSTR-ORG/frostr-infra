#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"
TRACE_DIR="$(mktemp -d)"
TRACE_BIN_DIR="${TRACE_DIR}/bin"
TRACE_FILE="${TRACE_DIR}/command-trace.log"
TRACE_HARNESS_DIR="${TRACE_DIR}/harness"
TRACE_PREBUILD_DIR="${TRACE_DIR}/prebuild"
TRACE_IGLOO_PAPER_DIR="${TRACE_DIR}/igloo-paper"

cleanup() {
  rm -rf "${TRACE_DIR}"
}

trap cleanup EXIT

mkdir -p \
  "${TRACE_BIN_DIR}" \
  "${TRACE_DIR}/.cargo/bin" \
  "${TRACE_HARNESS_DIR}" \
  "${TRACE_PREBUILD_DIR}" \
  "${TRACE_DIR}/wasm-target-lib" \
  "${TRACE_IGLOO_PAPER_DIR}/scripts"
: >"${TRACE_IGLOO_PAPER_DIR}/scripts/verify.py"
: >"${TRACE_IGLOO_PAPER_DIR}/scripts/export_from_paper.py"
: >"${TRACE_IGLOO_PAPER_DIR}/scripts/update_usage_coverage.py"
mkdir -p "${TRACE_DIR}/repos/igloo-paper/design/tokens" "${TRACE_DIR}/repos/igloo-ui/src/tokens"

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

assert_trace_not_contains() {
  local needle="$1"
  if grep -F --quiet -- "${needle}" "${TRACE_FILE}"; then
    echo "expected trace not to contain: ${needle}" >&2
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
printf "npm|cwd=%s|args=%s|shared_out=%s|wasm_source=%s|wasm_target=%s|pwa_wasm=%s|chrome_wasm=%s\n" "$PWD" "$*" "${IGLOO_SHARED_BROWSER_WASM_OUT_DIR:-}" "${IGLOO_BROWSER_WASM_SOURCE_DIR:-}" "${IGLOO_BROWSER_WASM_TARGET_DIR:-}" "${IGLOO_PWA_WASM_SOURCE_DIR:-}" "${IGLOO_CHROME_WASM_SOURCE_DIR:-}" >>"${TRACE_FILE}"
if [[ -n "${IGLOO_SHARED_BROWSER_WASM_OUT_DIR:-}" ]]; then
  mkdir -p "${IGLOO_SHARED_BROWSER_WASM_OUT_DIR}"
  cp -R "${ROOT_DIR}/repos/igloo-shared/public/wasm/." "${IGLOO_SHARED_BROWSER_WASM_OUT_DIR}/"
fi
if [[ -n "${IGLOO_BROWSER_WASM_SOURCE_DIR:-}" && -n "${IGLOO_BROWSER_WASM_TARGET_DIR:-}" ]]; then
  mkdir -p "${IGLOO_BROWSER_WASM_TARGET_DIR}"
  cp -R "${IGLOO_BROWSER_WASM_SOURCE_DIR}/." "${IGLOO_BROWSER_WASM_TARGET_DIR}/"
fi
exit 0'

write_stub "cargo" '#!/usr/bin/env bash
printf "cargo|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "rustup" '#!/usr/bin/env bash
printf "rustup|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "rustc" '#!/usr/bin/env bash
if [[ "$*" == "--print target-libdir --target wasm32-unknown-unknown" ]]; then
  printf "%s/wasm-target-lib\n" "${TRACE_DIR}"
  exit 0
fi
printf "rustc|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "wasm-pack" '#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf "wasm-pack 0.14.0\n"
  exit 0
fi
printf "wasm-pack|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "clang" '#!/usr/bin/env bash
if [[ "$*" == *"--target=wasm32-unknown-unknown"* ]]; then
  exit 0
fi
printf "clang|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "docker" '#!/usr/bin/env bash
printf "docker|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "python3" '#!/usr/bin/env bash
printf "python3|cwd=%s|py_dont=%s|args=%s\n" "$PWD" "${PYTHONDONTWRITEBYTECODE:-}" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "node" '#!/usr/bin/env bash
printf "node|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "lsof" '#!/usr/bin/env bash
printf "lsof|cwd=%s|args=%s|state=%s\n" "$PWD" "$*" "${IGLOO_PWA_DEV_TEST_PORT_STATE:-free}" >>"${TRACE_FILE}"
case "${IGLOO_PWA_DEV_TEST_PORT_STATE:-free}" in
  free)
    exit 1
    ;;
  occupied)
    printf "4242\n"
    exit 0
    ;;
  multi)
    printf "4242\n4343\n"
    exit 0
    ;;
  clears)
    state_file="${TRACE_DIR}/pwa-port-clears.state"
    if [[ -f "${state_file}" ]]; then
      exit 1
    fi
    printf "4242\n"
    : >"${state_file}"
    exit 0
    ;;
esac
exit 1'

write_stub "igloo-test-kill" '#!/usr/bin/env bash
printf "kill|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "igloo-test-sleep" '#!/usr/bin/env bash
printf "sleep|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

write_stub "ss" '#!/usr/bin/env bash
printf "ss|cwd=%s|args=%s\n" "$PWD" "$*" >>"${TRACE_FILE}"
exit 0'

cp "${TRACE_BIN_DIR}/cargo" "${TRACE_DIR}/.cargo/bin/cargo"
cp "${TRACE_BIN_DIR}/rustc" "${TRACE_DIR}/.cargo/bin/rustc"
cp "${TRACE_BIN_DIR}/rustup" "${TRACE_DIR}/.cargo/bin/rustup"
cp "${TRACE_BIN_DIR}/wasm-pack" "${TRACE_DIR}/.cargo/bin/wasm-pack"

run_with_trace() {
  TRACE_FILE="${TRACE_FILE}" TRACE_DIR="${TRACE_DIR}" ROOT_DIR="${ROOT_DIR}" PATH="${TRACE_BIN_DIR}:${PATH}" make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" "$@" >/dev/null
}

run_with_fresh_prebuild_trace() {
  local prebuild_dir
  prebuild_dir="$(mktemp -d "${TRACE_PREBUILD_DIR}/prebuild.XXXXXX")"
  TRACE_FILE="${TRACE_FILE}" \
    TRACE_DIR="${TRACE_DIR}" \
    ROOT_DIR="${ROOT_DIR}" \
    PATH="${TRACE_BIN_DIR}:${PATH}" \
    FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK=1 \
    FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
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
assert_contains "${HELP_OUTPUT}" "make browser-wasm-refresh"
assert_contains "${HELP_OUTPUT}" "make browser-wasm-check"
assert_contains "${HELP_OUTPUT}" "make wasm-toolchain-check"
assert_contains "${HELP_OUTPUT}" "make igloo-paper-sync [STRICT=1]"
assert_contains "${HELP_OUTPUT}" "make igloo-paper-verify [STRICT=1]"
assert_contains "${HELP_OUTPUT}" "make igloo-paper-usage-coverage-sync"
assert_contains "${HELP_OUTPUT}" "make igloo-ui-paper-token-sync"
assert_contains "${HELP_OUTPUT}" "make igloo-ui-paper-token-check"
assert_contains "${HELP_OUTPUT}" "make compose-logs SERVICES=\"<service> [service...]\""
assert_contains "${HELP_OUTPUT}" "make igloo-chrome-build"
assert_contains "${HELP_OUTPUT}" "make igloo-pwa-dev"
assert_contains "${HELP_OUTPUT}" "make igloo-home-package-release"
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
run_with_trace igloo-pwa-dev
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run dev"
assert_trace_contains "lsof|cwd=${ROOT_DIR}|args=-nP -iTCP:1430 -sTCP:LISTEN -t|state=free"

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_PWA_DEV_TEST_PORT_STATE=occupied \
  IGLOO_PWA_DEV_ASSUME_TTY=1 \
  IGLOO_PWA_DEV_KILL_BIN="${TRACE_BIN_DIR}/igloo-test-kill" \
  IGLOO_PWA_DEV_SLEEP_BIN="${TRACE_BIN_DIR}/igloo-test-sleep" \
  bash -c 'printf "n\n" | "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"' >"${TRACE_DIR}/igloo-pwa-dev-decline.out" 2>&1 || true
assert_contains "$(cat "${TRACE_DIR}/igloo-pwa-dev-decline.out")" "Port 1430 is already in use by PID 4242"
assert_trace_not_contains "kill|"
assert_trace_not_contains "npm|"

reset_trace
rm -f "${TRACE_DIR}/pwa-port-clears.state"
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_PWA_DEV_TEST_PORT_STATE=clears \
  IGLOO_PWA_DEV_ASSUME_TTY=1 \
  IGLOO_PWA_DEV_KILL_BIN="${TRACE_BIN_DIR}/igloo-test-kill" \
  IGLOO_PWA_DEV_SLEEP_BIN="${TRACE_BIN_DIR}/igloo-test-sleep" \
  bash -c 'printf "y\n" | "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"' >/dev/null 2>&1
assert_trace_contains "kill|cwd=${ROOT_DIR}|args=-TERM 4242"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run dev"

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_PWA_DEV_TEST_PORT_STATE=occupied \
  IGLOO_PWA_DEV_KILL_BIN="${TRACE_BIN_DIR}/igloo-test-kill" \
  IGLOO_PWA_DEV_SLEEP_BIN="${TRACE_BIN_DIR}/igloo-test-sleep" \
expect_fail_contains "Port 1430 is already in use by PID 4242" "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"
assert_trace_not_contains "kill|"
assert_trace_not_contains "npm|"

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_PWA_DEV_TEST_PORT_STATE=multi \
  IGLOO_PWA_DEV_KILL_BIN="${TRACE_BIN_DIR}/igloo-test-kill" \
  IGLOO_PWA_DEV_SLEEP_BIN="${TRACE_BIN_DIR}/igloo-test-sleep" \
  expect_fail_contains "Port 1430 is already in use by PIDs: 4242, 4343" "${ROOT_DIR}/scripts/igloo-pwa-dev.sh"
assert_trace_not_contains "kill|"
assert_trace_not_contains "npm|"

reset_trace
run_with_trace igloo-home-test-unit
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-home run test:unit"

HOME_PACKAGE_FIXTURE="${TRACE_DIR}/home-package"
mkdir -p \
  "${HOME_PACKAGE_FIXTURE}/home/src-tauri" \
  "${HOME_PACKAGE_FIXTURE}/bundle/appimage" \
  "${HOME_PACKAGE_FIXTURE}/stage"
printf '{"name":"igloo-home","version":"0.2.0"}\n' >"${HOME_PACKAGE_FIXTURE}/home/package.json"
printf '{"productName":"Igloo Home","version":"0.2.0"}\n' >"${HOME_PACKAGE_FIXTURE}/home/src-tauri/tauri.conf.json"
printf 'fixture-appimage' >"${HOME_PACKAGE_FIXTURE}/bundle/appimage/Igloo Home_0.2.0_amd64.AppImage"

TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_HOME_PACKAGE_HOME_DIR="${HOME_PACKAGE_FIXTURE}/home" \
  IGLOO_HOME_PACKAGE_BUNDLE_DIR="${HOME_PACKAGE_FIXTURE}/bundle" \
  IGLOO_HOME_PACKAGE_STAGE_ROOT="${HOME_PACKAGE_FIXTURE}/stage" \
  IGLOO_HOME_PACKAGE_OS="Linux" \
  IGLOO_HOME_PACKAGE_SKIP_BUILD=1 \
  IGLOO_HOME_PACKAGE_TIMESTAMP="2026-06-27T00:00:00Z" \
  IGLOO_HOME_PACKAGE_PARENT_COMMIT="parent-fixture" \
  IGLOO_HOME_PACKAGE_HOME_COMMIT="home-fixture" \
  make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" igloo-home-package-release >/dev/null

assert_contains "$(cat "${HOME_PACKAGE_FIXTURE}/stage/0.2.0/SHA256SUMS")" "Igloo Home_0.2.0_amd64.AppImage"

reset_trace
run_with_trace browser-wasm-refresh
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"

reset_trace
run_with_trace wasm-toolchain-check

reset_trace
run_with_trace IGLOO_PAPER_DIR="${TRACE_IGLOO_PAPER_DIR}" igloo-paper-verify
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/verify.py"

reset_trace
run_with_trace IGLOO_PAPER_DIR="${TRACE_IGLOO_PAPER_DIR}" igloo-paper-verify STRICT=1
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/verify.py --strict-drift"

reset_trace
run_with_trace IGLOO_PAPER_DIR="${TRACE_IGLOO_PAPER_DIR}" igloo-paper-usage-coverage-sync
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/update_usage_coverage.py"

reset_trace
run_with_trace IGLOO_PAPER_DIR="${TRACE_IGLOO_PAPER_DIR}" igloo-paper-sync
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/export_from_paper.py"
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/verify.py --strict-drift"

reset_trace
run_with_trace IGLOO_PAPER_DIR="${TRACE_IGLOO_PAPER_DIR}" igloo-paper-sync STRICT=0
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/export_from_paper.py"
assert_trace_contains "python3|cwd=${TRACE_IGLOO_PAPER_DIR}|py_dont=1|args=scripts/verify.py"

reset_trace
run_with_trace ROOT_DIR="${TRACE_DIR}" igloo-ui-paper-token-sync
assert_trace_contains "node|cwd=${TRACE_DIR}|args=dev/scripts/sync-igloo-paper-tokens-to-ui.mjs sync"

reset_trace
run_with_trace ROOT_DIR="${TRACE_DIR}" igloo-ui-paper-token-check
assert_trace_contains "node|cwd=${TRACE_DIR}|args=dev/scripts/sync-igloo-paper-tokens-to-ui.mjs check"

reset_trace
run_with_fresh_prebuild_trace test-prep
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_contains "npm|cwd=${ROOT_DIR}|args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_contains "shared_out=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_source=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_target=${TRACE_PREBUILD_DIR}"

reset_trace
PWA_RUNTIME_PREBUILD_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/pwa-runtime.XXXXXX")"
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK=1 \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_TEST_PREBUILD_DIR="${PWA_RUNTIME_PREBUILD_DIR}" \
  "${ROOT_DIR}/scripts/test-prebuild.sh" sync pwa-runtime >/dev/null
assert_trace_contains "args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_not_contains "args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_not_contains "args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:app"
test -f "${PWA_RUNTIME_PREBUILD_DIR}/stamps/pwa-runtime.state"

reset_trace
CHROME_RUNTIME_PREBUILD_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/chrome-runtime.XXXXXX")"
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK=1 \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_TEST_PREBUILD_DIR="${CHROME_RUNTIME_PREBUILD_DIR}" \
  "${ROOT_DIR}/scripts/test-prebuild.sh" sync chrome-runtime >/dev/null
assert_trace_contains "args=--prefix ${ROOT_DIR}/repos/igloo-shared run build:browser-wasm"
assert_trace_contains "args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:browser-wasm"
assert_trace_not_contains "args=--prefix ${ROOT_DIR}/repos/igloo-pwa run build:browser-wasm"
assert_trace_not_contains "args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:app"
test -f "${CHROME_RUNTIME_PREBUILD_DIR}/stamps/chrome-runtime.state"

reset_trace
CHROME_PREBUILD_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/chrome.XXXXXX")"
TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK=1 \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_TEST_PREBUILD_DIR="${CHROME_PREBUILD_DIR}" \
  "${ROOT_DIR}/scripts/test-prebuild.sh" sync chrome >/dev/null
assert_trace_contains "args=--prefix ${ROOT_DIR}/repos/igloo-chrome run build:app"
assert_trace_contains "chrome_wasm=${CHROME_PREBUILD_DIR}/browser-wasm/igloo-chrome/public/wasm"

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_BROWSER_WASM_CHECK_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/wasm-check.XXXXXX")" \
  WASM_CC="${TRACE_BIN_DIR}/clang" \
  "${ROOT_DIR}/scripts/prepare-browser-wasm.sh" check pwa >/dev/null
assert_trace_contains "shared_out=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_source=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_target=${TRACE_PREBUILD_DIR}"

reset_trace
TRACE_FILE="${TRACE_FILE}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_BROWSER_WASM_PREPARE_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/wasm-prepare.XXXXXX")" \
  WASM_CC="${TRACE_BIN_DIR}/clang" \
  "${ROOT_DIR}/scripts/prepare-browser-wasm.sh" prepare pwa >/dev/null
assert_trace_contains "shared_out=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_source=${TRACE_PREBUILD_DIR}"
assert_trace_contains "wasm_target=${TRACE_PREBUILD_DIR}"

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
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK=1 \
  FROSTR_TEST_PREBUILD_SKIP_WASM_TARGET_CHECK=1 \
  FROSTR_TEST_HARNESS_DIR="${TRACE_HARNESS_DIR}" \
  FROSTR_TEST_PREBUILD_DIR="$(mktemp -d "${TRACE_PREBUILD_DIR}/demo.XXXXXX")" \
  make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" demo-start PORT=8394 >/dev/null
# demo-start builds the demo images in-Docker (services/demo/Dockerfile compiles
# bifrost-devtools / igloo-shell and the browser WASM), so there are deliberately
# NO host-side `npm run build:browser-wasm` / `cargo build` steps to trace —
# `compose up --build` is fully self-contained. Asserting the compose invocation
# is what proves the in-Docker build path is wired.
assert_trace_contains "docker|cwd=${ROOT_DIR}|args=compose -f ${ROOT_DIR}/compose.test.yml up -d --build --remove-orphans dev-relay igloo-demo"

TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  HOME="${TRACE_DIR}" \
  PATH="${TRACE_DIR}/.cargo/bin:${TRACE_BIN_DIR}:${PATH}" \
  WASM_CC="${TRACE_BIN_DIR}/clang" \
  make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" repo-check >/dev/null

echo "ok: make command surface smoke tests passed"
