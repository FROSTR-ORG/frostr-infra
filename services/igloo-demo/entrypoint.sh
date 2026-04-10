#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="/workspace"
DEVTOOLS_DIR="${ROOT_DIR}/repos/bifrost-rs"
IGLOO_SHELL_DIR="${ROOT_DIR}/repos/igloo-shell"
DEVTOOLS_BIN="${DEVTOOLS_DIR}/target/debug/bifrost-devtools"
IGLOO_SHELL_BIN="${IGLOO_SHELL_DIR}/target/debug/igloo-shell"

DEV_RELAY_HOST="${DEV_RELAY_HOST:-dev-relay}"
DEV_RELAY_PORT="${DEV_RELAY_PORT:-8194}"
DEV_RELAY_INTERNAL_URL="${DEV_RELAY_INTERNAL_URL:-ws://${DEV_RELAY_HOST}:${DEV_RELAY_PORT}}"
DEV_RELAY_EXTERNAL_HOST="${DEV_RELAY_EXTERNAL_HOST:-127.0.0.1}"
DEV_RELAY_EXTERNAL_URL="${DEV_RELAY_EXTERNAL_URL:-ws://${DEV_RELAY_EXTERNAL_HOST}:${DEV_RELAY_PORT}}"
IGLOO_SHELL_DEMO_MEMBER="${IGLOO_SHELL_DEMO_MEMBER:-alice}"
IGLOO_SHELL_DEMO_INVITE_MEMBERS="${IGLOO_SHELL_DEMO_INVITE_MEMBERS:-bob,carol}"
IGLOO_SHELL_DEMO_RELAY_PROFILE="${IGLOO_SHELL_DEMO_RELAY_PROFILE:-local}"
IGLOO_SHELL_DEMO_THRESHOLD="${IGLOO_SHELL_DEMO_THRESHOLD:-2}"
IGLOO_SHELL_DEMO_COUNT="${IGLOO_SHELL_DEMO_COUNT:-3}"
FROSTR_TEST_HARNESS_CONTAINER_DIR="${FROSTR_TEST_HARNESS_CONTAINER_DIR:-${ROOT_DIR}/.tmp/test-harness}"
IGLOO_SHELL_DEMO_DIR="${IGLOO_SHELL_DEMO_DIR:-${FROSTR_TEST_HARNESS_CONTAINER_DIR}/demo-2of3}"
IGLOO_SHELL_DEMO_CONTROL_SOCKET="${IGLOO_SHELL_DEMO_CONTROL_SOCKET:-${FROSTR_TEST_HARNESS_CONTAINER_DIR}/igloo-shell-${IGLOO_SHELL_DEMO_MEMBER}.sock}"
IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE="${IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE:-${FROSTR_TEST_HARNESS_CONTAINER_DIR}/igloo-shell-${IGLOO_SHELL_DEMO_MEMBER}.token}"
IGLOO_SHELL_DEMO_ARTIFACT_DIR="${IGLOO_SHELL_DEMO_ARTIFACT_DIR:-${FROSTR_TEST_HARNESS_CONTAINER_DIR}}"
IGLOO_SHELL_DEMO_PASSWORD_BYTES="${IGLOO_SHELL_DEMO_PASSWORD_BYTES:-16}"
IGLOO_SHELL_DEMO_PASSPHRASE="${IGLOO_SHELL_DEMO_PASSPHRASE:-dev-harness-passphrase}"
IGLOO_SHELL_DEMO_XDG_ROOT="${IGLOO_SHELL_DEMO_XDG_ROOT:-${IGLOO_SHELL_DEMO_ARTIFACT_DIR}/igloo-shell-home}"
IGLOO_SHELL_DEMO_STATE_LINK="${IGLOO_SHELL_DEMO_STATE_LINK:-/w}"
IGLOO_SHELL_DEMO_TMPDIR="${IGLOO_SHELL_DEMO_TMPDIR:-${IGLOO_SHELL_DEMO_ARTIFACT_DIR}/tmp}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${IGLOO_SHELL_DEMO_XDG_ROOT}/config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${IGLOO_SHELL_DEMO_XDG_ROOT}/data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${IGLOO_SHELL_DEMO_STATE_LINK}}"
export IGLOO_SHELL_PROFILE_PASSPHRASE="${IGLOO_SHELL_DEMO_PASSPHRASE}"
export TMPDIR="${TMPDIR:-${IGLOO_SHELL_DEMO_TMPDIR}}"

declare -a ONBOARD_MEMBERS=()
DEMO_PROFILE_ID=""
DEMO_DAEMON_LOG=""

need_file() {
  if [ ! -f "$1" ]; then
    echo "missing required file: $1"
    exit 1
  fi
}

