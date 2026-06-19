#!/usr/bin/env bash
# Focused iOS export-artifact validator for VAL-SET-006/007/008/015.
#
# Strategy:
#   1. Fresh-install the debug app on the booted iOS simulator.
#   2. Create a real local keyset profile with the diagnostics-gated
#      igloo://test-create-keyset route, avoiding the external demo
#      provisioner while still using production profile storage.
#   3. Trigger the password-gated export route for profile and share.
#   4. Decode both artifacts with verify-export-artifact.sh.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"

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

[ -d "$APP_BUNDLE" ] || { echo "[focus-export-ios] missing $APP_BUNDLE; run 'just ios-build' first" >&2; exit 1; }

xcrun simctl terminate "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl keychain "$UDID" reset 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE"

capture_hierarchy() {
  local out="$1"
  maestro --device "$UDID" hierarchy > "$out" 2>&1 &
  local pid=$!
  local started
  started="$(date +%s)"
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(( $(date +%s) - started )) -ge 15 ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "[focus-export-ios] hierarchy capture timed out after 15s" > "$out"
      return 0
    fi
    sleep 1
  done
  wait "$pid" 2>/dev/null || true
}

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  capture_hierarchy "$EVIDENCE_DIR/hierarchy-${tag}.txt"
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

SENTINEL="validator-pre-export-sentinel"
echo "$SENTINEL" | xcrun simctl pbcopy "$UDID"

SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 \
SIMCTL_CHILD_IGLOO_EXPORT_DIAGNOSTICS=1 \
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "01-launch"

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="ExportKeyset-${RUN_TAG}"
DEVICE_NAME="ExportDevice-${RUN_TAG}"
KEYSET_RELAY="${KEYSET_RELAY:-ws://127.0.0.1:8194}"
RELAY_ENC="$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$KEYSET_RELAY")"
CREATE_URL="igloo://test-create-keyset?group_name=${GROUP_NAME}&threshold=2&count=3&device_name=${DEVICE_NAME}&relay=${RELAY_ENC}"

echo "$GROUP_NAME" > "$EVIDENCE_DIR/group_name.txt"
echo "$DEVICE_NAME" > "$EVIDENCE_DIR/device_name.txt"
echo "$KEYSET_RELAY" > "$EVIDENCE_DIR/keyset_relay.txt"
echo "[focus-export-ios $(date +%H:%M:%S)] creating keyset profile via URL"
xcrun simctl openurl "$UDID" "$CREATE_URL"
sleep 8
snapshot "02-dashboard-ready"

EXPORT_PASSWORD="validator-export-pwd"
EXPORT_PASSWORD_ENC="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${EXPORT_PASSWORD}'))")"

xcrun simctl openurl "$UDID" "igloo://test-export-actions?kind=profile&password=${EXPORT_PASSWORD_ENC}"
sleep 2
PROFILE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] profile_clipboard_prefix=${PROFILE_CLIP:0:12}"
echo -n "$PROFILE_CLIP" > "$EVIDENCE_DIR/clipboard-profile.txt"
if [[ "$PROFILE_CLIP" != bfprofile1* ]]; then
  echo "[focus-export-ios] expected bfprofile1 export, got prefix ${PROFILE_CLIP:0:12}" >&2
  snapshot "failure-export-profile"
  exit 1
fi
snapshot "03-after-export-profile"

bash "$APPS/scripts/verify-export-artifact.sh" profile "$EVIDENCE_DIR/clipboard-profile.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_profile.txt"

xcrun simctl openurl "$UDID" "igloo://test-export-actions?kind=share&password=${EXPORT_PASSWORD_ENC}"
sleep 2
SHARE_CLIP="$(xcrun simctl pbpaste "$UDID" | tr -d '\r\n')"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_length=${#SHARE_CLIP}"
echo "[focus-export-ios $(date +%H:%M:%S)] share_clipboard_prefix=${SHARE_CLIP:0:12}"
echo -n "$SHARE_CLIP" > "$EVIDENCE_DIR/clipboard-share.txt"
if [[ "$SHARE_CLIP" != bfshare1* ]]; then
  echo "[focus-export-ios] expected bfshare1 export, got prefix ${SHARE_CLIP:0:12}" >&2
  snapshot "failure-export-share"
  exit 1
fi
snapshot "04-after-export-share"

bash "$APPS/scripts/verify-export-artifact.sh" share "$EVIDENCE_DIR/clipboard-share.txt" "$EXPORT_PASSWORD" \
  > "$EVIDENCE_DIR/proof_export_share.txt"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
sentinel_length=${#SENTINEL}
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
keyset_relay=$KEYSET_RELAY
profile_clipboard_length=${#PROFILE_CLIP}
profile_clipboard_prefix=${PROFILE_CLIP:0:12}
share_clipboard_length=${#SHARE_CLIP}
share_clipboard_prefix=${SHARE_CLIP:0:12}
result=pass
EOF

echo "[focus-export-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -40
echo "[focus-export-ios RESULT] profile_clipboard_length=${#PROFILE_CLIP}"
echo "[focus-export-ios RESULT] share_clipboard_length=${#SHARE_CLIP}"
