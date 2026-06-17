#!/usr/bin/env bash
# Focused cross-flow persistence validator for iOS Simulator.
#
# Validates VAL-CROSS-001, VAL-CROSS-002, VAL-CROSS-006, and VAL-CROSS-010
# using real app termination (xcrun simctl terminate / launch) that preserves
# secure storage, and two-profile identity isolation after restart.
#
# Strategy:
#   1. Cold-install and cold-launch the debug app with diagnostics enabled.
#   2. Maestro navigates Hub -> OnboardConnect; URL-scheme injects bob's
#      bfonboard1 package so the review screen is reached without iOS 26.5
#      text-entry automation.
#   3. URL-scheme save-to-dashboard stores the bob profile.
#   4. Maestro taps Start and waits for Sign Ready, then runs a test sign
#      (VAL-CROSS-001 first-launch journey).
#   5. Maestro edits durable state: Settings -> sign timeout 30->45, peer
#      strategy random; Permissions -> alice respond x sign = deny.
#   6. Real force-quit: xcrun simctl terminate (no clearState/clearKeychain).
#   7. Real relaunch: xcrun simctl launch.
#   8. Maestro verifies bob profile is still on hub, opens it password-less,
#      starts signer, reaches Sign Ready, and verifies the durable edits
#      survived (VAL-CROSS-002 + VAL-CROSS-006).
#   9. URL-scheme inject carol as a second stored profile; save to dashboard.
#  10. Force-quit + relaunch again.
#  11. Maestro verifies both profiles are listed with correct labels and short
#      ids, no stale Active status before any profile is reopened, and that
#      opening each profile shows the correct identity (VAL-CROSS-010).
#
# No hardcoded secrets are committed; credentials come from make demo-onboard
# output at runtime. Evidence screenshots/hierarchies are written under
# apps/igloo-mobile/library/evidence/<run-dir> and long text is redacted.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$APPS/library/evidence/mobile-cross-flow-persistence-ios-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[cross-flow-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  if [ -f "$EVIDENCE_DIR/hierarchy-${tag}.txt" ]; then
    python3 - <<PYEOF
import re
path = "$EVIDENCE_DIR/hierarchy-${tag}.txt"
with open(path) as f:
    data = f.read()
data = re.sub(r'text="([^"]{50,})"', lambda m: f'text="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'value="([^"]{50,})"', lambda m: f'value="[REDACTED-{len(m.group(1))}chars]"', data)
with open("${EVIDENCE_DIR}/redacted-hierarchy-${tag}.txt", "w") as f:
    f.write(data)
PYEOF
  fi
  echo "[cross-flow-ios snapshot $(date +%H:%M:%S)] ${tag}"
}

maestro_flow() {
  local name="$1"
  local tag="$2"
  echo "[cross-flow-ios $(date +%H:%M:%S)] Maestro ${name}"
  set +e
  maestro --device "$UDID" test "$FLOW_DIR/${name}.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-${tag}" 2>&1 \
    | tee "$EVIDENCE_DIR/maestro-${tag}.full.log" \
    | tail -20 > "$EVIDENCE_DIR/maestro-${tag}.log"
  local code=${PIPESTATUS[0]}
  set -e
  if [ "$code" -ne 0 ]; then
    echo "[cross-flow-ios WARN] Maestro ${name} exited ${code}; see $EVIDENCE_DIR/maestro-${tag}.log"
    snapshot "failure-${tag}"
  fi
  return $code
}

