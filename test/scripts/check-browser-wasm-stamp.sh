#!/usr/bin/env bash
set -euo pipefail

# Guard against stale committed browser WASM.
#
# The blobs in repos/igloo-shared/public/wasm are compiled from the bifrost-rs
# WASM crates. If that source moves without a rebuild, the browser runtime
# silently drifts from the Rust core (this happened 2026-06-13: the committed
# blobs still exported a removed relay-backup API). We stamp a deterministic hash
# of *just* the WASM-relevant crates and verify the committed stamp still matches.
#
# Native-only crates (bifrost-app / bifrost-bridge-tokio / bifrost-devtools) are
# excluded, so a native-only bifrost-rs bump does NOT force a needless rebuild.
#
# Usage:
#   check-browser-wasm-stamp.sh            # verify (default; used by test:guards)
#   check-browser-wasm-stamp.sh --write    # regenerate the stamp (after a rebuild)

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bifrost_dir="${root_dir}/repos/bifrost-rs"
shared_dir="${root_dir}/repos/igloo-shared"
stamp_file="${root_dir}/test/browser-wasm-source.stamp"

# bifrost-rs paths that feed the browser WASM build (see
# repos/igloo-shared/scripts/build-bridge-wasm.sh WASM_MODULES) plus the workspace
# manifest/lock that determine the compiled output.
wasm_paths=(
  crates/bifrost-bridge-wasm
  crates/bifrost-profile-wasm
  crates/bifrost-profile
  crates/bifrost-router
  crates/bifrost-signer
  crates/bifrost-codec
  crates/bifrost-core
  crates/frostr-utils
  Cargo.toml
  Cargo.lock
)

# igloo-shared build driver: the script that actually invokes wasm-pack and copies
# the modules. A change here (module list, wasm-pack flags, post-processing) can
# change the compiled output even when the Rust source is byte-identical.
shared_wasm_paths=(
  scripts/build-bridge-wasm.sh
)

# Parent-repo paths that pin the WASM toolchain. A wasm-pack/clang version bump is
# recorded here (the toolchain check encodes the expected wasm-pack version), so
# bumping the pin invalidates the stamp and forces a rebuild + re-stamp.
toolchain_paths=(
  test/scripts/check-wasm-toolchain.sh
)

if [[ ! -d "${bifrost_dir}/.git" && ! -f "${bifrost_dir}/.git" ]]; then
  echo "not ok: repos/bifrost-rs is not checked out; run 'make repo-init'" >&2
  exit 1
fi

if [[ ! -d "${shared_dir}/.git" && ! -f "${shared_dir}/.git" ]]; then
  echo "not ok: repos/igloo-shared is not checked out; run 'make repo-init'" >&2
  exit 1
fi

compute_hash() {
  # `git rev-parse HEAD:<path>` prints each path's tree/blob object id; hashing the
  # concatenation across the bifrost-rs WASM source, the igloo-shared build driver,
  # and the parent-repo toolchain pin yields a stamp that changes only when one of
  # those committed inputs changes (deterministic, no rebuild required).
  {
    git -C "${bifrost_dir}" rev-parse "${wasm_paths[@]/#/HEAD:}"
    git -C "${shared_dir}" rev-parse "${shared_wasm_paths[@]/#/HEAD:}"
    git -C "${root_dir}" rev-parse "${toolchain_paths[@]/#/HEAD:}"
  } | shasum -a 256 | awk '{print $1}'
}

current="$(compute_hash)"

if [[ "${1:-}" == "--write" ]]; then
  printf '%s\n' "${current}" > "${stamp_file}"
  echo "ok: wrote browser-wasm source stamp ${current}"
  exit 0
fi

if [[ ! -f "${stamp_file}" ]]; then
  echo "not ok: missing ${stamp_file}" >&2
  echo "  Build the browser WASM, then re-stamp: make browser-wasm-refresh" >&2
  exit 1
fi

committed="$(tr -d '[:space:]' < "${stamp_file}")"
if [[ "${committed}" != "${current}" ]]; then
  echo "not ok: committed browser WASM is stale relative to bifrost-rs" >&2
  echo "  bifrost-rs WASM source hash: ${current}" >&2
  echo "  committed stamp:             ${committed}" >&2
  echo "  The bifrost-rs WASM crates moved without a browser-WASM rebuild." >&2
  echo "  Rebuild + re-stamp: make browser-wasm-refresh (then commit public/wasm" >&2
  echo "  in igloo-shared, bump its pointer, and commit the refreshed stamp)." >&2
  exit 1
fi

echo "ok: committed browser WASM matches the bifrost-rs WASM source"
