#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="/workspace"
BIFROST_RS_DIR="${ROOT_DIR}/repos/bifrost-rs"
BIFROST_BIN="${BIFROST_RS_DIR}/target/debug/bifrost"
BIFROST_DEVTOOLS_BIN="${BIFROST_RS_DIR}/target/debug/bifrost-devtools"

DEV_RELAY_HOST="${DEV_RELAY_HOST:-dev-relay}"
DEV_RELAY_PORT="${DEV_RELAY_PORT:-8194}"
DEV_RELAY_INTERNAL_URL="${DEV_RELAY_INTERNAL_URL:-ws://${DEV_RELAY_HOST}:${DEV_RELAY_PORT}}"
DEV_RELAY_EXTERNAL_HOST="${DEV_RELAY_EXTERNAL_HOST:-127.0.0.1}"
DEV_RELAY_EXTERNAL_URL="${DEV_RELAY_EXTERNAL_URL:-ws://${DEV_RELAY_EXTERNAL_HOST}:${DEV_RELAY_PORT}}"
BIFROST_DEMO_MEMBER="${BIFROST_DEMO_MEMBER:-alice}"
BIFROST_DEMO_INVITE_MEMBERS="${BIFROST_DEMO_INVITE_MEMBERS:-bob,carol}"
BIFROST_DEMO_THRESHOLD="${BIFROST_DEMO_THRESHOLD:-2}"
BIFROST_DEMO_COUNT="${BIFROST_DEMO_COUNT:-3}"
BIFROST_DEMO_DIR="${BIFROST_DEMO_DIR:-${ROOT_DIR}/data/test-harness/demo-2of3}"
BIFROST_DEMO_CONTROL_SOCKET="${BIFROST_DEMO_CONTROL_SOCKET:-${ROOT_DIR}/data/test-harness/bifrost-${BIFROST_DEMO_MEMBER}.sock}"
BIFROST_DEMO_CONTROL_TOKEN="${BIFROST_DEMO_CONTROL_TOKEN:-dev-harness-token}"
BIFROST_DEMO_CONTROL_TOKEN_FILE="${BIFROST_DEMO_CONTROL_TOKEN_FILE:-${ROOT_DIR}/data/test-harness/bifrost-${BIFROST_DEMO_MEMBER}.token}"
BIFROST_DEMO_ARTIFACT_DIR="${BIFROST_DEMO_ARTIFACT_DIR:-${ROOT_DIR}/data/test-harness}"
BIFROST_DEMO_PASSWORD_BYTES="${BIFROST_DEMO_PASSWORD_BYTES:-16}"

declare -a INVITE_MEMBERS=()
BIFROST_PID=""

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

parse_invite_members() {
  local raw="$1"
  local part=""
  INVITE_MEMBERS=()

  IFS=',' read -r -a parts <<< "${raw}"
  for part in "${parts[@]}"; do
    part="$(trim "${part}")"
    if [ -n "${part}" ]; then
      INVITE_MEMBERS+=("${part}")
    fi
  done

  if [ "${#INVITE_MEMBERS[@]}" -eq 0 ]; then
    echo "BIFROST_DEMO_INVITE_MEMBERS must include at least one recipient"
    exit 1
  fi
}

onboard_file() {
  printf '%s/onboard-%s.txt' "${BIFROST_DEMO_ARTIFACT_DIR}" "$1"
}

password_file() {
  printf '%s/onboard-%s.password.txt' "${BIFROST_DEMO_ARTIFACT_DIR}" "$1"
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

cleanup_demo_dir() {
  mkdir -p "${BIFROST_DEMO_DIR}"
  rm -f \
    "${BIFROST_DEMO_DIR}/group.json" \
    "${BIFROST_DEMO_DIR}/share-"*.json \
    "${BIFROST_DEMO_DIR}/bifrost-"*.json \
    "${BIFROST_DEMO_DIR}/state-"*.json \
    "${BIFROST_DEMO_DIR}/state-"*.lock
}

has_demo_material() {
  [ -f "${BIFROST_DEMO_DIR}/group.json" ] &&
    [ -f "${BIFROST_DEMO_DIR}/share-${BIFROST_DEMO_MEMBER}.json" ] &&
    [ -f "${BIFROST_DEMO_DIR}/bifrost-${BIFROST_DEMO_MEMBER}.json" ]
}

generate_demo_material_if_needed() {
  if has_demo_material; then
    echo "==> Reusing existing demo material in ${BIFROST_DEMO_DIR}"
    rm -f \
      "${BIFROST_DEMO_DIR}/state-"*.json \
      "${BIFROST_DEMO_DIR}/state-"*.lock
    return
  fi

  echo "==> Generating ${BIFROST_DEMO_THRESHOLD}-of-${BIFROST_DEMO_COUNT} demo material in ${BIFROST_DEMO_DIR}"
  cleanup_demo_dir
  "${BIFROST_DEVTOOLS_BIN}" keygen \
    --out-dir "${BIFROST_DEMO_DIR}" \
    --threshold "${BIFROST_DEMO_THRESHOLD}" \
    --count "${BIFROST_DEMO_COUNT}" \
    --relay "${DEV_RELAY_INTERNAL_URL}"
}

ensure_invite_members_exist() {
  local member=""
  for member in "${INVITE_MEMBERS[@]}"; do
    if [ "${member}" = "${BIFROST_DEMO_MEMBER}" ]; then
      echo "BIFROST_DEMO_INVITE_MEMBERS must not include ${BIFROST_DEMO_MEMBER}"
      exit 1
    fi
    need_file "${BIFROST_DEMO_DIR}/share-${member}.json"
  done
}

generate_password_file_if_needed() {
  local path="$1"

  if [ -s "${path}" ]; then
    chmod 0644 "${path}" >/dev/null 2>&1 || true
    return 0
  fi

  umask 077
  od -An -tx1 -N"${BIFROST_DEMO_PASSWORD_BYTES}" /dev/urandom | tr -d ' \n' > "${path}"
  chmod 0644 "${path}"
}

assemble_invite() {
  local member="$1"
  local password_path
  local invite_path
  local token

  password_path="$(password_file "${member}")"
  invite_path="$(onboard_file "${member}")"
  generate_password_file_if_needed "${password_path}"

  echo "==> Creating onboarding package for ${member}"
  token="$(
    "${BIFROST_BIN}" \
      --config "${BIFROST_DEMO_DIR}/bifrost-${BIFROST_DEMO_MEMBER}.json" \
      invite create \
      --relay "${DEV_RELAY_EXTERNAL_URL}"
  )"

  "${BIFROST_DEVTOOLS_BIN}" invite assemble \
    --token "${token}" \
    --share "${BIFROST_DEMO_DIR}/share-${member}.json" \
    --password-file "${password_path}" \
    > "${invite_path}"
}

