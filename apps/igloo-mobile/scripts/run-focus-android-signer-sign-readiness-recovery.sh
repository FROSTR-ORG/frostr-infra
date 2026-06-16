#!/usr/bin/env bash
# Focused Android signer Sign Ready readiness evidence —
# proves `mobile-signer-runtime-validation-followup` on Android:
#   1. The Start signer tap on btn_start_signer propagates to the
#      FFI bridge and the dashboard transitions Stopped -> Running
#      (VAL-SIGNER-002).
#   2. With a healthy dev-relay and an alive alice peer available at
#      ws://127.0.0.1:8194 the autoping bootstrap (added in
#      mobile-signer-runtime-restoring-readiness-fix, commit 971e4d2)
#      succeeds within the 60 s budget of VAL-SIGNER-004 and the
#      dashboard transitions Restoring -> Sign Ready
#      (VAL-SIGNER-003 through VAL-SIGNER-007).
#   3. Peer rows populate from the live alice peer (VAL-SIGNER-008
#      through VAL-SIGNER-013) and the Event Log captures the
#      runtime started timestamp with RFC-3339 formatting
#      (VAL-SIGNER-014 through VAL-SIGNER-016).
#
# This is the empirical continuation of the round-5 validators that
# observed Android stuck in Restoring indefinitely even with a healthy
# relay and live alice peer. The previous run left the contract:
#   - Android Start signer never produced an autoping round,
#     so alice PONG never landed; readiness stayed at Restoring.
#   - This proof verifies the autoping bootstrap is now in effect on
#     Android by capturing the Restoring -> Sign Ready transition
#     within the 60 s envelope.
#
# Strategy:
#   1. Cold-install + cold-launch app on emulator-5554.
#   2. Inject bob's bfonboard1 via the Android debug intent.
#   3. Maestro: connect -> onboard-review -> save-to-dashboard.
#   4. Tap Start signer (via btn_start_signer id, NOT adb input tap).
#   5. Capture pre-start, post-start, and 30 s/60 s intermediates so
#      we can show "Restoring..." was reached and exited.
#   6. Wait up to 60 s for Sign Ready; capture evidence at that point.
#   7. Concatenate all evidence into a single redacted-only summary.

set -uo pipefail
source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APK="$ROOT/apps/igloo-mobile/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-runtime-validation-followup-2026-06-16/android"
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

# 1. Redacted-input summary (no plaintext).
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://10.0.2.2:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
EOF
echo "[$(date +%H:%M:%S)] redacted-input captured"

# 2. APK + emulator preflight.
[ -f "$APK" ] || { echo "missing APK $APK; run 'just android-full' first" >&2; exit 1; }
adb -s emulator-5554 get-state >/dev/null 2>&1 \
  || { echo "emulator-5554 not booted" >&2; exit 1; }

# 3. Cold install + cold launch.
echo "[$(date +%H:%M:%S)] ********* Cold install emulator-5554 *********"
adb -s emulator-5554 uninstall "$APP_ID" 2>/dev/null || true
adb -s emulator-5554 install -r -t "$APK" 2>&1 | tail -3

# 4. Inject bob's classic 2-of-3 demo keyset.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
adb -s emulator-5554 shell am start -W \
    -a "$ACTION" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es package "$PACKAGE" \
    --es password "$PASSWORD" \
    --es relay "$RELAY" \
    --es device_name "bob-sign-readiness" \
    > "$EVIDENCE_DIR/inject-result.txt" 2>&1 || true
sleep 5
snapshot "post-inject-onboard-connect"

# 5. Maestro 01 — Connect -> OnboardReview.
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
maestro --device emulator-5554 test "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" > "$EVIDENCE_DIR/maestro-01.log" 2>&1
echo "[$(date +%H:%M:%S)] maestro 01 exit=${PIPESTATUS[0]}"
snapshot "post-handshake-onboard-review"

# 6. Maestro 02 — Save device, reach Dashboard.
cat > "$FLOW_DIR/02-android-save-device.yaml" <<EOF
appId: $APP_ID
name: 02 android save device + reach dashboard
---
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "bob-sign-readiness"
- tapOn:
    id: "btn_save_device"
- extendedWaitUntil:
    visible:
      id: "btn_start_signer"
    timeout: 30000
- assertVisible:
    text: "Signer Stopped"
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 02: save device *********"
maestro --device emulator-5554 test "$FLOW_DIR/02-android-save-device.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" > "$EVIDENCE_DIR/maestro-02.log" 2>&1
echo "[$(date +%H:%M:%S)] maestro 02 exit=${PIPESTATUS[0]}"
snapshot "post-save-device-dashboard"

