#!/usr/bin/env bash
#
# Wait for condition script for VAL-ERR-006 validation.
# Polls the app state to verify a condition remains false for a duration.
#
# Usage:
#   wait-for-condition.sh --timeout <seconds> --condition <condition_name>
#
# Conditions:
#   sign_ready_absent  - Verifies "Sign Ready" does not appear for timeout duration

set -euo pipefail

TIMEOUT=""
CONDITION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --condition)
            CONDITION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${TIMEOUT}" ]] || [[ -z "${CONDITION}" ]]; then
    echo "Usage: wait-for-condition.sh --timeout <seconds> --condition <name>"
    exit 1
fi

# For sign_ready_absent condition, we wait and check periodically
# The actual check is done by the Maestro flow assertions, this script
# just waits for the specified duration
echo "[wait-for-condition] Waiting ${TIMEOUT}s for condition: ${CONDITION}"

case "${CONDITION}" in
    sign_ready_absent)
        target="${RUNTIME_ABSENCE_TARGET:-}"
        started="$(date +%s)"
        while true; do
            if [[ "${target}" == "ios" ]]; then
                if maestro --device "${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}" hierarchy 2>/dev/null | grep -Fq "Sign Ready"; then
                    echo "[wait-for-condition] FAIL: Sign Ready appeared on iOS while it should be absent" >&2
                    exit 2
                fi
            elif [[ "${target}" == "android" ]]; then
                tmp="${TMPDIR:-/tmp}/igloo-runtime-absence-${$}.xml"
                adb -s "${ANDROID_SERIAL:-emulator-5554}" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
                adb -s "${ANDROID_SERIAL:-emulator-5554}" pull /sdcard/window_dump.xml "$tmp" >/dev/null 2>&1 || true
                if grep -Fq "Sign Ready" "$tmp" 2>/dev/null; then
                    rm -f "$tmp"
                    echo "[wait-for-condition] FAIL: Sign Ready appeared on Android while it should be absent" >&2
                    exit 2
                fi
                rm -f "$tmp"
            else
                echo "[wait-for-condition] RUNTIME_ABSENCE_TARGET must be ios or android" >&2
                exit 2
            fi
            if [ $(( $(date +%s) - started )) -ge "${TIMEOUT}" ]; then
                echo "[wait-for-condition] Condition satisfied: Sign Ready never appeared for ${TIMEOUT}s on ${target}"
                break
            fi
            sleep 3
        done
        ;;
    *)
        echo "[wait-for-condition] Unknown condition: ${CONDITION}"
        exit 1
        ;;
esac
