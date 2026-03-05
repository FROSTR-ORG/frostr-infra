#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIFROST_RS_DIR="${ROOT_DIR}/repos/bifrost-rs"
IGLOO_WEB_DIR="${ROOT_DIR}/repos/igloo-web"
DEMO_DIR="${DEMO_DIR:-${BIFROST_RS_DIR}/dev/demo-2of2}"
SESSION_NAME="${SESSION_NAME:-igloo-web-demo}"
LOG_DIR="${LOG_DIR:-${BIFROST_RS_DIR}/dev/demo-logs}"
RELAY_HOST="${RELAY_HOST:-127.0.0.1}"
RELAY_PORT="${RELAY_PORT:-8194}"
WEB_HOST="${WEB_HOST:-127.0.0.1}"
WEB_PORT="${WEB_PORT:-5173}"
ATTACH="${ATTACH:-1}"
FORCE_WASM_BUILD="${FORCE_WASM_BUILD:-0}"
FORCE_KEYGEN="${FORCE_KEYGEN:-0}"

RELAY_URL="ws://${RELAY_HOST}:${RELAY_PORT}"
ONBOARD_FILE="${DEMO_DIR}/onboard-bob.txt"
WASM_OUT_DIR="${IGLOO_WEB_DIR}/public/wasm"
WASM_TARGET="${WASM_OUT_DIR}/bifrost_bridge_wasm_bg.wasm"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

need_cmd cargo
need_cmd node
need_cmd npm
need_cmd tmux

cleanup_demo_state() {
  rm -f \
    "${DEMO_DIR}/group.json" \
    "${DEMO_DIR}/share-alice.json" \
    "${DEMO_DIR}/share-bob.json" \
    "${DEMO_DIR}/bifrost-alice.json" \
    "${DEMO_DIR}/bifrost-bob.json" \
    "${DEMO_DIR}/onboard-bob.txt" \
    "${DEMO_DIR}/state-alice.json" \
    "${DEMO_DIR}/state-bob.json" \
    "${DEMO_DIR}/state-alice.lock" \
    "${DEMO_DIR}/state-bob.lock"
}

has_demo_material() {
  [[ -f "${DEMO_DIR}/group.json" ]] &&
    [[ -f "${DEMO_DIR}/share-alice.json" ]] &&
    [[ -f "${DEMO_DIR}/share-bob.json" ]] &&
    [[ -f "${DEMO_DIR}/bifrost-alice.json" ]]
}

wait_for_tmux_panes() {
  local attempts=20
  local expected=3
  local count=0
  local panes=""
  while (( attempts > 0 )); do
    panes="$(tmux list-panes -t "${SESSION_NAME}" -F '#{pane_index}:#{pane_dead}:#{pane_current_command}' 2>/dev/null || true)"
    count="$(printf '%s\n' "${panes}" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "${count}" == "${expected}" ]]; then
      if ! printf '%s\n' "${panes}" | awk -F: '$2 != "0" { exit 1 }'; then
        break
      fi
      return 0
    fi
    sleep 0.25
    (( attempts-- ))
  done

  echo "error: demo services did not stay up (expected ${expected} panes, got ${count})" >&2
  if [[ -n "${panes}" ]]; then
    echo "tmux panes:" >&2
    printf '%s\n' "${panes}" >&2
  fi
  echo >&2
  echo "relay pane log tail:" >&2
  tmux capture-pane -p -t "${SESSION_NAME}:demo.0" 2>/dev/null | tail -n 40 >&2 || true
  echo >&2
  echo "peer pane log tail:" >&2
  tmux capture-pane -p -t "${SESSION_NAME}:demo.1" 2>/dev/null | tail -n 40 >&2 || true
  echo >&2
  echo "web pane log tail:" >&2
  tmux capture-pane -p -t "${SESSION_NAME}:demo.2" 2>/dev/null | tail -n 40 >&2 || true
  return 1
}

set_tmux_pane_titles() {
  tmux set -t "${SESSION_NAME}:demo" pane-border-status top
  tmux set -t "${SESSION_NAME}:demo" pane-border-format "#{pane_index}:#{pane_title}"
}

