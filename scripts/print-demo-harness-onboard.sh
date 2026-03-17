#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONBOARD_MEMBERS="${IGLOO_SHELL_DEMO_INVITE_MEMBERS:-bob,carol}"
TIMEOUT_SECS="${TIMEOUT_SECS:-60}"
RELAY_PORT_FILE="${ROOT_DIR}/data/test-harness/demo-relay-port.txt"
RELAY_PORT="${DEMO_RELAY_PORT:-}"

if [[ -z "${RELAY_PORT}" && -s "${RELAY_PORT_FILE}" ]]; then
  RELAY_PORT="$(tr -d '\n' < "${RELAY_PORT_FILE}")"
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

IFS=',' read -r -a members <<< "${ONBOARD_MEMBERS}"

attempt=0
while [ "${attempt}" -lt "$((TIMEOUT_SECS * 10))" ]; do
  ready=1
  for raw_member in "${members[@]}"; do
    member="$(trim "${raw_member}")"
    package_file="${ROOT_DIR}/data/test-harness/onboard-${member}.txt"
    password_file="${ROOT_DIR}/data/test-harness/onboard-${member}.password.txt"
    if [ ! -s "${package_file}" ] || [ ! -s "${password_file}" ]; then
      ready=0
      break
    fi
  done
  if [ "${ready}" -eq 1 ]; then
    for raw_member in "${members[@]}"; do
      member="$(trim "${raw_member}")"
      package_file="${ROOT_DIR}/data/test-harness/onboard-${member}.txt"
      password_file="${ROOT_DIR}/data/test-harness/onboard-${member}.password.txt"
      if [[ -n "${RELAY_PORT}" ]]; then
        echo "Relay URL (${member}):"
        echo "ws://localhost:${RELAY_PORT}"
        echo
      fi
      echo "Onboarding package (${member}):"
      cat "${package_file}"
      echo
      echo "Password (${member}):"
      cat "${password_file}"
      echo
    done
    exit 0
  fi
  sleep 0.1
  attempt=$((attempt + 1))
done

echo "Timed out waiting for onboarding packages for members: ${ONBOARD_MEMBERS}" >&2
exit 1
