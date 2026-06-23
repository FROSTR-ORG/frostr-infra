#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Static convergence guard: verify all three client landing surfaces consume the
# shared WelcomeReturningHero and have not reintroduced bespoke landing components.
# This is the recurrence-preventer for landing UI divergence across clients.

check_client() {
  local client="$1"
  local target="$2"

  if [[ ! -e "${target}" ]]; then
    echo "error: ${client} landing target not found: ${target}" >&2
    exit 1
  fi

  # Assert the shared hero is referenced (proves the client renders the converged landing).
  if ! grep -R -q --include='*.ts' --include='*.tsx' "WelcomeReturningHero" "${target}"; then
    echo "error: ${client} does not reference WelcomeReturningHero — landing has diverged from the shared hero" >&2
    echo "  target: ${target}" >&2
    exit 1
  fi

  # Assert the deleted bespoke landing components have not been reintroduced.
  if grep -R -q -E --include='*.ts' --include='*.tsx' "StoredProfilesLandingCard|HostEntryTile" "${target}"; then
    echo "error: ${client} references a deleted bespoke landing component (StoredProfilesLandingCard or HostEntryTile)" >&2
    echo "  target: ${target}" >&2
    exit 1
  fi

  echo "ok: ${client} landing converged (WelcomeReturningHero present, no bespoke components)"
}

check_client "igloo-pwa"    "${ROOT_DIR}/repos/igloo-pwa/src"
check_client "igloo-home"   "${ROOT_DIR}/repos/igloo-home/src"
check_client "igloo-chrome" "${ROOT_DIR}/repos/igloo-chrome/src/pages/Onboarding.tsx"

echo "ok: all client landing files converged on shared Welcome heroes"
