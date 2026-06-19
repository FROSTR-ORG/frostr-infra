#!/usr/bin/env bash
#
# Background/foreground cycling script for VAL-ERR-005 validation.
# Uses simctl for iOS and adb for Android.
#
# Usage:
#   background-app.sh background    # Put app in background
#   background-app.sh foreground    # Bring app to foreground

set -euo pipefail

ACTION="${1:-}"

case "${ACTION}" in
    background)
        # iOS: Press home button to background app
        if command -v xcrun >/dev/null 2>&1; then
            xcrun simctl ui booted home 2>/dev/null || true
        fi
        # Android: Go home to background the app
        if command -v adb >/dev/null 2>&1; then
            adb -s "${ANDROID_SERIAL:-emulator-5554}" shell input keyevent KEYCODE_HOME 2>/dev/null || true
        fi
        ;;
    foreground)
        # iOS: Re-launch app to foreground
        if command -v xcrun >/dev/null 2>&1; then
            xcrun simctl launch booted com.frostr.igloo.dev 2>/dev/null || true
        fi
        # Android: Bring app to foreground
        if command -v adb >/dev/null 2>&1; then
            adb -s "${ANDROID_SERIAL:-emulator-5554}" shell am start -W -n com.frostr.igloo.dev/com.frostr.igloo.MainActivity 2>/dev/null || true
        fi
        ;;
    *)
        echo "Usage: background-app.sh <background|foreground>"
        exit 1
        ;;
esac