should_build_wasm() {
  if [[ "${FORCE_WASM_BUILD}" == "1" ]]; then
    return 0
  fi

  if [[ ! -f "${WASM_TARGET}" ]]; then
    return 0
  fi

  local build_script="${IGLOO_WEB_DIR}/scripts/build-bridge-wasm.sh"
  if [[ "${build_script}" -nt "${WASM_TARGET}" ]]; then
    return 0
  fi

  if find \
    "${BIFROST_RS_DIR}/crates/bifrost-bridge-wasm" \
    "${BIFROST_RS_DIR}/crates/bifrost-bridge-core" \
    "${BIFROST_RS_DIR}/crates/bifrost-bridge" \
    "${BIFROST_RS_DIR}/crates/bifrost-signer" \
    -type f -newer "${WASM_TARGET}" -print -quit | grep -q .; then
    return 0
  fi

  if [[ "${BIFROST_RS_DIR}/Cargo.toml" -nt "${WASM_TARGET}" || "${BIFROST_RS_DIR}/Cargo.lock" -nt "${WASM_TARGET}" ]]; then
    return 0
  fi

  return 1
}

if [[ ! -f "${BIFROST_RS_DIR}/Cargo.toml" ]]; then
  echo "error: missing bifrost-rs workspace at ${BIFROST_RS_DIR}" >&2
  exit 1
fi

if [[ ! -f "${IGLOO_WEB_DIR}/package.json" ]]; then
  echo "error: missing igloo-web package at ${IGLOO_WEB_DIR}" >&2
  exit 1
fi

mkdir -p "${DEMO_DIR}"
mkdir -p "${LOG_DIR}"

if [[ "${FORCE_KEYGEN}" == "1" ]] || ! has_demo_material; then
  echo "==> Generating 2-of-2 demo keyset in ${DEMO_DIR}"
  cleanup_demo_state
  (
    cd "${BIFROST_RS_DIR}"
    cargo run -p bifrost-dev --bin bifrost-devtools -- \
      keygen \
      --out-dir "${DEMO_DIR}" \
      --threshold 2 \
      --count 2 \
      --relay "${RELAY_URL}"
  )
else
  echo "==> Reusing existing demo keyset in ${DEMO_DIR} (set FORCE_KEYGEN=1 to regenerate)"
  rm -f "${DEMO_DIR}/state-alice.lock" "${DEMO_DIR}/state-bob.lock"
fi

echo "==> Ensuring igloo-web dependencies are installed"
(
  cd "${IGLOO_WEB_DIR}"
  if [[ ! -d node_modules ]]; then
    npm install
  fi
)

if should_build_wasm; then
  echo "==> Building wasm bridge assets"
  (
    cd "${IGLOO_WEB_DIR}"
    npm run build:bridge-wasm
  )
else
  echo "==> Reusing existing wasm bridge assets (${WASM_TARGET})"
fi

