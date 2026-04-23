#!/usr/bin/env bash

set -euo pipefail

ERRORS=0
WARNINGS=0

print_check() { echo -n "Checking $1... "; }
print_ok() { echo "OK"; }
print_warn() { echo "WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
print_fail() { echo "FAILED: $1"; ERRORS=$((ERRORS + 1)); }

# Verify a required command is available on PATH. Missing tools are
# hard errors - the workspace cannot run its test / demo surface without
# them - so this script exits non-zero rather than warning.
require_cmd() {
  local name="$1"
  local install_hint="$2"
  print_check "${name}"
  if command -v "${name}" >/dev/null 2>&1; then
    print_ok
  else
    print_fail "${name} not found (install: ${install_hint})"
  fi
}

echo "=== FROSTR Workspace Setup Check ==="

require_cmd docker "https://docs.docker.com/get-docker/"

# docker compose is a separate check because docker can exist without the
# compose plugin (e.g. older docker-ce installs where compose is the
# standalone docker-compose binary).
print_check "Docker Compose"
if docker compose version >/dev/null 2>&1; then
  print_ok
else
  print_fail "docker compose plugin not found (install: https://docs.docker.com/compose/install/)"
fi

require_cmd cargo "https://rustup.rs/"
require_cmd npm "https://nodejs.org/"
require_cmd wasm-pack "cargo install --locked --version 0.14.0 wasm-pack"
require_cmd jq "apt-get install jq (or brew install jq)"

# xvfb-run is only required on Linux where headless Playwright / Tauri
# tests rely on a virtual display.
if [ "$(uname -s)" = "Linux" ]; then
  require_cmd xvfb-run "apt-get install xvfb"
fi

print_check "Git submodules"
if [ -f ".gitmodules" ]; then
  if git submodule status >/dev/null 2>&1; then
    print_ok
  else
    print_warn "submodules configured but not initialized (run make repo-init)"
  fi
else
  print_warn ".gitmodules missing"
fi

print_check ".env file"
if [ -f ".env" ]; then print_ok; else print_warn "missing (.env.example is available)"; fi

print_check "workspace scratch root"
if [ -e ".tmp" ] && [ ! -w ".tmp" ]; then
  print_warn ".tmp exists but is not writable (run make repo-reset)"
else
  print_ok
fi

echo ""
echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