assemble_invites() {
  local member=""
  for member in "${INVITE_MEMBERS[@]}"; do
    assemble_invite "${member}"
  done
}

print_invites() {
  local member=""
  local invite_path
  local password_path

  echo
  echo "Demo node is ready."
  echo "Relay (internal): ${DEV_RELAY_INTERNAL_URL}"
  echo "Relay (external): ${DEV_RELAY_EXTERNAL_URL}"
  echo "Node member:      ${BIFROST_DEMO_MEMBER}"
  echo "Invite members:   ${INVITE_MEMBERS[*]}"
  echo "Control socket:   ${BIFROST_DEMO_CONTROL_SOCKET}"
  echo

  for member in "${INVITE_MEMBERS[@]}"; do
    invite_path="$(onboard_file "${member}")"
    password_path="$(password_file "${member}")"
    echo "Recipient:        ${member}"
    echo "Password file:    ${password_path}"
    echo "Invite file:      ${invite_path}"
    echo "Password:"
    cat "${password_path}"
    echo
    echo "bfonboard package:"
    cat "${invite_path}"
    echo
  done
}

cleanup() {
  if [ -n "${BIFROST_PID}" ] && kill -0 "${BIFROST_PID}" >/dev/null 2>&1; then
    kill "${BIFROST_PID}" >/dev/null 2>&1 || true
    wait "${BIFROST_PID}" >/dev/null 2>&1 || true
  fi
}

if [ ! -f "${BIFROST_RS_DIR}/Cargo.toml" ]; then
  echo "bifrost-rs source is not available at ${BIFROST_RS_DIR} (missing Cargo.toml)"
  exit 1
fi

if [ ! -x "${BIFROST_BIN}" ]; then
  echo "missing required binary: ${BIFROST_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p bifrost-app --bin bifrost"
  exit 1
fi

if [ ! -x "${BIFROST_DEVTOOLS_BIN}" ]; then
  echo "missing required binary: ${BIFROST_DEVTOOLS_BIN}"
  echo "build it first with:"
  echo "  cargo build --locked -p bifrost-dev --bin bifrost-devtools"
  exit 1
fi

member_index "${BIFROST_DEMO_MEMBER}" >/dev/null || {
  echo "unsupported BIFROST_DEMO_MEMBER: ${BIFROST_DEMO_MEMBER}"
  exit 1
}

parse_invite_members "${BIFROST_DEMO_INVITE_MEMBERS}"

mkdir -p "${BIFROST_DEMO_ARTIFACT_DIR}"
rm -f "${BIFROST_DEMO_CONTROL_SOCKET}" "${BIFROST_DEMO_CONTROL_TOKEN_FILE}"
for member in "${INVITE_MEMBERS[@]}"; do
  rm -f "$(onboard_file "${member}")"
done

echo "==> Waiting for relay ${DEV_RELAY_INTERNAL_URL}"
wait_for_relay "${DEV_RELAY_HOST}" "${DEV_RELAY_PORT}" 60

cd "${BIFROST_RS_DIR}"

generate_demo_material_if_needed
ensure_invite_members_exist
assemble_invites

printf '%s\n' "${BIFROST_DEMO_CONTROL_TOKEN}" > "${BIFROST_DEMO_CONTROL_TOKEN_FILE}"

trap cleanup EXIT INT TERM

"${BIFROST_BIN}" \
  --config "${BIFROST_DEMO_DIR}/bifrost-${BIFROST_DEMO_MEMBER}.json" \
  listen \
  --control-socket "${BIFROST_DEMO_CONTROL_SOCKET}" \
  --control-token "${BIFROST_DEMO_CONTROL_TOKEN}" &
BIFROST_PID="$!"

wait_for_socket "${BIFROST_DEMO_CONTROL_SOCKET}" 60
print_invites
wait "${BIFROST_PID}"
