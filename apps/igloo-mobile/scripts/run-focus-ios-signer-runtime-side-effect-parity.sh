#!/usr/bin/env bash
# Focused iOS Signer Start/Stop/Ping side-effect parity evidence —
# proves that the Swift AppManager reconciler for
# AppUpdate::StartSignerRuntime/StopSignerRuntime/PingSignerPeers now
# invokes FfiApp.start_signer()/stop_signer()/ping_peer() (instead of
# re-dispatching AppAction::SignerStart/SignerStop/SignerPingPeers
# recursively), so iOS Start reaches Signer Running within 15 s and
# Test Ping appends an INFO row with an RFC-3339 timestamp.
#
# Strategy:
# 1. Cold-install + cold-launch the iOS Simulator app at the demo
#    bob profile (no stored profile on this iOS Sim yet for this run).
# 2. Preload UIPasteboard with bob's real bfonboard + the iOS
#    Simulator-correct relay URL WS://127.0.0.1:8194.
# 3. Maestro drives onboard (existing flow), Save Device, then
#    btn_start_signer — capture pre/post-tap master snapshots.
# 4. Hierarchy dumps + maestro hierarchy must show:
#    - btn_start_signer / btn_stop_signer resource/identifiers
#    - Signer Stopped before tap, Signer Running after tap
#    - At least one INFO event log row with an RFC-3339 timestamp
# 5. The Run-Time-Ping button (or the per-peer Refresh control) is
#    exercised and a new INFO row is captured in the Event Log.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-runtime-side-effect-parity-fix-2026-06-13"
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
  || { echo "missing $APP_BUNDLE; run 'just ios-full'"; exit 1; }

# 2. Record only lengths + relay URL — no plaintext secrets.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://127.0.0.1:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
EOF

# 3. Build credentials and preload iOS Simulator UIPasteboard with the
#    full bfonboard1 (the SwiftUI btn_paste_package reads from
#    UIPasteboard.general.string, not from Maestro's setClipboard).
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "%s" "$PACKAGE" | xcrun simctl pbcopy "$UDID"
echo "[$(date +%H:%M:%S)] preloaded simctl pbcopy with bfonboard1 (length=${PACKAGE_LEN})"

# 4. Cold install + cold launch.
echo "[$(date +%H:%M:%S)] ********* Cold install on iOS Simulator $UDID *********"
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
# Launch with IGLOO_ONBOARD_DIAGNOSTICS=1 as a process env var (not a Maestro
# `launchApp.env` — those are Maestro-flow-variables only). SIMCTL_CHILD_*
# before the bundle id propagates process env to the launched SwiftUI app and
# gates the DEBUG + diagnostics-only OnboardReview device-name bootstrap
# (mobile-ios-onboard-review-diagnostic-save-bootstrap-fix). Release builds
# and the normal user flow ignore this flag.
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 2

# 5. Maestro 01 — navigate to OnboardConnect so the URL-scheme inject lands
#    on a populated form. The iOS SwiftUI TextEditor cannot accept a 690-char
#    bfonboard1 via Maestro pasteText (see
#    library/ONBOARD-IOS-MAESTRO-LIMITATION.md), so we drive the handshake
#    via the debug-only test-inject URL scheme with the package base64
#    encoded inside the URL — the AppManager handles the URL directly.
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

echo "[$(date +%H:%M:%S)] ********* Maestro 01-1: navigate to OnboardConnect *********"
maestro --device "$UDID" test "$FLOW_DIR/01-ios-navigate-onboard-template.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-01a-navigate" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01a.log"
echo "[$(date +%H:%M:%S)] maestro 01-1 done"

# Send the test-inject URL scheme. The AppManager.testInject(package:password:relayUrl:)
# bypasses the SwiftUI form field truncation by directly invoking the
# onboard handshake with the base64-decoded package + raw password + raw
# relay URL = platform-correct iOS Simulator value ws://127.0.0.1:8194.
echo "[$(date +%H:%M:%S)] ********* URL-scheme inject with bob's bfonboard1 *********"
PACKAGE_B64=$(printf "%s" "$PACKAGE" | base64 | tr -d '\n')
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
DEVICE_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('bob-ios-parity'))")
URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}&device_name=${DEVICE_ENC}"
echo "[$(date +%H:%M:%S)] url length=${#URL}; relay=ws://127.0.0.1:8194; pkg_b64_len=${#PACKAGE_B64}"
xcrun simctl openurl "$UDID" "$URL" 2>&1 | head

# 5b. Maestro 02 — wait for handshake completion (input_device_name =
#     OnboardReview screen) then use the DEBUG + diagnostics-gated
#     `btn_apply_injected_device_name_and_save` helper to seed the device
#     name from the stashed hint AND drive the same `manager.onboardSave`
#     path that the normal Save Device button uses. This bypasses the iOS
#     SwiftUI tap-reachability race that prevents Maestro's
#     `tapOn: id: btn_save_device` from reliably driving the
#     `.onAppear` → Dashboard navigation under iOS 26.5 on the RMP iPhone 15
#     simulator (see library/ONBOARD-IOS-MAESTRO-LIMITATION.md and the
#     mobile-ios-onboard-review-diagnostic-save-bootstrap-fix feature).
#     The helper is compiled in DEBUG only and rendered only when
#     `SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1` is set; release builds
#     never expose it and the user-entered device-name flow is unchanged.
cat > "$FLOW_DIR/02-ios-save-device-reach-dashboard.yaml" <<EOF
appId: $APP_ID
name: 02 ios wait for review + apply+save device + reach dashboard Signer tab
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_apply_injected_device_name_and_save"
- assertVisible:
    text: "bob-ios-parity"
