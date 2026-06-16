#!/usr/bin/env bash
# Clears the currently focused text input field using keyboard shortcuts
# This is used to clear existing content before typing new text
set -euo pipefail

DEVICE_ID="${1:-emulator-5554}"

# Select all text using Ctrl+A (works in most Android text fields)
adb -s "$DEVICE_ID" shell input keyevent 67 67 67 67 67 67 67 67 67 67 2>/dev/null || true

echo "Input cleared"