#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"
source "${ROOT_DIR}/scripts/lib-demo-services.sh"

# Build/run the demo containers for the host architecture by default so the
# in-image Rust build compiles natively (not under QEMU). Override with
# DOCKER_PLATFORM. Exported so every `docker compose` call below inherits it.
if [[ -z "${DOCKER_PLATFORM:-}" ]]; then
  case "$(uname -m)" in
    arm64 | aarch64) export DOCKER_PLATFORM="linux/arm64" ;;
    x86_64 | amd64) export DOCKER_PLATFORM="linux/amd64" ;;
  esac
fi
ONBOARD_MEMBERS="${IGLOO_SHELL_DEMO_INVITE_MEMBERS:-bob,carol}"
TIMEOUT_SECS="${TIMEOUT_SECS:-60}"
HOST_HARNESS_DIR="$(resolve_workspace_scratch_dir FROSTR_TEST_HARNESS_DIR test-harness)"
CONTAINER_HARNESS_DIR="${FROSTR_TEST_HARNESS_CONTAINER_DIR:-/workspace/.tmp/test-harness}"
RELAY_PORT_FILE="${HOST_HARNESS_DIR}/demo-relay-port.txt"
DEFAULT_PORT="${DEMO_RELAY_PORT:-8194}"

usage() {
  cat <<'EOF'
usage: scripts/demo.sh <build-binaries|resolve-port|relay-up|start|foreground|stop|logs|onboard> [port]
EOF
}

run_compose_attached() {
  local resolved_port="$1"
  local compose_pid=""

  forward_signal() {
    local signal="$1"
    if [[ -n "${compose_pid}" ]] && kill -0 "${compose_pid}" 2>/dev/null; then
      kill "-${signal}" "${compose_pid}" 2>/dev/null || true
    fi
  }

  FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
  FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
  DEV_RELAY_PORT="${resolved_port}" DEV_RELAY_EXTERNAL_HOST=localhost \
  HOST_UID="$(id -u)" HOST_GID="$(id -g)" \
    docker compose -f "${ROOT_DIR}/compose.test.yml" up --build --remove-orphans "${DEMO_HARNESS_SERVICES[@]}" &
  compose_pid="$!"

  trap 'forward_signal INT' INT
  trap 'forward_signal TERM' TERM

  # Persist the port file only after compose has started producing output
  # successfully. print_onboard blocks waiting for the containers to write
  # their onboarding artifacts, so by the time it returns compose is up.
  printf '%s\n' "${resolved_port}" > "${RELAY_PORT_FILE}"
  print_onboard "${resolved_port}"

  set +e
  wait "${compose_pid}"
  local status=$?
  set -e

  trap - INT TERM
  return "${status}"
}

build_binaries() {
  if [[ "${FROSTR_DEMO_BINARIES_PREPARED:-0}" == "1" ]]; then
    return 0
  fi

  echo "==> Building demo harness binaries on host"
  "${ROOT_DIR}/scripts/test-prebuild.sh" ensure shared browser-wasm demo-binaries
}

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

resolve_port() {
  local port="${1:-$DEFAULT_PORT}"

  if docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q "${DEMO_RELAY_SERVICE}" >/dev/null 2>&1; then
    local existing
    existing="$(docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q "${DEMO_RELAY_SERVICE}" 2>/dev/null || true)"
    if [[ -n "${existing}" ]]; then
      printf '%s\n' "${port}"
      return 0
    fi
  fi

  if ! port_in_use "${port}"; then
    printf '%s\n' "${port}"
    return 0
  fi

  local resolved_port
  resolved_port="$(resolve_free_port "${port}")"
  echo "demo relay port ${port} is already in use; using ${resolved_port} instead" >&2
  printf '%s\n' "${resolved_port}"
}

