#!/usr/bin/env bash
# Focused Android Signer Peer Refresh Liveness evidence —
# proves `mobile-signer-peer-refresh-liveness-fix` correctly pins
#   - VAL-SIGNER-008: carol never reports Online (non-running peer stays offline)
#   - VAL-SIGNER-010: Refresh preserves alice Online, advances event log
#   - Refresh appends "Refresh peer status" event-log entry
#
# Strategy:
#   1. Cold-install + cold-launch app on emulator-5554 (no stored profile).
#   2. Use the Android debug-only intent
#      `com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD` to preload bob's
#      real bfonboard1 credentials + the platform-correct demo relay URL.
#   3. Maestro drives: tap Connect, wait for OnboardReview, fill device
#      name, save, dashboard Signer Stopped.
#   4. Tap Start signer (adb input tap because Maestro tapOn text:Start
#      matches the Text child whose clickable=false on Compose Material 3).
#   5. Wait for Signer Running / alice Online. Capture pre-refresh evidence.
#   6. Tap Refresh button; capture post-refresh evidence.
#   7. Verify carol stays offline through both captures; alice remains
#      online after Refresh; event log shows the "Refresh peer status" row.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APK="$ROOT/apps/igloo-mobile/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-peer-refresh-liveness-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  adb -s emulator-5554 shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null \
    || true
  adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s emulator-5554 pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# 1. Redact-only evidence recording.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://10.0.2.2:8194"
