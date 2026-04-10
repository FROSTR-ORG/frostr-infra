#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib-scratch.sh"
ONBOARD_MEMBERS="${IGLOO_SHELL_DEMO_INVITE_MEMBERS:-bob,carol}"
TIMEOUT_SECS="${TIMEOUT_SECS:-60}"
HOST_HARNESS_DIR="$(resolve_workspace_scratch_dir FROSTR_TEST_HARNESS_DIR test-harness)"
CONTAINER_HARNESS_DIR="${FROSTR_TEST_HARNESS_CONTAINER_DIR:-/workspace/.tmp/test-harness}"
RELAY_PORT_FILE="${HOST_HARNESS_DIR}/demo-relay-port.txt"
DEFAULT_PORT="${DEMO_RELAY_PORT:-8194}"
DEMO_HARNESS_SERVICES=(dev-relay igloo-demo)

usage() {
  cat <<'EOF'
usage: scripts/demo.sh <build-binaries|resolve-port|start|foreground|stop|logs|onboard> [port]
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
    docker compose -f "${ROOT_DIR}/compose.test.yml" up --build --remove-orphans "${DEMO_HARNESS_SERVICES[@]}" &
  compose_pid="$!"

  trap 'forward_signal INT' INT
  trap 'forward_signal TERM' TERM

  print_onboard "${resolved_port}"

  set +e
  wait "${compose_pid}"
  local status=$?
  set -e

  trap - INT TERM
  return "${status}"
}

build_binaries() {
  local bifrost_dir="${ROOT_DIR}/repos/bifrost-rs"
  local igloo_shell_dir="${ROOT_DIR}/repos/igloo-shell"

  if [ ! -f "${bifrost_dir}/Cargo.toml" ]; then
    echo "bifrost-rs source is not available at ${bifrost_dir} (missing Cargo.toml)" >&2
    exit 1
  fi

  if [ ! -f "${igloo_shell_dir}/Cargo.toml" ]; then
    echo "igloo-shell source is not available at ${igloo_shell_dir} (missing Cargo.toml)" >&2
    exit 1
  fi

  echo "==> Building demo harness binaries on host"
  (
    cd "${bifrost_dir}"
    cargo build --locked -p bifrost-devtools --bin bifrost-devtools
  )
  (
    cd "${igloo_shell_dir}"
    cargo build --locked -p igloo-shell-cli --bin igloo-shell
  )
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

  if docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q dev-relay >/dev/null 2>&1; then
    local existing
    existing="$(docker compose -f "${ROOT_DIR}/compose.test.yml" ps -q dev-relay 2>/dev/null || true)"
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
  mapfile -t projects < <(
    docker ps \
      --filter "label=com.docker.compose.project.working_dir=${ROOT_DIR}" \
      --filter "label=com.docker.compose.project.config_files=${ROOT_DIR}/compose.test.yml" \
      --format '{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.service"}}	{{.Ports}}' \
      | awk -F '\t' -v port="${port_filter}" '
          ($2 == "dev-relay" || $2 == "igloo-demo") {
            if (port == "" || index($3, ":" port "->") > 0) {
              print $1
            }
          }
        ' \
      | awk '!seen[$0]++'
  )

  if [[ "${#projects[@]}" -eq 0 ]]; then
    return 0
  fi

  for project in "${projects[@]}"; do
    echo "==> Stopping demo compose project ${project}"
    docker compose -p "${project}" -f "${ROOT_DIR}/compose.test.yml" down --remove-orphans >/dev/null
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
      for raw_member in "${members[@]}"; do
        member="$(trim "${raw_member}")"
        package_file="$(package_file_for_member "${member}")"
        password_file="$(password_file_for_member "${member}")"
        if [[ -n "${relay_port}" ]]; then
          echo "Relay URL (${member}):"
          echo "ws://localhost:${relay_port}"
          echo
        fi
        echo "Onboarding package (${member}):"
        cat "${package_file}"
        echo
        echo "Password (${member}):"
        cat "${password_file}"
        echo
      done
      return 0
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
  local resolved_port
  resolved_port="$(resolve_port "${requested_port}")"
  echo "==> Using demo relay port ${resolved_port}"
  mkdir -p "${HOST_HARNESS_DIR}"
  printf '%s\n' "${resolved_port}" > "${RELAY_PORT_FILE}"
  build_binaries

  if [[ "${action}" == "foreground" ]]; then
    run_compose_attached "${resolved_port}"
  else
    FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
    FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
    DEV_RELAY_PORT="${resolved_port}" DEV_RELAY_EXTERNAL_HOST=localhost \
      docker compose -f "${ROOT_DIR}/compose.test.yml" up -d --build --remove-orphans "${DEMO_HARNESS_SERVICES[@]}"
    print_onboard "${resolved_port}"
  fi
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