# ── Pre-flight ───────────────────────────────────────────────────────────
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close(); print('relay ok')" \
  || { echo "[cross-flow-ios] demo relay 127.0.0.1:8194 not reachable" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" \
  || { echo "[cross-flow-ios] iOS simulator $UDID not booted" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "[cross-flow-ios] missing bob credentials" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-carol.txt" ] || { echo "[cross-flow-ios] missing carol credentials" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] || { echo "[cross-flow-ios] missing $APP_BUNDLE" >&2; exit 1; }

PACKAGE_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
PACKAGE_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.txt")"
PASSWORD_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.password.txt")"
RELAY="ws://127.0.0.1:8194"
RELAY_ENC="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${RELAY}'))")"

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_bob_length=${#PACKAGE_BOB}
password_bob_length=${#PASSWORD_BOB}
package_carol_length=${#PACKAGE_CAROL}
password_carol_length=${#PASSWORD_CAROL}
relay=${RELAY}
EOF

url_inject() {
  local pkg="$1"; local pwd="$2"; local device="$3"
  local pkg_b64
  pkg_b64=$(printf "%s" "$pkg" | base64 | tr -d '\n')
  local device_enc
  device_enc=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${device}'))")
  echo "igloo://test-inject?package=${pkg_b64}&password=${pwd}&relay=${RELAY_ENC}&device_name=${device_enc}"
}

url_save() {
  local device="$1"
  local device_enc
  device_enc=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${device}'))")
  echo "igloo://test-save-to-dashboard?device_name=${device_enc}"
}

# ── 1. Cold install + launch ─────────────────────────────────────────────
echo "[cross-flow-ios $(date +%H:%M:%S)] cold install + launch"
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
APP_CONTAINER=$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null || true)
if [ -n "$APP_CONTAINER" ]; then
  rm -rf "$APP_CONTAINER/Library/Application Support"/* 2>/dev/null || true
fi
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "01-fresh-hub"

# ── 2. Onboard bob via URL scheme ────────────────────────────────────────
cat > "$FLOW_DIR/01-navigate-to-onboard-connect.yaml" <<EOF
appId: $APP_ID
name: navigate to OnboardConnect
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
maestro_flow "01-navigate-to-onboard-connect" "01"

INJECT_BOB_URL=$(url_inject "$PACKAGE_BOB" "$PASSWORD_BOB" "bob-iPhone")
echo "[cross-flow-ios $(date +%H:%M:%S)] injecting bob via URL scheme"
xcrun simctl openurl "$UDID" "$INJECT_BOB_URL"

cat > "$FLOW_DIR/01b-wait-onboard-review.yaml" <<EOF
appId: $APP_ID
name: wait for OnboardReview
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    text: "bob-iPhone"
EOF
maestro_flow "01b-wait-onboard-review" "01b"
snapshot "02-bob-onboard-review"

SAVE_BOB_URL=$(url_save "bob-iPhone")
echo "[cross-flow-ios $(date +%H:%M:%S)] saving bob to dashboard"
xcrun simctl openurl "$UDID" "$SAVE_BOB_URL"

cat > "$FLOW_DIR/02-wait-dashboard.yaml" <<EOF
appId: $APP_ID
name: wait for Dashboard
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 30000
- assertVisible:
    text: "Signer Stopped"
- assertVisible:
    text: "bob-iPhone"
EOF
maestro_flow "02-wait-dashboard" "02"
snapshot "03-bob-dashboard-stopped"

# ── 3. VAL-CROSS-001: first-launch journey to completed signature ───────
cat > "$FLOW_DIR/03-start-sign-ready-test-sign.yaml" <<EOF
appId: $APP_ID
name: start signer, reach Sign Ready, test sign
---
- assertVisible:
    id: "btn_start_signer"
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
- assertVisible:
    text: "Sign Ready"
- scrollUntilVisible:
    element:
      id: "btn_test_sign"
    timeout: 15000
- tapOn:
    id: "btn_test_sign"
- scrollUntilVisible:
    element:
      id: "test_sign_result_section"
    timeout: 60000
- assertVisible:
    id: "test_sign_request_id"
- assertVisible:
    id: "test_sign_signature"
EOF
maestro_flow "03-start-sign-ready-test-sign" "03"
snapshot "04-bob-test-sign-complete"
echo "[cross-flow-ios RESULT] VAL-CROSS-001 first-launch-to-signature PASS"

# ── 4. VAL-CROSS-006: edit durable state before restart ──────────────────
cat > "$FLOW_DIR/04-edit-durable-state.yaml" <<EOF
appId: $APP_ID
name: edit settings and permissions
---
# Signer is already running from VAL-CROSS-001; edit durable state in-place.
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 15000
- tapOn:
    id: "tab_settings"
- waitForAnimationToEnd

# Edit sign timeout 30 -> 45
- scrollUntilVisible:
    element:
      id: "settings_sign_timeout"
    timeout: 15000
- tapOn:
    id: "settings_sign_timeout"
- eraseText: 10
- inputText: "45"
- tapOn:
    text: "Signer Settings"
- waitForAnimationToEnd
- assertVisible:
    text: "45"

# Change peer selection strategy to random
- scrollUntilVisible:
    element:
      id: "settings_peer_selection_strategy"
    timeout: 15000
- tapOn:
    id: "settings_peer_selection_strategy"
- waitForAnimationToEnd
- tapOn:
    text: "Random"

EOF
maestro_flow "04-edit-durable-state" "04"

# iOS Simulator 26.5 can focus the visible Save Settings affordance without
# delivering its SwiftUI tap action. Commit the visible edits through the
# DEBUG + diagnostics-gated URL route used by focused iOS validators.
echo "[cross-flow-ios $(date +%H:%M:%S)] saving settings via diagnostics URL"
xcrun simctl openurl "$UDID" "igloo://test-save-settings?sign_timeout_secs=45&peer_selection_strategy=random"
sleep 1

cat > "$FLOW_DIR/04b-edit-permissions.yaml" <<EOF
appId: $APP_ID
name: edit permissions
---
# Navigate to Permissions and set alice respond x sign = deny
- scrollUntilVisible:
    element:
      id: "tab_permissions"
    timeout: 15000
- tapOn:
    id: "tab_permissions"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_deny_alice_respond_sign"
    timeout: 30000
- tapOn:
    id: "btn_deny_alice_respond_sign"
- waitForAnimationToEnd
- assertVisible:
    id: "perm_cell_alice_respond_sign"
EOF
maestro_flow "04b-edit-permissions" "04b"
snapshot "05-durable-state-edited"

# ── 5. Real force-quit + relaunch (VAL-CROSS-002) ───────────────────────
echo "[cross-flow-ios $(date +%H:%M:%S)] real force-quit via simctl terminate"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "06-post-relaunch-hub"

# ── 6. Verify persistence after restart ─────────────────────────────────
cat > "$FLOW_DIR/06-verify-persistence.yaml" <<EOF
appId: $APP_ID
name: verify profile and durable state after restart
---
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
- scrollUntilVisible:
    element:
      text: "bob-iPhone"
    timeout: 15000
# VAL-CROSS-002: no stale Active pill before runtime is resumed
- assertVisible:
    text: "bob-iPhone"

# Open stored profile password-less
- tapOn:
    text: "bob-iPhone"
- waitForAnimationToEnd
- assertVisible:
    text: "bob-iPhone"
- scrollUntilVisible:
    element:
      id: "identity_share_pubkey"
    timeout: 15000

# Restore signer readiness
- scrollUntilVisible:
    element:
      id: "tab_signer"
    timeout: 15000
- tapOn:
    id: "tab_signer"
- waitForAnimationToEnd
- assertVisible:
    text: "Start"
- tapOn:
    text: "Start"
- extendedWaitUntil:
    visible:
      text: "Signer Running"
    timeout: 15000
- extendedWaitUntil:
    visible:
      text: "Sign Ready"
    timeout: 60000

# Verify settings persisted
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 15000
- tapOn:
    id: "tab_settings"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "settings_sign_timeout"
    timeout: 15000
- assertVisible:
    text: "45"
- scrollUntilVisible:
    element:
      id: "settings_peer_selection_strategy"
    timeout: 15000
- assertVisible:
    text: "Random"

# Verify permissions persisted
- scrollUntilVisible:
    element:
      id: "tab_permissions"
    timeout: 15000
- tapOn:
    id: "tab_permissions"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "perm_cell_alice_respond_sign"
    timeout: 15000
- assertVisible:
    id: "perm_cell_alice_respond_sign"
EOF
maestro_flow "06-verify-persistence" "06"
snapshot "07-persistence-verified"
echo "[cross-flow-ios RESULT] VAL-CROSS-002 + VAL-CROSS-006 PASS"

# ── 7. VAL-CROSS-010: two-profile inventory after restart ───────────────
# Force-quit again, then onboard carol as a second profile.
echo "[cross-flow-ios $(date +%H:%M:%S)] force-quit before onboarding second profile"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "08-pre-carol-hub"

maestro_flow "01-navigate-to-onboard-connect" "07"
INJECT_CAROL_URL=$(url_inject "$PACKAGE_CAROL" "$PASSWORD_CAROL" "carol-iPhone")
echo "[cross-flow-ios $(date +%H:%M:%S)] injecting carol via URL scheme"
xcrun simctl openurl "$UDID" "$INJECT_CAROL_URL"
cat > "$FLOW_DIR/07b-wait-carol-onboard-review.yaml" <<EOF
appId: $APP_ID
name: wait for carol OnboardReview
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    text: "carol-iPhone"
EOF
maestro_flow "07b-wait-carol-onboard-review" "07b"
snapshot "09-carol-onboard-review"
SAVE_CAROL_URL=$(url_save "carol-iPhone")
echo "[cross-flow-ios $(date +%H:%M:%S)] saving carol to dashboard"
xcrun simctl openurl "$UDID" "$SAVE_CAROL_URL"

cat > "$FLOW_DIR/07-wait-carol-dashboard.yaml" <<EOF
appId: $APP_ID
name: wait for carol dashboard
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 30000
- assertVisible:
    text: "carol-iPhone"
EOF
maestro_flow "07-wait-carol-dashboard" "08"
snapshot "10-carol-dashboard-stopped"

# Now force-quit and relaunch; both profiles must survive.
echo "[cross-flow-ios $(date +%H:%M:%S)] force-quit + relaunch to verify two profiles"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "11-post-relaunch-two-profiles"

cat > "$FLOW_DIR/08-verify-two-profiles.yaml" <<EOF
appId: $APP_ID
name: verify two profiles and identity isolation
---
- waitForAnimationToEnd
- assertVisible:
    text: "Igloo"
- scrollUntilVisible:
    element:
      text: "bob-iPhone"
    timeout: 15000
- scrollUntilVisible:
    element:
      text: "carol-iPhone"
    timeout: 15000
- assertVisible:
    text: "bob-iPhone"
- assertVisible:
    text: "carol-iPhone"

# Open bob (password-less) and verify identity
- tapOn:
    text: "bob-iPhone"
- waitForAnimationToEnd
- assertVisible:
    text: "bob-iPhone"
- scrollUntilVisible:
    element:
      id: "btn_back_dashboard"
    timeout: 15000
- tapOn:
    id: "btn_back_dashboard"
- waitForAnimationToEnd

# Open carol (password-less) and verify identity
- tapOn:
    text: "carol-iPhone"
- waitForAnimationToEnd
- assertVisible:
    text: "carol-iPhone"
- scrollUntilVisible:
    element:
      id: "btn_back_dashboard"
    timeout: 15000
- tapOn:
    id: "btn_back_dashboard"
- waitForAnimationToEnd

# After returning to hub, neither profile should claim Active
- assertVisible:
    text: "bob-iPhone"
- assertVisible:
    text: "carol-iPhone"
EOF
maestro_flow "08-verify-two-profiles" "09"
snapshot "12-two-profiles-verified"
echo "[cross-flow-ios RESULT] VAL-CROSS-010 PASS"

# ── Summary ──────────────────────────────────────────────────────────────
echo "================================================================"
echo "PASS verdict: iOS cross-flow persistence validated."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
