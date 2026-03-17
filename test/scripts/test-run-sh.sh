#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_SH="${ROOT_DIR}/run.sh"

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

HELP_OUTPUT="$("${RUN_SH}" help)"
assert_contains "${HELP_OUTPUT}" "./run.sh infra dev --bg"
assert_contains "${HELP_OUTPUT}" "./run.sh demo start [--port <port>]"

INFRA_HELP="$("${RUN_SH}" infra help)"
assert_contains "${INFRA_HELP}" "./run.sh infra reset"

DEMO_HELP="$("${RUN_SH}" demo help)"
assert_contains "${DEMO_HELP}" "./run.sh demo smoke [--port <port>]"

TEST_HELP="$("${RUN_SH}" test help)"
assert_contains "${TEST_HELP}" "./run.sh test e2e"

COMPOSE_HELP="$("${RUN_SH}" compose help)"
assert_contains "${COMPOSE_HELP}" "./run.sh compose logs <service> [service...]"

BROWSER_HELP="$("${RUN_SH}" browser help)"
assert_contains "${BROWSER_HELP}" "./run.sh browser <igloo-pwa|igloo-chrome>"

expect_fail_contains "unknown command namespace" "${RUN_SH}" nope
expect_fail_contains "Run './run.sh help'" "${RUN_SH}" infra nope
expect_fail_contains "compose start requires at least one service" "${RUN_SH}" compose start
expect_fail_contains "browser requires <app> and <action>" "${RUN_SH}" browser igloo-chrome

"${RUN_SH}" infra check >/dev/null

echo "ok: run.sh command router smoke tests passed"