echo "==> Building onboarding package for bob"
(
  cd "${IGLOO_WEB_DIR}"
  DEMO_DIR="${DEMO_DIR}" RELAY_URL="${RELAY_URL}" node --input-type=module - <<'EOF' > "${ONBOARD_FILE}"
import fs from 'node:fs';
import path from 'node:path';
import { bech32m } from '@scure/base';

const demoDir = path.resolve(process.env.DEMO_DIR || '../bifrost-rs/dev/demo-2of2');
const group = JSON.parse(fs.readFileSync(path.join(demoDir, 'group.json'), 'utf8'));
const share = JSON.parse(fs.readFileSync(path.join(demoDir, 'share-bob.json'), 'utf8'));
const relay = process.env.RELAY_URL || 'ws://127.0.0.1:8194';

const alice = group.members.find((m) => m.idx === 1);
if (!alice) throw new Error('alice member not found');

const out = [];
const push = (...bytes) => out.push(...bytes);
const hexBytes = (hex) => hex.match(/../g).map((v) => parseInt(v, 16));
const u16be = (n) => [ (n >> 8) & 0xff, n & 0xff ];
const u32be = (n) => [ (n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff ];

push(...u32be(share.idx));
push(...hexBytes(share.seckey));
push(...hexBytes(alice.pubkey.slice(2)));

const relayBytes = new TextEncoder().encode(relay);
push(...u16be(1));
push(...u16be(relayBytes.length));
push(...relayBytes);

const words = bech32m.toWords(Uint8Array.from(out));
const onboard = bech32m.encode('bfonboard', words, 4096);
console.log(onboard);
EOF
)

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "==> Replacing existing tmux session: ${SESSION_NAME}"
  tmux kill-session -t "${SESSION_NAME}"
fi

echo "==> Starting tmux session ${SESSION_NAME}"
tmux new-session -d -s "${SESSION_NAME}" -n demo \
  "cd '${BIFROST_RS_DIR}' && cargo run -p bifrost-dev --bin bifrost-devtools -- relay ${RELAY_PORT}"

RELAY_PANE="$(tmux display-message -p -t "${SESSION_NAME}:demo.0" '#{pane_id}')"
PEER_PANE="$(tmux split-window -h -t "${SESSION_NAME}:demo" -P -F '#{pane_id}' \
  "cd '${BIFROST_RS_DIR}' && echo 'Peer node output (alice) -> ${LOG_DIR}/peer-alice.log' && echo '---' && cargo run -p bifrost-app --bin bifrost -- --config '${DEMO_DIR}/bifrost-alice.json' listen 2>&1 | tee '${LOG_DIR}/peer-alice.log'"
)"

WEB_PANE="$(tmux split-window -v -t "${SESSION_NAME}:demo.0" -P -F '#{pane_id}' \
  "cd '${IGLOO_WEB_DIR}' && npm run dev -- --host ${WEB_HOST} --port ${WEB_PORT}"
)"

tmux select-layout -t "${SESSION_NAME}:demo" tiled
if ! wait_for_tmux_panes; then
  tmux kill-session -t "${SESSION_NAME}" || true
  exit 1
fi
tmux select-pane -t "${RELAY_PANE}" -T relay
tmux select-pane -t "${PEER_PANE}" -T peer
tmux select-pane -t "${WEB_PANE}" -T web
set_tmux_pane_titles

ONBOARD_ENCODED="$(node -e "const fs=require('fs');const v=fs.readFileSync(process.argv[1],'utf8').trim();process.stdout.write(encodeURIComponent(v));" "${ONBOARD_FILE}")"
ONBOARD_LINK="http://${WEB_HOST}:${WEB_PORT}/?onboard=${ONBOARD_ENCODED}"

echo
echo "Demo environment is up."
echo "Relay:       ${RELAY_URL}"
echo "Web:         http://${WEB_HOST}:${WEB_PORT}"
echo "Onboarding:  ${ONBOARD_FILE}"
echo "Onboard URL: ${ONBOARD_LINK}"
echo "Peer log:    ${LOG_DIR}/peer-alice.log"
echo "Tmux panes:  $(tmux list-panes -t "${SESSION_NAME}:demo" -F '#{pane_index}:#{pane_title}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
echo
echo "bfonboard package:"
cat "${ONBOARD_FILE}"
echo
echo "Use this package in igloo-web onboarding, then click Start Signer."

if [[ "${ATTACH}" == "1" ]]; then
  on_interrupt_before_attach() {
    echo
    echo "Stopping demo session ${SESSION_NAME}..."
    tmux kill-session -t "${SESSION_NAME}" 2>/dev/null || true
    exit 130
  }

  trap on_interrupt_before_attach INT
  echo
  echo "Onboarding file: ${ONBOARD_FILE}"
  echo "Press Enter to attach to tmux session ${SESSION_NAME} (detach: Ctrl-b d)."
  echo "Press Ctrl-C to stop relay/peer/web and exit."
  read -r
  trap - INT
  exec tmux attach -t "${SESSION_NAME}"
fi
