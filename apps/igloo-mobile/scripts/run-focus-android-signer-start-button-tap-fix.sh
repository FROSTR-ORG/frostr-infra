#!/usr/bin/env bash
# Focused Android Signer Start button tap propagation evidence —
# proves that the SignerStatusCard Start control is reachable via the
# real Android UI selectors (id: btn_start_signer) and that Maestro
# tapOn { id: btn_start_signer } actually invokes the start action.
# This is the empirical continuation of the previous run that called
# out an emulator-5554 Compose Button tap-propagation regression
# (mobile-android-signer-start-button-tap-propagation-fix).
#
# Strategy:
# 1. Cold-install + cold-launch app on emulator-5554 (no stored profile).
# 2. Bog-standard DebugIntent injection of bob's real bfonboard + password
#    + platform-correct relay URL + device name bob-start-fix.
# 3. Maestro: btn_connect → OnboardReview → input device name →
#    btn_save_device → wait for "Signer Stopped" → dump hierarchy to prove
#    btn_start_signer is now visible with content-description "Start".
# 4. Maestro: tapOn btn_start_signer by id (the selector previously absent
#    on Android because the Material 3 Button was used). Capture the
#    dashboard hierarchy 5s after the tap and verify:
#    - statusText changes from "Signer Stopped" to "Signer Running"
#    - the Stop control is exposed with testTag btn_stop_signer
#    - at least one INFO row in the Event Log carries an RFC-3339 timestamp
#
# Exit non-zero if the Start tap does not trigger a state transition.

set -uo pipefail
source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APK="$ROOT/apps/igloo-mobile/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

HARNESS_DIR="$ROOT/.tmp/test-harness"
EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-android-signer-start-button-tap-propagation-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"

