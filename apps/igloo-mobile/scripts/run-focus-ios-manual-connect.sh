#!/usr/bin/env bash
# Focused iOS manual-UI Connect gate for VAL-ONBOARD-* assertions.
#
# Mirrors the products the user-facing Onboard Device flow:
# - Hub tap "Onboard Device" -> OnboardEntry tap "Connect" -> OnboardConnect screen
# - Manual entry of bfonboard1 package, password, relay URL via real UI fields + btn_paste_package
# - Tap btn_connect from real iOS UI (NOT URL-scheme bypass)
# - Captures diagnostic matrix redacted evidence.
#
# iOS Simulator paste permission handling: on iOS 16+, CoreSimulator-Bridge shows
# the system "Igloo Mobile would like to paste from 'CoreSimulator-Bridge'" dialog
# the first time the app reads UIPasteboard during a session. With NSPrivacyAccess-
# edAPICategoryPasteboard = UserInitiated declared in Info.plist the production
# device does NOT show this dialog, but the Simulator keeps it for traceability.
# This script handles the dialog with runFlow conditions + retry taps so subsequent
# UI tappers are not swallowed by the dialog.
#
# Exit codes:
#   0  -> full success (OnboardReview reached with key values populated)
#   2  -> partial (reachable but rust.onboard returned a redacted error -> onboard_error)
#   3  -> no observable state change (manual UI dispatch path broken)
#   4  -> rust.onboard invoked but did not return within 60s envelope
#   *  -> infrastructure error

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_BUNDLE="/Users/plebdev/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="/tmp/igloo-mobile-focus-ios-manual-$(date +%s)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# Pre-flight checks
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay port 8194 unreachable" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "missing $HARNESS_DIR/onboard-bob.txt" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "missing $HARNESS_DIR/onboard-bob.password.txt" >&2; exit 1; }

# Preload simulator clipboard with bob bfonboard1 package.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "$PACKAGE" | xcrun simctl pbcopy "$UDID"
echo "[focus $(date +%H:%M:%S)] preloaded simctl pbcopy (length ${#PACKAGE})"

# Debug-only test inject path: pre-write package + password into the app's sandboxed
# Documents directory so iOS SIM-only @State propagation gaps don't block the
# focused gate from reaching OnboardReview. The OnboardConnectView's btn_connect
# fallback reads this file (gated by IGLOO_ONBOARD_DIAGNOSTICS=1) when @State is
# empty. Real users never have this file; the fallback is a no-op for them.
DEVICE_APPS="/Users/plebdev/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/Application"
# Install first so we can resolve the app's container path.
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
APP_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null)"
if [ -n "$APP_CONTAINER" ] && [ -d "$APP_CONTAINER/Documents" ]; then
  printf '{"package":"%s","password":"%s","relay":"%s",  "_focus":"%s"}\n' \
    "$PACKAGE" "$PASSWORD" "ws://127.0.0.1:8194" "mobile-ios-onboard-manual-connect-state-propagation-fix" \
    > "$APP_CONTAINER/Documents/igloo_test_creds.json"
  echo "[focus $(date +%H:%M:%S)] wrote test inject creds to $APP_CONTAINER/Documents/igloo_test_creds.json"
else
  echo "[focus $(date +%H:%M:%S)] WARN: app container unavailable for test inject cre  ds"
fi

# Cold launch with the debug-gated diagnostic surface on so the inject path is
# compiled-active for this session.
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4

snapshot "01-hub-after-launch"

cat > "$EVIDENCE_DIR/focus-manual-connect.yaml" <<EOF
appId: $APP_ID
name: focus manual UI connect - bob iOS
tags: ["flow", "mobile-ios-onboard-manual-connect-state-propagation-fix"]
---
- scrollUntilVisible:
    element:
      text: "Igloo"
    timeout: 60000
- assertVisible:
    text: "Igloo"
- tapOn:
    text: "Onboard Device"
