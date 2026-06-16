#!/usr/bin/env bash
# Reads demo onboarding credentials from .tmp/test-harness and writes them
# to files that Maestro flows can read. Also copies the PACKAGE to system clipboard
# via pbcopy so Maestro's pasteText can enter the 690-char package into iOS.
#
# Usage: Run this BEFORE starting Maestro. It writes temp files and sets clipboard.
# The password is written to a temp file but NOT copied to clipboard (inputText handles it).
set -euo pipefail

# Determine platform from PLATFORM env var (passed by Maestro flow)
PLATFORM="${PLATFORM:-ios}"

# Use absolute paths to .tmp/test-harness
HARNESS_DIR="/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness"

# Read credentials based on platform
if [ "$PLATFORM" = "ios" ]; then
    PACKAGE_FILE="$HARNESS_DIR/onboard-bob.txt"
    PASSWORD_FILE="$HARNESS_DIR/onboard-bob.password.txt"
elif [ "$PLATFORM" = "android" ]; then
    PACKAGE_FILE="$HARNESS_DIR/onboard-carol.txt"
    PASSWORD_FILE="$HARNESS_DIR/onboard-carol.password.txt"
else
    echo "Unknown PLATFORM: $PLATFORM" >&2
    exit 1
fi

# Check that files exist
if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Package file not found: $PACKAGE_FILE" >&2
    exit 1
fi

if [ ! -f "$PASSWORD_FILE" ]; then
    echo "Password file not found: $PASSWORD_FILE" >&2
    exit 1
fi

# Read credentials and trim whitespace/newlines
# Use printf to avoid trailing newline in temp files
PACKAGE_CONTENT="$(cat "$PACKAGE_FILE" | tr -d '\r\n' | xargs echo)"
PASSWORD_CONTENT="$(cat "$PASSWORD_FILE" | tr -d '\r\n' | xargs echo)"

printf '%s' "$PACKAGE_CONTENT" > /tmp/igloo-mobile-demo-package.txt
printf '%s' "$PASSWORD_CONTENT" > /tmp/igloo-mobile-demo-password.txt

# Copy ONLY the package to system clipboard (for Maestro's pasteText)
# The password is 32 chars and works fine with Maestro's inputText
/usr/bin/pbcopy < /tmp/igloo-mobile-demo-package.txt

echo "Credentials written for $PLATFORM"
echo "DEMO_PACKAGE length: ${#PACKAGE_CONTENT}"
echo "DEMO_PASSWORD length: ${#PASSWORD_CONTENT}"
echo "System clipboard set to PACKAGE (${#PACKAGE_CONTENT} chars)"