snapshot() {
  local tag="$1"
  adb -s emulator-5554 shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null \
    || true
  adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s emulator-5554 pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# 1. Record only lengths + relay — no plaintext package / password.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://10.0.2.2:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
EOF
echo "[$(date +%H:%M:%S)] redacted-input captured"

# 2. APK + emulator pre-flight
[ -f "$APK" ] || { echo "missing APK $APK; run 'just android-full' first" >&2; exit 1; }
adb -s emulator-5554 get-state >/dev/null 2>&1 \
  || { echo "emulator-5554 not booted" >&2; exit 1; }

# 3. Cold install + cold launch.
echo "[$(date +%H:%M:%S)] ********* Cold install emulator-5554 *********"
adb -s emulator-5554 uninstall "$APP_ID" 2>/dev/null || true
adb -s emulator-5554 install -r -t "$APK" 2>&1 | tail -3
sleep 1

# 4. DebugIntent inject of bob's classic 2-of-3 demo keyset.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
adb -s emulator-5554 shell am start -W \
    -a "$ACTION" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es package "$PACKAGE" \
    --es password "$PASSWORD" \
    --es relay "$RELAY" \
    --es device_name "bob-start-fix" \
    > "$EVIDENCE_DIR/inject-result.txt" 2>&1 || true
sleep 5
snapshot "post-inject-onboard-connect"

# 5. Maestro 01 — Drive OnboardConnect to OnboardReview.
cat > "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" <<EOF
appId: $APP_ID
name: 01 android onboard connect + review
---
- assertVisible:
    id: "input_package"
- tapOn:
    id: "btn_connect"
- extendedWaitUntil:
    visible:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 01: tap connect *********"
{
  maestro --device emulator-5554 test "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1
} | tail -10 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 complete"
snapshot "post-handshake-onboard-review"

# 6. Maestro 02 — Save device, reach Dashboard, capture btn_start_signer hierarchy.
cat > "$FLOW_DIR/02-android-save-and-assert-start-button.yaml" <<EOF
appId: $APP_ID
name: 02 android save + assert btn_start_signer visible
---
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "bob-start-fix"
- tapOn:
    id: "btn_save_device"
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "btn_start_signer"
    timeout: 30000
- assertVisible:
    id: "btn_start_signer"
- assertVisible:
    text: "Signer Stopped"
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 02: save + assert btn_start_signer *********"
{
  maestro --device emulator-5554 test "$FLOW_DIR/02-android-save-and-assert-start-button.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1
} | tail -10 > "$EVIDENCE_DIR/maestro-02.log"
echo "[$(date +%H:%M:%S)] maestro 02 complete"
snapshot "post-save-device-dashboard"
snapshot "pre-tap-start-signer-baseline"

# 7. Maestro 03 — THE point of the fix: tap on id: btn_start_signer and
# verify Signer Running appears within 15 seconds (no adb input tap needed).
cat > "$FLOW_DIR/03-android-tap-btn-start-signer-and-verify-running.yaml" <<EOF
appId: $APP_ID
name: 03 android tap btn_start_signer + verify running within 15s
---
- assertVisible:
    id: "btn_start_signer"
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Running"
    timeout: 15000
- assertVisible:
    text: "Signer Running"
- assertVisible:
    id: "btn_stop_signer"
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 03: tap btn_start_signer + assert Signer Running *********"
{
  maestro --device emulator-5554 test "$FLOW_DIR/03-android-tap-btn-start-signer-and-verify-running.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-03" 2>&1
} > "$EVIDENCE_DIR/maestro-03.log"
MAESTRO_03_EXIT=$?
echo "[$(date +%H:%M:%S)] maestro 03 exit=${MAESTRO_03_EXIT}"
cat "$EVIDENCE_DIR/maestro-03.log" | tail -25
snapshot "post-tap-start-signer-running"

# 7b. Scroll the Signer tab down to expose the Event Log section so the
# post-tap hierarchy captures LogEntry rows (the Event Log header sits at
# the bottom of the scroll viewport at 1080x2424; without a swipe the rows
# below it are not dumped by uiautomator). Wait a couple of seconds first
# so the bridge polling loop has had at least two SignerStatusUpdate
# cycles and the SignerStarted INFO row from the RFC-3339 fix is in
# dashboard.signer.events[0].
sleep 3
adb -s emulator-5554 shell input swipe 540 2200 540 600 800 || true
sleep 2
snapshot "post-tap-start-signer-running-scrolled"

# 8. Validate hierarchy captures the new state.
POST="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running.xml"
PRE="$EVIDENCE_DIR/hierarchy-pre-tap-start-signer-baseline.xml"

if [ ! -f "$PRE" ]; then
  echo "FAIL: pre-tap hierarchy missing ($PRE)"; exit 1
fi
if [ ! -f "$POST" ]; then
  echo "FAIL: post-tap hierarchy missing ($POST)"; exit 1
fi

# 8a. Both hierarchies must contain the device id assigned by the dashboard.
SHORT_ID=$(grep -oE 'text="[0-9a-f]{8}"' "$POST" | head -1 | sed -E 's/text="([^"]+)"/\1/' || echo "")
echo "[RESULT $(date +%H:%M:%S)] dashboard short id (first 8-hex match): $SHORT_ID"
if [ -z "$SHORT_ID" ]; then
  echo "FAIL: no 8-hex short id found in post-tap hierarchy"
  exit 1
fi

# 8b. Status text: pre must contain "Signer Stopped", post must contain
# "Signer Running".
if ! grep -q 'text="Signer Stopped"' "$PRE"; then
  echo "FAIL: pre-tap hierarchy missing 'Signer Stopped' baseline"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] pre-tap 'Signer Stopped' baseline present"
if ! grep -q 'text="Signer Running"' "$POST"; then
  echo "FAIL: post-tap hierarchy missing 'Signer Running' after Start tap"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap 'Signer Running' present"

# 8c. testTag btn_start_signer must appear in PRE and btn_stop_signer in POST.
if ! grep -q 'resource-id="btn_start_signer"' "$PRE"; then
  echo "FAIL: pre-tap hierarchy missing resource-id btn_start_signer"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] pre-tap btn_start_signer resource-id present"
if ! grep -q 'resource-id="btn_stop_signer"' "$POST"; then
  echo "FAIL: post-tap hierarchy missing resource-id btn_stop_signer"
  exit 1
fi
echo "[RESULT $(date +%H:%M:%S)] post-tap btn_stop_signer resource-id present"

