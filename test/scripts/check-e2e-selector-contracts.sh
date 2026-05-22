#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

scope="${1:-all}"
case "${scope}" in
  all)
    search_roots=(test/igloo-pwa test/igloo-chrome)
    allowed_helpers=("test/igloo-pwa/support/ui.ts" "test/igloo-chrome/support/ui.ts")
    ignored_globs=("!test/igloo-pwa/support/ui.ts" "!test/igloo-chrome/support/ui.ts")
    ;;
  pwa|igloo-pwa)
    search_roots=(test/igloo-pwa)
    allowed_helpers=("test/igloo-pwa/support/ui.ts")
    ignored_globs=("!test/igloo-pwa/support/ui.ts")
    ;;
  chrome|igloo-chrome)
    search_roots=(test/igloo-chrome)
    allowed_helpers=("test/igloo-chrome/support/ui.ts")
    ignored_globs=("!test/igloo-chrome/support/ui.ts")
    ;;
  *)
    echo "usage: test/scripts/check-e2e-selector-contracts.sh [all|pwa|chrome]" >&2
    exit 1
    ;;
esac

imported_contract_files=()
while IFS= read -r file; do
  imported_contract_files+=("${file}")
done < <(rg -l "e2e-test-ids" "${search_roots[@]}" || true)
for file in "${imported_contract_files[@]}"; do
  allowed=0
  for helper in "${allowed_helpers[@]}"; do
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

rg_ignore_args=()
for ignored_glob in "${ignored_globs[@]}"; do
  rg_ignore_args+=(--glob "${ignored_glob}")
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
  "${search_roots[@]}" \
  "${rg_ignore_args[@]}"
then
  echo "critical browser E2E hooks must route through shared helpers only" >&2
  exit 1
fi

echo "ok: browser E2E selector contract is helper-owned"
