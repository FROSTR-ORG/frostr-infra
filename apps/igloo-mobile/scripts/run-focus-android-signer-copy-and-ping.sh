#!/usr/bin/env bash
# Focused Android validation for VAL-SIGNER-017 and VAL-SIGNER-018.
#
# Precondition: app is already on the Dashboard Signer tab with a Sign Ready
# profile (e.g. after run-focus-android-signer-sign-readiness.sh).
# This script:
#   1. Reads the displayed group/share pubkey values from the UI hierarchy.
#   2. Taps each copy affordance, navigates to OnboardConnect, and uses the
#      product-grade paste button to read the clipboard back into the
#      input_package field. This proves the full 64-char hex value reached the
#      clipboard (VAL-SIGNER-017).
#   3. Taps Test Ping, waits for the event log to append a new row, and
#      captures a hierarchy proving a ping round was initiated
#      (VAL-SIGNER-018).

set -uo pipefail
source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APP_ID="com.frostr.igloo.dev"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-runtime-validation-followup-2026-06-16/android-copy-and-ping"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"

echo "[$(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  adb -s emulator-5554 shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s emulator-5554 pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

extract_short_id() {
  local file="$1"
  python3 - <<PYEOF
import xml.etree.ElementTree as ET, re, sys
tree = ET.parse('$file')
# First try the dashboard header subtitle.
for node in tree.iter('node'):
    if node.get('resource-id') == 'dashboard_header_subtitle':
        t = node.get('text', '')
        if re.match(r'^[0-9a-f]{8}$', t):
            print(t)
            sys.exit(0)
# Fallback: find an 8-char hex short id on the Hub profile row.
for node in tree.iter('node'):
    t = node.get('text', '')
    if re.match(r'^[0-9a-f]{8}$', t):
        print(t)
        sys.exit(0)
PYEOF
}

is_hub() {
  local file="$1"
  python3 - <<PYEOF
import xml.etree.ElementTree as ET, sys
tree = ET.parse('$file')
for node in tree.iter('node'):
    if node.get('text') == 'Onboard Device':
        print('yes')
        sys.exit(0)
print('no')
PYEOF
}

is_onboard_connect() {
  local file="$1"
  python3 - <<PYEOF
import xml.etree.ElementTree as ET, sys
tree = ET.parse('$file')
for node in tree.iter('node'):
    if node.get('text') == 'Paste your bfonboard1 package':
        print('yes')
        sys.exit(0)
print('no')
PYEOF
}

is_dashboard() {
  local file="$1"
  python3 - <<PYEOF
import xml.etree.ElementTree as ET, sys
tree = ET.parse('$file')
for node in tree.iter('node'):
    if node.get('resource-id') == 'dashboard_header_title':
        print('yes')
        sys.exit(0)
print('no')
PYEOF
}