member_index() {
  local name="$1"
  local members=(
    alice bob carol dave erin frank grace heidi ivan judy
    karl laura mallory nia oscar peggy quentin ruth sybil trent
  )
  local idx=1
  local entry
  for entry in "${members[@]}"; do
    if [ "${entry}" = "${name}" ]; then
      echo "${idx}"
      return 0
    fi
    idx=$((idx + 1))
  done
  return 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

parse_onboard_members() {
  local raw="$1"
  local part=""
  ONBOARD_MEMBERS=()

  IFS=',' read -r -a parts <<< "${raw}"
  for part in "${parts[@]}"; do
    part="$(trim "${part}")"
    if [ -n "${part}" ]; then
      ONBOARD_MEMBERS+=("${part}")
    fi
  done

  if [ "${#ONBOARD_MEMBERS[@]}" -eq 0 ]; then
    echo "IGLOO_SHELL_DEMO_INVITE_MEMBERS must include at least one recipient"
    exit 1
  fi
}

onboard_file() {
  printf '%s/onboard-%s.txt' "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}" "$1"
}

password_file() {
  printf '%s/onboard-%s.password.txt' "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}" "$1"
}

wait_for_relay() {
  local host="$1"
  local port="$2"
  local timeout_secs="${3:-60}"
  local attempt=0

  while [ "${attempt}" -lt "$((timeout_secs * 10))" ]; do
    if bash -lc "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  echo "timed out waiting for relay at ${host}:${port}"
  return 1
}

wait_for_socket() {
  local path="$1"
  local timeout_secs="${2:-60}"
  local attempt=0

  while [ "${attempt}" -lt "$((timeout_secs * 10))" ]; do
    if [ -S "${path}" ]; then
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  echo "timed out waiting for control socket at ${path}"
  return 1
}

wait_for_onboard_ready() {
  local profile_id="$1"
  local timeout_secs="${2:-60}"
  local attempt=0
  local check_json=""

  while [ "${attempt}" -lt "${timeout_secs}" ]; do
    check_json="$("${IGLOO_SHELL_BIN}" check onboard --profile "${profile_id}" 2>/dev/null || true)"
    if printf '%s' "${check_json}" | grep -q '"ready"[[:space:]]*:[[:space:]]*true'; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "timed out waiting for onboarding readiness for profile ${profile_id}" >&2
  if [ -n "${check_json}" ]; then
    printf '%s\n' "${check_json}" >&2
  fi
  return 1
}

cleanup_demo_dir() {
  mkdir -p "${IGLOO_SHELL_DEMO_DIR}"
  rm -f \
    "${IGLOO_SHELL_DEMO_DIR}/group.json" \
    "${IGLOO_SHELL_DEMO_DIR}/share-"*.json \
    "${IGLOO_SHELL_DEMO_DIR}/igloo-shell-"*.json \
    "${IGLOO_SHELL_DEMO_DIR}/state-"*.json \
    "${IGLOO_SHELL_DEMO_DIR}/state-"*.lock
}

cleanup_shell_home() {
  rm -rf \
    "${XDG_CONFIG_HOME}/igloo-shell" \
    "${XDG_DATA_HOME}/igloo-shell" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/state/igloo-shell"
  if [ "${XDG_STATE_HOME}" = "${IGLOO_SHELL_DEMO_STATE_LINK}" ]; then
    rm -f "${IGLOO_SHELL_DEMO_STATE_LINK}"
  fi
}

prepare_shell_home() {
  mkdir -p \
    "${TMPDIR}" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/config" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/data" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/state"
  if [ "${XDG_STATE_HOME}" = "${IGLOO_SHELL_DEMO_STATE_LINK}" ]; then
    ln -sfn "${IGLOO_SHELL_DEMO_XDG_ROOT}/state" "${IGLOO_SHELL_DEMO_STATE_LINK}"
  fi
}

relax_artifact_permissions() {
  chmod -R a+rwX "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}" >/dev/null 2>&1 || true
}

has_demo_material() {
  [ -f "${IGLOO_SHELL_DEMO_DIR}/group.json" ] &&
    [ -f "${IGLOO_SHELL_DEMO_DIR}/share-${IGLOO_SHELL_DEMO_MEMBER}.json" ] &&
    [ -f "${IGLOO_SHELL_DEMO_DIR}/igloo-shell-${IGLOO_SHELL_DEMO_MEMBER}.json" ]
}

generate_demo_material_if_needed() {
  if has_demo_material; then
    echo "==> Reusing existing demo material in ${IGLOO_SHELL_DEMO_DIR}"
    rm -f \
      "${IGLOO_SHELL_DEMO_DIR}/state-"*.json \
      "${IGLOO_SHELL_DEMO_DIR}/state-"*.lock
    return
  fi

  echo "==> Generating ${IGLOO_SHELL_DEMO_THRESHOLD}-of-${IGLOO_SHELL_DEMO_COUNT} demo material in ${IGLOO_SHELL_DEMO_DIR}"
  cleanup_demo_dir
  "${DEVTOOLS_BIN}" keygen \
    --out-dir "${IGLOO_SHELL_DEMO_DIR}" \
    --threshold "${IGLOO_SHELL_DEMO_THRESHOLD}" \
    --count "${IGLOO_SHELL_DEMO_COUNT}" \
    --relay "${DEV_RELAY_INTERNAL_URL}"
}

json_string_field() {
  local key="$1"
  awk -F'"' -v key="${key}" '$2 == key { print $4; exit }'
}

json_number_field() {
  local key="$1"
  sed -n "s/^[[:space:]]*\"${key}\":[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n 1
}

imported_profile_id() {
  awk '
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
}

configure_relay_profile() {
  "${IGLOO_SHELL_BIN}" relays set "${IGLOO_SHELL_DEMO_RELAY_PROFILE}" "${DEV_RELAY_INTERNAL_URL}" >/dev/null
  "${IGLOO_SHELL_BIN}" relays default "${IGLOO_SHELL_DEMO_RELAY_PROFILE}" >/dev/null
}

import_demo_profile() {
  local import_json

  import_json="$(
    "${IGLOO_SHELL_BIN}" import \
      --group "${IGLOO_SHELL_DEMO_DIR}/group.json" \
      --share "${IGLOO_SHELL_DEMO_DIR}/share-${IGLOO_SHELL_DEMO_MEMBER}.json" \
      --label "${IGLOO_SHELL_DEMO_MEMBER}" \
      --relay-profile "${IGLOO_SHELL_DEMO_RELAY_PROFILE}" \
      --passphrase "${IGLOO_SHELL_PROFILE_PASSPHRASE}" \
      --json
  )"
  DEMO_PROFILE_ID="$(printf '%s\n' "${import_json}" | imported_profile_id)"
  if [ -z "${DEMO_PROFILE_ID}" ]; then
    echo "failed to determine imported profile id"
    printf '%s\n' "${import_json}"
    exit 1
  fi
}

