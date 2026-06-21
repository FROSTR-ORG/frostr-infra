#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Static convergence guard: verify all three client landing files consume the
# shared WelcomeReturningHero and have not reintroduced bespoke landing components.
# This is the recurrence-preventer for landing UI divergence across clients.

check_client() {
  local client="$1"
  local file="$2"

  if [[ ! -f "${file}" ]]; then
    echo "error: ${client} landing file not found: ${file}" >&2
    exit 1
  fi

  # Assert the shared hero is referenced (proves the client renders the converged landing).
  if ! grep -q "WelcomeReturningHero" "${file}"; then
    echo "error: ${client} does not reference WelcomeReturningHero — landing has diverged from the shared hero" >&2
    echo "  file: ${file}" >&2
    exit 1
  fi

  # Assert the deleted bespoke landing components have not been reintroduced.
  if grep -qE "StoredProfilesLandingCard|HostEntryTile" "${file}"; then
    echo "error: ${client} references a deleted bespoke landing component (StoredProfilesLandingCard or HostEntryTile)" >&2
    echo "  file: ${file}" >&2
    exit 1
  fi

  echo "ok: ${client} landing converged (WelcomeReturningHero present, no bespoke components)"
}

check_client "igloo-pwa"    "${ROOT_DIR}/repos/igloo-pwa/src/App.tsx"
check_client "igloo-home"   "${ROOT_DIR}/repos/igloo-home/src/App.tsx"
check_client "igloo-chrome" "${ROOT_DIR}/repos/igloo-chrome/src/pages/Onboarding.tsx"

echo "ok: all client landing files converged on shared Welcome heroes"
