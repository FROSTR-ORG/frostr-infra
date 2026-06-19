#!/usr/bin/env bash
# Focused iOS Load Profile validator for exported bfprofile1 / bfshare1 artifacts.
#
# Uses the latest successful iOS export evidence as input, fresh-installs the
# debug app for each leg, drives diagnostics-gated Load Profile import/recover
# actions, confirms the resolved profile, and captures dashboard evidence.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="${APP_BUNDLE:-$HOME/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app}"
EXPORT_PASSWORD="validator-export-pwd"

UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/RMP iPhone 15/ { print $2; exit }')"
if [ -z "${UDID:-}" ]; then
  echo "[focus-load-ios] no booted RMP iPhone 15 simulator; boot one first" >&2
  exit 1
fi

EXPORT_DIR="${EXPORT_DIR:-$(ls -td "$APPS"/library/evidence/mobile-export-artifact-validation-ios-* 2>/dev/null | head -1 || true)}"
[ -n "$EXPORT_DIR" ] || { echo "[focus-load-ios] no export evidence found; run just focus-ios-export first or pass EXPORT_DIR" >&2; exit 1; }
[ -f "$EXPORT_DIR/clipboard-profile.txt" ] || { echo "[focus-load-ios] missing clipboard-profile.txt in $EXPORT_DIR" >&2; exit 1; }
[ -f "$EXPORT_DIR/clipboard-share.txt" ] || { echo "[focus-load-ios] missing clipboard-share.txt in $EXPORT_DIR" >&2; exit 1; }
[ -d "$APP_BUNDLE" ] || { echo "[focus-load-ios] missing $APP_BUNDLE; run just ios-build first" >&2; exit 1; }

PROFILE_PKG="$(tr -d '\r\n' < "$EXPORT_DIR/clipboard-profile.txt")"
SHARE_PKG="$(tr -d '\r\n' < "$EXPORT_DIR/clipboard-share.txt")"

EVIDENCE_DIR="$APPS/library/evidence/mobile-load-profile-artifacts-ios-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-load-ios $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
echo "[focus-load-ios $(date +%H:%M:%S)] source_export: $EXPORT_DIR"

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
source_export=$EXPORT_DIR
profile_package_length=${#PROFILE_PKG}
share_package_length=${#SHARE_PKG}
export_password_length=${#EXPORT_PASSWORD}
EOF

snapshot() {
  local tag="$1"
  xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/${tag}.png" >/dev/null
  xcrun simctl ui "$UDID" dump > "$EVIDENCE_DIR/hierarchy-${tag}.txt" 2>/dev/null || true
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
  echo "[focus-load-ios snapshot $(date +%H:%M:%S)] ${tag}"
}

wait_for_text() {
  local needle="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"
  while true; do
    xcrun simctl ui "$UDID" dump > "$EVIDENCE_DIR/.wait-hierarchy.txt" 2>/dev/null || true
    if grep -Fq "$needle" "$EVIDENCE_DIR/.wait-hierarchy.txt" 2>/dev/null; then
      rm -f "$EVIDENCE_DIR/.wait-hierarchy.txt"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      rm -f "$EVIDENCE_DIR/.wait-hierarchy.txt"
      echo "[focus-load-ios] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

wait_for_load_proof() {
  local prefix="$1"
  local timeout_secs="$2"
  local container
  local proof
  local started
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data)"
  proof="$container/Documents/debug-last-load-profile-proof.txt"
  started="$(date +%s)"
  while true; do
    if [ -s "$proof" ]; then
      cp "$proof" "$EVIDENCE_DIR/${prefix}-load-proof.txt"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-load-ios] timed out waiting for load proof: $proof" >&2
      snapshot "${prefix}-failure-load-proof"
      return 1
    fi
    sleep 1
  done
}

fresh_launch() {
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl keychain "$UDID" reset >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP_BUNDLE"
  SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 \
  SIMCTL_CHILD_IGLOO_EXPORT_DIAGNOSTICS=1 \
    xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
  sleep 3
}

write_debug_package() {
  local package="$1"
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data)"
  mkdir -p "$container/Documents"
  printf '%s' "$package" > "$container/Documents/debug-load-profile-package.txt"
}

run_leg() {
  local mode="$1"
  local package="$2"
  local prefix="$3"

  echo "[focus-load-ios $(date +%H:%M:%S)] ${mode} leg"
  fresh_launch
  snapshot "${prefix}-01-launch"

  write_debug_package "$package"
  xcrun simctl openurl "$UDID" "igloo://test-load-profile-file?mode=${mode}&password=${EXPORT_PASSWORD}"
  sleep 8
  snapshot "${prefix}-02-confirm"

  xcrun simctl openurl "$UDID" "igloo://test-load-profile-confirm"
  wait_for_load_proof "$prefix" 90
  sleep 3
  snapshot "${prefix}-03-dashboard"
}

run_leg import "$PROFILE_PKG" "import"
run_leg recover "$SHARE_PKG" "recover"

cat > "$EVIDENCE_DIR/summary.txt" <<EOF
source_export=$EXPORT_DIR
import_profile_length=${#PROFILE_PKG}
recover_share_length=${#SHARE_PKG}
result=pass
EOF

echo "[focus-load-ios RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
