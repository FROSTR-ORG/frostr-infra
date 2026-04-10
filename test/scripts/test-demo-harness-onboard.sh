#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_NAME="igloo-demo-smoke-$$"
RELAY_PORT="${RELAY_PORT:-8394}"
RECIPIENT="${RECIPIENT:-bob}"
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/igloo-demo-artifacts.XXXXXX")"
CONTAINER_ARTIFACT_DIR="${FROSTR_TEST_HARNESS_CONTAINER_DIR:-/workspace/.tmp/test-harness/${PROJECT_NAME}}"
XDG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/igloo-demo-shell.XXXXXX")"
IGLOO_SHELL_BIN="${ROOT_DIR}/repos/igloo-shell/target/debug/igloo-shell"
PROFILE_ID=""

cleanup() {
  if [[ -n "${PROFILE_ID}" ]]; then
    env \
      XDG_CONFIG_HOME="${XDG_ROOT}/config" \
      XDG_DATA_HOME="${XDG_ROOT}/data" \
      XDG_STATE_HOME="${XDG_ROOT}/state" \
      IGLOO_SHELL_PROFILE_PASSPHRASE="demo-harness-smoke-pass" \
      "${IGLOO_SHELL_BIN}" daemon stop --profile "${PROFILE_ID}" >/dev/null 2>&1 || true
  fi
  env DEV_RELAY_PORT="${RELAY_PORT}" docker compose -p "${PROJECT_NAME}" -f "${ROOT_DIR}/compose.test.yml" down -v >/dev/null 2>&1 || true
  rm -rf "${ARTIFACT_DIR}" "${XDG_ROOT}"
}
trap cleanup EXIT INT TERM

wait_for_file() {
  local path="$1"
  local attempts="${2:-120}"
  local try
  for ((try = 1; try <= attempts; try++)); do
    if [[ -s "${path}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for ${path}" >&2
  return 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd cargo

"${ROOT_DIR}/scripts/demo.sh" build-binaries

env \
  DEV_RELAY_PORT="${RELAY_PORT}" \
  DEV_RELAY_EXTERNAL_HOST="localhost" \
  FROSTR_TEST_HARNESS_DIR="${ARTIFACT_DIR}" \
  FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_ARTIFACT_DIR}" \
  IGLOO_SHELL_DEMO_ARTIFACT_DIR="${CONTAINER_ARTIFACT_DIR}" \
  docker compose -p "${PROJECT_NAME}" -f "${ROOT_DIR}/compose.test.yml" up -d --build dev-relay igloo-demo >/dev/null

PACKAGE_FILE="${ARTIFACT_DIR}/onboard-${RECIPIENT}.txt"
PASSWORD_FILE="${ARTIFACT_DIR}/onboard-${RECIPIENT}.password.txt"
PASSPHRASE_FILE="${XDG_ROOT}/passphrase.txt"
wait_for_file "${PACKAGE_FILE}"
wait_for_file "${PASSWORD_FILE}"

mkdir -p "${XDG_ROOT}/config" "${XDG_ROOT}/data" "${XDG_ROOT}/state"
printf '%s\n' "demo-harness-smoke-pass" >"${PASSPHRASE_FILE}"
export XDG_CONFIG_HOME="${XDG_ROOT}/config"
export XDG_DATA_HOME="${XDG_ROOT}/data"
export XDG_STATE_HOME="${XDG_ROOT}/state"
export IGLOO_SHELL_PROFILE_PASSPHRASE="demo-harness-smoke-pass"

ONBOARD_JSON="$(
  "${IGLOO_SHELL_BIN}" onboard "${PACKAGE_FILE}" \
    --onboard-secret-file "${PASSWORD_FILE}" \
    --passphrase-file "${PASSPHRASE_FILE}" \
    --json \
    --label "${RECIPIENT}-smoke"
)"
PROFILE_ID="$(
  printf '%s\n' "${ONBOARD_JSON}" | awk '
    /"import"[[:space:]]*:[[:space:]]*{/ { in_import=1 }
    in_import && /"profile"[[:space:]]*:[[:space:]]*{/ { in_profile=1; next }
    in_profile && /"id"[[:space:]]*:[[:space:]]*"/ {
      line = $0
      sub(/.*"id"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      print line
      exit
    }
    in_profile && /^[[:space:]]*}/ { in_profile=0 }
  '
)"
if [[ -z "${PROFILE_ID}" ]]; then
  echo "failed to parse onboarded profile id" >&2
  printf '%s\n' "${ONBOARD_JSON}" >&2
  exit 1
fi

"${IGLOO_SHELL_BIN}" daemon start --profile "${PROFILE_ID}" >/dev/null
"${IGLOO_SHELL_BIN}" runtime status --profile "${PROFILE_ID}" >/dev/null
PEER_LIST="$("${IGLOO_SHELL_BIN}" peer list --profile "${PROFILE_ID}")"
if ! printf '%s\n' "${PEER_LIST}" | grep -q '"pubkey"'; then
  echo "demo harness peer list did not include any peers" >&2
  printf '%s\n' "${PEER_LIST}" >&2
  exit 1
fi

echo "demo harness onboard smoke passed"
