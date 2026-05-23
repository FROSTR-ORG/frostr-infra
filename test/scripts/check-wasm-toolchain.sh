#!/usr/bin/env bash

set -euo pipefail

if ! command -v rustc >/dev/null 2>&1 && [[ -n "${HOME:-}" && -x "${HOME}/.cargo/bin/rustc" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

if ! command -v rustc >/dev/null 2>&1; then
  echo "error: rustc is required; install Rust with rustup and put ~/.cargo/bin on PATH" >&2
  exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup is required for the wasm32-unknown-unknown target" >&2
  exit 1
fi

target_libdir="$(rustc --print target-libdir --target wasm32-unknown-unknown 2>/dev/null || true)"
if [[ -z "${target_libdir}" || ! -d "${target_libdir}" ]]; then
  echo "error: wasm32-unknown-unknown Rust target is not installed" >&2
  echo "hint: rustup target add wasm32-unknown-unknown" >&2
  exit 1
fi

if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "error: wasm-pack 0.14.0 is required" >&2
  exit 1
fi

wasm_pack_version="$(wasm-pack --version 2>/dev/null || true)"
if [[ "${wasm_pack_version}" != "wasm-pack 0.14.0" ]]; then
  echo "error: expected wasm-pack 0.14.0, found '${wasm_pack_version}'" >&2
  exit 1
fi

wasm_clang=""
for candidate in \
  "${CC_wasm32_unknown_unknown:-}" \
  "${WASM_CC:-}" \
  "/opt/homebrew/opt/llvm/bin/clang" \
  "clang"; do
  if [[ -z "${candidate}" ]]; then
    continue
  fi
  if command -v "${candidate}" >/dev/null 2>&1 && printf 'int main(void){return 0;}' | "${candidate}" --target=wasm32-unknown-unknown -x c -c - -o /dev/null >/dev/null 2>&1; then
    wasm_clang="${candidate}"
    break
  fi
done

if [[ -z "${wasm_clang}" ]]; then
  echo "error: no clang with wasm32-unknown-unknown target support found" >&2
  exit 1
fi

echo "ok: wasm toolchain is ready"