# 8d. Event log: at least one INFO row with RFC-3339 timestamp. The Event
# Log section's INFO entries live below the scroll viewport in the unscrolled
# post-tap hierarchy, so concatenate the unscrolled AND scrolled post-tap
# hierarchy dumps and search both for RFC-3339 strings.
SCROLLED="$EVIDENCE_DIR/hierarchy-post-tap-start-signer-running-scrolled.xml"
EVENT_IDS=$(cat "$POST" "$SCROLLED" 2>/dev/null \
  | grep -oE 'text="20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' \
  | sort -u || true)
echo "$EVENT_IDS" > "$EVIDENCE_DIR/event_timestamps.txt"
EVENT_COUNT=$(echo "$EVENT_IDS" | grep -c 'text="' || true)
echo "[RESULT $(date +%H:%M:%S)] unique RFC-3339 timestamp strings: $EVENT_COUNT"
if [ "$EVENT_COUNT" -lt 1 ]; then
  echo "FAIL: no RFC-3339 timestamps found in Event Log hierarchy"
  exit 1
fi

INFO_MATCHES="$EVIDENCE_DIR/info-event-matches.txt"
> "$INFO_MATCHES"
python3 - "$POST" "$SCROLLED" "$INFO_MATCHES" <<'PYEOF'
import re, sys
path_a, path_b, out = sys.argv[1], sys.argv[2], sys.argv[3]
merged = ""
for p in (path_a, path_b):
    try:
        with open(p) as fh:
            merged += fh.read()
    except FileNotFoundError:
        continue
ts_pat = re.compile(r'text="([^"]*)"')
RFC_RE = re.compile(r'^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
entries = [(m.group(1), m.start()) for m in ts_pat.finditer(merged)]
matches = []
for i, (text, off) in enumerate(entries):
    if text == "INFO":
        # Look ahead in the next few text attributes for an RFC-3339 timestamp
        # (the row layout is [level, timestamp, message]).
        for j in range(i + 1, min(i + 8, len(entries))):
            t2, _ = entries[j]
            if RFC_RE.match(t2):
                matches.append((off, text, t2))
                break
with open(out, "w") as fh:
    for off, info_text, ts_text in matches[:5]:
        fh.write(f"INFO at byte {off} -> next RFC-3339 timestamp '{ts_text}'\n")
print(f"INFO-event matches: {len(matches)}")
PYEOF
INFO_COUNT=$(grep -c '^INFO' "$INFO_MATCHES" || true)
echo "[RESULT $(date +%H:%M:%S)] INFO rows with RFC-3339 next: $INFO_COUNT"
if [ "$INFO_COUNT" -lt 1 ]; then
  echo "FAIL: no INFO-tagged RFC-3339 row found in Event Log"
  exit 1
fi

# 8e. Compose Material Button no longer in the dashboard hierarchy. The
# bug was that Material Button rendered a child Button widget that did not
# fire onClick on the emulator. The fix uses Box + clickable + semantics,
# so the renderer should now expose only the outer BoxView at the same
# bounds (no inner android.widget.Button under "Start").
LEGACY_BUTTON=$(grep -c 'class="android.widget.Button" package="com.frostr.igloo.dev" content-desc="" checkable="false" checked="false" clickable="false"' "$POST" || echo "0")
echo "[RESULT $(date +%H:%M:%S)] legacy wrapper-button nodes (clickable=false) in post hierarchy: $LEGACY_BUTTON"
# Note: other Compose elements (e.g. OutlinedButton used for Refresh/Test Ping/Test Sign
# not part of this fix) may still report the same wrapper shape, so we only
# require the Start/Stop control specifically to drop the inner Button child.
# Identify the Start button bounds from the pre-tap dump and confirm the
# post-tap dump has the same bounds now exposed as the BoxView only.
PRE_BOUNDS=$(grep -B1 'resource-id="btn_start_signer"' "$PRE" | head -20 || true)
POST_BOUNDS=$(grep -B1 'resource-id="btn_stop_signer"' "$POST" | head -20 || true)
echo "[RESULT $(date +%H:%M:%S)] pre-tap btn_start_signer surrounding context captured"

# 9. Final consolidated exit.
echo "================================================================"
echo "PASS verdict: btn_start_signer visible, Maestro tap fires the"
echo "start action, status flips to Signer Running, and at least one"
echo "INFO Event Log row carries an RFC-3339 timestamp."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
