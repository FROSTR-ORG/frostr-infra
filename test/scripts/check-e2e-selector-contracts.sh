#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

scope="${1:-all}"
pwa_in_scope=0
case "${scope}" in
  all)
    search_roots=(test/igloo-pwa test/igloo-chrome)
    allowed_helpers=("test/igloo-pwa/support/ui.ts" "test/igloo-chrome/support/ui.ts")
    pwa_in_scope=1
    ;;
  pwa|igloo-pwa)
    search_roots=(test/igloo-pwa)
    allowed_helpers=("test/igloo-pwa/support/ui.ts")
    pwa_in_scope=1
    ;;
  chrome|igloo-chrome)
    search_roots=(test/igloo-chrome)
    allowed_helpers=("test/igloo-chrome/support/ui.ts")
    ;;
  *)
    echo "usage: test/scripts/check-e2e-selector-contracts.sh [all|pwa|chrome]" >&2
    exit 1
    ;;
esac

# 1. The e2e-test-id registry must be imported only in support/ui.ts. Page objects
#    (support/pages.ts) consume it via the TID re-export from support/ui.ts.
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

# 2. Spec files must not use getByTestId directly — they drive the UI through the
#    support/pages page objects (which own the test-id locators). `@agent`
#    render-and-verify tool specs (agent-screenshot.spec.ts) are exempt: they are
#    headless capture tools, not gated tests, and waiting on a stable surface
#    test-id is the right primitive for them.
spec_roots=()
for root in "${search_roots[@]}"; do
  spec_roots+=("${root}/specs")
done
if rg -n "getByTestId\\(" "${spec_roots[@]}" -g '!**/agent-screenshot.spec.ts' 2>/dev/null; then
  echo "specs must not call getByTestId directly; route through support/pages page objects" >&2
  exit 1
fi

# 3. igloo-pwa specs must be copy-independent: interaction selectors (button/tab by
#    accessible name, label, placeholder) and the mutating flow CSS classes belong
#    in the page objects, not specs. getByText / getByRole('heading') stay allowed
#    as deliberate content assertions. (igloo-chrome specs are migrated separately.)
if [[ "${pwa_in_scope}" -eq 1 ]]; then
  if rg -n \
    -e "getByRole\\('(button|tab)'" \
    -e "getByRole\\(\"(button|tab)\"" \
    -e "getByLabel\\(" \
    -e "getByPlaceholder\\(" \
    -e "igloo-welcome-profile-row" \
    -e "igloo-create-distribution-card" \
    -e "igloo-create-share-option" \
    -e "igloo-create-relay-row" \
    test/igloo-pwa/specs 2>/dev/null; then
    echo "igloo-pwa specs must drive the UI via support/pages (no role/label/placeholder/class locators)" >&2
    exit 1
  fi
fi

echo "ok: browser E2E selector contract is helper-owned"