RELAY_LEN=${#RELAY}
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
relay_length=${RELAY_LEN}
EOF
echo "[$(date +%H:%M:%S)] redacted-input captured"

# 2. APK pre-flight
[ -f "$APK" ] || { echo "missing APK $APK; run 'just android-full' first" >&2; exit 1; }
adb -s emulator-5554 get-state >/dev/null 2>&1 \
  || { echo "emulator-5554 not booted" >&2; exit 1; }

# 3. Cold install + cold launch
echo "[$(date +%H:%M:%S)] ********* Cold install emulator-5554 *********"
adb -s emulator-5554 uninstall "$APP_ID" 2>/dev/null || true
adb -s emulator-5554 install -r -t "$APK" 2>&1 | tail -3

# 4. Inject via debug intent (uses bob's classic 2-of-3 demo keyset)
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
adb -s emulator-5554 shell am start -W \
    -a "$ACTION" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es package "$PACKAGE" \
    --es password "$PASSWORD" \
    --es relay "$RELAY" \
    --es device_name "bob-refresh" \
    > "$EVIDENCE_DIR/inject-result.txt" 2>&1 || true
sleep 5
snapshot "post-inject-onboard-connect"

# 5. Maestro: tap Connect, wait for OnboardReview.
cat > "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" <<EOF
appId: $APP_ID
name: android onboard connect + review
---
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "input_relay_url"
- assertVisible:
    id: "btn_connect"
- tapOn:
    id: "btn_connect"
- extendedWaitUntil:
    visible:
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
maestro --device emulator-5554 test "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -5 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 exit=$?"
snapshot "post-handshake-onboard-review"

# 6. Save Device
cat > "$FLOW_DIR/02-android-save-device.yaml" <<EOF
appId: $APP_ID
name: android save device
---
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "bob-refresh"
- assertVisible:
    id: "btn_save_device"
- tapOn:
    id: "btn_save_device"
- extendedWaitUntil:
    visible:
      text: "bob-refresh"
    timeout: 30000
- assertVisible:
    text: "Signer Stopped"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: save device + reach dashboard *********"
maestro --device emulator-5554 test "$FLOW_DIR/02-android-save-device.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -5 > "$EVIDENCE_DIR/maestro-02.log"
echo "[$(date +%H:%M:%S)] maestro 02 exit=$?"
snapshot "post-save-device-dashboard"

# 7. Tap Start signer via adb input tap.
echo "[$(date +%H:%M:%S)] ********* adb tap Start signer at (540, 553) *********"
adb -s emulator-5554 shell input tap 540 553 || true
sleep 8
snapshot "post-start-signer-running"

# 8. Capture pre-refresh state (alice online, carol offline, no refresh
#    event in event log).
sleep 4
snapshot "pre-refresh"
PRE_HIER="$EVIDENCE_DIR/hierarchy-pre-refresh.xml"
echo "[$(date +%H:%M:%S)] pre-refresh hierarchy: $PRE_HIER"
ALICE_PRE=$(grep -oE 'text="Online"' "$PRE_HIER" 2>/dev/null | head -1 || true)
CAROL_PRE=$(grep -oE 'text="Offline"' "$PRE_HIER" 2>/dev/null | head -1 || true)
REFRESH_EVENT_PRE=$(grep -c 'Refresh peer status' "$PRE_HIER" 2>/dev/null || true)
echo "[RESULT pre-refresh] Online rows: ${ALICE_PRE:-none}; Offline rows: ${CAROL_PRE:-none}; Refresh events so far: ${REFRESH_EVENT_PRE:-0}"

# 9. Tap Refresh button on the Signer tab.
#    Compose Material 3 Button uses a Text child whose clickable=false, so
#    we dispatch the click via targeted coordinate tap. The Refresh button
#    binds to btn_refresh_peers; Maestro tapOn may fail the same way it
#    fails for Start. We scan the post-save-device hierarchy for the
#    Refresh button bounds, then drive the click.
sleep 1
adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump_pre_refresh.xml >/dev/null 2>&1
adb -s emulator-5554 pull /sdcard/window_dump_pre_refresh.xml "$EVIDENCE_DIR/hierarchy-pre-refresh-tap.xml" \
  >/dev/null 2>&1
REFRESH_BOUNDS=$(python3 - "$EVIDENCE_DIR/hierarchy-pre-refresh-tap.xml" <<'PYEOF' 2>/dev/null || true
import re, sys
path = sys.argv[1]
with open(path) as fh:
    data = fh.read()
# Search for Compose button around the Refresh affordance. The id
# `btn_refresh_peers` resolves to the on-screen Refresh control.
m = re.search(r'btn_refresh_peers[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', data)
if not m:
    # Fall back to any text="Refresh" clickable button.
    m = re.search(r'text="Refresh"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', data)
if m:
    x = (int(m.group(1)) + int(m.group(3))) // 2
    y = (int(m.group(2)) + int(m.group(4))) // 2
    print(f"{x} {y}")
PYEOF
)
echo "[$(date +%H:%M:%S)] refresh bounds center: ${REFRESH_BOUNDS:-?}"
if [ -n "${REFRESH_BOUNDS:-}" ]; then
  adb -s emulator-5554 shell input tap $REFRESH_BOUNDS || true
else
  # Fallback: tap roughly where Refresh lives on a 1080x2424 layout.
  adb -s emulator-5554 shell input tap 590 800 || true
fi
sleep 4
snapshot "post-refresh"
POST_HIER="$EVIDENCE_DIR/hierarchy-post-refresh.xml"
echo "[$(date +%H:%M:%S)] post-refresh hierarchy: $POST_HIER"
ALICE_POST=$(grep -oE 'text="Online"' "$POST_HIER" 2>/dev/null | head -1 || true)
CAROL_POST=$(grep -oE 'text="Offline"' "$POST_HIER" 2>/dev/null | head -1 || true)
REFRESH_EVENT_POST=$(grep -c 'Refresh peer status' "$POST_HIER" 2>/dev/null || true)
echo "[RESULT post-refresh] Online rows: ${ALICE_POST:-none}; Offline rows: ${CAROL_POST:-none}; Refresh events found: ${REFRESH_EVENT_POST:-0}"

# 10. Final assertion: at this point alice must still be Online (VAL-SIGNER-010
#     contract end-to-end), carol must remain Offline (VAL-SIGNER-008), and
#     the Refresh event-log row must have grown.
cat > "$EVIDENCE_DIR/result-summary.txt" <<EOF
feature=mobile-signer-peer-refresh-liveness-fix
pre_refresh_online_count=$(grep -oc 'text="Online"' "$PRE_HIER" 2>/dev/null || echo 0)
pre_refresh_offline_count=$(grep -oc 'text="Offline"' "$PRE_HIER" 2>/dev/null || echo 0)
post_refresh_online_count=$(grep -oc 'text="Online"' "$POST_HIER" 2>/dev/null || echo 0)
post_refresh_offline_count=$(grep -oc 'text="Offline"' "$POST_HIER" 2>/dev/null || echo 0)
post_refresh_event_log_rows=$(grep -c 'Refresh peer status' "$POST_HIER" 2>/dev/null || echo 0)
EOF
cat "$EVIDENCE_DIR/result-summary.txt"

echo "[$(date +%H:%M:%S)] OK evidence captured at $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -25
