#!/usr/bin/env bash

set -euo pipefail

ERRORS=0
WARNINGS=0

print_check() { echo -n "Checking $1... "; }
print_ok() { echo "OK"; }
print_warn() { echo "WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
print_fail() { echo "FAILED: $1"; ERRORS=$((ERRORS + 1)); }

echo "=== Bifrost Infra Setup Check ==="

a=0
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
  if git submodule status --recursive >/dev/null 2>&1; then
    :
  else
    print_warn "recursive submodule traversal failed (expected with current igloo-web upstream state); use non-recursive submodule commands in this repo"
  fi
else
  print_warn ".gitmodules missing"
fi

for port in 8002 5173; do
  print_check "Port $port"
  if command -v lsof >/dev/null 2>&1 && lsof -i ":$port" >/dev/null 2>&1; then
    print_warn "in use"
  else
    print_ok
  fi
done

print_check ".env file"
if [ -f ".env" ]; then print_ok; else print_warn "missing (.env.example is available)"; fi

echo ""
echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
