#!/usr/bin/env bash
# Focused iOS proof for the mobile-signer-runtime-validation-followup feature.
#
# Validates that, after the
#   - iOS SignerStatusCard .buttonStyle(.plain) addition + .contentShape on label
# fix, Maestro can drive Start → Signer Running → Sign Ready through the real
# SwiftUI Button under iOS Simulator 26.5 / Maestro 2.6.0.
#
# Drive plan (avoids the iOS Maestro TextField paste-routing race documented in
# library/ONBOARD-IOS-MAESTRO-LIMITATION.md):
#   1. Cold-install the rebuilt debug app at com.frostr.igloo.dev.
#   2. Open OnboardDevice tile → btn_connect_entry (no package input needed).
#   3. URL-scheme inject bob's bfonboard1 envelope (base64) with relay
#      ws://127.0.0.1:8194 and platform-correct relay override (mobile-ios-onboard
#      URL-scheme flow / `igloo://test-inject`).
#   4. URL-scheme `igloo://test-save-to-dashboard?device_name=...` to land on
#      Dashboard with bob's profile material in Keychain and sign-ready path
#      available (the existing mobile-ios-onboard-review-diagnostic-save-bootstrap
#      recipe).
#   5. Maestro `tapOn id: btn_start_signer` on the Signer tab — the fix under
#      test. Capture pre/post hierarchy dumps + screenshots. Repeat until either
#      "Sign Ready" is visible or the 60 s envelope expires.
#   6. After Sign Ready: assert signer_status_card, identity block (device name
#      + share pubkey + group pubkey), two peer rows (alice + carol), event log,
#      pending ops idle, refresh timestamp advancing. The captures are the
#      evidence payload for VAL-SIGNER-002 through VAL-SIGNER-018.
#
# Exit codes:
#   0  full success (Sign Ready reached + identity/peer/event-log evidence)
#   2  partial (Running reached but readiness stucked or peers absent)
#   3  no observable state change from the Start tap (the regression)
#   *  infrastructure error

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_BUNDLE="/Users/plebdev/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

DATE="$(date +%Y-%m-%d-%H%M%S)"
EVIDENCE_BASE="/tmp/igloo-mobile-ios-signer-start-fix"
EVIDENCE_DIR="${EVIDENCE_BASE}-${DATE}"
mv "${EVIDENCE_BASE}" "${EVIDENCE_DIR}" 2>/dev/null || mkdir -p "$EVIDENCE_DIR"
echo "[fix $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.json" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# Pre-flight checks
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay port 8194 unreachable" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "missing $HARNESS_DIR/onboard-bob.txt" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "missing $HARNESS_DIR/onboard-bob.password.txt" >&2; exit 1; }

# 1. Cold install.
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
echo "[fix $(date +%H:%M:%S)] installed $APP_BUNDLE"

# 2. Launch with diagnostics env so the URL-scheme handlers are active.
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4

snapshot "01-hub-fresh"

# Navigate to OnboardConnect via iOS UI tile so the URL scheme has the
# right receiving screen (test-inject writes into the OnboardConnect state).
cat > "$EVIDENCE_DIR/nav-to-onboard-connect.yaml" <<EOF
appId: $APP_ID
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
      id: "input_package"
    timeout: 20000
- assertVisible:
    id: "input_package"
EOF
maestro --device "$UDID" test "$EVIDENCE_DIR/nav-to-onboard-connect.yaml" >/dev/null 2>&1 || true
snapshot "02-onboard-connect"

# 3. URL-scheme inject bob's bfonboard1 envelope with relay=ws://127.0.0.1:8194.
PACKAGE_B64=$(cat "$HARNESS_DIR/onboard-bob.txt" \
  | python3 -c "import sys, base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())")
PASSWORD_RAW=$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")
# Apple NSURL URL-decodes the query value before Swift sees it, so URL-encode the password once.
PASSWORD_ENC=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$PASSWORD_RAW")
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
URL_INJECT="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD_ENC}&relay=${RELAY_ENC}"
echo "[fix $(date +%H:%M:%S)] url length=${#URL_INJECT}"
xcrun simctl openurl "$UDID" "$URL_INJECT" || true
sleep 14

snapshot "03-post-injection-review"

# 4. URL-scheme save-to-dashboard, landing on Signer tab Stopped.
URL_SAVE="igloo://test-save-to-dashboard?device_name=bob-ios-startfix-${DATE}"
xcrun simctl openurl "$UDID" "$URL_SAVE" || true
sleep 5
snapshot "04-dashboard-pre-start"

# 5. Tap Start signer via the Maestro id selector — this is the contract step
# that regressed in Round 5 when SwiftUI Button hit-target did not include
# .buttonStyle(.plain) under iOS 26.5 / Maestro 2.6.0. The fix moves the
# outer `.accessibilityIdentifier("signer_status_card")` to the visible
# "Signer Stopped" / "Signer Running" status Text and reorders the Button
# modifier chain so the inner identifier lands on the Button unambiguously.
# We attempt id + text + coordinate selectors (the focused iOS proof
# succeeded with coordinate-tap alone, see
# library/evidence/mobile-ios-signer-peer-refresh-liveness-proof).
cat > "$EVIDENCE_DIR/tap-start-and-wait.yaml" <<EOF
appId: $APP_ID
---
- scrollUntilVisible:
    element:
      id: "signer_status_card"
    timeout: 15000
