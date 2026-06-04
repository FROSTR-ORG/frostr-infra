#!/usr/bin/env bash
# Sourced by services/igloo-demo/entrypoint.sh.
# Polling helpers with consistent timeout / interval semantics.

# wait_for_condition <description> <timeout_secs> <interval_secs> <cmd...>
#
# Polls a command until it returns zero or the timeout elapses. The
# interval may be a fractional second (e.g. "0.2"); the per-iteration
# sleep uses that literal value. The attempt budget is derived from
# timeout_secs (integer) using a matching integer tick count, so:
#   interval "0.1" => 10 ticks per second
#   interval "0.2" =>  5 ticks per second
#   interval "1"   =>  1 tick  per second
wait_for_condition() {
  local description="$1"
  local timeout_secs="$2"
  local interval_secs="$3"
  shift 3

  local ticks_per_second
  case "${interval_secs}" in
    0.1) ticks_per_second=10 ;;
    0.2) ticks_per_second=5 ;;
    0.5) ticks_per_second=2 ;;
    1|1.0) ticks_per_second=1 ;;
    *)
      # Fall back to treating interval_secs as an integer.
      ticks_per_second=$(( 1 / (interval_secs + 0) ))
      if [ "${ticks_per_second}" -lt 1 ]; then
        ticks_per_second=1
      fi
      ;;
  esac

  local max_attempts=$(( timeout_secs * ticks_per_second ))
  if [ "${max_attempts}" -lt 1 ]; then
    max_attempts=1
  fi

  local attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    if "$@"; then
      return 0
    fi
    sleep "${interval_secs}"
    attempt=$((attempt + 1))
  done

  echo "timed out after ${timeout_secs}s waiting for: ${description}" >&2
  return 1
}

# wait_for_relay — expects DEV_RELAY_HOST and DEV_RELAY_PORT in the env.
wait_for_relay() {
  local host="${1:-${DEV_RELAY_HOST}}"
  local port="${2:-${DEV_RELAY_PORT}}"
  wait_for_condition "relay at ${host}:${port}" 60 0.2 \
    bash -c "exec 3<>/dev/tcp/${host}/${port} && exec 3>&-"
}

wait_for_socket() {
  local path="$1"
  wait_for_condition "socket at ${path}" 60 0.2 \
    test -S "${path}"
}

# wait_for_onboard_ready <profile_id>
#
# Polls `igloo-shell check onboard --profile <id>` until its JSON output
# reports "ready": true (via jq). Relies on IGLOO_SHELL_BIN being set.
wait_for_onboard_ready() {
  local profile_id="$1"
  wait_for_condition "onboard readiness for ${profile_id}" 60 1 \
    bash -c "\"${IGLOO_SHELL_BIN}\" check onboard --profile \"${profile_id}\" 2>/dev/null | jq -e '.ready == true' >/dev/null"
}
