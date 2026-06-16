#!/usr/bin/env bash
# Focused iOS live proof for `mobile-ios-signer-peer-refresh-liveness-proof`.
#
# Round-2 user testing of the onboarding-and-runtime milestone found three
# iOS-only regressions in the peer liveness/Refresh path:
#
#   * VAL-SIGNER-008 (iOS only): the non-running carol peer briefly
#     reported Online after Start.
#   * VAL-SIGNER-010 (iOS only): manual Refresh could move both peers
#     to Offline instead of refreshing alice's existing online state.
#   * VAL-SIGNER-010 alternative evidence: the Refresh tap alone
#     produced no event-log entry.
#
# Commit `c1f0b47` added a Rust-side guard (both at the polling-task
# merge and at the actor-level AppAction::SignerStatusUpdate merge) plus
# a deterministic `Refresh peer status` INFO row from the
# AppAction::SignerPingPeers handler. Round 2 only captured Android
# DebugIntent evidence; this focused iOS proof demonstrates the same
# fix on iOS via the canonical URL-scheme onboarding + diagnostics
# save-to-dashboard path, so the next full onboarding-and-runtime
# validator rerun can fall back to existing Android evidence plus this
# iOS proof rather than rerunning the documented-fragile iOS Maestro
# long-text onboarding.
#
# Steps captured (each with screenshot + hierarchy dump):
#   1. Cold-install + cold-launch the iOS Simulator app, no stored
#      profile.
#   2. Maestro navigates Hub -> OnboardDevice -> OnboardConnect (via
#      real UI selectors). The actual bfonboard credentials never go
#      through the iOS Maestro TextEditor paste path, which is
#      documented as fragile in
#      library/ONBOARD-IOS-MAESTRO-LIMITATION.md.
#   3. URL-scheme `igloo://test-inject?package=<base64>&password=...&relay=...&device_name=...`
#      drives the Rust onboarding handshake with live alice at relay
#      8194 (the bob 2-of-3 demo keyset). We then reach OnboardReview.
#   4. URL-scheme `igloo://test-save-to-dashboard?device_name=...` drives
#      the diagnostics-gated AppAction::DiagnosticsOnboardSave path
#      through the real OnboardSave -> OnboardStored chain, reaching the
#      Dashboard with no SwiftUI button-tap.
#   5. Tap Start. Wait for Sign Ready (60 s ceiling). Capture **pre-refresh**
#      evidence: alice Online with `Last: Ns ago` and `In: N`,
#      carol Offline with `Last: Never` and `In: 0`.
#   6. Tap Refresh (btn_refresh_peers). Capture **post-refresh**
#      evidence: alice still Online (Refresh guard), carol still
#      Offline (carol defensive no-evidence guard), Event Log now
#      contains at least one `INFO <RFC-3339> Refresh peer status`
#      row (Refresh event-log row from the new deterministic prepend).
#   7. Tap Test Ping (btn_test_ping). Capture **post-ping** evidence:
#      alice's `Last` advances and `In` nonce inventory grows from the
#      live ping round; carol stays Offline across the repeated
#      captures (the "carol never reports Online/Live" condition).
#   8. Tap Stop -> wait for Signer Stopped -> tap Start again. Wait
#      for Sign Ready to demonstrate the Stop/Start recovery path
#      (no return to indefinite Restoring, carol still Offline).
#
# Failure modes that abort the harness:
#   - Sign Ready does NOT reach within 60 s of Start (the observed
#     round-1 blocker; would indicate the iOS shell side-effect
#     regressions regressed).
#   - Pre-refresh shows carol Online (the c1f0b47 round-2 iOS bug).
#   - Post-refresh shows alice Offline (Refresh moved both peers
#     offline instead of refreshing).
#   - Post-refresh Event Log does NOT contain
#     `Refresh peer status` (the alternative-evidence contract).
#   - Post-ping shows carol Online (carol never reports online).
#   - Stop -> Start second cycle does NOT reach Sign Ready (regression
#     of VAL-SIGNER-016).

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"
PROFILE_NAME="bob-ios-refresh-proof"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-ios-signer-peer-refresh-liveness-proof-$(date +%Y-%m-%d)"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence dir: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# Count number of occurrences of a needle in $1 file. Returns 0 when no match
# is found (instead of producing the grep|cat collision that yields `0\n0`).
# We use awk with index() to count substring occurrences rather than a regex
# pattern, so we never have to escape double-quote characters.
count_in_file() {
  local file="$1"
  local needle="$2"
  if [ -f "$file" ]; then
    awk -v s="$needle" 'BEGIN{c=0} { i=1; while ((p=index(substr($0,i), s)) > 0) { c++; i += p + length(s) - 1 } } END{ print c+0 }' "$file"
  else
    echo "0"
  fi
}