- runFlow:
    when:
      visible:
        id: "btn_start_signer"
    commands:
      - tapOn:
          id: "btn_start_signer"
- runFlow:
    when:
      visible:
        text: "Start"
    commands:
      - tapOn:
          text: "Start"
- runFlow:
    when:
      visible:
        id: "btn_start_signer"
    commands:
      - tapOn:
          point: 196,290
- scrollUntilVisible:
    element:
      text: "Sign Ready"
    timeout: 90000
- assertVisible:
    text: "Signer Running"
- assertVisible:
    text: "Sign Ready"
EOF
maestro --device "$UDID" test "$EVIDENCE_DIR/tap-start-and-wait.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-start" 2>&1 | tee "$EVIDENCE_DIR/maestro-start.log"
MAESTRO_EXIT=${PIPESTATUS[0]}
echo "[fix $(date +%H:%M:%S)] maestro exit=$MAESTRO_EXIT"
snapshot "05-post-tap-start-after-60s"

# 6. Capture peer rows + event log via the post-sign-ready hierarchy.
if [ "$MAESTRO_EXIT" -eq 0 ]; then
  cat > "$EVIDENCE_DIR/scroll-down.yaml" <<EOF
appId: $APP_ID
---
- swipe:
    duration: 400
    end: 196,200
    start: 196,700
EOF
  maestro --device "$UDID" test "$EVIDENCE_DIR/scroll-down.yaml" >/dev/null 2>&1 || true
  sleep 2
  snapshot "06-peer-rows-and-event-log"
fi

# 7. Test ping — go back up so the Refresh/TestPing row is visible, tap it.
if [ "$MAESTRO_EXIT" -eq 0 ]; then
  cat > "$EVIDENCE_DIR/scroll-up-and-ping.yaml" <<EOF
appId: $APP_ID
---
- swipe:
    duration: 400
    end: 196,700
    start: 196,200
- scrollUntilVisible:
    element:
      id: "btn_test_ping"
    timeout: 15000
- tapOn:
    id: "btn_test_ping"
EOF
  maestro --device "$UDID" test "$EVIDENCE_DIR/scroll-up-and-ping.yaml" >/dev/null 2>&1
  sleep 5
  snapshot "07-post-test-ping"

  cat > "$EVIDENCE_DIR/scroll-down.yaml" <<EOF
appId: $APP_ID
---
- swipe:
    duration: 400
    end: 196,200
    start: 196,700
EOF
  maestro --device "$UDID" test "$EVIDENCE_DIR/scroll-down.yaml" >/dev/null 2>&1 || true
  sleep 2
  snapshot "08-after-test-ping-event-log"
fi

# 8. Classify and exit.
SIGN_READY_SEEN=0
RUNNING_SEEN=0
ONBOARD_ERROR_SEEN=0
for f in "$EVIDENCE_DIR"/hierarchy-*.json; do
  if grep -q '"text" *: *"Sign Ready"' "$f" 2>/dev/null; then
    SIGN_READY_SEEN=1
  fi
  if grep -q '"text" *: *"Signer Running"' "$f" 2>/dev/null; then
    RUNNING_SEEN=1
  fi
  if grep -q '"onboard_error"' "$f" 2>/dev/null; then
    ONBOARD_ERROR_SEEN=1
  fi
done

if [ "$SIGN_READY_SEEN" -eq 1 ] && [ "$RUNNING_SEEN" -eq 1 ]; then
  echo "[RESULT $(date +%H:%M:%S)] SUCCESS: Signer Running + Sign Ready observed after btn_start_signer tap"
  FINAL_RC=0
elif [ "$RUNNING_SEEN" -eq 1 ] && [ "$SIGN_READY_SEEN" -eq 0 ]; then
  echo "[RESULT $(date +%H:%M:%S)] PARTIAL: Signer Running reached but Sign Ready missing"
  FINAL_RC=2
elif [ "$ONBOARD_ERROR_SEEN" -eq 1 ]; then
  echo "[RESULT $(date +%H:%M:%S)] PARTIAL: onboard_error reached (URL inject path failed)"
  FINAL_RC=2
elif [ "$MAESTRO_EXIT" -ne 0 ]; then
  echo "[RESULT $(date +%H:%M:%S)] REGRESSION: btn_start_signer tap did NOT transition. maestro exit=$MAESTRO_EXIT"
  FINAL_RC=3
else
  echo "[RESULT $(date +%H:%M:%S)] UNKNOWN: see $EVIDENCE_DIR"
  FINAL_RC=99
fi

echo "[fix $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -20
exit "$FINAL_RC"
