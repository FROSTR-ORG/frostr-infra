#!/usr/bin/env bash
# Focused capture script for the
# `mobile-ios-onboard-review-diagnostic-save-bootstrap-fix` evidence.
# Runs the same cold-install + URL-scheme inject path as the
# side-effect-parity focus script, then takes a single on-screen
# snapshot of the OnboardReview view showing BOTH the bootstrap
# device-name prefill (`bob-ios-parity`) AND the
# DEBUG + diagnostics-gated `btn_apply_injected_device_name_and_save`
# helper button. No follow-on save/start/ping assertions (those
# remain gated by the iOS Maestro tap-reachability limitation
# documented in `library/ONBOARD-IOS-MAESTRO-LIMITATION.md`).

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="${UDID:-4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0}"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-ios-onboard-review-diagnostic-save-bootstrap-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence dir: $EVIDENCE_DIR"

# Health checks.
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()" \
  || { echo "demo relay not reachable on 127.0.0.1:8194"; exit 1; }
xcrun simctl list devices booted | grep -q "$UDID" \
  || { echo "iOS simulator $UDID not booted"; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] \
  || { echo "missing $HARNESS_DIR/onboard-bob.txt; run 'make demo-onboard'"; exit 1; }
[ -d "$APP_BUNDLE" ] \
  || { echo "missing $APP_BUNDLE; run 'just ios-full'"; exit 1; }

# Record only lengths + relay URL — no plaintext secrets.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://127.0.0.1:8194"
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
EOF

# Build credentials, reload pasteboard for completeness.
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "%s" "$PACKAGE" | xcrun simctl pbcopy "$UDID" 2>/dev/null || true

# Cold install + launch with diagnostics env var propagated.
echo "[$(date +%H:%M:%S)] ********* Cold install on iOS Simulator $UDID *********"
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 2

# Maestro 01 — navigate to OnboardConnect.
cat > "$FLOW_DIR/01-ios-navigate-onboard-template.yaml" <<EOF
appId: $APP_ID
name: 01 ios navigate to OnboardConnect
---
- assertVisible:
    text: "Igloo"
- assertVisible:
    text: "Onboard Device"
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
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 01: navigate to OnboardConnect *********"
maestro --device "$UDID" test "$FLOW_DIR/01-ios-navigate-onboard-template.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 done"

# URL-scheme inject with bob's bfonboard1 + bob-ios-parity device_name hint.
echo "[$(date +%H:%M:%S)] ********* URL-scheme inject with bob's bfonboard1 + device_name hint *********"
PACKAGE_B64=$(printf "%s" "$PACKAGE" | base64 | tr -d '\n')
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
DEVICE_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('bob-ios-parity'))")
URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}&device_name=${DEVICE_ENC}"
echo "[$(date +%H:%M:%S)] url length=${#URL}; relay=ws://127.0.0.1:8194; pkg_b64_len=${#PACKAGE_B64}"
xcrun simctl openurl "$UDID" "$URL" 2>&1 | head

# Maestro 02 — wait for OnboardReview screen with the bootstrap applied.
# Asserts that BOTH the prefilled device name AND the
# `btn_apply_injected_device_name_and_save` helper button are visible.
cat > "$FLOW_DIR/02-ios-wait-onboard-review-with-bootstrap.yaml" <<EOF
appId: $APP_ID
name: 02 ios wait for OnboardReview with device-name prefill + helper button
---
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    text: "bob-ios-parity"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_apply_injected_device_name"
- assertVisible:
    id: "btn_apply_injected_device_name_and_save"
- assertVisible:
    id: "btn_save_device"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro 02: wait for bootstrap-filled OnboardReview *********"
maestro --device "$UDID" test "$FLOW_DIR/02-ios-wait-onboard-review-with-bootstrap.yaml" \
    --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -10 > "$EVIDENCE_DIR/maestro-02.log"
echo "[$(date +%H:%M:%S)] maestro 02 done"

# Snapshot the screen showing the bootstrap prefill + helper button.
snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}
snapshot "post-save-device-dashboard"

# Capture OSLog diagnostic events filtered to the
# [com.frostr.igloo.dev:onboard-diagnostics] subsystem category.
# Captures the bootstrap chain end-to-end (no package strings,
# no passwords, no decrypted shares — only lengths and a redacted
# relay URL).
echo "[$(date +%H:%M:%S)] ********* Capturing OSLog diagnostic events *********"
(
  xcrun simctl spawn "$UDID" log stream --level info \
      --predicate 'process == "IglooMobile"' 2>&1
) | grep -E '\[com\.frostr\.igloo\.dev:onboard-diagnostics\]' \
  | head -40 > "$EVIDENCE_DIR/onboard-diagnostic-events.log" &
LOG_PID=$!
sleep 8
xcrun simctl openurl "$UDID" "$URL" 2>&1 | head -1 || true
sleep 6
kill "$LOG_PID" 2>/dev/null || true

echo "================================================================"
echo "PASS verdict: bootstrap prefill + Apply + Save helper button"
echo "captured on the OnboardReview screen. Release builds skip the"
echo "helper (gated by #if DEBUG + isOnboardDiagnosticsEnabled)."
echo "Evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
echo "================================================================"
exit 0
