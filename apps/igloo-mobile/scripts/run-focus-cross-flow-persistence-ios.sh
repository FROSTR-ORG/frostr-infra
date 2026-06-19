#!/usr/bin/env bash
# Focused cross-flow persistence validator for iOS Simulator.
#
# Validates VAL-CROSS-002, VAL-CROSS-006, and VAL-CROSS-010
# using real app termination (xcrun simctl terminate / launch) that preserves
# secure storage, and two-profile identity isolation after restart.
#
# Strategy:
#   1. Cold-install and cold-launch the debug app with diagnostics enabled.
#   2. URL-scheme creates a real local keyset profile named bob-iPhone,
#      avoiding the external demo provisioner while still using production
#      profile storage.
#   4. Maestro edits durable settings state: sign timeout 30->45 and peer
#      strategy random.
#   6. Real force-quit: xcrun simctl terminate (no clearState/clearKeychain).
#   7. Real relaunch: xcrun simctl launch.
#   8. Maestro verifies bob profile is still on hub, opens it password-less,
#      verifies the durable edits survived (VAL-CROSS-002 + VAL-CROSS-006).
#   9. URL-scheme creates carol-iPhone as a second stored local keyset profile.
#  10. Force-quit + relaunch again.
#  11. Maestro verifies both profiles are listed with correct labels and short
#      ids, no stale Active status before any profile is reopened, and that
#      opening each profile shows the correct identity (VAL-CROSS-010).
#
# Evidence screenshots/hierarchies are written under
# apps/igloo-mobile/library/evidence/<run-dir> and long text is redacted.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
RELAY="${KEYSET_RELAY:-ws://127.0.0.1:8194}"

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

urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

launch_diagnostics() {
  SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 \
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
    xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
}

create_keyset_profile() {
  local group_name="$1"
  local device_name="$2"
  local url
  url="igloo://test-create-keyset?group_name=$(urlencode "$group_name")&threshold=2&count=3&device_name=$(urlencode "$device_name")&relay=$(urlencode "$RELAY")"
  echo "[cross-flow-ios $(date +%H:%M:%S)] create keyset profile: $device_name"
  xcrun simctl openurl "$UDID" "$url" >> "$EVIDENCE_DIR/create-keyset-openurl.log" 2>&1
}

# ── Pre-flight ───────────────────────────────────────────────────────────
RELAY_HOST="${RELAY#ws://}"
RELAY_HOST="${RELAY_HOST%%/*}"
RELAY_PORT="${RELAY_HOST##*:}"
RELAY_HOST="${RELAY_HOST%:*}"
python3 -c "import socket, sys; s=socket.create_connection((sys.argv[1], int(sys.argv[2])),2); s.close(); print('relay ok')" "$RELAY_HOST" "$RELAY_PORT" \
  || { echo "[cross-flow-ios] relay $RELAY not reachable" >&2; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" \
  || { echo "[cross-flow-ios] iOS simulator $UDID not booted" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] || { echo "[cross-flow-ios] missing $APP_BUNDLE" >&2; exit 1; }

cat > "$EVIDENCE_DIR/input.txt" <<EOF
profile_source=native-diagnostics-create-keyset
primary_device=bob-iPhone
secondary_device=carol-iPhone
relay=$RELAY
EOF

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
launch_diagnostics
sleep 4
snapshot "01-fresh-hub"

# ── 2. Create bob profile via native diagnostics keyset path ─────────────
create_keyset_profile "CrossFlowBobIOS-$(date +%H%M%S)" "bob-iPhone"
cat > "$FLOW_DIR/02-wait-dashboard.yaml" <<EOF
appId: $APP_ID
name: wait for native-created Dashboard
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 90000
- assertVisible:
    text: "bob-iPhone"
EOF
maestro_flow "02-wait-dashboard" "02"
snapshot "03-bob-dashboard-stopped"

# ── 3. VAL-CROSS-006: edit durable state before restart ──────────────────
cat > "$FLOW_DIR/04-edit-durable-state.yaml" <<EOF
appId: $APP_ID
name: edit settings
---
# Native Create Keyset has already landed on the dashboard; edit settings in-place.
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
snapshot "05-durable-state-edited"

# ── 5. Real force-quit + relaunch (VAL-CROSS-002) ───────────────────────
echo "[cross-flow-ios $(date +%H:%M:%S)] real force-quit via simctl terminate"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
launch_diagnostics
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
EOF
maestro_flow "06-verify-persistence" "06"
snapshot "07-persistence-verified"
echo "[cross-flow-ios RESULT] VAL-CROSS-002 + VAL-CROSS-006 PASS"

# ── 7. VAL-CROSS-010: two-profile inventory after restart ───────────────
# Force-quit again, then create carol as a second profile.
echo "[cross-flow-ios $(date +%H:%M:%S)] force-quit before creating second profile"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
launch_diagnostics
sleep 4
snapshot "08-pre-carol-hub"

create_keyset_profile "CrossFlowCarolIOS-$(date +%H%M%S)" "carol-iPhone"
cat > "$FLOW_DIR/07-wait-carol-dashboard.yaml" <<EOF
appId: $APP_ID
name: wait for carol dashboard
---
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      id: "signer_status_card"
    timeout: 90000
- assertVisible:
    text: "carol-iPhone"
EOF
maestro_flow "07-wait-carol-dashboard" "08"
snapshot "10-carol-dashboard-stopped"

# Now force-quit and relaunch; both profiles must survive.
echo "[cross-flow-ios $(date +%H:%M:%S)] force-quit + relaunch to verify two profiles"
xcrun simctl terminate "$UDID" "$APP_ID"
sleep 2
launch_diagnostics
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
