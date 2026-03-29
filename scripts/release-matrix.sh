#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/test"
BIFROST_DIR="${ROOT_DIR}/repos/bifrost-rs"
SHELL_DIR="${ROOT_DIR}/repos/igloo-shell"
HOME_BINARY="${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home"

run_step() {
  local label="$1"
  shift
  echo "==> ${label}"
  "$@"
}

run_parallel_step() {
  local label="$1"
  shift
  echo "==> ${label}"
  "$@" &
  LAST_PID=$!
}

run_step "Prebuild shared test artifacts" bash "${ROOT_DIR}/scripts/test-prebuild.sh" release
run_step "Run bifrost-rs workspace tests" cargo test --manifest-path "${BIFROST_DIR}/Cargo.toml" --workspace --offline
run_step "Run igloo-shell CLI tests" cargo test --manifest-path "${SHELL_DIR}/Cargo.toml" -p igloo-shell-cli --offline
run_step "Run igloo-shell devnet smoke" bash -lc "cd '${SHELL_DIR}' && bash scripts/devnet.sh smoke"
run_step "Run igloo-shell node E2E" bash -lc "cd '${SHELL_DIR}' && bash scripts/test-node-e2e.sh"
run_step "Run igloo-shared typecheck" npm --prefix "${ROOT_DIR}/repos/igloo-shared" run test:typecheck

declare -A PIDS
LAST_PID=""
run_parallel_step "Run igloo-home E2E" env FROSTR_TEST_PREPARED=1 IGLOO_HOME_TEST_SKIP_BUILD=1 IGLOO_HOME_TEST_BINARY="${HOME_BINARY}" npm --prefix "${TEST_DIR}" run test:e2e:igloo-home
PIDS["igloo-home"]="${LAST_PID}"
run_parallel_step "Run igloo-pwa fast E2E" env FROSTR_TEST_PREPARED=1 IGLOO_PWA_TEST_PORT=4174 npm --prefix "${TEST_DIR}" run test:e2e:igloo-pwa:fast
PIDS["igloo-pwa:fast"]="${LAST_PID}"
run_parallel_step "Run igloo-pwa live E2E" env FROSTR_TEST_PREPARED=1 IGLOO_PWA_TEST_PORT=4175 npm --prefix "${TEST_DIR}" run test:e2e:igloo-pwa:live
PIDS["igloo-pwa:live"]="${LAST_PID}"
run_parallel_step "Run igloo-chrome fast E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:fast
PIDS["igloo-chrome:fast"]="${LAST_PID}"
run_parallel_step "Run igloo-chrome live E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:live
PIDS["igloo-chrome:live"]="${LAST_PID}"
run_parallel_step "Run igloo-chrome demo E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:demo
PIDS["igloo-chrome:demo"]="${LAST_PID}"

FAILURES=0
for label in "igloo-home" "igloo-pwa:fast" "igloo-pwa:live" "igloo-chrome:fast" "igloo-chrome:live" "igloo-chrome:demo"; do
  pid="${PIDS[$label]}"
  if ! wait "${pid}"; then
    echo "error: ${label} release-matrix step failed" >&2
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "${FAILURES}" -ne 0 ]]; then
  exit 1
fi

echo "release matrix passed"
