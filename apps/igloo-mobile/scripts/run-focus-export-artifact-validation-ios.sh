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

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"
HARNESS_DIR="$ROOT/.tmp/test-harness"

UDID="$(xcrun simctl list devices booted | grep -E 'RMP iPhone 15' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
if [ -z "${UDID:-}" ]; then
  echo "[focus-export-ios] no booted RMP iPhone 15 simulator; boot one first" >&2
  exit 1
fi

APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"

EVIDENCE_DIR="${EVIDENCE_DIR:-$APPS/library/evidence/mobile-export-artifact-validation-ios-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-export-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

# Pre-flight
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),1); s.close()" \
  || { echo "[focus-export-ios] demo relay port 8194 unreachable; run make demo-start first" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] || { echo "[focus-export-ios] missing $APP_BUNDLE; run 'just ios-build' first" >&2; exit 1; }
xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE"

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
sleep 1
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
SIMCTL_CHILD_IGLOO_EXPORT_DIAGNOSTICS=1 \
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
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

# 5. Export real artifacts through the diagnostics-gated companion route.
EXPORT_PASSWORD="validator-export-pwd"
EXPORT_PASSWORD_ENC="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${EXPORT_PASSWORD}'))")"

xcrun simctl openurl "$UDID" "igloo://test-export-actions?kind=profile&password=${EXPORT_PASSWORD_ENC}"
sleep 2
PROFILE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_prefix=${PROFILE_CLIP:0:12}"
echo -n "$PROFILE_CLIP" > "$EVIDENCE_DIR/clipboard-profile.txt"
snapshot "04-after-export-profile"

# 6. Decode via verify-export-artifact.sh.
bash "$APPS/scripts/verify-export-artifact.sh" profile "$EVIDENCE_DIR/clipboard-profile.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_profile.txt"

# 7. Same leg for Copy Share.
xcrun simctl openurl "$UDID" "igloo://test-export-actions?kind=share&password=${EXPORT_PASSWORD_ENC}"
sleep 2
SHARE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_length=${#SHARE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_prefix=${SHARE_CLIP:0:12}"
echo -n "$SHARE_CLIP" > "$EVIDENCE_DIR/clipboard-share.txt"
snapshot "05-after-export-share"

# 8. Decode the share artifact.
bash "$APPS/scripts/verify-export-artifact.sh" share "$EVIDENCE_DIR/clipboard-share.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_share.txt"

# 9. Final summary (length/prefix only, never the raw bytes).
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
