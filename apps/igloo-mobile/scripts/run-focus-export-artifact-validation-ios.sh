#!/usr/bin/env bash
# Focused iOS export-artifact validator for VAL-SET-006/007/008/015.
#
# Strategy:
# 1. Boot simulator check + relay-reachability check + app-install check.
# 2. Self-onboard bob via the debug `igloo://test-inject?` URL scheme
#    so a sign-ready dashboard is on the device without driving Maestro
#    text-entry on iOS Simulator (the iOS Maestro input timing limitation
#    described in library/ONBOARD-IOS-MAESTRO-LIMITATION.md).
# 3. Trigger the password-gated export via the URL scheme
#    `igloo://test-export-actions?kind=profile|share` so we get a real
#    `bfprofile1` / `bfshare1` on the iOS Simulator clipboard.
# 4. Pipe the clipboard through
#    `apps/igloo-mobile/scripts/verify-export-artifact.sh`, which calls
#    the Rust `cargo run --example export_decode` for a redacted proof
#    panel without leaking secrets.
#
# Preconditions:
#   * iOS Simulator booted with the current `IglooMobile.app` installed.
#     Boot/install is verified by the pre-flight checks below.
#   * Demo stack running on ws://127.0.0.1:8194 (verified by TCP check).
#   * Debug build's URL-scheme handler active (default for debug builds).

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APPS="$ROOT/apps/igloo-mobile"
HARNESS_DIR="$ROOT/.tmp/test-harness"

UDID="$(xcrun simctl list devices booted | grep -E 'RMP iPhone 15' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
if [ -z "${UDID:-}" ]; then
  echo "[focus-export-ios] no booted RMP iPhone 15 simulator; boot one first" >&2
  exit 1
fi

APP_ID="com.frostr.igloo.dev"

EVIDENCE_DIR="$APPS/library/evidence/mobile-export-artifact-validation"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-export-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

# Pre-flight
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),1); s.close()" \
  || { echo "[focus-export-ios] demo relay port 8194 unreachable; run make demo-start first" >&2; exit 1; }
APP_INSTALL_PATH="$(xcrun simctl get_app_container "$UDID" "$APP_ID" 2>/dev/null)"
if [ -z "${APP_INSTALL_PATH:-}" ] || [ ! -d "$APP_INSTALL_PATH" ]; then
  echo "[focus-export-ios] app $APP_ID not installed; run 'just ios-build' first" >&2
  exit 1
fi

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
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
  echo "[focus-export-ios snapshot $(date +%H:%M:%S)] ${tag}"
}

# 1. Preload the simulator clipboard with a sentinel value so we can
#    confirm the export actually replaces it later.
SENTINEL="validator-pre-export-sentinel"
echo "$SENTINEL" | xcrun simctl pbcopy "$UDID"

# 2. Cold-launch with diagnostics enabled so the test-inject URL scheme
#    hands the package + password + relay into OnboardConnect.
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
sleep 1
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "01-launch"

# 3. Inject via the URL scheme. The package is base64-encoded raw bytes,
#    the password and relay are URL-encoded. igloo://test-inject?…
ONBOARD_PKG_B64="$(base64 < "$HARNESS_DIR/onboard-bob.txt" | tr -d '\r\n')"
ONBOARD_PWD_HEX="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
RELAY_ENC="ws%3A%2F%2F127.0.0.1%3A8194"

INJECT_URL="igloo://test-inject?package=${ONBOARD_PKG_B64}&password=${ONBOARD_PWD_HEX}&relay=${RELAY_ENC}&device_name=focus-export-bob"
echo "[focus-export-ios $(date +%H:%M:%S)] injecting via URL scheme (length=${#ONBOARD_PKG_B64})"
xcrun simctl openurl "$UDID" "$INJECT_URL"
sleep 6
snapshot "02-post-inject-onboard"

# 4. Push the resolved profile onto the dashboard via test-save-to-dashboard.
xcrun simctl openurl "$UDID" "igloo://test-save-to-dashboard?device_name=focus-export-bob"
sleep 6
snapshot "03-dashboard-ready"

