#!/usr/bin/env bash
# Wrapper that runs the focused Android inject gate and then a Maestro
# flow that continues through Connect/review/save/dashboard using the
# preloaded state from the debug intent. This is the production-grade
# replacement for the prior `setClipboard`/`pasteText`/`adb shell input
# text` reliability path used by `flows/onboard-android.yaml`.
#
# Usage:  bash apps/igloo-mobile/scripts/run-android-inject-onboard-carol.sh
set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"

# 1. Run the focused injection gate. It uninstalls, reinstalls the
#    debug APK, fires the bypass intent, and writes redacted evidence
#    under apps/igloo-mobile/library/evidence/VAL-ONBOARD-android-debug-inject/.
bash "$ROOT/apps/igloo-mobile/scripts/android-inject-onboard-carol.sh"

# 2. Continue through Connect/review/save/dashboard via Maestro. The
#    flow does NOT paste or type the package — the value is already in
#    the field from the inject path. Maestro validates stability
#    selectors below the inject and proves the rest of the contract
#    for the focused feature.
maestro --device emulator-5554 test \
  "$ROOT/apps/igloo-mobile/flows/onboard-android-inject.yaml"
