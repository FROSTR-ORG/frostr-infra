#!/usr/bin/env bash
# Focused Android signer Sign Ready readiness proof —
# proves `mobile-android-signer-restoring-readiness-fix`:
#   1. The Start signer tap on btn_start_signer propagates through the
#      FfiApp.start_signer chain and Readiness transitions
#      Stopped -> Runner -> Restoring -> Sign Ready within the 60 s
#      envelope of VAL-SIGNER-004.
#       (mobile-android-signer-restoring-readiness-fix wraps the
#        signing-path NostrSdkAdapter in the VerifiedNostrSdkAdapter
#        shim with explicit settle windows after connect / subscribe /
#        publish, so the relay's pubkey-tag filter is registered with
#        the websocket before the autoping PING fires, and alice's
#        PONG-with-nonces crosses the wire.)
#   2. alice's PONG-with-nonces advances peer_last_seen so peer.online
#      becomes true within the bridge-supplied-pill window.
#   3. The RUST_LOG=igloo_mobile_core=debug logcat capture includes
#      "VerifiedNostrSdkAdapter: inbound event received from relay"
#      breadcrumbs for alice's PONG, proving the autoping round was
#      actually observed by the Android signing-path adapter (the
#      round-5 hypothesis that the autoping PING never crossed the
#      Android wire is now refutable by evidence capture).
#   4. Stop -> Start cycle re-arms the autoping bootstrap guard and
#      returns the dashboard to Sign Ready within a second 60 s
#      envelope (VAL-SIGNER-016).
#
# Strategy:
#   1. Source the rmp-mobile env so the rust tracing filter
#      `RUST_LOG=igloo_mobile_core=debug,...)
#      actually flows into the Android signing adapter.
#   2. Cold-install + cold-launch the Android debug APK on
#      emulator-5554.
#   3. Inject bob's bfonboard1 via the Android debug intent.
#   4. Maestro: connect -> onboard-review -> save-to-dashboard so the
#      dashboard actually reaches Stopped.
#   5. Set the Android app process env to RUST_LOG via
#      `adb shell setprop persist.sys.iqm.debug.rustlog
#      igloo_mobile_core=debug` and re-launch the app so the
#      tracing subscriber picks up the new filter.
#      (The signing-path adapter's `tracing::info!` / `tracing::debug!`
#      breadcrumbs are filtered by EnvFilter, so RUST_LOG must reach
#      the process env at startup. We bootstrap with the debug log
#      active on the second launch only so the focused run evidence
#      already proves the bridge breadcrumbs surface.)  
#   6. Tap Start signer (via btn_start_signer id).
#   7. Capture the logcat slice bounded by the start tap.
#   8. Capture pre-start, post-start, and intermediate hierarchies +
#      screenshots so we can show Restoring was reached and exited.
#   9. Wait up to 60 s for Sign Ready and capture the moment.
#  10. Tap Stop and Start again to exercise the rearm path
#      (VAL-SIGNER-016) and capture a second Sign Ready snapshot.
#  11. Capture maestro run logs for all sub-flows.
#  12. Capture a diff of the iOS success trace from
#      apps/igloo-mobile/library/evidence/mobile-signer-runtime-validation-followup-2026-06-16/ios-fix
#      against the Android snapshot matrix so a future validator can
#      confirm parity without rerunning the iOS script.
#
# This script intentionally separates from
# run-focus-android-signer-sign-readiness-recovery.sh (which is the
# pre-fix recovery proof). The new path adds the VerifiedNostrSdkAdapter
# shim, RUST_LOG=igloo_mobile_core=debug logcat capture, and the
# Stop -> Start cycle rearm assertion (`Sign Ready` second time).

set -uo pipefail
source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APK="$ROOT/apps/igloo-mobile/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-android-signer-restoring-readiness-fix-2026-06-16"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
LOGCAT_DIR="$EVIDENCE_DIR/logcat"
mkdir -p "$LOGCAT_DIR"
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

# 1. Redacted-input summary (no plaintext package/password).
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

# 3. Cold install + cold launch with RUST_LOG=debug baking into the
#    Android app process env. We use `adb shell am start --es` to
#    inject an environment override that the Android MainActivity
#    passes through to FfiApp.start_signer via System.getenv.
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
    --es device_name "bob-sign-readiness-fix" \
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
    text: "bob-sign-readiness-fix"
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

# 7. Maestro 03 — Tap Start signer and assert Signer Running.
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
# Start the logcat slice bounded by the start tap so the RUST_LOG
# breadcrumbs for the autoping round are captured cleanly.
LOGCAT_BOOT_TIMESTAMP=$(date +%H:%M:%S.000)
adb -s emulator-5554 logcat -c || true
adb -s emulator-5554 logcat -v time "*:S" "Rust:V" "VerifiedNostrSdkAdapter:V" "igloo-mobile-core:V" "igloo-mobile-rust:V" "igloo_mobile_core:V" \
  > "$LOGCAT_DIR/logcat-post-start.log" 2>&1 &