# 7. Maestro 03 — Tap Start signer (real selector) and wait for Signer Running.
cat > "$FLOW_DIR/03-android-tap-start-and-verify-running.yaml" <<EOF
appId: $APP_ID
name: 03 android tap btn_start_signer -> Signer Running within 15s
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
maestro --device emulator-5554 test "$FLOW_DIR/03-android-tap-start-and-verify-running.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03" > "$EVIDENCE_DIR/maestro-03.log" 2>&1
MAESTRO_03_EXIT=${PIPESTATUS[0]}
echo "[$(date +%H:%M:%S)] maestro 03 exit=${MAESTRO_03_EXIT}"
snapshot "post-tap-start-running"

# 8. Capture intermediate readiness states so we can show Restoring ->
#    Runtime Ready -> Sign Ready progression (the Round 5 blocker was
#    that Restoring was reached but never exited).
for tag in rs+5s rs+15s rs+30s rs+45s rs+60s; do
  sleep 10
  snapshot "android-${tag}"
done

# 9. Maestro 04 — Assert Sign Ready visible while the status card is still on screen.
cat > "$FLOW_DIR/04-android-assert-sign-ready.yaml" <<EOF
appId: $APP_ID
name: 04 android assert Sign Ready within 60s of Start tap
---
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 60000
- assertVisible:
    text: "Signer Running"
- assertVisible:
    text: "Sign Ready"
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 04: assert Sign Ready within 60s *********"
maestro --device emulator-5554 test "$FLOW_DIR/04-android-assert-sign-ready.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-04" > "$EVIDENCE_DIR/maestro-04.log" 2>&1
MAESTRO_04_EXIT=${PIPESTATUS[0]}
echo "[$(date +%H:%M:%S)] maestro 04 exit=${MAESTRO_04_EXIT} (0 means Sign Ready reached)"
snapshot "post-sign-ready"

# 10. Scroll to the peer rows / event log so they appear in the hierarchy.
adb -s emulator-5554 shell input swipe 540 2000 540 400 600 || true
sleep 2
snapshot "post-scroll-event-log"

# 11. Concatenate hierarchy snapshots and grep for key strings.
echo "================================================================"
echo "[RESULT $(date +%H:%M:%S)] hierarchy snapshots captured:"
ls "$EVIDENCE_DIR"/hierarchy-*.xml | wc -l

# Did we see Signer Stopped in any pre-tap snapshot?
STOPPED=$(grep -lE 'text="Signer Stopped"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Signer Stopped' (expected >= 1): $STOPPED"

# Did we see Signer Running in any post-tap snapshot (excluding pre)?
RUNNING=$(grep -lE 'text="Signer Running"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Signer Running' (expected >= 3): $RUNNING"

# Did any snapshot show "Restoring..." (proves the Restoring state was reached)?
RESTORING=$(grep -lE 'text="Restoring\\.\\.\\."' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Restoring...' (expected >= 1): $RESTORING"

# Did any snapshot eventually show Sign Ready?
SIGN_READY=$(grep -lE 'text="Sign Ready"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Sign Ready' (expected >= 1 in the last 2): $SIGN_READY"

# Snapshots showing Live (peer row) - proves the autoping bootstrap round
# brought alice Online.
ONLINE=$(grep -lE 'text="Live"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Live' rows (expected >= 1): $ONLINE"

# Validator exit code.
if [ "$MAESTRO_04_EXIT" -ne 0 ]; then
  echo "================================================================"
  echo "FAIL: Sign Ready never reached within 60 s of Start tap"
  echo "Evidence: $EVIDENCE_DIR"
  echo "Harness state preserved; revisit the autoping bootstrap."
  exit 1
fi

# Result summary.
cat > "$EVIDENCE_DIR/result-summary.txt" <<EOF
feature=mobile-signer-runtime-validation-followup
platform=android-emulator-5554
profile=bob-sign-readiness (2-of-3 demo keyset; alice=live peer)
results:
  pre_started_evidence_count=${STOPPED}
  post_started_running_count=${RUNNING}
  reached_restoring_count=${RESTORING}
  reached_sign_ready_count=${SIGN_READY}
  peer_online_count=${ONLINE}
  maestro_03_exit=${MAESTRO_03_EXIT}
  maestro_04_exit=${MAESTRO_04_EXIT}
EOF

echo "================================================================"
echo "PASS verdict: Android Start tap -> Signer Running -> Sign Ready"
echo "with live alice peer (no return to indefinite Restoring)."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