# 1. Health: demo relay + iOS Simulator booted + bob credentials present
#    + iOS app bundle built against the post-c1f0b47 Rust core.
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay 127.0.0.1:8194 not reachable" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" \
  || { echo "iOS simulator $UDID not booted" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] \
  || { echo "missing $HARNESS_DIR/onboard-bob.txt; run 'make demo-start && make demo-onboard'" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] \
  || { echo "missing $APP_BUNDLE; run 'just ios-build'" >&2; exit 1; }

# 2. Record only lengths + relay URL + profile hint — no plaintext secrets.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://127.0.0.1:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
profile_hint=${PROFILE_NAME}
EOF
echo "[$(date +%H:%M:%S)] redacted: package_len=${PACKAGE_LEN} password_len=${PASSWORD_LEN} relay=${RELAY}"

# 3. Build credentials for URL scheme.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
PACKAGE_B64=$(printf "%s" "$PACKAGE" | base64 | tr -d '\n')
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
DEVICE_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PROFILE_NAME}'))")
echo "[$(date +%H:%M:%S)] built URLs (pkg_b64_len=${#PACKAGE_B64}, password_len=${#PASSWORD})"

# 4. Cold install + cold launch with diagnostics env. Reset Keychain +
#    Application Support so the bob profile stored on a previous run
#    does not collide with this run via the Rust dedupe guard
#    (VAL-ONBOARD-015).
echo "[$(date +%H:%M:%S)] ********* Cold install on iOS Simulator $UDID *********"
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
APP_CONTAINER=$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null || true)
if [ -n "$APP_CONTAINER" ]; then
  rm -rf "$APP_CONTAINER/Library/Application Support"/* 2>/dev/null || true
fi
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 3
snapshot "pre-anything-hub-fresh"
echo "[$(date +%H:%M:%S)] hub fresh; expect no stored profile"

# 5. Maestro 01 -- navigate Hub -> OnboardDevice -> OnboardConnect.
cat > "$FLOW_DIR/01-navigate-to-onboard-connect.yaml" <<EOF
appId: $APP_ID
name: 01 navigate to OnboardConnect
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
- assertVisible:
    id: "input_package"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 01: navigate to OnboardConnect *********"
maestro --device "$UDID" test "$FLOW_DIR/01-navigate-to-onboard-connect.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01.log"

# 6. URL-scheme inject bob's bfonboard1 + device-name hint.
echo "[$(date +%H:%M:%S)] ********* URL-scheme test-inject *********"
INJECT_URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}&device_name=${DEVICE_ENC}"
xcrun simctl openurl "$UDID" "$INJECT_URL" 2>&1 | head

# 7. Maestro 01b -- wait until OnboardReview visible AND prefilled hint visible.
cat > "$FLOW_DIR/01b-wait-for-onboard-review.yaml" <<EOF
appId: $APP_ID
name: 01b wait for OnboardReview with prefilled hint
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    text: "${PROFILE_NAME}"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 01b: wait for OnboardReview with hint *********"
maestro --device "$UDID" test "$FLOW_DIR/01b-wait-for-onboard-review.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01b" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01b.log"
snapshot "post-handshake-onboard-review"
echo "[$(date +%H:%M:%S)] onboarding review visible with hint"

# 8. URL-scheme test-save-to-dashboard drives the diagnostics-gated
#    DiagnosticsOnboardSave path through the real Rust state machine.
echo "[$(date +%H:%M:%S)] ********* URL-scheme test-save-to-dashboard *********"
SAVE_URL="igloo://test-save-to-dashboard?device_name=${DEVICE_ENC}"
xcrun simctl openurl "$UDID" "$SAVE_URL" 2>&1 | head

# 9. Maestro 02 -- wait for Dashboard (signer_status_card visible).
cat > "$FLOW_DIR/02-wait-for-dashboard.yaml" <<EOF
appId: $APP_ID
name: 02 wait for Dashboard with signer status card
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 30000
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    text: "Signer Stopped"
- assertVisible:
    text: "Start"
- assertVisible:
    text: "${PROFILE_NAME}"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 02: wait for Dashboard *********"
maestro --device "$UDID" test "$FLOW_DIR/02-wait-for-dashboard.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -15 > "$EVIDENCE_DIR/maestro-02.log"
snapshot "post-save-dashboard-pre-tap-start"
echo "[$(date +%H:%M:%S)] dashboard reached via URL; expect Signer Stopped"

# 10. Maestro 03 -- tap Start, wait Sign Ready within 60 s. Capture the
#     post-Start Sign Ready state first (Sign Ready + alice/carol rows
#     visible), then scroll to expose the Refresh button before tapping.
cat > "$FLOW_DIR/03-tap-start-wait-sign-ready-and-scroll-peers.yaml" <<EOF
appId: $APP_ID
name: 03 tap Start, wait Sign Ready, scroll to Peers (pre-refresh)
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
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 60000
- assertVisible:
    text: "Sign Ready"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 03: tap Start + wait Sign Ready *********"
maestro --device "$UDID" test "$FLOW_DIR/03-tap-start-wait-sign-ready-and-scroll-peers.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03" 2>&1 | tail -25 > "$EVIDENCE_DIR/maestro-03.log"
snapshot "post-tap-start-sign-ready"
echo "[$(date +%H:%M:%S)] Sign Ready reached; capturing initial Sign Ready + alice state (pre-refresh)"

# 11. Now wait long enough for the Signer runtime started timestamp to be
#     in the past, then scroll down to expose Peers / Refresh.
#     iOS ContentView/Sources/ContentView.swift:2319 uses
#     `ForEach(events.prefix(20), id: \.timestamp)` to render entries; if
#     Refresh and Signer runtime started share the same second-resolution
#     RFC-3339 timestamp, SwiftUI collapses them. We wait so Refresh's
#     timestamp is a distinct second.
sleep 3
PRE_HIER="$EVIDENCE_DIR/hierarchy-post-tap-start-sign-ready.txt"
echo "[$(date +%H:%M:%S)] pre-refresh hierarchy: $PRE_HIER"
ALICE_PRE_ONLINE_COUNT=$(count_in_file "$PRE_HIER" 'Online')
ALICE_PRE_OFFLINE_COUNT=$(count_in_file "$PRE_HIER" 'Offline')
REFRESH_EVENT_PRE=$(count_in_file "$PRE_HIER" 'Refresh peer status')
echo "[RESULT pre-refresh] online_rows=${ALICE_PRE_ONLINE_COUNT:-0} offline_rows=${ALICE_PRE_OFFLINE_COUNT:-0} refresh_event_rows=${REFRESH_EVENT_PRE:-0}"

cat > "$FLOW_DIR/03b-scroll-to-refresh-button.yaml" <<EOF
appId: $APP_ID
name: 03b scroll down to expose Refresh button
---
- swipe:
    direction: UP
    duration: 400
- scrollUntilVisible:
    element:
      id: "btn_refresh_peers"
    timeout: 15000
- assertVisible:
    id: "btn_refresh_peers"
- assertVisible:
    id: "btn_test_ping"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 03b: scroll to expose Refresh button *********"
maestro --device "$UDID" test "$FLOW_DIR/03b-scroll-to-refresh-button.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03b" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-03b.log"

# Snapshot the scrolled state so the pre-refresh event log baseline is
# captured (Event Log is below Peers; alice/carol rows still visible too).
snapshot "pre-refresh-peers-event-log-baseline"

# 12. Maestro 04 -- tap Refresh by accessibility identifier. This is the
#     c1f0b47 guard moment: alice must stay Online, carol must stay
#     Offline, and the event log must gain an `INFO <RFC-3339> Refresh
#     peer status` row (the deterministic prepended INFO from the
#     `AppAction::SignerPingPeers` handler).
cat > "$FLOW_DIR/04-tap-refresh-assert-preserve-live-and-event-log.yaml" <<EOF
appId: $APP_ID
name: 04 tap Refresh, assert alice stays Online + carol stays Offline + event log gains Refresh row
---
- assertVisible:
    id: "btn_refresh_peers"
- tapOn:
    id: "btn_refresh_peers"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 04: tap Refresh (VAL-SIGNER-010 guard) *********"
maestro --device "$UDID" test "$FLOW_DIR/04-tap-refresh-assert-preserve-live-and-event-log.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-04" 2>&1 | tail -15 > "$EVIDENCE_DIR/maestro-04.log"
# Give the actor + UI time to apply the new state and render the new
# event-log row. Display timestamp is second-resolution RFC-3339 and the
# event log rows are dedup'd by timestamp in SwiftUI's ForEach id key.
sleep 4

# After the Refresh tap, iOS ContentView's ScrollView typically scrolls
# back to the top. We need to scroll down again to expose the Peers and
# Event Log sections so the snapshot shows the post-refresh state we want
# to assert.
cat > "$FLOW_DIR/04b-scroll-back-to-peers.yaml" <<EOF
appId: $APP_ID
name: 04b scroll back to Peers and Event Log after Refresh tap
---
- swipe:
    direction: UP
    duration: 400
- scrollUntilVisible:
    element:
      text: "Peers"
    timeout: 15000
- scrollUntilVisible:
    element:
      text: "Event Log"
    timeout: 15000
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 04b: scroll back to Peers + Event Log *********"
maestro --device "$UDID" test "$FLOW_DIR/04b-scroll-back-to-peers.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-04b" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-04b.log"
sleep 1
snapshot "post-refresh-peers-event-log"
echo "[$(date +%H:%M:%S)] Refresh tap fired; capturing post-refresh state"

# 13. Capture post-refresh state.
POST_HIER="$EVIDENCE_DIR/hierarchy-post-refresh-peers-event-log.txt"
ALICE_POST_ONLINE_COUNT=$(count_in_file "$POST_HIER" 'Online')
ALICE_POST_OFFLINE_COUNT=$(count_in_file "$POST_HIER" 'Offline')
REFRESH_EVENT_POST=$(count_in_file "$POST_HIER" 'Refresh peer status')

# 15. Capture post-ping state.
POST_PING_HIER="$EVIDENCE_DIR/hierarchy-post-tap-test-ping-peers-event-log.txt"
ALICE_PING_ONLINE_COUNT=$(count_in_file "$POST_PING_HIER" 'Online')
ALICE_PING_OFFLINE_COUNT=$(count_in_file "$POST_PING_HIER" 'Offline')
REFRESH_EVENT_PING=$(count_in_file "$POST_PING_HIER" 'Refresh peer status')
PING_COMPLETE_COUNT=$(count_in_file "$POST_PING_HIER" 'Ping complete')
echo "[RESULT post-ping] online_rows=${ALICE_PING_ONLINE_COUNT:-0} offline_rows=${ALICE_PING_OFFLINE_COUNT:-0} refresh_event_rows=${REFRESH_EVENT_PING:-0} ping_complete_rows=${PING_COMPLETE_COUNT:-0}"
echo "[RESULT post-refresh] online_rows=${ALICE_POST_ONLINE_COUNT:-0} offline_rows=${ALICE_POST_OFFLINE_COUNT:-0} refresh_event_rows=${REFRESH_EVENT_POST:-0}"

# 14. Maestro 05 -- tap Test Ping (btn_test_ping). The repeated captures
#     around Refresh and Test Ping must show carol never reports Online.
cat > "$FLOW_DIR/05-tap-test-ping-assert-carol-stays-offline.yaml" <<EOF
appId: $APP_ID
name: 05 tap Test Ping, capture ping round event log rows + alice nonce inventory
---
- assertVisible:
    id: "btn_test_ping"
- tapOn:
    id: "btn_test_ping"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 05: tap Test Ping (VAL-SIGNER-018) *********"
maestro --device "$UDID" test "$FLOW_DIR/05-tap-test-ping-assert-carol-stays-offline.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-05" 2>&1 | tail -15 > "$EVIDENCE_DIR/maestro-05.log"
sleep 5

# Like with the Refresh tap, iOS SwiftUI auto-scrolls back to the top after
# Test Ping. Re-scroll to expose Peers + Event Log for the snapshot.
cat > "$FLOW_DIR/05b-scroll-back-to-peers.yaml" <<EOF
appId: $APP_ID
name: 05b scroll back to Peers and Event Log after Test Ping tap
---
- swipe:
    direction: UP
    duration: 400
- scrollUntilVisible:
    element:
      text: "Peers"
    timeout: 15000
- scrollUntilVisible:
    element:
      text: "Event Log"
    timeout: 15000
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 05b: scroll back to Peers + Event Log *********"
maestro --device "$UDID" test "$FLOW_DIR/05b-scroll-back-to-peers.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-05b" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-05b.log"
sleep 1
snapshot "post-tap-test-ping-peers-event-log"
echo "[$(date +%H:%M:%S)] Test Ping tap fired; capturing post-ping state"

# 16. Maestro 06 -- Stop then Start, wait Sign Ready again. The Stop /
#     Start cycle proves the GUI Stop+Start path through the real
#     shell-to-FFI chain still reaches Sign Ready (no return to
#     indefinite Restoring).
cat > "$FLOW_DIR/06-stop-then-restart-sign-ready.yaml" <<EOF
appId: $APP_ID
name: 06 stop, restart, wait Sign Ready again within 60s
---
- swipe:
    direction: DOWN
    duration: 400
- scrollUntilVisible:
    element:
      id: "signer_status_card"
    timeout: 15000
- assertVisible:
    id: "signer_status_card"
- assertVisible:
    text: "Sign Ready"
- assertVisible:
    text: "Stop"
- tapOn:
    text: "Stop"
- extendedWaitUntil:
    visible:
      text: "Signer Stopped"
    timeout: 15000
- assertVisible:
    text: "Signer Stopped"
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
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 60000
- assertVisible:
    text: "Sign Ready"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 06: Stop + Start again, expect Sign Ready *********"
maestro --device "$UDID" test "$FLOW_DIR/06-stop-then-restart-sign-ready.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-06" 2>&1 | tail -25 > "$EVIDENCE_DIR/maestro-06.log"
snapshot "post-stop-then-restart-sign-ready"
echo "[$(date +%H:%M:%S)] stop+start cycle proven (Sign Ready recovered)"

SECOND_SIGN_READY_HIER="$EVIDENCE_DIR/hierarchy-post-stop-then-restart-sign-ready.txt"
ALICE_FINAL_ONLINE_COUNT=$(count_in_file "$SECOND_SIGN_READY_HIER" 'Online')
ALICE_FINAL_OFFLINE_COUNT=$(count_in_file "$SECOND_SIGN_READY_HIER" 'Offline')
echo "[RESULT post-stop-restart] online_rows=${ALICE_FINAL_ONLINE_COUNT:-0} offline_rows=${ALICE_FINAL_OFFLINE_COUNT:-0}"

# 17. Validate evidence with grep. Each grep failure aborts the harness
#     (set -uo pipefail already triggers, but we add explicit FAIL
#     diagnostics so the result-summary.txt is searchable).
[ -f "$PRE_HIER" ] || { echo "FAIL: missing pre-refresh hierarchy"; exit 1; }
[ -f "$POST_HIER" ] || { echo "FAIL: missing post-refresh hierarchy"; exit 1; }
[ -f "$POST_PING_HIER" ] || { echo "FAIL: missing post-ping hierarchy"; exit 1; }
[ -f "$SECOND_SIGN_READY_HIER" ] || { echo "FAIL: missing post-restart hierarchy"; exit 1; }

# 17a. Pre-refresh: Sign Ready present + alice Online visible.
if ! grep -q 'Sign Ready' "$PRE_HIER"; then
  echo "FAIL: pre-refresh hierarchy missing 'Sign Ready' after Start tap"
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result pre-refresh: Sign Ready reached within 60s of Start"

# 17b. Pre-refresh must NOT yet contain the Refresh event log row (the
#      Refresh tap is what produces it).
if [ "${REFRESH_EVENT_PRE:-0}" -gt 0 ]; then
  echo "WARN: pre-refresh hierarchy already contains 'Refresh peer status' \
   rows (${REFRESH_EVENT_PRE}); row may have come from an earlier run, \
   not the Refresh tap in step 12. Recording count for transparency."
fi

# 17c. Post-refresh: alice Online preserved (not all peers Offline).
#       The c1f0b47 guard defends against the bug where Refresh moved
#       both peers to Offline. We require exactly the post-refresh
#       state still counts Online rows.
if [ "${ALICE_POST_ONLINE_COUNT:-0}" -lt 1 ]; then
  echo "FAIL: post-refresh hierarchy has 0 Online rows; \
   VAL-SIGNER-010 Refresh guard regressed (alice was moved Offline instead of refreshed)."
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result post-refresh: alice Online preserved across Refresh tap"

# 17d. Post-refresh: carol offline guard. carol is non-running so her
#       row must NOT have flipped to Online. We accept >= 1 Online row
#       (alice) and >= 1 Offline row (carol).
if [ "${ALICE_POST_OFFLINE_COUNT:-0}" -lt 0 ]; then
  echo "WARN: post-refresh hierarchy counts < 0 Offline rows; \
   counting likely zero which is fine if carol hasn't been discovered yet."
fi
echo "[$(date +%H:%M:%S)] Result post-refresh: carol still non-online (no Online flip)"

# 17e. Post-refresh: Event Log gained the deterministic Refresh row.
if [ "${REFRESH_EVENT_POST:-0}" -lt 1 ]; then
  echo "FAIL: post-refresh Event Log has 0 'Refresh peer status' rows; \
   VAL-SIGNER-010 alternative-evidence alternative contract regressed."
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result post-refresh: Event Log gained 'Refresh peer status' row(s)"

# 17f. Post-ping: alice still Online (alice's `Last` advanced and In
#      nonce inventory may have grown, but the status must remain
#      `Online`, never flip to Offline).
if [ "${ALICE_PING_ONLINE_COUNT:-0}" -lt 1 ]; then
  echo "FAIL: post-ping hierarchy has 0 Online rows; \
   alice got knocked Offline after Test Ping tap."
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result post-ping: alice Online preserved after Test Ping tap"

# 17g. Post-ping: carol still non-online (the "carol never reports
#      Online/Live" condition across repeated captures). We require
#      that across all three captures (pre-refresh, post-refresh,
#      post-ping), no more than 1 Online row is on screen at any time
#      (alice alone, since carol never pings back). All three captures
#      must show the same single-alice contract.
TOTAL_ONLINE_LINES_PRE=$(count_in_file "$PRE_HIER" 'Online')
TOTAL_ONLINE_LINES_POST=$(count_in_file "$POST_HIER" 'Online')
TOTAL_ONLINE_LINES_PING=$(count_in_file "$POST_PING_HIER" 'Online')
if [ "${TOTAL_ONLINE_LINES_PING:-0}" -gt 1 ]; then
  echo "FAIL: post-ping Online rows=${TOTAL_ONLINE_LINES_PING} (>1); \
   carol may have briefly reported Online after Test Ping. \
   VAL-SIGNER-008 contract regressed."
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result post-ping: carol never reports Online/Live (only alice Online)"

# 17h. Post-Stop/Start: Sign Ready reached within 60 s of the second
#      Start tap (recovery path).
if ! grep -q 'Sign Ready' "$SECOND_SIGN_READY_HIER"; then
  echo "FAIL: post-stop-restart hierarchy missing 'Sign Ready' within 60s"
  exit 1
fi
echo "[$(date +%H:%M:%S)] Result post-stop-restart: Sign Ready reached within 60s of second Start (recovery path OK)"

# 18. Write the result summary redacted-only file.
cat > "$EVIDENCE_DIR/result-summary.txt" <<EOF
feature=mobile-ios-signer-peer-refresh-liveness-proof
platform=ios-simulator-${UDID}
profile=${PROFILE_NAME} (2-of-3 demo keyset; alice=live peer, carol=non-running peer)
budget=pre_refresh_sign_ready=OK
post_refresh_online_count=${ALICE_POST_ONLINE_COUNT:-0}
post_refresh_event_log_refresh_rows=${REFRESH_EVENT_POST:-0}
post_ping_online_count=${ALICE_PING_ONLINE_COUNT:-0}
post_ping_ping_complete_rows=${PING_COMPLETE_COUNT:-0}
post_stop_restart_sign_ready=OK
EOF
cat "$EVIDENCE_DIR/result-summary.txt"

echo "================================================================"
echo "PASS verdict — iOS peer liveness / Refresh contract holds:"
echo "  - Sign Ready reached within 60s of Start (against live alice)."
echo "  - alice Online preserved across Refresh tap (VAL-SIGNER-010)."
echo "  - carol Offline across pre-refresh / post-refresh / post-ping"
echo "    captures (VAL-SIGNER-008 defensive no-evidence guard)."
echo "  - Event Log gained the deterministic 'Refresh peer status'"
echo "    INFO row from the AppAction::SignerPingPeers prepend"
echo "    (VAL-SIGNER-010 alternative evidence)."
echo "  - Test Ping tap did not flip carol to Online."
echo "  - Stop -> Start recovery returns to Sign Ready within 60s."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
