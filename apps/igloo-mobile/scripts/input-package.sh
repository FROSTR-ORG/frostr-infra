#!/usr/bin/env bash
# Tap the package field to focus it (coordinates from hierarchy analysis)
set -euo pipefail

DEVICE="${DEVICE:-emulator-5554}"

# Package field is at approximately y=650 in the OnboardConnect scroll view
# Tap to focus the field
adb -s "$DEVICE" shell input tap 540 650

echo "Package field tapped"