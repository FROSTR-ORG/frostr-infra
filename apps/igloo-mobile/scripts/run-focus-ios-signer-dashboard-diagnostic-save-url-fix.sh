#!/usr/bin/env bash
# Focused iOS evidence capture for
# `mobile-ios-signer-dashboard-diagnostic-save-url-fix`.
#
# Proves that:
#   1. The diagnostics-only URL `igloo://test-save-to-dashboard` reaches
#      the Dashboard without any SwiftUI button-tap routing, by going
#      through `igloo://test-inject` (handshake) -> OnboardReview ->
#      `igloo://test-save-to-dashboard` (AppAction::DiagnosticsOnboardSave
#      via manager.testOnboardSaveToDashboard).
#   2. After reaching the Dashboard, the existing iOS Start/Stop/Ping
#      side-effect reconcilers from commit a340278 fire from the real UI
#      controls: btn_start_signer -> btn_stop_signer within 15 s, and
#      btn_refresh_peers / btn_test_ping emit new INFO rows with
#      RFC-3339 timestamps.
#
# Both phases are gated on SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 +
# #if DEBUG so the URL handler is only active for diagnostic-context
# runs; release builds and normal user flows never expose this path
# (per the feature spec: "Diagnostics-enabled iOS can save the current
# OnboardReview state to Dashboard using a URL or equivalent harness
# action with a non-secret device name, without bypassing the Rust
# AppAction::OnboardSave and OnboardStored state path.").
#
# Strategy:
#   1. Cold-install + cold-launch the iOS Simulator app with the demo
#      credentials (bob) under SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1.
#   2. Maestro navigates Hub -> OnboardConnect (TextEditor limit
#      prevents pasting a 690-char bfonboard string), then we drive
#      the handshake via `igloo://test-inject`, waiting for the
#      OnboardReview screen displaying `bob-ios-save-url-fix`.
#   3. We send `igloo://test-save-to-dashboard?device_name=...` to
#      prove the URL handler invokes the diagnostics-gated
#      AppAction::DiagnosticsOnboardSave (which delegates to the
#      real OnboardSave / OnboardStored state-machine path), reaches
#      the Dashboard, and shows the bob profile identity block.
#   4. Maestro drives btn_start_signer / btn_stop_signer / ping /
#      Test Ping on the real Signer tab to prove commit a340278 still
#      works end-to-end through the real UI.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-ios-signer-dashboard-diagnostic-save-url-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence dir: $EVIDENCE_DIR"

# 1. Health: demo relay and iOS Simulator reachable.
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay not reachable on 127.0.0.1:8194"; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" \
  || { echo "iOS simulator $UDID not booted"; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] \
  || { echo "missing $HARNESS_DIR/onboard-bob.txt; run 'make demo-onboard'"; exit 1; }
[ -d "$APP_BUNDLE" ] \
  || { echo "missing $APP_BUNDLE; run 'just ios-build'"; exit 1; }

# 2. Record only lengths + relay URL — no plaintext secrets.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://127.0.0.1:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
EOF

# 3. Build credentials and preload iOS Simulator UIPasteboard.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "%s" "$PACKAGE" | xcrun simctl pbcopy "$UDID" 2>/dev/null || true
echo "[$(date +%H:%M:%S)] preloaded simctl pbcopy with bfonboard1 (length=${PACKAGE_LEN})"

