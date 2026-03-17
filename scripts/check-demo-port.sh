#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="resolve"
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      MODE="strict"
      shift
      ;;
    --print)
      MODE="resolve"
      shift
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      PORT="$1"
      shift
      ;;
  esac
done

PORT="${PORT:-8194}"

port_in_use() {
  local port="$1"
  ss -ltn "( sport = :${port} )" 2>/dev/null | tail -n +2 | grep -q .
}

resolve_free_port() {
  local requested_port="$1"
  local candidate="${requested_port}"
  local upper_bound=$((requested_port + 100))

  while [[ "${candidate}" -le "${upper_bound}" ]]; do
    if ! port_in_use "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    candidate=$((candidate + 1))
  done

  echo "could not find a free demo relay port between ${requested_port} and ${upper_bound}" >&2
  exit 1
}

if docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q dev-relay >/dev/null 2>&1; then
  existing="$(docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q dev-relay 2>/dev/null || true)"
  if [[ -n "${existing}" ]]; then
    printf '%s\n' "${PORT}"
    exit 0
  fi
fi

if ! port_in_use "${PORT}"; then
  printf '%s\n' "${PORT}"
  exit 0
fi

if [[ "${MODE}" = "resolve" ]]; then
  resolved_port="$(resolve_free_port "${PORT}")"
  echo "demo relay port ${PORT} is already in use; using ${resolved_port} instead" >&2
  printf '%s\n' "${resolved_port}"
  exit 0
fi

if port_in_use "${PORT}"; then
  echo "demo relay port ${PORT} is already in use" >&2
  ss -ltnp "( sport = :${PORT} )" >&2 || true
  echo >&2
  echo "stop the existing process, run './run.sh demo stop' if an older demo stack owns it," >&2
  echo "or choose a different relay port, for example:" >&2
  echo "  ./run.sh demo start --port 8394" >&2
  exit 1
fi