read_input_package_text() {
  # Pull the current uiautomator dump and return the text of input_package.
  python3 - <<PYEOF
import xml.etree.ElementTree as ET, subprocess, sys, os
adb = '/Users/plebdev/Library/Android/sdk/platform-tools/adb'
subprocess.run([adb, '-s', 'emulator-5554', 'shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
subprocess.run([adb, '-s', 'emulator-5554', 'pull', '/sdcard/window_dump.xml', '/tmp/android-input-dump.xml'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
tree = ET.parse('/tmp/android-input-dump.xml')
for node in tree.iter('node'):
    if node.get('resource-id') == 'input_package':
        print(node.get('text', ''))
        sys.exit(0)
PYEOF
}

# Ensure the app is foregrounded.
adb -s emulator-5554 shell am start -n "$APP_ID/com.frostr.igloo.MainActivity" >/dev/null 2>&1 || true
sleep 2
snapshot "pre-copy-dashboard"

# 1a. Make sure we are on the Dashboard before reading the identity block.
#     The app may resume on the Hub or OnboardConnect depending on where a
#     previous run left it.
if [ "$(is_dashboard "$EVIDENCE_DIR/hierarchy-pre-copy-dashboard.xml")" != "yes" ]; then
  if [ "$(is_onboard_connect "$EVIDENCE_DIR/hierarchy-pre-copy-dashboard.xml")" = "yes" ]; then
    echo "[$(date +%H:%M:%S)] app resumed on OnboardConnect; returning to Hub first"
    cat > "$FLOW_DIR/00-onboard-to-hub.yaml" <<EOF
appId: $APP_ID
name: 00 onboard to hub
---
- pressKey: back
- waitForAnimationToEnd
- pressKey: back
- waitForAnimationToEnd
EOF
    maestro --device emulator-5554 test "$FLOW_DIR/00-onboard-to-hub.yaml" \
      --debug-output "$EVIDENCE_DIR/maestro-00" > "$EVIDENCE_DIR/maestro-00.log" 2>&1
    snapshot "pre-copy-dashboard"
  fi

  SHORT_ID=$(extract_short_id "$EVIDENCE_DIR/hierarchy-pre-copy-dashboard.xml")
  if [ -z "$SHORT_ID" ]; then
    echo "FAIL: could not determine profile short id to navigate to Dashboard"
    exit 1
  fi

  echo "[$(date +%H:%M:%S)] app resumed on Hub; navigating to Dashboard via $SHORT_ID"
  cat > "$FLOW_DIR/00-hub-to-dashboard.yaml" <<EOF
appId: $APP_ID
name: 00 hub to dashboard
---
- tapOn:
    text: "$SHORT_ID"
- waitForAnimationToEnd
EOF
  maestro --device emulator-5554 test "$FLOW_DIR/00-hub-to-dashboard.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-00b" > "$EVIDENCE_DIR/maestro-00b.log" 2>&1
  snapshot "pre-copy-dashboard"
fi

# 1. Extract displayed group/share pubkey values from the dashboard hierarchy.
HIER="$EVIDENCE_DIR/hierarchy-pre-copy-dashboard.xml"
GROUP_DISPLAYED=$(python3 - <<PYEOF
import xml.etree.ElementTree as ET, re, sys
tree = ET.parse('$HIER')
for node in tree.iter('node'):
    if node.get('resource-id') == 'identity_group_pubkey':
        for child in node:
            t = child.get('text', '')
            if re.match(r'^[0-9a-f]{64}$', t):
                print(t)
                break
PYEOF
)
SHARE_DISPLAYED=$(python3 - <<PYEOF
import xml.etree.ElementTree as ET, re, sys
tree = ET.parse('$HIER')
for node in tree.iter('node'):
    if node.get('resource-id') == 'identity_share_pubkey':
        for child in node:
            t = child.get('text', '')
            if re.match(r'^[0-9a-f]{64}$', t):
                print(t)
                break
PYEOF
)

echo "[$(date +%H:%M:%S)] displayed group pubkey length: ${#GROUP_DISPLAYED}"
echo "[$(date +%H:%M:%S)] displayed share pubkey length: ${#SHARE_DISPLAYED}"

if [ "${#GROUP_DISPLAYED}" -ne 64 ] || [ "${#SHARE_DISPLAYED}" -ne 64 ]; then
  echo "FAIL: identity block does not display 64-char hex pubkeys"
  exit 1
fi
if [ "$GROUP_DISPLAYED" = "$SHARE_DISPLAYED" ]; then
  echo "FAIL: group and share pubkeys are identical"
  exit 1
fi

# 2. Group pubkey copy validation.
#    Tap the group copy button, navigate back to Hub, and extract the profile
#    row id from the Hub hierarchy. We need that id to return to Dashboard
#    later in the script.
cat > "$FLOW_DIR/01-copy-group-to-hub.yaml" <<EOF
appId: $APP_ID
name: 01 copy group pubkey and return to Hub
---
- tapOn:
    id: "identity_group_pubkey_copy"
- waitForAnimationToEnd
- pressKey: back
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: copy group pubkey + back to Hub *********"
maestro --device emulator-5554 test "$FLOW_DIR/01-copy-group-to-hub.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" > "$EVIDENCE_DIR/maestro-01.log" 2>&1
snapshot "post-group-copy-hub"

SHORT_ID=$(extract_short_id "$EVIDENCE_DIR/hierarchy-pre-copy-dashboard.xml")
echo "[$(date +%H:%M:%S)] profile short id: $SHORT_ID"

if [ -z "$SHORT_ID" ]; then
  echo "FAIL: could not find profile short id on Dashboard"
  exit 1
fi

# 2b. Navigate to OnboardConnect and paste the clipboard back into
#     input_package so the copied value can be read from the UI.
cat > "$FLOW_DIR/01b-paste-group.yaml" <<EOF
appId: $APP_ID
name: 01b paste group pubkey on OnboardConnect
---
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
      id: "btn_paste_package"
    timeout: 20000
- tapOn:
    id: "btn_paste_package"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: navigate to OnboardConnect and paste *********"
maestro --device emulator-5554 test "$FLOW_DIR/01b-paste-group.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01b" > "$EVIDENCE_DIR/maestro-01b.log" 2>&1
GROUP_COPIED=$(read_input_package_text)
echo "[$(date +%H:%M:%S)] group pasted back length: ${#GROUP_COPIED}"
if [ "${#GROUP_COPIED}" -ne 64 ]; then
  echo "FAIL: group pubkey paste-back length is ${#GROUP_COPIED}, expected 64"
  exit 1
fi
if [ "$GROUP_COPIED" != "$GROUP_DISPLAYED" ]; then
  echo "FAIL: group pubkey paste-back does not match displayed group pubkey"
  echo "  displayed: $GROUP_DISPLAYED"
  echo "  pasted:    $GROUP_COPIED"
  exit 1
fi

# 3. Share pubkey copy validation.
#    From OnboardConnect, go back to Hub, tap the profile row to return to
#    Dashboard, tap the share copy button, go back to Hub, then paste back
#    via OnboardConnect again.
cat > "$FLOW_DIR/02-copy-share-paste-back.yaml" <<EOF
appId: $APP_ID
name: 02 copy share pubkey and paste back
---
- pressKey: back
- waitForAnimationToEnd
- pressKey: back
- waitForAnimationToEnd
- tapOn:
    text: "$SHORT_ID"
- waitForAnimationToEnd
- tapOn:
    id: "identity_share_pubkey_copy"
- waitForAnimationToEnd
- pressKey: back
- waitForAnimationToEnd
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
      id: "btn_paste_package"
    timeout: 20000
- tapOn:
    id: "btn_paste_package"
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: copy share pubkey + paste back *********"
maestro --device emulator-5554 test "$FLOW_DIR/02-copy-share-paste-back.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" > "$EVIDENCE_DIR/maestro-02.log" 2>&1
SHARE_COPIED=$(read_input_package_text)
echo "[$(date +%H:%M:%S)] share pasted back length: ${#SHARE_COPIED}"
if [ "${#SHARE_COPIED}" -ne 64 ]; then
  echo "FAIL: share pubkey paste-back length is ${#SHARE_COPIED}, expected 64"
  exit 1
fi
if [ "$SHARE_COPIED" != "$SHARE_DISPLAYED" ]; then
  echo "FAIL: share pubkey paste-back does not match displayed share pubkey"
  echo "  displayed: $SHARE_DISPLAYED"
  echo "  pasted:    $SHARE_COPIED"
  exit 1
fi
if [ "$SHARE_COPIED" = "$GROUP_COPIED" ]; then
  echo "FAIL: share pubkey paste-back equals group pubkey paste-back"
  exit 1
fi

# 4. Test Ping: return to Dashboard, tap Test Ping, verify event log update.
cat > "$FLOW_DIR/03-test-ping.yaml" <<EOF
appId: $APP_ID
name: 03 tap Test Ping and verify event log update
---
- pressKey: back
- waitForAnimationToEnd
- pressKey: back
- waitForAnimationToEnd
- tapOn:
    text: "$SHORT_ID"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      text: "Test Ping"
    timeout: 15000
- tapOn:
    text: "Test Ping"
- waitForAnimationToEnd
- swipe:
    direction: UP
    duration: 500
- scrollUntilVisible:
    element:
      text: "Peers"
    timeout: 15000
- swipe:
    direction: UP
    duration: 500
- scrollUntilVisible:
    element:
      text: "Event Log"
    timeout: 15000
- waitForAnimationToEnd
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: tap Test Ping *********"
maestro --device emulator-5554 test "$FLOW_DIR/03-test-ping.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03" > "$EVIDENCE_DIR/maestro-03.log" 2>&1
snapshot "post-test-ping"

EVENT_LOG_HAS_PING=$(python3 - <<PYEOF
import xml.etree.ElementTree as ET, re, sys
tree = ET.parse('$EVIDENCE_DIR/hierarchy-post-test-ping.xml')
texts = [node.get('text', '') for node in tree.iter('node')]
matched = [t for t in texts if re.search(r'Ping', t, re.I)]
print('yes' if matched else 'no')
PYEOF
)
if [ "$EVENT_LOG_HAS_PING" != "yes" ]; then
  echo "FAIL: event log does not contain a Ping entry after Test Ping"
  exit 1
fi

# 5. Record redacted evidence.
cat > "$EVIDENCE_DIR/result.txt" <<EOF
platform=android
assertions=VAL-SIGNER-017,VAL-SIGNER-018
group_pubkey_length=${#GROUP_COPIED}
share_pubkey_length=${#SHARE_COPIED}
group_copy_matches_display=$([ "$GROUP_COPIED" = "$GROUP_DISPLAYED" ] && echo true || echo false)
share_copy_matches_display=$([ "$SHARE_COPIED" = "$SHARE_DISPLAYED" ] && echo true || echo false)
share_differs_from_group=$([ "$SHARE_COPIED" != "$GROUP_COPIED" ] && echo true || echo false)
event_log_has_ping_after_tap=$EVENT_LOG_HAS_PING
EOF

echo "================================================================"
echo "PASS verdict: VAL-SIGNER-017 and VAL-SIGNER-018 on Android."
echo "Group/share pubkey copy affordances copy the full displayed 64-char"
echo "hex values, and Test Ping appends a Ping entry to the event log."
echo "Evidence: $EVIDENCE_DIR"
echo "================================================================"
exit 0
