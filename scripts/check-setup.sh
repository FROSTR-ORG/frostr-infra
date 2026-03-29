#!/usr/bin/env bash

set -euo pipefail

ERRORS=0
WARNINGS=0

print_check() { echo -n "Checking $1... "; }
print_ok() { echo "OK"; }
print_warn() { echo "WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
print_fail() { echo "FAILED: $1"; ERRORS=$((ERRORS + 1)); }

echo "=== FROSTR Workspace Setup Check ==="

print_check "Docker"
if command -v docker >/dev/null 2>&1; then print_ok; else print_fail "docker not found"; fi

print_check "Docker Compose"
if docker compose version >/dev/null 2>&1; then print_ok; else print_fail "docker compose not found"; fi

print_check "Git submodules"
if [ -f ".gitmodules" ]; then
  if git submodule status >/dev/null 2>&1; then
    print_ok
  else
    print_warn "submodules configured but not initialized"
  fi
else
  print_warn ".gitmodules missing"
fi

print_check ".env file"
if [ -f ".env" ]; then print_ok; else print_warn "missing (.env.example is available)"; fi

echo ""
echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
