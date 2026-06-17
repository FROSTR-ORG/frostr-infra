#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${IGLOO_PWA_DEV_PORT:-1430}"
KILL_BIN="${IGLOO_PWA_DEV_KILL_BIN:-kill}"
SLEEP_BIN="${IGLOO_PWA_DEV_SLEEP_BIN:-sleep}"
RELAY="${RELAY:-0}"
RELAY_PORT="${RELAY_PORT:-8194}"
RELAY_BIN="${ROOT_DIR}/repos/bifrost-rs/target/debug/bifrost-devtools"
RELAY_PID=""

cd "${ROOT_DIR}"

find_port_pids() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | awk '!seen[$0]++'
    return 0
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null \
      | awk -v port=":${port}" '$4 ~ port "$" { print $0 }' \
      | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
      | awk '!seen[$0]++'
    return 0
  fi

  return 0
}

describe_pid() {
  local pid="$1"
  local command_name
  command_name="$(ps -p "${pid}" -o comm= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
  if [[ -n "${command_name}" ]]; then
    printf ' (%s)' "${command_name}"
  fi
}

describe_pids() {
  local pid
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    printf '  - PID %s%s\n' "${pid}" "$(describe_pid "${pid}")"
  done
}

join_pids() {
  awk 'NF { if (out) out = out ", " $0; else out = $0 } END { print out }'
}

pid_count() {
  awk 'NF { count++ } END { print count + 0 }'
}

pid_phrase() {
  local count="$1"
  local list="$2"
  if [[ "${count}" -eq 1 ]]; then
    printf 'PID %s' "${list}"
  else
    printf 'PIDs: %s' "${list}"
  fi
}

kill_pids() {
  local pid
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    "${KILL_BIN}" -TERM "${pid}"
  done
}

is_interactive() {
  [[ -t 0 || "${IGLOO_PWA_DEV_ASSUME_TTY:-0}" == "1" ]]
}

wait_for_port_clear() {
  local port="$1"
  local pids
  local attempt
  for attempt in 1 2 3 4 5; do
    pids="$(find_port_pids "${port}" || true)"
    if [[ -z "${pids}" ]]; then
      return 0
    fi
    "${SLEEP_BIN}" 0.2
  done
  return 1
}

build_relay_if_needed() {
  if [[ -x "${RELAY_BIN}" ]]; then
    return 0
  fi
  printf 'Building bifrost-devtools relay binary (first run, this can take a minute)...\n' >&2
  cargo build --manifest-path "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml" \
    --locked -p bifrost-devtools --bin bifrost-devtools >&2
}

stop_relay() {
  if [[ -n "${RELAY_PID}" ]] && kill -0 "${RELAY_PID}" 2>/dev/null; then
    "${KILL_BIN}" -TERM "${RELAY_PID}" 2>/dev/null || true
  fi
}

# Start the dev relay natively (not via the Docker demo lane). The relay binary
# from test-prebuild is always built for the host (`cargo build` with no
# --target), so it's a host-native binary — a macOS Mach-O on Apple Silicon. The
# Docker dev-relay runs linux/x86_64 and bind-mounts the same binary, so it can
# never exec a macOS build ("Exec format error", crash-loop). Running natively
# matches the host on macOS and Linux alike and ties the relay to this dev
# session. The Docker relay remains for the demo/CI lanes (make demo-start).
maybe_start_relay() {
  [[ "${RELAY}" == "1" ]] || return 0

  # If a relay is already listening on the port, reuse it rather than starting
  # (or killing) a second one we don't own.
  if [[ -n "$(find_port_pids "${RELAY_PORT}" || true)" ]]; then
    export VITE_DEFAULT_RELAYS="ws://127.0.0.1:${RELAY_PORT}"
    printf 'Relay already running at %s — reusing it.\n' "${VITE_DEFAULT_RELAYS}" >&2
    return 0
  fi

  build_relay_if_needed
  "${RELAY_BIN}" relay --host 0.0.0.0 --port "${RELAY_PORT}" >&2 &
  RELAY_PID="$!"
  export VITE_DEFAULT_RELAYS="ws://127.0.0.1:${RELAY_PORT}"
  printf 'Local relay started (PID %s) at %s — stops with this dev server.\n' \
    "${RELAY_PID}" "${VITE_DEFAULT_RELAYS}" >&2
}

start_dev() {
  maybe_start_relay
  # When we own a relay process, keep it tied to the dev server's lifetime: run
  # npm in the foreground (not exec) so the EXIT trap can tear the relay down.
  if [[ -n "${RELAY_PID}" ]]; then
    trap stop_relay EXIT INT TERM
    local rc=0
    npm --prefix "${ROOT_DIR}/repos/igloo-pwa" run dev || rc=$?
    exit "${rc}"
  fi
  exec npm --prefix "${ROOT_DIR}/repos/igloo-pwa" run dev
}

pids="$(find_port_pids "${PORT}" || true)"
if [[ -z "${pids}" ]]; then
  start_dev
fi

pid_list="$(printf '%s\n' "${pids}" | join_pids)"
pid_total="$(printf '%s\n' "${pids}" | pid_count)"
pid_owner="$(pid_phrase "${pid_total}" "${pid_list}")"

# Non-interactive auto-resolve (agents/CI): terminate the squatter and continue,
# no prompt. Opt-in so a human's stray process isn't killed by surprise.
if [[ "${FROSTR_NONINTERACTIVE:-0}" == "1" ]]; then
  printf 'Port %s in use by %s; FROSTR_NONINTERACTIVE=1 set — terminating it.\n' "${PORT}" "${pid_owner}" >&2
  printf '%s\n' "${pids}" | kill_pids
  if wait_for_port_clear "${PORT}"; then
    start_dev
  fi
  printf 'error: Port %s is still in use after TERM.\n' "${PORT}" >&2
  exit 1
fi

if ! is_interactive; then
  printf 'error: Port %s is already in use by %s.\n' "${PORT}" "${pid_owner}" >&2
  printf '%s\n' "${pids}" | describe_pids >&2
  printf 'Stop that process, set FROSTR_NONINTERACTIVE=1 to auto-terminate it, or rerun from an interactive terminal.\n' >&2
  exit 1
fi

printf 'Port %s is already in use by %s. Kill and continue? [y/N] ' "${PORT}" "${pid_owner}" >&2
if ! read -r reply; then
  reply=""
fi

case "${reply}" in
  y|Y|yes|YES|Yes)
    printf '%s\n' "${pids}" | kill_pids
    if wait_for_port_clear "${PORT}"; then
      start_dev
    fi
    printf 'error: Port %s is still in use after TERM.\n' "${PORT}" >&2
    printf 'Stop that process manually, then rerun make igloo-pwa-dev.\n' >&2
    exit 1
    ;;
  *)
    printf 'Aborted. Port %s is still in use by %s.\n' "${PORT}" "${pid_owner}" >&2
    exit 1
    ;;
esac
