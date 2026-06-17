#!/usr/bin/env bash
# Focused iOS QR display validator for VAL-QR-001.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
UDID="${UDID:-$(xcrun simctl list devices booted | awk -F '[()]' '/RMP iPhone 15/ { print $2; exit }')}"

[ -n "${UDID:-}" ] || { echo "[focus-qr-ios] no booted RMP iPhone 15 simulator" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] || { echo "[focus-qr-ios] missing $APP_BUNDLE; run just ios-build first" >&2; exit 1; }
command -v zbarimg >/dev/null || { echo "[focus-qr-ios] missing zbarimg; brew install zbar" >&2; exit 1; }

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="QrDisplayIOS-${RUN_TAG}"
DEVICE_NAME="QrDisplayIOS-${RUN_TAG}"
PASSWORD="qrdisplay${RUN_TAG}"
SHARE_IDX="2"
RELAY="ws://127.0.0.1:8194"
RELAY_ENC="$(python3 -c 'import urllib.parse; print(urllib.parse.quote("ws://127.0.0.1:8194"))')"
EVIDENCE_DIR="${EVIDENCE_DIR:-$APPS/library/evidence/mobile-ios-qr-display-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$EVIDENCE_DIR"

echo "[focus-qr-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
password_length=${#PASSWORD}
share_idx=$SHARE_IDX
relay=$RELAY
EOF

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null 2>&1 || true
  maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>&1 || true
  if [ -f "$EVIDENCE_DIR/hierarchy-${tag}.txt" ]; then
    python3 - <<PYEOF
import re
path = "$EVIDENCE_DIR/hierarchy-${tag}.txt"
with open(path, encoding="utf-8") as f:
    data = f.read()
data = re.sub(r'(value|label): ([A-Za-z0-9]{50,})', lambda m: f'{m.group(1)}: [REDACTED-{len(m.group(2))}chars]', data)
with open("${EVIDENCE_DIR}/redacted-hierarchy-${tag}.txt", "w", encoding="utf-8") as f:
    f.write(data)
PYEOF
  fi
  echo "[focus-qr-ios snapshot $(date +%H:%M:%S)] ${tag}"
}

wait_for_text() {
  local needle="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"
  while true; do
    maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/.wait-hierarchy.txt" 2>&1 || true
    if grep -Fq "$needle" "$EVIDENCE_DIR/.wait-hierarchy.txt" 2>/dev/null; then
      rm -f "$EVIDENCE_DIR/.wait-hierarchy.txt"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      rm -f "$EVIDENCE_DIR/.wait-hierarchy.txt"
      echo "[focus-qr-ios] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

echo "[focus-qr-ios $(date +%H:%M:%S)] fresh install + diagnostic launch"
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 3
snapshot "01-launch"

URL="igloo://test-create-keyset?group_name=${GROUP_NAME}&threshold=2&count=3&device_name=${DEVICE_NAME}&relay=${RELAY_ENC}&auto_finish=false"
echo "[focus-qr-ios $(date +%H:%M:%S)] create keyset to Distribute"
xcrun simctl openurl "$UDID" "$URL" > "$EVIDENCE_DIR/openurl.txt" 2>&1
wait_for_text "Distribute" 90
wait_for_text "Package password" 30
snapshot "02-distribute"

PASSWORD_ENC="$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$PASSWORD")"
SEED_URL="igloo://test-keyset-distribute-password?share_idx=${SHARE_IDX}&password=${PASSWORD_ENC}"
echo "[focus-qr-ios $(date +%H:%M:%S)] seed distribute password"
xcrun simctl openurl "$UDID" "$SEED_URL" >> "$EVIDENCE_DIR/openurl.txt" 2>&1
sleep 2

FLOW="$EVIDENCE_DIR/qr-display-ios.yaml"
cat > "$FLOW" <<EOF
appId: $APP_ID
---
- scrollUntilVisible:
    element:
      text: "QR"
    timeout: 30000
- tapOn:
    text: "QR"
- scrollUntilVisible:
    element:
      id: "qr_payload_text"
    timeout: 45000
- assertVisible:
    id: "qr_image"
- assertVisible:
    id: "qr_payload_text"
EOF

echo "[focus-qr-ios $(date +%H:%M:%S)] open QR modal"
maestro --device "$UDID" test "$FLOW" --debug-output "$EVIDENCE_DIR/maestro" 2>&1 \
  | tee "$EVIDENCE_DIR/maestro.log"
snapshot "03-qr-modal"

DECODED="$(
  zbarimg --quiet --raw "$EVIDENCE_DIR/03-qr-modal.png" 2>/dev/null \
    | grep -E '^bfonboard1' \
    | head -1 || true
)"
[ -n "$DECODED" ] || { echo "[focus-qr-ios] zbarimg did not decode bfonboard1 from QR modal screenshot" >&2; exit 1; }
[ "${#DECODED}" -ge 600 ] || { echo "[focus-qr-ios] decoded bfonboard1 too short: ${#DECODED}" >&2; exit 1; }

printf '%s' "$DECODED" | shasum -a 256 | awk '{ print "decoded_sha256=" $1 }' > "$EVIDENCE_DIR/qr-decode-proof.txt"
{
  echo "decoded_prefix=${DECODED:0:10}"
  echo "decoded_length=${#DECODED}"
  echo "result=pass"
} >> "$EVIDENCE_DIR/qr-decode-proof.txt"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
relay=$RELAY
decoded_length=${#DECODED}
result=pass
EOF

echo "[focus-qr-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
