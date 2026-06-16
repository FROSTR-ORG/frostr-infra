#!/usr/bin/env bash
# Copies credential files to the system clipboard for reliable Maestro text entry.
# Reads from well-known paths written by read-demo-credentials.sh setup script.
# iOS: /tmp/igloo-mobile-demo-{package,password}.txt
# Android: /tmp/igloo-mobile-android-demo-{package,password}.txt
set -euo pipefail

PLATFORM="${PLATFORM:-ios}"

# Read credentials based on platform
if [ "$PLATFORM" = "ios" ]; then
    PKG_FILE="/tmp/igloo-mobile-demo-package.txt"
    PWD_FILE="/tmp/igloo-mobile-demo-password.txt"
elif [ "$PLATFORM" = "android" ]; then
    PKG_FILE="/tmp/igloo-mobile-android-demo-package.txt"
    PWD_FILE="/tmp/igloo-mobile-android-demo-password.txt"
else
    echo "Unknown PLATFORM: $PLATFORM" >&2
    exit 1
fi

# Determine which file to copy based on CLIPBOARD_TARGET env var (passed by Maestro flow)
TARGET="${CLIPBOARD_TARGET:-package}"
if [ "$TARGET" = "package" ]; then
    FILE="$PKG_FILE"
elif [ "$TARGET" = "password" ]; then
    FILE="$PWD_FILE"
else
    echo "Unknown CLIPBOARD_TARGET: $TARGET" >&2
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE" >&2
    exit 1
fi

# Read content and copy to clipboard (strips trailing newline for clean paste)
/bin/cat "$FILE" | /usr/bin/tr -d '\n' | /usr/bin/pbcopy
echo "Copied $(wc -c < "$FILE" | xargs) chars to clipboard ($TARGET)"