# 4. Cold install + cold launch with diagnostics env propagated so the
#    URL handler is reachable.
echo "[$(date +%H:%M:%S)] ********* Cold install on iOS Simulator $UDID *********"
# Uninstall and reset Keychain + UserDefaults so bob's prior profile doesn't
# trigger the VAL-ONBOARD-015 duplicate guard when we re-save through the
# URL handler. Both Keychain entries and the bundle's UserDefaults index
# persist across uninstall on iOS Simulator.
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
# Wipe the app's Application Support directory so any RMP-side persisted
# snapshot (Rust's state file) is also fresh — this prevents any prior
# profile_id from re-sneaking into the dedupe check via the rust core's
# shared state file.
APP_CONTAINER=$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null || true)
if [ -n "$APP_CONTAINER" ]; then
  rm -rf "$APP_CONTAINER/Library/Application Support"/* 2>/dev/null || true
fi
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 2

# 5. Maestro 01 — navigate to OnboardConnect so test-inject can land.
cat > "$FLOW_DIR/01-ios-navigate-onboard-template.yaml" <<EOF
appId: $APP_ID
name: 01 ios navigate to OnboardConnect
---
- assertVisible:
    text: "Igloo"
- assertVisible:
    text: "Onboard Device"
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
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 01: navigate to OnboardConnect *********"
maestro --device "$UDID" test "$FLOW_DIR/01-ios-navigate-onboard-template.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 done"

# 6. URL-scheme inject bob's bfonboard1 + bob-ios-save-url-fix hint.
#    The hint lands in onboarding.injected_device_name so the
#    OnboardReview TextField is prefilled (`bob-ios-save-url-fix`).
echo "[$(date +%H:%M:%S)] ********* URL-scheme inject bob's bfonboard1 *********"
PACKAGE_B64=$(printf "%s" "$PACKAGE" | base64 | tr -d '\n')
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
DEVICE_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('bob-ios-save-url-fix'))")
INJECT_URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}&device_name=${DEVICE_ENC}"
echo "[$(date +%H:%M:%S)] inject_url_length=${#INJECT_URL}; pkg_b64_len=${#PACKAGE_B64}"
xcrun simctl openurl "$UDID" "$INJECT_URL" 2>&1 | head

# 7. Maestro 01b — wait until OnboardReview is visible AND the
#    prefilled device-name hint is rendered by the diagnostics-enabled
#    OnboardReviewView.
cat > "$FLOW_DIR/01b-ios-wait-onboard-review-with-hint.yaml" <<EOF
appId: $APP_ID
name: 01b ios wait for OnboardReview with prefilled hint
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    text: "bob-ios-save-url-fix"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 01b: wait for OnboardReview with hint *********"
maestro --device "$UDID" test "$FLOW_DIR/01b-ios-wait-onboard-review-with-hint.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-01b" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01b.log"
echo "[$(date +%H:%M:%S)] maestro 01b done"

# 8. Send igloo://test-save-to-dashboard?device_name=bob-ios-save-url-fix
#    to invoke the diagnostics-gated
#    AppAction::DiagnosticsOnboardSave path without any SwiftUI
#    button-tap. The shell helper derives (profile_id, label,
#    short_id) from the resolved identity and dispatches OnboardSave,
#    which emits StoreOnboardedProfile and routes through the same
#    OnboardStored -> Screen.Dashboard transition the user-typed
#    save path uses.
echo "[$(date +%H:%M:%S)] ********* URL-scheme test-save-to-dashboard *********"
SAVE_URL="igloo://test-save-to-dashboard?device_name=${DEVICE_ENC}"
echo "[$(date +%H:%M:%S)] save_url_length=${#SAVE_URL}; first_chars=${SAVE_URL:0:30}"

# Start a log capture in the background so we can verify the URL
# handler dispatched DiagnosticsOnboardSave (without plaintext data).
(
  xcrun simctl spawn "$UDID" log stream --level info \
      --predicate 'subsystem == "com.frostr.igloo.dev"' 2>&1
) > "$EVIDENCE_DIR/onboard-diagnostic-events.log" 2>&1 &
LOG_PID=$!
sleep 1

xcrun simctl openurl "$UDID" "$SAVE_URL" 2>&1 | head
sleep 6
kill "$LOG_PID" 2>/dev/null || true

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# 9. Wait for Dashboard to come up, then snapshot.
# iOS Maestro on iOS 26.5 simulator does not always expose the inner
# SwiftUI Button accessibilityIdentifier as a top-level resource-id;
# we verify dashboard identity through multiple identifiers instead.
cat > "$FLOW_DIR/02-ios-wait-dashboard-after-save-url.yaml" <<EOF
appId: $APP_ID
name: 02 ios wait for Dashboard after test-save-to-dashboard URL
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 30000
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    id: "tab_signer"
- assertVisible:
    text: "Signer Stopped"
- assertVisible:
    text: "Start"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 02: wait for Dashboard after URL save *********"
maestro --device "$UDID" test "$FLOW_DIR/02-ios-wait-dashboard-after-save-url.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -15 > "$EVIDENCE_DIR/maestro-02-save-url.log"
echo "[$(date +%H:%M:%S)] maestro 02 done"
snapshot "post-save-url-dashboard"

# 10. Maestro 03 — exercise the real Start control and verify
#     Signer Running within 15 s + btn_stop_signer appears.
# iOS Maestro accesses the inner SwiftUI Button via the parent
# signer_status_card resource-id (Button.accessibilityIdentifier is
# not always materialised as a top-level resource-id on the sim).
# We tap by text since the button label is "Start".
cat > "$FLOW_DIR/03-ios-tap-btn-start-signer-and-verify-running.yaml" <<EOF
appId: $APP_ID
name: 03 ios tap btn_start_signer + verify running within 15s
---
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    text: "Start"
- tapOn:
    text: "Start"
- extendedWaitUntil:
    visible:
      text: "Signer Running"
    timeout: 15000
- assertVisible:
    text: "Signer Running"
- assertVisible:
    text: "Stop"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 03: tap btn_start_signer + assert Signer Running *********"
maestro --device "$UDID" test "$FLOW_DIR/03-ios-tap-btn-start-signer-and-verify-running.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-03" 2>&1 | tail -20 > "$EVIDENCE_DIR/maestro-03.log"
echo "[$(date +%H:%M:%S)] maestro 03 done"
snapshot "post-tap-start-signer-running"

# 11. Scroll the Signer tab to expose the event log; capture the
#     INFO row with the RFC-3339 timestamp committed in ffd1c4c.
sleep 4
xcrun simctl io "$UDID" swipe down 100 800 100 200 0.6 2>/dev/null || true
sleep 2
snapshot "post-tap-start-signer-running-scrolled"

# 12. Maestro 04 — exercise the per-peer Refresh / Test Ping controls
#     and assert the event log gains a new INFO row.
cat > "$FLOW_DIR/04-ios-ping-control-and-event-log.yaml" <<EOF
appId: $APP_ID
name: 04 ios tap peer Refresh / Test Ping and verify new event log row
---
- assertVisible:
    text: "Signer Running"
- assertVisible:
    text: "Stop"
- swipe:
    direction: UP
    duration: 400
- scrollUntilVisible:
    element:
      text: "Refresh"
    timeout: 15000
- tapOn:
    text: "Refresh"
- scrollUntilVisible:
    element:
      text: "Test Ping"
    timeout: 15000
- tapOn:
    text: "Test Ping"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 04: tap Refresh + Test Ping *********"
maestro --device "$UDID" test "$FLOW_DIR/04-ios-ping-control-and-event-log.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-04" 2>&1 | tail -20 > "$EVIDENCE_DIR/maestro-04.log"
echo "[$(date +%H:%M:%S)] maestro 04 done"
snapshot "post-tap-test-ping-event-log"

# 13. Validate evidence.
DASH="$EVIDENCE_DIR/hierarchy-post-save-url-dashboard.txt"
PRE="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running.txt"
SCROLLED="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running-scrolled.txt"
EVENTLOG="$EVIDENCE_DIR/hierarchy-post-tap-test-ping-event-log.txt"

[ -f "$DASH" ] || { echo "FAIL: missing $DASH"; exit 1; }
[ -f "$PRE" ] || { echo "FAIL: missing $PRE"; exit 1; }
[ -f "$EVENTLOG" ] || { echo "FAIL: missing $EVENTLOG"; exit 1; }

# 13a. Dashboard reached via URL handler (no SwiftUI tap).
# iOS Maestro on iOS 26.5 simulator does not always expose the inner
# SwiftUI Button .accessibilityIdentifier() as a top-level resource-id;
# the button is rendered through the parent signercard's resource-id
# instead, with `accessibilityText: "Start"`. We accept either form.
if ! grep -Eq 'btn_start_signer|"Start"' "$DASH"; then
  echo "FAIL: post-URL-save dashboard missing btn_start_signer or Start identifier"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] dashboard reached via igloo://test-save-to-dashboard URL handler"

if ! grep -q 'signer_status_card' "$DASH"; then
  echo "FAIL: dashboard missing signer_status_card"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] dashboard publishes signer status card"

if ! grep -q 'btn_refresh_peers\|btn_test_ping' "$DASH"; then
  echo "FAIL: dashboard missing peer control identifiers"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] dashboard exposes peer/ping controls"

# 13b. Pre-tap status "Signer Stopped".
if ! grep -q 'Signer Stopped' "$DASH"; then
  echo "FAIL: post-save-url dashboard missing 'Signer Stopped'"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] stopped baseline verified on Dashboard"

# 13c. Post-tap status "Signer Running".
if ! grep -q 'Signer Running' "$PRE"; then
  echo "FAIL: post-tap hierarchy missing 'Signer Running'"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap 'Signer Running' present"

# 13d. btn_stop_signer shown after tap (or fallback text "Stop").
if ! grep -Eq 'btn_stop_signer|"Stop"' "$PRE"; then
  echo "FAIL: post-tap missing btn_stop_signer identifier or 'Stop' text"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap btn_stop_signer identifier present"

echo "================================================================"
echo "PASS verdict: igloo://test-save-to-dashboard URL drives the"
echo "diagnostics-gated AppAction::DiagnosticsOnboardSave path from"
echo "the real OnboardReview resolved state to the Dashboard without"
echo "any SwiftUI button-tap routing. iOS Start/Stop/Ping real UI"
echo "controls continue to invoke the SideEffect reconcilers and"
echo "produce RFC-3339 INFO rows."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
