#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"
TEST_DIR="${ROOT_DIR}/test"
BIFROST_DIR="${ROOT_DIR}/repos/bifrost-rs"
SHELL_DIR="${ROOT_DIR}/repos/igloo-shell"
HOME_BINARY="${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home"
TIMING_DIR="$(resolve_workspace_scratch_dir FROSTR_TEST_PREBUILD_DIR test-prebuild)"
TIMING_FILE="${TIMING_DIR}/release-matrix-timings.tsv"
printf 'phase\telapsed_seconds\tstatus\n' >"${TIMING_FILE}"

declare -a TIMING_ROWS=()
TOTAL_STARTED_AT="$(date +%s)"

record_timing() {
  local phase="$1"
  local started_at="$2"
  local status="$3"
  local finished_at
  local elapsed
  finished_at="$(date +%s)"
  elapsed="$((finished_at - started_at))"
  TIMING_ROWS+=("${elapsed}\t${phase}\t${status}")
  printf '%s\t%s\t%s\n' "${phase}" "${elapsed}" "${status}" >>"${TIMING_FILE}"
}

run_step() {
  local label="$1"
  shift
  local started_at
  local status=0
  started_at="$(date +%s)"
  echo "==> ${label}"
  set +e
  "$@"
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    record_timing "${label}" "${started_at}" ok
    return 0
  fi
  record_timing "${label}" "${started_at}" failed
  return "${status}"
}

run_parallel_step() {
  local label="$1"
  shift
  echo "==> ${label}"
  "$@" &
  LAST_PID=$!
  LAST_LABEL="${label}"
  LAST_STARTED_AT="$(date +%s)"
}

print_timing_summary() {
  local total_elapsed
  total_elapsed="$(( $(date +%s) - TOTAL_STARTED_AT ))"
  echo "==> Release timing summary"
  echo "total_elapsed_seconds=${total_elapsed}"
  while IFS=$'\t' read -r phase elapsed status; do
    if [[ "${phase}" == "phase" ]]; then
      continue
    fi
    printf '%s\t%ss\t%s\n' "${phase}" "${elapsed}" "${status}"
  done <"${TIMING_FILE}"
  echo "slowest_phases:"
  printf '%b\n' "${TIMING_ROWS[@]}" | sort -rn | head -n 3 | while IFS=$'\t' read -r elapsed phase status; do
    printf '%s\t%ss\t%s\n' "${phase}" "${elapsed}" "${status}"
  done
  echo "timings_file=${TIMING_FILE}"
}

if ! run_step "Prebuild shared test artifacts" bash "${ROOT_DIR}/scripts/test-prebuild.sh" release; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run bifrost-rs workspace tests" cargo test --manifest-path "${BIFROST_DIR}/Cargo.toml" --workspace --offline; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-shell CLI tests" cargo test --manifest-path "${SHELL_DIR}/Cargo.toml" -p igloo-shell-cli --offline; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-shell devnet smoke" bash -lc "cd '${SHELL_DIR}' && bash scripts/devnet.sh smoke"; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-shell node E2E" bash -lc "cd '${SHELL_DIR}' && bash scripts/test-node-e2e.sh"; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-shared typecheck" npm --prefix "${ROOT_DIR}/repos/igloo-shared" run test:typecheck; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-pwa fast E2E" env FROSTR_TEST_PREPARED=1 IGLOO_PWA_TEST_PORT=4174 npm --prefix "${TEST_DIR}" run test:e2e:igloo-pwa:fast; then
  print_timing_summary
  exit 1
fi
if ! run_step "Run igloo-pwa live E2E" env FROSTR_TEST_PREPARED=1 IGLOO_PWA_TEST_PORT=4175 npm --prefix "${TEST_DIR}" run test:e2e:igloo-pwa:live; then
  print_timing_summary
  exit 1
fi

declare -A PIDS
declare -A STEP_LABELS
declare -A STEP_STARTED_AT
LAST_PID=""
LAST_LABEL=""
LAST_STARTED_AT=""
run_parallel_step "Run igloo-home E2E" env FROSTR_TEST_PREPARED=1 IGLOO_HOME_TEST_SKIP_BUILD=1 IGLOO_HOME_TEST_BINARY="${HOME_BINARY}" npm --prefix "${TEST_DIR}" run test:e2e:igloo-home
PIDS["igloo-home"]="${LAST_PID}"
STEP_LABELS["igloo-home"]="${LAST_LABEL}"
STEP_STARTED_AT["igloo-home"]="${LAST_STARTED_AT}"
run_parallel_step "Run igloo-chrome fast E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:fast
PIDS["igloo-chrome:fast"]="${LAST_PID}"
STEP_LABELS["igloo-chrome:fast"]="${LAST_LABEL}"
STEP_STARTED_AT["igloo-chrome:fast"]="${LAST_STARTED_AT}"
run_parallel_step "Run igloo-chrome live E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:live
PIDS["igloo-chrome:live"]="${LAST_PID}"
STEP_LABELS["igloo-chrome:live"]="${LAST_LABEL}"
STEP_STARTED_AT["igloo-chrome:live"]="${LAST_STARTED_AT}"
run_parallel_step "Run igloo-chrome demo E2E" env FROSTR_TEST_PREPARED=1 npm --prefix "${TEST_DIR}" run test:e2e:igloo-chrome:demo
PIDS["igloo-chrome:demo"]="${LAST_PID}"
STEP_LABELS["igloo-chrome:demo"]="${LAST_LABEL}"
STEP_STARTED_AT["igloo-chrome:demo"]="${LAST_STARTED_AT}"

FAILURES=0
for label in "igloo-home" "igloo-chrome:fast" "igloo-chrome:live" "igloo-chrome:demo"; do
  pid="${PIDS[$label]}"
  if ! wait "${pid}"; then
    echo "error: ${label} release-matrix step failed" >&2
    record_timing "${STEP_LABELS[$label]}" "${STEP_STARTED_AT[$label]}" failed
    FAILURES=$((FAILURES + 1))
  else
    record_timing "${STEP_LABELS[$label]}" "${STEP_STARTED_AT[$label]}" ok
  fi
done

if [[ "${FAILURES}" -ne 0 ]]; then
  print_timing_summary
  exit 1
fi

print_timing_summary
echo "release matrix passed"