ensure_onboard_members_exist() {
  local member=""
  for member in "${ONBOARD_MEMBERS[@]}"; do
    if [ "${member}" = "${IGLOO_SHELL_DEMO_MEMBER}" ]; then
      echo "IGLOO_SHELL_DEMO_INVITE_MEMBERS must not include ${IGLOO_SHELL_DEMO_MEMBER}"
      exit 1
    fi
    need_file "${IGLOO_SHELL_DEMO_DIR}/share-${member}.json"
  done
}

generate_password_file_if_needed() {
  local path="$1"
  local old_umask

  if [ -s "${path}" ]; then
    chmod 0644 "${path}" >/dev/null 2>&1 || true
    return 0
  fi

  old_umask="$(umask)"
  umask 077
  od -An -tx1 -N"${IGLOO_SHELL_DEMO_PASSWORD_BYTES}" /dev/urandom | tr -d ' \n' > "${path}"
  umask "${old_umask}"
  chmod 0644 "${path}"
}

export_onboarding_package() {
  local member="$1"
  local password_path
  local onboard_path

  password_path="$(password_file "${member}")"
  onboard_path="$(onboard_file "${member}")"
  generate_password_file_if_needed "${password_path}"

  echo "==> Creating onboarding package for ${member}"
  IGLOO_SHELL_PACKAGE_PASSWORD="$(tr -d '\r\n' < "${password_path}")" \
    "${IGLOO_SHELL_BIN}" export "${DEMO_PROFILE_ID}" \
      --format bfonboard \
      --out "${onboard_path}" \
      --recipient-share "${IGLOO_SHELL_DEMO_DIR}/share-${member}.json" \
      --relay-url "${DEV_RELAY_EXTERNAL_URL}" \
      --package-password-env IGLOO_SHELL_PACKAGE_PASSWORD \
      >/dev/null
  chmod 0644 "${onboard_path}" >/dev/null 2>&1 || true
}

