#!/usr/bin/env bash
# Focused iOS onboarding flow wrapper.
#
# Why this exists: the Maestro `setClipboard` command goes into Maestro's
# internal clipboard (not the iOS Simulator UIPasteboard). The product-grade
# `btn_paste_package` SwiftUI button reads from UIPasteboard.general.string,
# so Maestro's setClipboard + tapOn doesn't reach the app. The pre-existing
# orchestrator recipe was: "igloo://test-inject or pbcopy plus manual
# simulator tap". This wrapper preloads the iOS Simulator's UIPasteboard via
# `xcrun simctl pbcopy`, then runs the Maestro flow which taps the
# `btn_paste_package` button. The Swift UIButton reads from the simulator's
# UIPasteboard and the paste works end-to-end.
#
# Usage:
#   bash apps/igloo-mobile/scripts/run-onboard-ios-bob.sh
#
# Precondition: demo stack running on 8194 with current bob credentials.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

printf "[run-onboard-ios] checking demo stack...\n"
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay not reachable on 127.0.0.1:8194" >&2; exit 1; }

if [ ! -f "$HARNESS_DIR/onboard-bob.txt" ]; then
  echo "missing bob package at $HARNESS_DIR/onboard-bob.txt; run 'make demo-onboard'" >&2
  exit 1
fi

# Step 1: Preload the iOS Simulator UIPasteboard (system clipboard) with the
# bob bfonboard1 package. This is what the Swift btn_paste_package button
# reads from. simctl pbcopy writes the string to the simulator's
# UIPasteboard.general; subsequent SwiftUI Paste from Clipboard taps see it.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "$PACKAGE" | xcrun simctl pbcopy "$UDID"
printf "[run-onboard-ios] preloaded simctl pbcopy with bfonboard1 (length %d)\n" "${#PACKAGE}"

# Step 2: Fresh-install the latest debug build to test the committed flow.
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 5

# Step 3: Run the Maestro flow that pre-loads simctl clipboard content into
# the SwiftUI on-package field via the paste button. The Maestro flow passes
# -e env vars so setClipboard + pasteText can populate the password field
# (which Maestro *can* set internally).
maestro --device "$UDID" test \
    "$ROOT/apps/igloo-mobile/flows/onboard-ios.yaml" \
    -e ONBOARD_PACKAGE="$PACKAGE" \
    -e ONBOARD_PASSWORD="$PASSWORD" \
    -e RELAY_URL="ws://127.0.0.1:8194" \
    --debug-output "/tmp/igloo-mobile-run-onboard-ios-$(date +%s)"
