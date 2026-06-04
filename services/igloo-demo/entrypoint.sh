#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="/workspace"
# Binaries are compiled into the image (see services/demo/Dockerfile) and installed
# on PATH; no host bind-mount or source tree is required.
DEVTOOLS_BIN="${BIFROST_DEVTOOLS_BIN:-bifrost-devtools}"
IGLOO_SHELL_BIN="${IGLOO_SHELL_BIN:-igloo-shell}"

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
# Short alias for the (long, bind-mounted) XDG_STATE_HOME. Lives under
# world-writable /tmp because `/` is not writable by the non-root `igloo`
# container user (so the historical `/w` at the filesystem root cannot be
# created).
IGLOO_SHELL_DEMO_STATE_LINK="${IGLOO_SHELL_DEMO_STATE_LINK:-/tmp/w}"
# Short, writable XDG_RUNTIME_DIR for the daemon's AF_UNIX control socket.
# igloo-shell shortens the socket to `<XDG_RUNTIME_DIR>/igloo-shell-<hash>.sock`
# when the state-dir path would exceed the 100-byte sun_path budget; the
# default `/run/user/$UID` does not exist for the non-root demo user, so the
# fallback would otherwise fail with SocketPathTooLong.
IGLOO_SHELL_DEMO_RUNTIME_DIR="${IGLOO_SHELL_DEMO_RUNTIME_DIR:-/tmp/r}"
IGLOO_SHELL_DEMO_TMPDIR="${IGLOO_SHELL_DEMO_TMPDIR:-${IGLOO_SHELL_DEMO_ARTIFACT_DIR}/tmp}"

export IGLOO_SHELL_BIN
export DEV_RELAY_HOST
export DEV_RELAY_PORT

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${IGLOO_SHELL_DEMO_XDG_ROOT}/config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${IGLOO_SHELL_DEMO_XDG_ROOT}/data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${IGLOO_SHELL_DEMO_STATE_LINK}}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${IGLOO_SHELL_DEMO_RUNTIME_DIR}}"
export IGLOO_SHELL_TEST_PASSPHRASE="${IGLOO_SHELL_DEMO_PASSPHRASE}"
export TMPDIR="${TMPDIR:-${IGLOO_SHELL_DEMO_TMPDIR}}"

declare -a ONBOARD_MEMBERS=()
DEMO_PROFILE_ID=""
DEMO_DAEMON_LOG=""

# Source shared polling helpers from the services bind-mount.
# shellcheck disable=SC1091
source "${ROOT_DIR}/services/igloo-demo/lib-wait.sh"

cleanup() {
  if [ -n "${DEMO_PROFILE_ID}" ]; then
    "${IGLOO_SHELL_BIN}" daemon stop --profile "${DEMO_PROFILE_ID}" >/dev/null 2>&1 || true
  fi
}

# Register cleanup trap before any side effects (file writes, daemon spawns).
trap cleanup EXIT INT TERM

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
    "${XDG_RUNTIME_DIR}" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/config" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/data" \
    "${IGLOO_SHELL_DEMO_XDG_ROOT}/state"
  # XDG_RUNTIME_DIR must be private (0700) per spec; the control socket lives here.
  chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
  if [ "${XDG_STATE_HOME}" = "${IGLOO_SHELL_DEMO_STATE_LINK}" ]; then
    ln -sfn "${IGLOO_SHELL_DEMO_XDG_ROOT}/state" "${IGLOO_SHELL_DEMO_STATE_LINK}"
  fi
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
      --passphrase "${IGLOO_SHELL_TEST_PASSPHRASE}" \
      --json
  )"
  DEMO_PROFILE_ID="$(printf '%s' "${import_json}" | jq -r '.import.profile.id // empty')"
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
    chmod 0600 "${path}" >/dev/null 2>&1 || true
    return 0
  fi

  old_umask="$(umask)"
  umask 077
  od -An -tx1 -N"${IGLOO_SHELL_DEMO_PASSWORD_BYTES}" /dev/urandom | tr -d ' \n' > "${path}"
  umask "${old_umask}"
  chmod 0600 "${path}"
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
      --passphrase-env IGLOO_SHELL_TEST_PASSPHRASE \
      >/dev/null
}

start_demo_daemon() {
  local daemon_json
  local daemon_token
  local daemon_socket_bind
  local daemon_socket_link_name
  local daemon_socket_link_target
  local daemon_socket_dir

  # Bucket C removed the implicit profile-passphrase env fallback, so the
  # daemon must be handed the passphrase explicitly. Pipe it on stdin (the CLI
  # reads the passphrase from a stdin pipe) rather than putting it on argv.
  daemon_json="$(printf '%s\n' "${IGLOO_SHELL_TEST_PASSPHRASE}" \
    | "${IGLOO_SHELL_BIN}" daemon start --profile "${DEMO_PROFILE_ID}")"
  daemon_token="$(printf '%s' "${daemon_json}" | jq -r '.token // empty')"
  daemon_socket_bind="$(printf '%s' "${daemon_json}" | jq -r '.socket_path // empty')"
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

  # Token file must stay private to the running user.
  (
    umask 077
    printf '%s\n' "${daemon_token}" > "${IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE}"
  )
  chmod 0600 "${IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE}" >/dev/null 2>&1 || true

  # Ensure the socket directory exists with tight perms; no world-writable fallback.
  daemon_socket_dir="$(dirname "${daemon_socket_bind}")"
  if [ -d "${daemon_socket_dir}" ]; then
    chmod 0700 "${daemon_socket_dir}" >/dev/null 2>&1 || true
  fi
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

if ! command -v "${DEVTOOLS_BIN}" >/dev/null 2>&1; then
  echo "missing required binary: ${DEVTOOLS_BIN} (expected on PATH; rebuild the image)"
  exit 1
fi

if ! command -v "${IGLOO_SHELL_BIN}" >/dev/null 2>&1; then
  echo "missing required binary: ${IGLOO_SHELL_BIN} (expected on PATH; rebuild the image)"
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
wait_for_relay "${DEV_RELAY_HOST}" "${DEV_RELAY_PORT}"

# Run from a stable, always-present directory. igloo-shell uses explicit XDG_*
# dirs (set above), so its state/config don't depend on the working directory.
cd "${ROOT_DIR}"

generate_demo_material_if_needed
ensure_onboard_members_exist
configure_relay_profile
import_demo_profile
start_demo_daemon
wait_for_socket "${IGLOO_SHELL_DEMO_CONTROL_SOCKET}"
wait_for_onboard_ready "${DEMO_PROFILE_ID}"
export_onboarding_packages

print_onboarding_packages
if [ -n "${DEMO_DAEMON_LOG}" ]; then
  touch "${DEMO_DAEMON_LOG}"
  exec tail -F "${DEMO_DAEMON_LOG}"
fi
exec tail -f /dev/null
