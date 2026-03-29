#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/test"
CHROME_DIR="${ROOT_DIR}/repos/igloo-chrome"
SHARED_DIR="${ROOT_DIR}/repos/igloo-shared"
BIFROST_DIR="${ROOT_DIR}/repos/bifrost-rs"
SHELL_DIR="${ROOT_DIR}/repos/igloo-shell"

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

run_step "Prebuild shared bridge wasm artifacts" npm --prefix "${CHROME_DIR}" run build:bridge-wasm
run_step "Run bifrost-rs workspace tests" cargo test --manifest-path "${BIFROST_DIR}/Cargo.toml" --workspace --offline
run_step "Run igloo-shell CLI tests" cargo test --manifest-path "${SHELL_DIR}/Cargo.toml" -p igloo-shell-cli --offline
run_step "Run igloo-shell devnet smoke" bash -lc "cd '${SHELL_DIR}' && bash scripts/devnet.sh smoke"
run_step "Run igloo-shell node E2E" bash -lc "cd '${SHELL_DIR}' && bash scripts/test-node-e2e.sh"
run_step "Run igloo-shared typecheck" npm --prefix "${SHARED_DIR}" run test:typecheck

declare -A PIDS
LAST_PID=""
run_parallel_step "Run igloo-home E2E" npm --prefix "${TEST_DIR}" run test:e2e:igloo-home
PIDS["igloo-home"]="${LAST_PID}"
run_parallel_step "Run igloo-pwa E2E" npm --prefix "${TEST_DIR}" run test:e2e:igloo-pwa
PIDS["igloo-pwa"]="${LAST_PID}"
run_parallel_step "Run igloo-chrome E2E" npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome
PIDS["igloo-chrome"]="${LAST_PID}"

FAILURES=0
for label in "igloo-home" "igloo-pwa" "igloo-chrome"; do
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
