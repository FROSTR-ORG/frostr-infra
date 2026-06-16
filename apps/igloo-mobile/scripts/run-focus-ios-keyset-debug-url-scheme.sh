#!/usr/bin/env bash
# Focused validation: exercises igloo://test-create-keyset on iOS Simulator.
#
# mobile-ios-keyset-debug-url-scheme:
#   1. Cold-installs the latest debug build on RMP iPhone 15.
#   2. Launches the app with SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 so the
#      DEBUG + env-gated URL scheme testCreateKeyset path is exposed.
#   3. Issues `xcrun simctl openurl igloo://test-create-keyset?...` with
#      pre-filled parameters so validators do not need to type into the
#      simulator's UITextFields or tap SwiftUI Buttons (Maestro 2.6.0
#      cannot do this reliably on iOS 26.5).
#   4. Captures pre- and post-injection screenshots + Maestro hierarchies
#      proving the freshly-built DiagDevice dashboard renders identity
#      with the right Share/Group Pubkeys.
#   5. Runs the Maestro flow `flows/keyset-create-url-scheme-ios.yaml`
#      for stability regression (assertions on the dashboard).
#
# Evidence is written under /tmp/igloo-mobile-keyset-debug-url-scheme-evidence/
# (and propagated to apps/igloo-mobile/library/evidence/ by the orchestrator).

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"

EVIDENCE_DIR="/tmp/igloo-mobile-keyset-debug-url-scheme-evidence"
mkdir -p "$EVIDENCE_DIR"

# Use a per-run device_name so the keychain reset + fresh install produce
# a clean validation surface. Maestro's `-e DEVICE_NAME=…` syncs the
# validation env into the YAML's `env:` block so the post-injection
# assertions can target the same per-run tag.
RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="ScriptKeyset-${RUN_TAG}"
DEVICE_NAME="ScriptDevice-${RUN_TAG}"
COUNT=3
THRESHOLD=2
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
URL="igloo://test-create-keyset?group_name=${GROUP_NAME}&threshold=${THRESHOLD}&count=${COUNT}&device_name=${DEVICE_NAME}&relay=${RELAY_ENC}"

# Persist the per-run tags so the README / evidence note can cite them.
echo "${DEVICE_NAME}" > "$EVIDENCE_DIR/device_name.txt"
echo "${GROUP_NAME}"  > "$EVIDENCE_DIR/group_name.txt"

xcrun simctl bootstatus "$UDID" -b 2>&1 | tail -2 || true

xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
# Erasing the simulator's keychain guarantees the URL-scheme path creates
# a fresh profile row + Dashboard identity — without this, repeated runs
# would land on an existing profile row from a prior invocation.
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE"

# 2. Launch with the diagnostics env var so the URL-scheme handler is exposed.
#    Maestro's `launchApp.env` only injects Maestro-flow variables, so we
#    use the SIMCTL_CHILD_<NAME>=<value> xcrun simctl launch pattern (per
#    the mobile-feature-worker skill).
echo "[$(date +%H:%M:%S)] launching app with IGLOO_KEYSET_DIAGNOSTICS=1"
SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" \
    | tee "$EVIDENCE_DIR/launch.txt"

# Give SwiftUI a moment to render the hub before injecting.
sleep 4

# 3. Snapshot pre-injection: hub should be visible (no DiagDevice row).
xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/01-pre-injection-hub.png" 2>/dev/null
maestro --device "$UDID" hierarchy 2>&1 \
    > "$EVIDENCE_DIR/01-pre-injection-hierarchy.txt" || true

# 4. Open the URL scheme. The iOS shell routes the URL through
#    App.swift::onOpenURL → AppManager.testCreateKeyset → actor
#    AppAction::DiagnosticsCreateKeysetRun → emits StoreKeysetCreatedProfile
#    side effect → shell writes to Keychain → auto-dispatches
#    CreateKeysetAccepted + CreateKeysetDistributeFinish → Dashboard.
echo "[$(date +%H:%M:%S)] injecting URL: $URL"
xcrun simctl openurl "$UDID" "$URL" 2>&1 \
    | tee "$EVIDENCE_DIR/02-openurl.txt"

# 5. Wait for the wizard to reach the Dashboard. The actor's inline
#    frostr_utils::create_keyset() runs in milliseconds on the actor thread;
#    the shell's Keychain write + auto-finish dispatch happens immediately
#    after. 8 seconds is more than enough headroom under the Rust actor's
#    normal scheduling.
sleep 8

xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/03-post-injection-8s.png" 2>/dev/null
maestro --device "$UDID" hierarchy 2>&1 \
    > "$EVIDENCE_DIR/03-post-injection-hierarchy.txt" || true

# 6. Capture keyset-diagnostics OSLog events so the validator can audit the
#    URL parser → action dispatch → side-effect chain.
xcrun simctl spawn "$UDID" log show --last 1m \
    --predicate 'category == "keyset-diagnostics"' --debug --info 2>&1 \
    | tee "$EVIDENCE_DIR/04-keyset-diagnostics-oslog.txt" > /dev/null 2>&1 \
    || true

# 7. Run the Maestro focus flow's assertions on the cached state.
#    Pass DEVICE_NAME / GROUP_NAME via Maestro's `-e` so the YAML's `env:`
#    defaults are overridden by the per-run tags.
echo "[$(date +%H:%M:%S)] running Maestro flow keyset-create-url-scheme-ios"
maestro --device "$UDID" test \
    -e DEVICE_NAME="$DEVICE_NAME" \
    -e GROUP_NAME="$GROUP_NAME" \
    "$ROOT/apps/igloo-mobile/flows/keyset-create-url-scheme-ios.yaml" \
    --debug-output "$EVIDENCE_DIR/05-maestro-run" 2>&1 \
    | tee "$EVIDENCE_DIR/05-maestro-log.txt" | tail -20

# 8. Final-state pre-screen capture for evidence completeness.
xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/06-final-state.png" 2>/dev/null

# 9. Summary
echo ""
echo "[$(date +%H:%M:%S)] evidence in $EVIDENCE_DIR:"
ls -la "$EVIDENCE_DIR" | tail -20

# 10. Success check: at least one Maestro assertion should have run cleanly.
if grep -qE 'AssertVisible.*DiagDevice|allFlowsCompleted' "$EVIDENCE_DIR/05-maestro-log.txt" 2>/dev/null; then
    echo "[$(date +%H:%M:%S)] RESULT: URL-scheme validation PASSED"
else
    echo "[$(date +%H:%M:%S)] RESULT: review evidence under $EVIDENCE_DIR"
fi
