#!/usr/bin/env bash
# Focused iOS Rotate Share validator using real demo bfonboard artifacts.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APPS/../.." && pwd)"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
HARNESS_DIR="$ROOT/.tmp/test-harness"
RELAY="ws://127.0.0.1:8194"

UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/RMP iPhone 15/ { print $2; exit }')"
if [ -z "${UDID:-}" ]; then
  echo "[focus-rotate-ios] no booted RMP iPhone 15 simulator; boot one first" >&2
  exit 1
fi

[ -d "$APP_BUNDLE" ] || { echo "[focus-rotate-ios] missing $APP_BUNDLE; run just ios-full first" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "[focus-rotate-ios] missing bob package; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-bob.password.txt" ] || { echo "[focus-rotate-ios] missing bob password; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-carol.txt" ] || { echo "[focus-rotate-ios] missing carol package; run make demo-onboard" >&2; exit 1; }
[ -f "$HARNESS_DIR/onboard-carol.password.txt" ] || { echo "[focus-rotate-ios] missing carol password; run make demo-onboard" >&2; exit 1; }

python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close(); print('relay ok')" \
  || { echo "[focus-rotate-ios] demo relay 127.0.0.1:8194 not reachable; run make demo-start" >&2; exit 1; }

PACKAGE_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD_BOB="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
PACKAGE_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.txt")"
PASSWORD_CAROL="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-carol.password.txt")"
DEVICE_NAME="rotate-bob-ios"

EVIDENCE_DIR="$APPS/library/evidence/mobile-ios-rotate-share-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-rotate-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_bob_length=${#PACKAGE_BOB}
password_bob_length=${#PASSWORD_BOB}
package_carol_length=${#PACKAGE_CAROL}
password_carol_length=${#PASSWORD_CAROL}
relay=$RELAY
device_name=$DEVICE_NAME
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
  echo "[focus-rotate-ios snapshot $(date +%H:%M:%S)] ${tag}"
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
      echo "[focus-rotate-ios] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

wait_for_rotate_proof() {
  local timeout_secs="$1"
  local container
  local proof
  local started
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data)"
  proof="$container/Documents/debug-last-rotate-share-proof.txt"
  started="$(date +%s)"
  while true; do
    if [ -s "$proof" ] \
      && grep -Fq "replaced=yes" "$proof" \
      && grep -Fq "profile_changed=true" "$proof"; then
      cp "$proof" "$EVIDENCE_DIR/rotate-share-proof.txt"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-rotate-ios] timed out waiting for rotate proof: $proof" >&2
      snapshot "failure-rotate-proof"
      return 1
    fi
    sleep 1
  done
}

echo "[focus-rotate-ios $(date +%H:%M:%S)] fresh install + launch"
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
SIMCTL_CHILD_IGLOO_EXPORT_DIAGNOSTICS=1 \
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "01-launch"

echo "[focus-rotate-ios $(date +%H:%M:%S)] onboard bob"
INJECT_BOB_URL="igloo://test-inject?package=$(b64 "$PACKAGE_BOB")&password=$(urlencode "$PASSWORD_BOB")&relay=$(urlencode "$RELAY")&device_name=$(urlencode "$DEVICE_NAME")"
xcrun simctl openurl "$UDID" "$INJECT_BOB_URL" >/dev/null
wait_for_text "$DEVICE_NAME" 180
snapshot "02-onboard-review"

SAVE_BOB_URL="igloo://test-save-to-dashboard?device_name=$(urlencode "$DEVICE_NAME")"
xcrun simctl openurl "$UDID" "$SAVE_BOB_URL" >/dev/null
wait_for_text "Signer Stopped" 60
wait_for_text "$DEVICE_NAME" 60
snapshot "03-dashboard-before-rotate"

echo "[focus-rotate-ios $(date +%H:%M:%S)] connect replacement package"
ROTATE_URL="igloo://test-rotate-share?package=$(b64 "$PACKAGE_CAROL")&password=$(urlencode "$PASSWORD_CAROL")&relay=$(urlencode "$RELAY")"
xcrun simctl openurl "$UDID" "$ROTATE_URL" >/dev/null
wait_for_text "Replacement Preview" 180
wait_for_text "$DEVICE_NAME" 60
snapshot "04-replacement-preview"

echo "[focus-rotate-ios $(date +%H:%M:%S)] replace share"
xcrun simctl openurl "$UDID" "igloo://test-rotate-share-replace" >/dev/null
wait_for_rotate_proof 90
ROTATED_SHORT_ID="$(awk -F= '$1 == "short_id" { print $2 }' "$EVIDENCE_DIR/rotate-share-proof.txt")"
[ -n "$ROTATED_SHORT_ID" ] \
  || { echo "[focus-rotate-ios] rotate proof missing short_id" >&2; exit 1; }
wait_for_text "$DEVICE_NAME" 60
wait_for_text "$ROTATED_SHORT_ID" 60
wait_for_text "Signer" 30
snapshot "05-dashboard-after-rotate"

grep -Fq "$ROTATED_SHORT_ID" "$EVIDENCE_DIR/hierarchy-05-dashboard-after-rotate.txt" \
  || { echo "[focus-rotate-ios] dashboard did not render rotated short id $ROTATED_SHORT_ID" >&2; exit 1; }

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
device_name=$DEVICE_NAME
relay=$RELAY
rotated_short_id=$ROTATED_SHORT_ID
result=pass
EOF

echo "[focus-rotate-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