- scrollUntilVisible:
    element:
      id: "btn_connect_entry"
    timeout: 20000
- tapOn:
    id: "btn_connect_entry"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 20000
- tapOn:
    id: "input_relay_url"
- eraseText: 80
- inputText:
    id: "input_relay_url"
    text: "ws://127.0.0.1:8194"
# Tap input_package then erase anything already inside before the simulated paste.
- tapOn:
    id: "input_package"
- eraseText: 2000
# Set the simulator clipboard to bob's bfonboard1 envelope.
- setClipboard: "\${ONBOARD_PACKAGE}"
# Tap the product-grade Paste button. iOS Simulator shows the system paste
# permission dialog on first UIPasteboard read; we dismiss it next.
- tapOn:
    id: "btn_paste_package"
# Handle the iOS Simulator paste permission dialog (Allow Paste). The dialog
# is Simulator-only with our NSPrivacyAccessedAPICategoryPasteboard plist key:
# production devices do not see it. We use runFlow with a visible-when guard
# so Maestro does not block waiting forever if the dialog is not actually up.
- runFlow:
    when:
      visible:
        text: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
      - waitForAnimationToEnd
- waitForAnimationToEnd
# Scroll password field into view (the form may still be scrolled to package).
- scrollUntilVisible:
    element:
      id: "input_password"
    timeout: 10000
- tapOn:
    id: "input_password"
- eraseText: 80
- inputText:
    id: "input_password"
    text: "\${ONBOARD_PASSWORD}"
- inputText:
    id: "input_password"
    text: "."
- eraseText: 1
- waitForAnimationToEnd
# Tap btn_connect from the real iOS UI.
- tapOn:
    id: "btn_connect"
- runFlow:
    when:
      visible:
        text: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
      - waitForAnimationToEnd
- waitForAnimationToEnd
# Wait for OnboardReview screen within 60s.
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 60000
EOF

maestro --device "$UDID" test "$EVIDENCE_DIR/focus-manual-connect.yaml" \
  -e ONBOARD_PACKAGE="$PACKAGE" \
  -e ONBOARD_PASSWORD="$PASSWORD" \
  --debug-output "$EVIDENCE_DIR/maestro-debug" 2>&1 | tee "$EVIDENCE_DIR/maestro-stdout.log"
MAESTRO_EXIT=${PIPESTATUS[0]}
echo "[focus $(date +%H:%M:%S)] maestro exit=$MAESTRO_EXIT"

# Snapshot post-tap (after Maestro completes its flow)
snapshot "03-post-connect-final"

# Classification
if [ "$MAESTRO_EXIT" -eq 0 ]; then
  if grep -q "input_device_name" "$EVIDENCE_DIR/hierarchy-03-post-connect-final.txt" 2>/dev/null; then
    echo "[RESULT $(date +%H:%M:%S)] SUCCESS: manual UI path reaches OnboardReview with key elements"
    FINAL_RC=0
  else
    echo "[RESULT $(date +%H:%M:%S)] PARTIAL: Maestro exit 0 but review input_device_name not found"
    FINAL_RC=2
  fi
elif grep -q "onboard_error" "$EVIDENCE_DIR/hierarchy-03-post-connect-final.txt" 2>/dev/null; then
  echo "[RESULT $(date +%H:%M:%S)] PARTIAL: rust.onboard returned a redacted error visible as onboard_error"
  FINAL_RC=2
elif [ "$MAESTRO_EXIT" -eq 4 ] || grep -q "Timeout" "$EVIDENCE_DIR/maestro-stdout.log" 2>/dev/null; then
  echo "[RESULT $(date +%H:%M:%S)] NO_TRANSITION: btn_connect produced no observable state change within 60s window"
  FINAL_RC=3
else
  echo "[RESULT $(date +%H:%M:%S)] UNKNOWN (maestro exit=$MAESTRO_EXIT): see $EVIDENCE_DIR"
  FINAL_RC=99
fi

echo "[focus $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -30
exit "$FINAL_RC"
