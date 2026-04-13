#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

ALLOWED_HELPERS=(
  "test/igloo-chrome/support/ui.ts"
  "test/igloo-pwa/support/ui.ts"
)

mapfile -t imported_contract_files < <(rg -l "e2e-test-ids" test/igloo-chrome test/igloo-pwa || true)
for file in "${imported_contract_files[@]}"; do
  allowed=0
  for helper in "${ALLOWED_HELPERS[@]}"; do
    if [[ "${file}" == "${helper}" ]]; then
      allowed=1
      break
    fi
  done

  if [[ "${allowed}" -ne 1 ]]; then
    echo "critical browser E2E hooks must only be imported in shared helper modules: ${file}" >&2
    exit 1
  fi
done

if rg -n \
  -e "getByTestId\\('stored-profile-load'\\)" \
  -e 'getByTestId\("stored-profile-load"\)' \
  -e "getByTestId\\('stored-profile-unlock-submit'\\)" \
  -e 'getByTestId\("stored-profile-unlock-submit"\)' \
  -e "getByTestId\\('landing-continue-onboarding'\\)" \
  -e 'getByTestId\("landing-continue-onboarding"\)' \
  -e "getByTestId\\('maintenance-rotate-share'\\)" \
  -e 'getByTestId\("maintenance-rotate-share"\)' \
  -e "getByTestId\\('rotation-connect-submit'\\)" \
  -e 'getByTestId\("rotation-connect-submit"\)' \
  -e "getByTestId\\('rotation-confirm-submit'\\)" \
  -e 'getByTestId\("rotation-confirm-submit"\)' \
  test/igloo-pwa test/igloo-chrome \
  --glob '!test/igloo-pwa/support/ui.ts' \
  --glob '!test/igloo-chrome/support/ui.ts'
then
  echo "critical browser E2E hooks must route through shared helpers only" >&2
  exit 1
fi

echo "ok: browser E2E selector contract is helper-owned"
