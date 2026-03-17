#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-}"
PORT="${2:-8194}"
DEMO_HARNESS_SERVICES=(dev-relay igloo-demo)

case "${ACTION}" in
  start|foreground)
    ;;
  *)
    echo "usage: scripts/run-demo-stack.sh <start|foreground> [port]" >&2
    exit 1
    ;;
esac

"${ROOT_DIR}/scripts/stop-demo-stacks.sh" --port "${PORT}"
RESOLVED_PORT="$("${ROOT_DIR}/scripts/check-demo-port.sh" --print "${PORT}")"
echo "==> Using demo relay port ${RESOLVED_PORT}"
mkdir -p "${ROOT_DIR}/data/test-harness"
printf '%s\n' "${RESOLVED_PORT}" > "${ROOT_DIR}/data/test-harness/demo-relay-port.txt"
"${ROOT_DIR}/scripts/build-demo-harness-binaries.sh"

if [[ "${ACTION}" == "foreground" ]]; then
  DEV_RELAY_PORT="${RESOLVED_PORT}" DEV_RELAY_EXTERNAL_HOST=localhost \
    docker compose -f "${ROOT_DIR}/compose.test.yml" up --remove-orphans "${DEMO_HARNESS_SERVICES[@]}"
else
  DEV_RELAY_PORT="${RESOLVED_PORT}" DEV_RELAY_EXTERNAL_HOST=localhost \
    docker compose -f "${ROOT_DIR}/compose.test.yml" up -d --remove-orphans "${DEMO_HARNESS_SERVICES[@]}"
  "${ROOT_DIR}/scripts/print-demo-harness-onboard.sh"
fi
