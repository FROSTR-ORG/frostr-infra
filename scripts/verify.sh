#!/usr/bin/env bash
#
# Canonical "did I break anything" gate, with a machine-readable result.
#
# Runs the test/ verify lane (lean guards + typecheck + the render-only @fast e2e
# lane — defined once as `test:verify` in test/package.json) and mirrors its
# pass/fail into .tmp/agent/verify.json so an agent can read the outcome as data
# instead of interpreting an exit code. The exit code stays authoritative: this
# script exits with the lane's exit code.
#
# Usage: make verify        (preferred)
#        scripts/verify.sh

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="${ROOT_DIR}/.tmp/agent"

npm --prefix "${ROOT_DIR}/test" run test:verify
code=$?

mkdir -p "${AGENT_DIR}"
if [[ "${code}" -eq 0 ]]; then ok="true"; else ok="false"; fi
printf '{"command":"verify","ok":%s,"exitCode":%d}\n' "${ok}" "${code}" >"${AGENT_DIR}/verify.json"

exit "${code}"
