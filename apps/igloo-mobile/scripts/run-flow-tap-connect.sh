#!/usr/bin/env bash
# Focused iOS tap-connect diagnostic gate.
set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"

if [ ! -f "$ROOT/.tmp/test-harness/onboard-bob.txt" ]; then
  echo "missing bob credentials; run 'make demo-onboard'" >&2; exit 1
fi

PACKAGE="$(tr -d '\r\n' < "$ROOT/.tmp/test-harness/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$ROOT/.tmp/test-harness/onboard-bob.password.txt")"

# Preload the iOS Simulator UIPasteboard.general with the bfonboard1
# via simctl pbcopy — the SwiftUI btn_paste_package reads from there.
printf "$PACKAGE" | xcrun simctl pbcopy "$UDID"

maestro --device "$UDID" test \
    /tmp/igloo-mobile-flow-tap-connect.yaml \
    -e ONBOARD_PACKAGE="$PACKAGE" \
    -e ONBOARD_PASSWORD="$PASSWORD" \
    -e RELAY_URL="ws://127.0.0.1:8194" \
    --debug-output "/tmp/igloo-mobile-diagnostic-tap-connect-$(date +%s)"
