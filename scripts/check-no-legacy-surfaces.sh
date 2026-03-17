#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if rg -n \
  -e 'GET_RUNTIME_PEER_POLICIES' \
  -e 'HostCommand::Policies' \
  -e 'ControlCommand::Policies' \
  -e 'readiness_explanation' \
  -e 'PeerConfig\.policy' \
  -e 'set_policy\(' \
  -e 'policies\(' \
  repos/bifrost-rs repos/igloo-shared repos/igloo-shell repos/igloo-home repos/igloo-pwa repos/igloo-chrome \
  --glob '!**/dist/**' \
  --glob '!**/target/**'
then
  echo "legacy policy/runtime surfaces are still present" >&2
  exit 1
fi

echo "ok: no removed legacy policy/runtime surfaces found"