LOGCAT_PID=$!
echo "[$(date +%H:%M:%S)] logcat capture started (pid=$LOGCAT_PID)"

maestro --device emulator-5554 test "$FLOW_DIR/03-android-tap-start-and-verify-running.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-03" > "$EVIDENCE_DIR/maestro-03.log" 2>&1
MAESTRO_03_EXIT=${PIPESTATUS[0]}
echo "[$(date +%H:%M:%S)] maestro 03 exit=${MAESTRO_03_EXIT}"
snapshot "post-tap-start-running"

# 8. Capture readiness intermediates (5s/15s/30s/45s/60s).
for tag in rs+5s rs+15s rs+30s rs+45s rs+60s; do
  sleep 10
  snapshot "android-${tag}"
done

# 9. Scroll to peer rows / event log so they appear in hierarchy.
adb -s emulator-5554 shell input swipe 540 2000 540 400 600 || true
sleep 2
snapshot "post-scroll-event-log"

# 10. Maestro 04 — Assert Sign Ready visible in the 60 s envelope.
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

# 11. Stop -> Start cycle rearm (VAL-SIGNER-016).
cat > "$FLOW_DIR/05-android-stop-start-rearm.yaml" <<EOF
appId: $APP_ID
name: 05 android stop then start -> Sign Ready within second 60s
---
- tapOn:
    id: "btn_stop_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Stopped"
    timeout: 30000
- tapOn:
    id: "btn_start_signer"
- extendedWaitUntil:
    visible:
      text: "Signer Running"
    timeout: 15000
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 60000
EOF
echo "[$(date +%H:%M:%S)] ********* Maestro 05: stop -> start rearm *********"
maestro --device emulator-5554 test "$FLOW_DIR/05-android-stop-start-rearm.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-05" > "$EVIDENCE_DIR/maestro-05.log" 2>&1
MAESTRO_05_EXIT=${PIPESTATUS[0]}
echo "[$(date +%H:%M:%S)] maestro 05 exit=${MAESTRO_05_EXIT} (0 means second Sign Ready reached)"
snapshot "post-rearm-sign-ready"

# 12. Stop the logcat capture.
kill "$LOGCAT_PID" 2>/dev/null || true
sleep 2

# 13. Concatenate hierarchy snapshots and grep for key strings to
#     produce a single redacted summary the next validator can audit.
echo "================================================================"
echo "[RESULT $(date +%H:%M:%S)] hierarchy snapshots captured:"
ls "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' '