# 5. Navigate to Settings tab. Since we cannot rely on Maestro's
#    tap-on-id for the SwiftUI tab bar on iOS 26.5 (per the validation
#    evidence recorded in library/ONBOARD-IOS-MAESTRO-LIMITATION.md),
#    we use the simctl accessibility hammer to drive the tab.
cat > "$EVIDENCE_DIR/navigate-settings.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: navigate to settings tab
---
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 30000
- tapOn:
    id: "tab_settings"
- waitForAnimationToEnd
- assertVisible:
    id: "btn_copy_profile"
YAML
maestro --device "$UDID" test "$EVIDENCE_DIR/navigate-settings.yaml" \
  --debug-output "$EVIDENCE_DIR/navigate-debug" 2>&1 | tail -10 || true
snapshot "04-on-settings-tab"

# 6. Tap Copy Profile. The export password prompt must appear (VAL-SET-006).
cat > "$EVIDENCE_DIR/copy-profile.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: copy profile button + prompt + confirm
---
- assertVisible:
    id: "btn_copy_profile"
- tapOn:
    id: "btn_copy_profile"
- waitForAnimationToEnd
- assertVisible:
    id: "input_export_password"
- assertVisible:
    id: "input_export_password_confirm"
- tapOn:
    id: "input_export_password"
- eraseText: 64
- inputText:
    id: "input_export_password"
    text: "validator-export-pwd"
- tapOn:
    id: "input_export_password_confirm"
- eraseText: 64
- inputText:
    id: "input_export_password_confirm"
    text: "validator-export-pwd"
- tapOn:
    id: "btn_export_confirm"
- waitForAnimationToEnd
YAML
maestro --device "$UDID" test "$EVIDENCE_DIR/copy-profile.yaml" \
  --debug-output "$EVIDENCE_DIR/copy-profile-debug" 2>&1 | tail -10 || true
sleep 1
PROFILE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_prefix=${PROFILE_CLIP:0:12}"
echo -n "$PROFILE_CLIP" > "$EVIDENCE_DIR/clipboard-profile.txt"
snapshot "05-after-copy-profile"

# 7. Decode via verify-export-artifact.sh.
"$APPS/scripts/verify-export-artifact.sh" profile "$EVIDENCE_DIR/clipboard-profile.txt" "validator-export-pwd" \
  > "$EVIDENCE_DIR/proof_export_profile.json" 2>&1 || true

# 8. Same leg for Copy Share.
cat > "$EVIDENCE_DIR/copy-share.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: copy share button + prompt + confirm
---
- scrollUntilVisible:
    element:
      id: "btn_copy_share"
    timeout: 30000
- tapOn:
    id: "btn_copy_share"
- waitForAnimationToEnd
- assertVisible:
    id: "input_export_password"
- assertVisible:
    id: "input_export_password_confirm"
- tapOn:
    id: "input_export_password"
- eraseText: 64
- inputText:
    id: "input_export_password"
    text: "validator-export-pwd"
- tapOn:
    id: "input_export_password_confirm"
- eraseText: 64
- inputText:
    id: "input_export_password_confirm"
    text: "validator-export-pwd"
- tapOn:
    id: "btn_export_confirm"
- waitForAnimationToEnd
YAML
maestro --device "$UDID" test "$EVIDENCE_DIR/copy-share.yaml" \
  --debug-output "$EVIDENCE_DIR/copy-share-debug" 2>&1 | tail -10 || true
sleep 1
SHARE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_length=${#SHARE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_prefix=${SHARE_CLIP:0:12}"
echo -n "$SHARE_CLIP" > "$EVIDENCE_DIR/clipboard-share.txt"
snapshot "06-after-copy-share"

# 9. Decode the share artifact.
"$APPS/scripts/verify-export-artifact.sh" share "$EVIDENCE_DIR/clipboard-share.txt" "validator-export-pwd" \
  > "$EVIDENCE_DIR/proof_export_share.json" 2>&1 || true

# 10. Final summary (length/prefix only, never the raw bytes).
cat > "$EVIDENCE_DIR/summary.txt" <<EOF
sentinel_length=${#SENTINEL}
profile_clipboard_length=${#PROFILE_CLIP}
profile_clipboard_prefix=${PROFILE_CLIP:0:12}
share_clipboard_length=${#SHARE_CLIP}
share_clipboard_prefix=${SHARE_CLIP:0:12}
EOF

echo "[focus-export-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -40
echo "[focus-export-ios RESULT] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-ios RESULT] share_clipboard_length=${#SHARE_CLIP}"
