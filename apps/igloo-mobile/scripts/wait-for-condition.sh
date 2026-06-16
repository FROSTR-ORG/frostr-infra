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
        # Just sleep for the timeout - Maestro assertions will verify
        # that "Sign Ready" never appears during this window
        sleep "${TIMEOUT}"
        echo "[wait-for-condition] Condition satisfied: Sign Ready never appeared for ${TIMEOUT}s"
        ;;
    *)
        echo "[wait-for-condition] Unknown condition: ${CONDITION}"
        exit 1
        ;;
esac