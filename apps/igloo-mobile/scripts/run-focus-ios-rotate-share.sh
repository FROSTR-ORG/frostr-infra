#!/usr/bin/env bash
# Focused iOS Rotate Share validator using a native-generated bfonboard package.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
RELAY="${ROTATE_RELAY:-${KEYSET_RELAY:-ws://127.0.0.1:8194}}"
SHARE_IDX="${SHARE_IDX:-2}"

UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/RMP iPhone 15/ { print $2; exit }')"
if [ -z "${UDID:-}" ]; then
  echo "[focus-rotate-ios] no booted RMP iPhone 15 simulator; boot one first" >&2
  exit 1
fi

[ -d "$APP_BUNDLE" ] || { echo "[focus-rotate-ios] missing $APP_BUNDLE; run just ios-build first" >&2; exit 1; }

RELAY_HOST="${RELAY#ws://}"
RELAY_HOST="${RELAY_HOST%%/*}"
RELAY_PORT="${RELAY_HOST##*:}"
RELAY_HOST="${RELAY_HOST%:*}"
python3 -c "import socket, sys; s=socket.create_connection((sys.argv[1], int(sys.argv[2])), 2); s.close(); print('relay ok')" "$RELAY_HOST" "$RELAY_PORT" \
  || { echo "[focus-rotate-ios] relay $RELAY not reachable; start the local relay first" >&2; exit 1; }

RUN_TAG="$(date +%H%M%S)"
GROUP_NAME="RotateIOS-${RUN_TAG}"
DEVICE_NAME="RotateIOS-${RUN_TAG}"
PASSWORD="rotateios${RUN_TAG}"
EVIDENCE_DIR="$APPS/library/evidence/mobile-ios-rotate-share-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-rotate-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

urlencode() {
  python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

cat > "$EVIDENCE_DIR/input.txt" <<EOF
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
share_idx=$SHARE_IDX
password_length=${#PASSWORD}
relay=$RELAY
package_source=native-create-keyset-distribute
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

wait_for_distribute_package() {
  local timeout_secs="$1"
  local container
  local pkg_file
  local proof_file
  local started
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data)"
  pkg_file="$container/Documents/debug-last-keyset-distribute-package.txt"
  proof_file="$container/Documents/debug-last-keyset-distribute-package-proof.txt"
  started="$(date +%s)"
  while true; do
    if [ -s "$pkg_file" ] && grep -Fq "bfonboard1" "$pkg_file"; then
      cp "$proof_file" "$EVIDENCE_DIR/distribute-package-proof.txt" 2>/dev/null || true
      tr -d '\r\n' < "$pkg_file"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-rotate-ios] timed out waiting for native distribute package" >&2
      snapshot "failure-distribute-package"
      return 1
    fi
    sleep 1
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

echo "[focus-rotate-ios $(date +%H:%M:%S)] fresh install + diagnostic launch"
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 \
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
SIMCTL_CHILD_IGLOO_EXPORT_DIAGNOSTICS=1 \
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4
snapshot "01-launch"

CREATE_URL="igloo://test-create-keyset?group_name=$(urlencode "$GROUP_NAME")&threshold=2&count=3&device_name=$(urlencode "$DEVICE_NAME")&relay=$(urlencode "$RELAY")&auto_finish=false"
echo "[focus-rotate-ios $(date +%H:%M:%S)] create local keyset to Distribute"
xcrun simctl openurl "$UDID" "$CREATE_URL" > "$EVIDENCE_DIR/create-openurl.txt" 2>&1
wait_for_text "Distribute" 90
wait_for_text "Package password" 30
snapshot "02-distribute"

PASSWORD_ENC="$(urlencode "$PASSWORD")"
echo "[focus-rotate-ios $(date +%H:%M:%S)] generate native replacement package"
xcrun simctl openurl "$UDID" "igloo://test-keyset-distribute-password?share_idx=${SHARE_IDX}&password=${PASSWORD_ENC}" >> "$EVIDENCE_DIR/create-openurl.txt" 2>&1
sleep 1
xcrun simctl openurl "$UDID" "igloo://test-keyset-distribute-submit?share_idx=${SHARE_IDX}&method=copy" >> "$EVIDENCE_DIR/create-openurl.txt" 2>&1
PACKAGE_REPLACEMENT="$(wait_for_distribute_package 90)"
[ "${PACKAGE_REPLACEMENT:0:10}" = "bfonboard1" ] \
  || { echo "[focus-rotate-ios] native replacement package has unexpected prefix" >&2; exit 1; }
[ "${#PACKAGE_REPLACEMENT}" -ge 600 ] \
  || { echo "[focus-rotate-ios] native replacement package too short: ${#PACKAGE_REPLACEMENT}" >&2; exit 1; }
printf '%s' "$PACKAGE_REPLACEMENT" | shasum -a 256 | awk '{ print "replacement_package_sha256=" $1 }' > "$EVIDENCE_DIR/replacement-package-redacted-proof.txt"
{
  echo "replacement_package_prefix=${PACKAGE_REPLACEMENT:0:10}"
  echo "replacement_package_length=${#PACKAGE_REPLACEMENT}"
} >> "$EVIDENCE_DIR/replacement-package-redacted-proof.txt"

echo "[focus-rotate-ios $(date +%H:%M:%S)] finish keyset and land on dashboard"
xcrun simctl openurl "$UDID" "igloo://test-keyset-distribute-finish" >> "$EVIDENCE_DIR/create-openurl.txt" 2>&1
wait_for_text "$DEVICE_NAME" 60
wait_for_text "Signer" 60
snapshot "03-dashboard-before-rotate"

echo "[focus-rotate-ios $(date +%H:%M:%S)] connect native replacement package"
ROTATE_URL="igloo://test-rotate-share?package=$(b64 "$PACKAGE_REPLACEMENT")&password=${PASSWORD_ENC}&relay=$(urlencode "$RELAY")"
xcrun simctl openurl "$UDID" "$ROTATE_URL" > "$EVIDENCE_DIR/rotate-openurl.txt" 2>&1
wait_for_text "Replacement Preview" 180
wait_for_text "$DEVICE_NAME" 60
snapshot "04-replacement-preview"

echo "[focus-rotate-ios $(date +%H:%M:%S)] replace share"
xcrun simctl openurl "$UDID" "igloo://test-rotate-share-replace" >> "$EVIDENCE_DIR/rotate-openurl.txt" 2>&1
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
group_name=$GROUP_NAME
device_name=$DEVICE_NAME
relay=$RELAY
share_idx=$SHARE_IDX
replacement_package_length=${#PACKAGE_REPLACEMENT}
rotated_short_id=$ROTATED_SHORT_ID
result=pass
EOF

echo "[focus-rotate-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