start_demo_daemon() {
  local daemon_json
  local daemon_token
  local daemon_socket_bind
  local daemon_socket_link_name
  local daemon_socket_link_target

  daemon_json="$("${IGLOO_SHELL_BIN}" daemon start --profile "${DEMO_PROFILE_ID}")"
  daemon_token="$(printf '%s\n' "${daemon_json}" | json_string_field "token")"
  daemon_socket_bind="$(printf '%s\n' "${daemon_json}" | json_string_field "socket_path")"
  daemon_socket_link_name="$(basename "${IGLOO_SHELL_DEMO_CONTROL_SOCKET}")"
  DEMO_DAEMON_LOG="${IGLOO_SHELL_DEMO_XDG_ROOT}/state/igloo-shell/profiles/${DEMO_PROFILE_ID}/daemon.log"
  if [ -z "${daemon_token}" ] || [ -z "${daemon_socket_bind}" ]; then
    echo "failed to determine daemon transport for profile ${DEMO_PROFILE_ID}"
    printf '%s\n' "${daemon_json}"
    exit 1
  fi

  daemon_socket_link_target="${daemon_socket_bind}"
  case "${daemon_socket_bind}" in
    "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}"/*)
      daemon_socket_link_target="${daemon_socket_bind#${IGLOO_SHELL_DEMO_ARTIFACT_DIR}/}"
      ;;
  esac

  (
    cd "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}"
    ln -sfn "${daemon_socket_link_target}" "${daemon_socket_link_name}"
  )
  printf '%s\n' "${daemon_token}" > "${IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE}"
  chmod 0777 "$(dirname "${daemon_socket_bind}")" "${daemon_socket_bind}" >/dev/null 2>&1 || true
}

export_onboarding_packages() {
  local member=""
  for member in "${ONBOARD_MEMBERS[@]}"; do
    export_onboarding_package "${member}"
  done
}

print_onboarding_packages() {
  local member=""
  local onboard_path
  local password_path

  echo
  echo "Demo node is ready."
  echo "Relay (internal): ${DEV_RELAY_INTERNAL_URL}"
  echo "Relay (external): ${DEV_RELAY_EXTERNAL_URL}"
  echo "Node member:      ${IGLOO_SHELL_DEMO_MEMBER}"
  echo "Onboard members:  ${ONBOARD_MEMBERS[*]}"
  echo

  for member in "${ONBOARD_MEMBERS[@]}"; do
    onboard_path="$(onboard_file "${member}")"
    password_path="$(password_file "${member}")"
    echo "Recipient:        ${member}"
    echo "Password file:    ${password_path}"
    echo "Onboard file:     ${onboard_path}"
    echo "Password:"
    cat "${password_path}"
    echo
    echo "bfonboard package:"
    cat "${onboard_path}"
    echo
  done
}

cleanup() {
  if [ -n "${DEMO_PROFILE_ID}" ]; then
    "${IGLOO_SHELL_BIN}" daemon stop --profile "${DEMO_PROFILE_ID}" >/dev/null 2>&1 || true
  fi
}

if [ ! -f "${DEVTOOLS_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${DEVTOOLS_DIR} (missing Cargo.toml)"
  exit 1
fi

if [ ! -f "${IGLOO_SHELL_DIR}/Cargo.toml" ]; then
  echo "igloo-shell source is not available at ${IGLOO_SHELL_DIR} (missing Cargo.toml)"
  exit 1
fi

if [ ! -x "${DEVTOOLS_BIN}" ]; then
  echo "missing required binary: ${DEVTOOLS_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p bifrost-devtools --bin bifrost-devtools"
  exit 1
fi

if [ ! -x "${IGLOO_SHELL_BIN}" ]; then
  echo "missing required binary: ${IGLOO_SHELL_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p igloo-shell-cli --bin igloo-shell"
  exit 1
fi

member_index "${IGLOO_SHELL_DEMO_MEMBER}" >/dev/null || {
  echo "unsupported IGLOO_SHELL_DEMO_MEMBER: ${IGLOO_SHELL_DEMO_MEMBER}"
  exit 1
}

parse_onboard_members "${IGLOO_SHELL_DEMO_INVITE_MEMBERS}"

mkdir -p "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}"
rm -f "${IGLOO_SHELL_DEMO_CONTROL_SOCKET}" "${IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE}"
for member in "${ONBOARD_MEMBERS[@]}"; do
  rm -f "$(onboard_file "${member}")"
done
cleanup_shell_home
prepare_shell_home

echo "==> Waiting for relay ${DEV_RELAY_INTERNAL_URL}"
wait_for_relay "${DEV_RELAY_HOST}" "${DEV_RELAY_PORT}" 60

cd "${IGLOO_SHELL_DIR}"

generate_demo_material_if_needed
ensure_onboard_members_exist
configure_relay_profile
import_demo_profile
start_demo_daemon
wait_for_socket "${IGLOO_SHELL_DEMO_CONTROL_SOCKET}" 60
wait_for_onboard_ready "${DEMO_PROFILE_ID}" 60
export_onboarding_packages
relax_artifact_permissions

trap cleanup EXIT INT TERM

print_onboarding_packages
if [ -n "${DEMO_DAEMON_LOG}" ]; then
  touch "${DEMO_DAEMON_LOG}"
  exec tail -F "${DEMO_DAEMON_LOG}"
fi
exec tail -f /dev/null
