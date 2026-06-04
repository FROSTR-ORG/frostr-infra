#!/usr/bin/env bash

set -euo pipefail

ERRORS=0
WARNINGS=0

print_check() { echo -n "Checking $1... "; }
print_ok() { echo "OK"; }
print_warn() { echo "WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
print_fail() { echo "FAILED: $1"; ERRORS=$((ERRORS + 1)); }

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

expected_wasm_pack_version="0.14.0"
rustup_bin_dir="${HOME}/.cargo/bin"

clang_supports_wasm() {
  local clang_bin="$1"
  printf 'int main(void){return 0;}' \
    | "${clang_bin}" --target=wasm32-unknown-unknown -x c -c - -o /dev/null >/dev/null 2>&1
}

find_wasm_clang() {
  local candidate
  for candidate in \
    "${CC_wasm32_unknown_unknown:-}" \
    "${WASM_CC:-}" \
    "/opt/homebrew/opt/llvm/bin/clang" \
    "clang"; do
    if [[ -z "${candidate}" ]]; then
      continue
    fi
    if command -v "${candidate}" >/dev/null 2>&1 && clang_supports_wasm "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
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

print_check "rustup"
if command -v rustup >/dev/null 2>&1; then
  print_ok
else
  print_fail "rustup not found (install from https://rustup.rs)"
fi

print_check "rustup-managed cargo"
if command -v cargo >/dev/null 2>&1; then
  cargo_path="$(command -v cargo)"
  if [[ "${cargo_path}" == "${rustup_bin_dir}/cargo" ]]; then
    print_ok
  else
    print_fail "cargo resolves to ${cargo_path}; put ${rustup_bin_dir} ahead of Homebrew on PATH"
  fi
else
  print_fail "cargo not found"
fi

print_check "rustup-managed rustc"
if command -v rustc >/dev/null 2>&1; then
  rustc_path="$(command -v rustc)"
  if [[ "${rustc_path}" == "${rustup_bin_dir}/rustc" ]]; then
    print_ok
  else
    print_fail "rustc resolves to ${rustc_path}; put ${rustup_bin_dir} ahead of Homebrew on PATH"
  fi
else
  print_fail "rustc not found"
fi

print_check "wasm32 Rust target"
target_libdir="$(rustc --print target-libdir --target wasm32-unknown-unknown 2>/dev/null || true)"
if [[ -n "${target_libdir}" && -d "${target_libdir}" ]]; then
  print_ok
else
  print_fail "wasm32-unknown-unknown target unavailable (run: rustup target add wasm32-unknown-unknown)"
fi

print_check "wasm-pack ${expected_wasm_pack_version}"
if command -v wasm-pack >/dev/null 2>&1; then
  wasm_pack_version="$(wasm-pack --version 2>/dev/null | awk '{print $2}')"
  if [[ "${wasm_pack_version}" == "${expected_wasm_pack_version}" ]]; then
    print_ok
  else
    print_fail "wasm-pack ${wasm_pack_version:-unknown} found at $(command -v wasm-pack); expected ${expected_wasm_pack_version} (run: cargo install --locked --version ${expected_wasm_pack_version} wasm-pack)"
  fi
else
  print_fail "wasm-pack not found (run: cargo install --locked --version ${expected_wasm_pack_version} wasm-pack)"
fi

print_check "wasm-capable clang"
if wasm_clang="$(find_wasm_clang)"; then
  print_ok
else
  print_fail "no clang supports wasm32-unknown-unknown (install LLVM, for example: brew install llvm)"
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