stop_projects() {
  local port_filter="${1:-}"
  local -a projects=()
  local project
  while IFS= read -r project; do
    projects+=("${project}")
  done < <(
    docker ps -a \
      --filter "label=com.docker.compose.project.working_dir=${ROOT_DIR}" \
      --filter "label=com.docker.compose.project.config_files=${ROOT_DIR}/compose.test.yml" \
      --format '{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.service"}}	{{.Ports}}' \
      | awk -F '\t' -v port="${port_filter}" -v relay_service="${DEMO_RELAY_SERVICE}" -v node_service="${DEMO_NODE_SERVICE}" '
          ($2 == relay_service || $2 == node_service) {
            if (port == "" || index($3, ":" port "->") > 0) {
              print $1
            }
          }
        ' \
      | awk '!seen[$0]++'
  )

  # Always sweep the default compose project too. `relay_up` (and any bare
  # `docker compose -f compose.test.yml up`) run without `-p`, so their
  # containers land in the dir-named default project and aren't guaranteed to be
  # in the label scan above (e.g. a crash-looping/exited relay).
  local default_project
  default_project="$(basename "${ROOT_DIR}")"
  # bash 3.2 (macOS) treats an empty array as unset under `set -u`, so guard the
  # expansion with `:-` — `projects` is empty whenever the label scan matched no
  # containers.
  if [[ ! " ${projects[*]:-} " == *" ${default_project} "* ]]; then
    projects+=("${default_project}")
  fi

  for project in "${projects[@]}"; do
    echo "==> Stopping demo compose project ${project}"
    docker compose -p "${project}" -f "${ROOT_DIR}/compose.test.yml" down --remove-orphans >/dev/null 2>&1 || true
  done
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

package_file_for_member() {
  local member="$1"
  printf '%s/onboard-%s.txt' "${HOST_HARNESS_DIR}" "${member}"
}

password_file_for_member() {
  local member="$1"
  printf '%s/onboard-%s.password.txt' "${HOST_HARNESS_DIR}" "${member}"
}

print_onboard() {
  local relay_port="${1:-${DEMO_RELAY_PORT:-}}"

  if [[ -z "${relay_port}" && -s "${RELAY_PORT_FILE}" ]]; then
    relay_port="$(tr -d '\n' < "${RELAY_PORT_FILE}")"
  fi

  IFS=',' read -r -a members <<< "${ONBOARD_MEMBERS}"
  local attempt=0
  while [ "${attempt}" -lt "$((TIMEOUT_SECS * 10))" ]; do
    local ready=1
    local raw_member member package_file password_file
    for raw_member in "${members[@]}"; do
      member="$(trim "${raw_member}")"
      package_file="$(package_file_for_member "${member}")"
      password_file="$(password_file_for_member "${member}")"
      if [ ! -s "${package_file}" ] || [ ! -s "${password_file}" ]; then
        ready=0
        break
      fi
    done
    if [ "${ready}" -eq 1 ]; then
      # Buffer the reads under the readiness gate. A crash-looping demo signer
      # can wipe a freshly-written package on restart (its entrypoint clears
      # stale onboard files before regenerating); if that race empties a file
      # between the check above and the read here, fall back to waiting rather
      # than printing a half-read package or erroring on a vanished path.
      local output="" package_contents password_contents raced=0
      for raw_member in "${members[@]}"; do
        member="$(trim "${raw_member}")"
        package_file="$(package_file_for_member "${member}")"
        password_file="$(password_file_for_member "${member}")"
        package_contents="$(cat "${package_file}" 2>/dev/null || true)"
        password_contents="$(cat "${password_file}" 2>/dev/null || true)"
        if [[ -z "${package_contents}" || -z "${password_contents}" ]]; then
          raced=1
          break
        fi
        if [[ -n "${relay_port}" ]]; then
          output+="Relay URL (${member}):"$'\n'"ws://localhost:${relay_port}"$'\n\n'
        fi
        output+="Onboarding package (${member}):"$'\n'"${package_contents}"$'\n\n'
        output+="Password (${member}):"$'\n'"${password_contents}"$'\n\n'
      done
      if [ "${raced}" -eq 0 ]; then
        printf '%s' "${output}"
        return 0
      fi
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  echo "Timed out waiting for onboarding packages for members: ${ONBOARD_MEMBERS}" >&2
  exit 1
}

start_stack() {
  local action="$1"
  local requested_port="${2:-$DEFAULT_PORT}"

  stop_projects "${requested_port}"
  echo "==> Using demo relay port ${requested_port}"
  mkdir -p "${HOST_HARNESS_DIR}"
  printf '%s\n' "${requested_port}" > "${RELAY_PORT_FILE}"
  # No host binary build: the demo images compile bifrost-devtools / igloo-shell
  # in-Docker (services/demo/Dockerfile), so `up --build` is fully self-contained.

  # Let docker compose fail loud on port conflict rather than probing here
  # (which had a TOCTOU race where the probe saw the port free, then another
  # process grabbed it before compose bound). If the port is truly in use,
  # docker exits with a clear error and the operator can retry with
  # PORT=<alternative>.

  if [[ "${action}" == "foreground" ]]; then
    # run_compose_attached writes the port file itself after compose is up
    # but before print_onboard blocks, so a failed attached start never
    # leaves a stale RELAY_PORT_FILE.
    if ! run_compose_attached "${requested_port}"; then
      echo "compose failed (port ${requested_port} may be in use); retry with PORT=<alternative>" >&2
      return 1
    fi
    return 0
  fi

  if ! FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
    FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
    DEV_RELAY_PORT="${requested_port}" DEV_RELAY_EXTERNAL_HOST=localhost \
    HOST_UID="$(id -u)" HOST_GID="$(id -g)" \
      docker compose -f "${ROOT_DIR}/compose.test.yml" up -d --build --remove-orphans \
        "${DEMO_HARNESS_SERVICES[@]}"
  then
    echo "compose failed (port ${requested_port} may be in use); retry with PORT=<alternative>" >&2
    return 1
  fi

  # Persist the port file only after compose up -d succeeded; a failed
  # start should not leave a stale port hint for subsequent demo-onboard.
  printf '%s\n' "${requested_port}" > "${RELAY_PORT_FILE}"
  print_onboard "${requested_port}"
}

relay_up() {
  local requested_port="${1:-$DEFAULT_PORT}"
  local resolved_port
  resolved_port="$(resolve_port "${requested_port}")"
  echo "==> Using demo relay port ${resolved_port}" >&2
  mkdir -p "${HOST_HARNESS_DIR}"
  printf '%s\n' "${resolved_port}" > "${RELAY_PORT_FILE}"

  # Bring up only the relay (no demo signer node); compose output to stderr so
  # stdout carries just the resolved port for the caller to capture.
  FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
  FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
  DEV_RELAY_PORT="${resolved_port}" DEV_RELAY_EXTERNAL_HOST=localhost \
    docker compose -f "${ROOT_DIR}/compose.test.yml" up -d --build --remove-orphans "${DEMO_RELAY_SERVICE}" >&2

  printf '%s\n' "${resolved_port}"
}

logs() {
  FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
  FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
    docker compose -f "${ROOT_DIR}/compose.test.yml" logs -f "${DEMO_HARNESS_SERVICES[@]}"
}

main() {
  local action="${1:-}"
  local port="${2:-$DEFAULT_PORT}"

  case "${action}" in
    build-binaries)
      build_binaries
      ;;
    resolve-port)
      resolve_port "${port}"
      ;;
    relay-up)
      relay_up "${port}"
      ;;
    start)
      if [[ "${BG:-0}" == "1" ]]; then
        start_stack start "${port}"
      else
        start_stack foreground "${port}"
      fi
      ;;
    foreground)
      start_stack foreground "${port}"
      ;;
    stop)
      stop_projects "${port:-}"
      rm -f "${RELAY_PORT_FILE}"
      ;;
    logs)
      logs
      ;;
    onboard)
      print_onboard
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
