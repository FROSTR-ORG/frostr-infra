#!/bin/bash
# Maestro runScript entry point - copies package to system clipboard.
# Called from Maestro flow: runScript: file: ../scripts/maestro-clipboard-init.sh
# Works because Maestro's runScript with file: runs shell scripts (not JS) for .sh files.
# Usage: This script is run by Maestro, reads platform from env, copies package to clipboard.
set -e

PLATFORM="${PLATFORM:-ios}"
HARNESS_DIR="/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness"

if [ "$PLATFORM" = "ios" ]; then
    PKG_FILE="$HARNESS_DIR/onboard-bob.txt"
elif [ "$PLATFORM" = "android" ]; then
    PKG_FILE="$HARNESS_DIR/onboard-carol.txt"
else
    echo "Unknown PLATFORM: $PLATFORM" >&2
    exit 1
fi

# Read package, strip whitespace, copy to clipboard
PKG_CONTENT="$(cat "$PKG_FILE" | tr -d '\r\n' | xargs echo)"
/usr/bin/pbcopy << EOF
$PKG_CONTENT
EOF

echo "Package ($PLATFORM, ${#PKG_CONTENT} chars) copied to clipboard"