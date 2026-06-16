#!/usr/bin/env bash
# Copies the password credential to system clipboard.
# Used by Maestro flows to set clipboard before pasting password.
# Run with: PLATFORM=ios bash scripts/copy-password-to-clipboard.sh
set -euo pipefail

PLATFORM="${PLATFORM:-ios}"

if [ "$PLATFORM" = "ios" ]; then
    PWD_FILE="/tmp/igloo-mobile-demo-password.txt"
elif [ "$PLATFORM" = "android" ]; then
    PWD_FILE="/tmp/igloo-mobile-android-demo-password.txt"
else
    echo "Unknown PLATFORM: $PLATFORM" >&2
    exit 1
fi

if [ ! -f "$PWD_FILE" ]; then
    echo "Password file not found: $PWD_FILE" >&2
    exit 1
fi

/usr/bin/pbcopy < "$PWD_FILE"
echo "Password copied to clipboard ($(wc -c < "$PWD_FILE" | xargs) chars)"