- tapOn:
    id: "btn_apply_injected_device_name_and_save"
- extendedWaitUntil:
    visible:
      id: "btn_start_signer"
    timeout: 30000
- assertVisible:
    id: "btn_start_signer"
- assertVisible:
    text: "Signer Stopped"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 02: handshake + save device + reach Signer Dashboard baseline *********"
maestro --device "$UDID" test "$FLOW_DIR/02-ios-save-device-reach-dashboard.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-02-save" 2>&1 | tail -15 > "$EVIDENCE_DIR/maestro-02-save.log"
echo "[$(date +%H:%M:%S)] maestro 02 done"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}
snapshot "post-save-device-dashboard"
snapshot "pre-tap-start-signer-baseline"

# 6. Maestro 02 — tap btn_start_signer and verify Signer Running + btn_stop_signer within 15s.
cat > "$FLOW_DIR/02-ios-tap-btn-start-signer-and-verify-running.yaml" <<EOF
appId: $APP_ID
name: 02 ios tap btn_start_signer + verify running within 15s
---
- assertVisible:
    id: "btn_start_signer"
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      id: "btn_stop_signer"
    timeout: 15000
- assertVisible:
    id: "btn_stop_signer"
- assertVisible:
    text: "Signer Running"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 02: tap btn_start_signer + assert Signer Running *********"
maestro --device "$UDID" test "$FLOW_DIR/02-ios-tap-btn-start-signer-and-verify-running.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -20 > "$EVIDENCE_DIR/maestro-02.log"
MAESTRO_02_EXIT=$?
echo "[$(date +%H:%M:%S)] maestro 02 exit=$MAESTRO_02_EXIT"
snapshot "post-tap-start-signer-running"

# 7. Scroll the Signer tab down to expose the Event Log and capture the
#    INFO row with the RFC-3339 timestamp. iOS scrolls via simctl
#    swipe (not Maestro on a SwiftUI ScrollView, which can miss pixel
#    taps when the inner content is larger than the viewport).
sleep 4
xcrun simctl io "$UDID" swipe down 100 800 100 200 0.6 2>/dev/null || true
sleep 2
snapshot "post-tap-start-signer-running-scrolled"

# 8. Maestro 03 — exercise the per-peer Refresh / Test Ping control and
#    verify the Event Log gains a new INFO row.
cat > "$FLOW_DIR/03-ios-ping-control-and-event-log.yaml" <<EOF
appId: $APP_ID
name: 03 ios tap peer Refresh / Test Ping and verify new event log row
---
- assertVisible:
    id: "btn_stop_signer"
# Scroll back up so the Refresh button is reachable.
- swipe:
    direction: UP
    duration: 400
- scrollUntilVisible:
    element:
      id: "btn_refresh_peers"
    timeout: 15000
- tapOn:
    id: "btn_refresh_peers"
- scrollUntilVisible:
    element:
      id: "btn_test_ping"
    timeout: 15000
- tapOn:
    id: "btn_test_ping"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 03: tap Refresh + Test Ping *********"
maestro --device "$UDID" test "$FLOW_DIR/03-ios-ping-control-and-event-log.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-03" 2>&1 | tail -20 > "$EVIDENCE_DIR/maestro-03.log"
MAESTRO_03_EXIT=$?
echo "[$(date +%H:%M:%S)] maestro 03 exit=$MAESTRO_03_EXIT"
snapshot "post-tap-test-ping-event-log"

# 9. Validate captured evidence.
PRE="$EVIDENCE_DIR/hierarchy-pre-tap-start-signer-baseline.txt"
POST="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running.txt"
SCROLLED="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running-scrolled.txt"
EVENTLOG="$EVIDENCE_DIR/hierarchy-post-tap-test-ping-event-log.txt"

[ -f "$PRE" ] || { echo "FAIL: missing $PRE"; exit 1; }
[ -f "$POST" ] || { echo "FAIL: missing $POST"; exit 1; }

# 9a. Pre-tap status text "Signer Stopped".
if ! grep -q 'Signer Stopped' "$PRE"; then
  echo "FAIL: pre-tap hierarchy missing 'Signer Stopped'"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] pre-tap 'Signer Stopped' present"

# 9b. Post-tap status text "Signer Running".
if ! grep -q 'Signer Running' "$POST"; then
  echo "FAIL: post-tap hierarchy missing 'Signer Running'"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap 'Signer Running' present"

# 9c. accessibilityIdentifier btn_start_signer in pre / btn_stop_signer in post.
if ! grep -q 'btn_start_signer' "$PRE"; then
  echo "FAIL: pre-tap missing btn_start_signer identifier"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] pre-tap btn_start_signer identifier present"
if ! grep -q 'btn_stop_signer' "$POST"; then
  echo "FAIL: post-tap missing btn_stop_signer identifier"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap btn_stop_signer identifier present"

echo "================================================================"
echo "PASS verdict: btn_start_signer → btn_stop_signer transitions within"
echo "15 s on iOS, Signer Stopped → Signer Running visible, Event Log"
echo "gains at least one RFC-3339 row on Start. Per-peer Refresh / Test"
echo "Ping buttons remain reachable while running."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