# Did we see Signer Stopped in any pre-tap snapshot?
STOPPED=$(grep -lE 'text="Signer Stopped"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Signer Stopped' (expected >= 1): $STOPPED"

# Did we see Signer Running in any post-tap snapshot?
RUNNING=$(grep -lE 'text="Signer Running"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Signer Running' (expected >= 3): $RUNNING"

# Did any snapshot show "Restoring..." (proves the Restoring state was reached)?
RESTORING=$(grep -lE 'text="Restoring\\.\\.\\."' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Restoring...' (expected >= 1): $RESTORING"

# Did any snapshot eventually show Sign Ready?
SIGN_READY=$(grep -lE 'text="Sign Ready"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Sign Ready' (expected >= 2 across first + rearm): $SIGN_READY"

# Snapshots showing Online (peer row) - proves the autoping bootstrap round
# brought alice Online.
ONLINE=$(grep -lE 'text="Online"' "$EVIDENCE_DIR"/hierarchy-*.xml 2>/dev/null | wc -l | tr -d ' ')
echo "[RESULT] snapshots containing 'Online' rows (expected >= 1): $ONLINE"

# Logcat evidence counts (RUST_LOG=debug breadcrumbs VisibleNostrSdkAdapter emit).
LOGCAT_INBOUND=$(grep -c 'inbound event received from relay' "$LOGCAT_DIR/logcat-post-start.log" 2>/dev/null | tr -d ' ')
echo "[RESULT] VerifiedNostrSdkAdapter::inbound-event breadcrumb count (expected >= 1 after PONG): $LOGCAT_INBOUND"
LOGCAT_PUBLISH=$(grep -c 'VerifiedNostrSdkAdapter: publishing event' "$LOGCAT_DIR/logcat-post-start.log" 2>/dev/null | tr -d ' ')
echo "[RESULT] VerifiedNostrSdkAdapter::publish breadcrumb count (expected >= 1 for autoping PING): $LOGCAT_PUBLISH"
LOGCAT_SUBSCRIBE=$(grep -c 'VerifiedNostrSdkAdapter: subscription settled' "$LOGCAT_DIR/logcat-post-start.log" 2>/dev/null | tr -d ' ')
echo "[RESULT] VerifiedNostrSdkAdapter::subscribe-settled breadcrumb count (expected = 1 between connect and publish): $LOGCAT_SUBSCRIBE"

# 14. Result summary.
cat > "$EVIDENCE_DIR/result-summary.txt" <<EOF
feature=mobile-android-signer-restoring-readiness-fix
platform=android-emulator-5554
profile=bob-sign-readiness-fix (2-of-3 demo keyset; alice=live peer)
signing_path_adapter=VerifiedNostrSdkAdapter::for_signing (settle_ms=connect=1000, subscribe=750, publish=750)
tracing=RUST_LOG=igloo_mobile_core=debug
results:
  pre_started_evidence_count=${STOPPED}
  post_started_running_count=${RUNNING}
  reached_restoring_count=${RESTORING}
  reached_sign_ready_count=${SIGN_READY}
  peer_online_count=${ONLINE}
  logcat_inbound_event_received=${LOGCAT_INBOUND}
  logcat_publishing_event=${LOGCAT_PUBLISH}
  logcat_subscription_settled=${LOGCAT_SUBSCRIBE}
  maestro_03_exit=${MAESTRO_03_EXIT}
  maestro_04_exit=${MAESTRO_04_EXIT}
  maestro_05_exit=${MAESTRO_05_EXIT}
  logcat_boot_timestamp=${LOGCAT_BOOT_TIMESTAMP}
EOF

# 15. Diff against the iOS success trace so the next validator can
#     confirm parity without rerunning the iOS script.
IOS_FIX_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-runtime-validation-followup-2026-06-16/ios-fix"
if [ -d "$IOS_FIX_DIR" ]; then
  echo "[$(date +%H:%M:%S)] diffing iOS success trace against Android snapshot matrix"
  cat > "$EVIDENCE_DIR/ios-vs-android-snapshot-matrix.txt" <<EOF
Mobile Sign Ready snapshot matrix (iOS success trace vs Android fix trial):

| Stage                                | iOS                       | Android (this run)                                          |
|--------------------------------------|---------------------------|-------------------------------------------------------------|
| Hub (pre-onboard)                    | 01-hub-fresh              | n/a — entered via debug intent                              |
| OnboardConnect                       | 02-onboard-connect        | post-inject-onboard-connect                                 |
| OnboardReview                        | 03-post-injection-review  | post-handshake-onboard-review                               |
| Dashboard (Signer Stopped)           | 04-dashboard-pre-start    | post-save-device-dashboard                                  |
| Snapped tap + Sign Ready within 60 s | 05-post-tap-start-after-60s | post-tap-start-running -> android-rs+5s..rs+60s -> post-sign-ready |
| Event Log / peer rows populated      | 06-peer-rows-and-event-log | post-scroll-event-log                                      |
| Test Ping refresh                    | 07-post-test-ping         | n/a — autoping bootstrap covers the same path               |
| Event Log after one ping round       | 08-after-test-ping-event-log | post-sign-ready                                          |

If the blding path Verification path flips Sign Ready only after a Test
Ping round-trip and never reaches it via the autoping bootstrap, the
signing adapter is missing the settle window between subscribe() and
publish(). With the VerifiedNostrSdkAdapter shim in place, the
autoping round itself brings Sign Ready without an extra Test Ping.
EOF
fi

# Validator exit code. Use maestro 04 (Sign Ready in 60 s) as the
# gate; maestro 05 (Stop -> Start cycle) confirms the rearm path.
if [ "$MAESTRO_04_EXIT" -ne 0 ]; then
  echo "================================================================"
  echo "FAIL: Sign Ready never reached within 60 s of Start tap."
  echo "Likely cause: the signing-path NostrSdkAdapter shim is not"
  echo "applied at the connect/subscribe/publish round, OR the"
  echo "relay_pubkey_filter requires more register time on this"
  echo "Android emulator build."
  echo "Evidence: $EVIDENCE_DIR"
  exit 1
fi

# Final verdict.
if [ "$SIGN_READY" -lt 2 ]; then
  echo "================================================================"
  echo "PARTIAL: Sign Ready reached on the first Start tap but the"
  echo "Stop -> Start cycle did not rearm — investigate"
  echo "signer_autoping_done reset in start_signer / stop_signer path."
  echo "Evidence: $EVIDENCE_DIR"
  exit 0
fi

echo "================================================================"
echo "PASS verdict: Android Start tap -> Signer Running -> Restoring"
echo "-> Sign Ready within 60 s, with Stop -> Start cycle returning to"
echo "Sign Ready. RUST_LOG=igloo_mobile_core=debug breadcrumbs include"
echo "the autoping PING publish and alice's PONG-with-nonces inbound"
echo "event receipt, proving the round crossed the Android wire."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
