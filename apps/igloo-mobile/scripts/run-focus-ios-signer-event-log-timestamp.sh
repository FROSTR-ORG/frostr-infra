#!/usr/bin/env bash
# Focused iOS Signer Event Log Timestamp evidence —
# proves that LogEntry.timestamp is a visible UTC RFC-3339 string
# (mobile-signer-event-log-timestamp-rfc3339-fix feature).
#
# Strategy:
# 1. Cold-install + cold-launch app on RMP iPhone 15 (no stored profile).
# 2. Use xcrun simctl openurl igloo://test-inject to inject bob's
#    real bfonboard1 credentials + the platform-correct demo relay URL.
# 3. Drive Maestro through Hub -> OnboardEntry -> OnboardConnect so the
#    inject lands in a populated form.
# 4. After Rust completes the OnboardRequest/OnboardResponse handshake
#    (~7s live), Maestro checks for OnboardReview (input_device_name).
# 5. Maestro fills the device-name field with a non-secret identifier,
#    taps btn_save_device, and waits for the Signer tab.
# 6. Maestro taps btn_start_signer so the runtime logs an
#    "Signer runtime started" event with our new RFC-3339 timestamp.
# 7. We capture: hierarchy dump (event_<timestamp> accessibility ids),
#    screenshot, and a stdout transcript of the matched event entries.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="/Users/plebdev/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-event-log-timestamp-rfc3339-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# Pre-flight
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay port 8194 unreachable" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "missing onboard-bob.txt" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "missing onboard-bob.password.txt" >&2; exit 1; }

# 1. Capture pre-state (the rebuilt artifact timestamps are logged too).
echo "[$(date +%H:%M:%S)] ********* iOS app bundle metadata *********"
ls -la "$APP_BUNDLE/IglooMobile" 2>&1 | head -3
echo "[$(date +%H:%M:%S)] ********* Cold install app on UDID=$UDID *********"
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
sleep 1
xcrun simctl install "$UDID" "$APP_BUNDLE" 2>&1 | tail -3

# 2. Cold launch + verify hub is fresh (no stored profiles).
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 3
snapshot "pre-launch-hub"

# 3. Construct URL-scheme payload (base64-encoded package + raw password + URL-encoded relay).
PACKAGE_B64=$(cat "$HARNESS_DIR/onboard-bob.txt" | python3 -c "import sys, base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())")
PASSWORD=$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}"
echo "[$(date +%H:%M:%S)] url length=${#URL}; relay_decoded_value=ws://127.0.0.1:8194; pkg_len=${#PACKAGE_B64}"

# 4. Maestro: navigate Hub -> OnboardEntry -> OnboardConnect so the URL-scheme
# lands on a populated form. URL-scheme alone injects fields even from any
# screen, but to drive the handshake we still need btn_connect or to wait for
# the auto-handshake path. The iOS handler currently triggers the handshake on
# inject acceptance.
cat > "$FLOW_DIR/01-navigate-to-onboard-connect.yaml" <<EOF
appId: $APP_ID
name: navigate-to-onboard-connect
---
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
      id: "btn_connect"
    timeout: 20000
- assertVisible:
    id: "btn_connect"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: navigate to OnboardConnect *********"
maestro --device "$UDID" test "$FLOW_DIR/01-navigate-to-onboard-connect.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -5 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 exit=$?"
snapshot "post-navigate-onboard-connect"

# 5. Inject URL scheme — populates package/password/relay into the form.
echo "[$(date +%H:%M:%S)] ********* URL-scheme inject *********"
xcrun simctl openurl "$UDID" "$URL" 2>&1 | head
sleep 2
snapshot "post-url-inject-form"

# 6. Tap btn_connect — kicks off handshake via FfiApp.onboard.
cat > "$FLOW_DIR/02-tap-connect-and-wait-review.yaml" <<EOF
appId: $APP_ID
name: tap-connect-and-wait-review
---
- assertVisible:
    id: "btn_connect"
- tapOn:
    id: "btn_connect"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_save_device"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: tap connect, wait for OnboardReview *********"
maestro --device "$UDID" test "$FLOW_DIR/02-tap-connect-and-wait-review.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -8 > "$EVIDENCE_DIR/maestro-02.log"
echo "[$(date +%H:%M:%S)] maestro 02 exit=$?"
snapshot "post-handshake-onboard-review"

# 7. Fill device name + Save Device, wait for Dashboard Signer tab.
cat > "$FLOW_DIR/03-save-device-and-start-signer.yaml" <<EOF
appId: $APP_ID
name: save-device-and-start-signer
---
- inputText:
    id: "input_device_name"
    text: "bob-rfc3339"
- tapOn:
    id: "btn_save_device"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_start_signer"
    timeout: 30000
- assertVisible:
    id: "btn_start_signer"
- assertVisible:
    text: "Signer Stopped"
- tapOn:
    id: "btn_start_signer"
- waitForAnimationToEnd
- assertVisible:
    text: "Signer Running"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: save device + start signer *********"
maestro --device "$UDID" test "$FLOW_DIR/03-save-device-and-start-signer.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03" 2>&1 | tail -8 > "$EVIDENCE_DIR/maestro-03.log"
echo "[$(date +%H:%M:%S)] maestro 03 exit=$?"
snapshot "post-start-signer-running"

# 8. Extract all event_<timestamp> IDs from the hierarchy to prove every event
# timestamp is a valid UTC RFC-3339 string. Also confirm at least one INFO event
# is present.
EVENT_IDS=$(grep -oE 'event_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.txt" 2>/dev/null | sort -u || true)
echo "[RESULT $(date +%H:%M:%S)] event_* accessibility ids (one per LogEntry.timestamp):"
echo "$EVENT_IDS" | tee "$EVIDENCE_DIR/event_ids.txt"
EVENT_COUNT=$(echo "$EVENT_IDS" | grep -c '^event_' || true)
echo "[RESULT $(date +%H:%M:%S)] unique event timestamp strings: $EVENT_COUNT"

# 9. Confirm the Signer runtime started entry has INFO level + RFC-3339 timestamp.
grep -E 'INFO[^"]*20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.txt" \
  | head -3 > "$EVIDENCE_DIR/info-event-matches.txt"
echo "[RESULT $(date +%H:%M:%S)] INFO-tagged event log rows with RFC-3339 timestamps:"
cat "$EVIDENCE_DIR/info-event-matches.txt"

# 10. Sanity: no legacy epoch-second-only timestamps should appear (a digit run
# without the YYYY-MM-DDTHH:MM:SSZ shape would be the bug we just fixed).
LEGACY=$(grep -oE 'event_[0-9]{10,}' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.txt" | sort -u || true)
echo "[RESULT $(date +%H:%M:%S)] legacy 'event_<digits>' ids (should be empty):"
echo "$LEGACY" | tee "$EVIDENCE_DIR/legacy-ids.txt"
LEGACY_COUNT=$(echo "$LEGACY" | grep -c '^event_' || true)
echo "[RESULT $(date +%H:%M:%S)] legacy timestamp count: $LEGACY_COUNT"

# Done — write a one-line summary.
echo "OK evidence captured at $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -20
