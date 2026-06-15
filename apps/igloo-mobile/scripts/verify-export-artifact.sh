#!/usr/bin/env bash
# Verifier script for `Copy Profile` / `Copy Share` export artifacts.
#
# Drives the mobile export flow's `bfprofile1` / `bfshare1` outputs through
# `cargo run --example export_decode`, which decodes the package and emits
# a redacted proof panel — package type, prefix, length, shape — without
# committing package bytes, passwords, decrypted shares, or key material.
#
# Usage:
#   ./scripts/verify-export-artifact.sh <kind> <package-file-or-string> <password-file-or-string>
#
#   kind: profile | share
#   package: path to file containing the package, OR `-` for stdin, OR the
#            raw string (when first char is "bfprofile1"/"bfshare1").
#   password: path to file containing the password, OR the raw string.
#
# Exit codes:
#   0  -> decode succeeded and shape is consistent
#   2  -> decode failed (wrong password, malformed package, kind mismatch)
#   *  -> infrastructure error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APPS_ROOT="$REPO_ROOT/apps/igloo-mobile"
EXAMPLE="$APPS_ROOT/rust/examples/export_decode.rs"

if [ "$#" -lt 3 ]; then
  cat <<USAGE >&2
Usage: $0 <kind> <package> <password>

  kind:      profile | share
  package:   file path, or '-' for stdin, or raw bech32m string
  password:  file path or raw string

Note: passing secrets on the command line is intentional for short
validator runs; do not commit raw values to scripts or evidence.
USAGE
  exit 1
fi

KIND="$1"
PKG_ARG="$2"
PWD_ARG="$3"

if [ ! -f "$EXAMPLE" ]; then
  echo "[verify-export-artifact] FAIL: example not found: $EXAMPLE" >&2
  exit 1
fi

if [ "$PKG_ARG" = "-" ]; then
  PKG_CONTENT="$(cat)"
elif [ -f "$PKG_ARG" ]; then
  PKG_CONTENT="$(cat "$PKG_ARG")"
else
  PKG_CONTENT="$PKG_ARG"
fi

if [ -f "$PWD_ARG" ]; then
  PWD_CONTENT="$(cat "$PWD_ARG")"
else
  PWD_CONTENT="$PWD_ARG"
fi

# Trim stray whitespace from files; do NOT trim if the user passed a raw
# bech32m string directly because the bech32m alphabet is contiguous and
# never includes whitespace.
if [ -f "$PWD_ARG" ]; then
  PWD_CONTENT="$(printf '%s' "$PWD_CONTENT" | tr -d '\r\n ' | xargs -n1 echo)"
  # `xargs -n1 echo` collapses the trimmed text back into a single line.
  PWD_CONTENT="$(printf '%s' "$PWD_CONTENT")"
fi

echo "[verify-export-artifact] kind=$KIND"
echo "[verify-export-artifact] package_length=${#PKG_CONTENT}"
echo "[verify-export-artifact] password_length=${#PWD_CONTENT}"

source ~/.config/frostr/rmp-mobile-env.zsh
cd "$APPS_ROOT/rust"

# Build the example if it isn't already, so validator runs without
# `cargo test` still pass.
cargo build --example export_decode --quiet >/dev/null

EXP_OUTPUT="$(
  EXPORT_PACKAGE="$PKG_CONTENT" \
  EXPORT_PASSWORD="$PWD_CONTENT" \
  EXPORT_KIND="$KIND" \
  cargo run --quiet --example export_decode 2>&1
)"
EXP_EXIT=$?
echo "$EXP_OUTPUT"
if [ "$EXP_EXIT" -ne 0 ]; then
  echo "[verify-export-artifact] FAIL: export_decode exited $EXP_EXIT" >&2
  exit 2
fi

# Confirm the proof panel and the OK marker are present.
if ! grep -q "^\[export-decode\] OK: " <<<"$EXP_OUTPUT"; then
  echo "[verify-export-artifact] FAIL: missing OK marker in decoder output" >&2
  exit 2
fi
echo "[verify-export-artifact] OK: artifact verified"
