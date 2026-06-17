#!/usr/bin/env bash
# Focused Android Load Profile validator for exported bfprofile1 / bfshare1 artifacts.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTIVITY="$APP_ID/com.frostr.igloo.MainActivity"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ACTION_LOAD="com.frostr.igloo.DEBUG_TEST_LOAD_PROFILE"
ACTION_CONFIRM="com.frostr.igloo.DEBUG_TEST_LOAD_PROFILE_CONFIRM"
EXPORT_PASSWORD="validator-export-pwd"

EXPORT_DIR="$(ls -td "$APPS"/library/evidence/mobile-export-artifact-validation-android-* 2>/dev/null | head -1 || true)"
[ -n "$EXPORT_DIR" ] || { echo "[focus-load-android] no Android export evidence found; run just focus-android-export first" >&2; exit 1; }
[ -f "$EXPORT_DIR/clipboard-profile.txt" ] || { echo "[focus-load-android] missing clipboard-profile.txt in $EXPORT_DIR" >&2; exit 1; }
[ -f "$EXPORT_DIR/clipboard-share.txt" ] || { echo "[focus-load-android] missing clipboard-share.txt in $EXPORT_DIR" >&2; exit 1; }
[ -f "$APK" ] || { echo "[focus-load-android] missing $APK; run just android-full first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 || { echo "[focus-load-android] $SERIAL not booted" >&2; exit 1; }

PROFILE_PKG="$(tr -d '\r\n' < "$EXPORT_DIR/clipboard-profile.txt")"
SHARE_PKG="$(tr -d '\r\n' < "$EXPORT_DIR/clipboard-share.txt")"

EVIDENCE_DIR="$APPS/library/evidence/mobile-load-profile-artifacts-android-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-load-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
echo "[focus-load-android $(date +%H:%M:%S)] source_export: $EXPORT_DIR"

cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
source_export=$EXPORT_DIR
profile_package_length=${#PROFILE_PKG}
share_package_length=${#SHARE_PKG}
export_password_length=${#EXPORT_PASSWORD}
EOF

snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  if [ -f "$EVIDENCE_DIR/hierarchy-${tag}.xml" ]; then
    python3 - <<PYEOF
import re
path = "$EVIDENCE_DIR/hierarchy-${tag}.xml"
with open(path, encoding="utf-8") as f:
    data = f.read()
data = re.sub(r'text="([^"]{50,})"', lambda m: f'text="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'content-desc="([^"]{50,})"', lambda m: f'content-desc="[REDACTED-{len(m.group(1))}chars]"', data)
with open("${EVIDENCE_DIR}/redacted-hierarchy-${tag}.xml", "w", encoding="utf-8") as f:
    f.write(data)
PYEOF
  fi
  echo "[focus-load-android snapshot $(date +%H:%M:%S)] ${tag}"
}

wait_for_text() {
  local needle="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"
  while true; do
    adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
    adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/.wait-window.xml" \
      >/dev/null 2>&1 || true
    if [ -f "$EVIDENCE_DIR/.wait-window.xml" ] && grep -Fq "$needle" "$EVIDENCE_DIR/.wait-window.xml"; then
      rm -f "$EVIDENCE_DIR/.wait-window.xml"
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      rm -f "$EVIDENCE_DIR/.wait-window.xml"
      echo "[focus-load-android] timed out waiting for: $needle" >&2
      snapshot "failure-wait-${needle//[^A-Za-z0-9]/-}"
      return 1
    fi
    sleep 2
  done
}

wait_for_load_proof() {
  local prefix="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"
  while true; do
    if adb -s "$SERIAL" exec-out run-as "$APP_ID" cat files/debug-last-load-profile-proof.txt \
      > "$EVIDENCE_DIR/${prefix}-load-proof.txt" 2>/dev/null \
      && grep -Fq "stored=yes" "$EVIDENCE_DIR/${prefix}-load-proof.txt"; then
      return 0
    fi
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[focus-load-android] timed out waiting for load proof" >&2
      snapshot "${prefix}-failure-load-proof"
      return 1
    fi
    sleep 1
  done
}

fresh_launch() {
  adb -s "$SERIAL" shell pm clear "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$SERIAL" install -r "$APK" >/dev/null
  adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
  sleep 3
}

run_leg() {
  local mode="$1"
  local package="$2"
  local prefix="$3"

  echo "[focus-load-android $(date +%H:%M:%S)] ${mode} leg"
  fresh_launch
  snapshot "${prefix}-01-launch"

  adb -s "$SERIAL" shell am start \
    -a "$ACTION_LOAD" \
    -n "$ACTIVITY" \
    --es mode "$mode" \
    --es package "$package" \
    --es password "$EXPORT_PASSWORD" >/dev/null
  wait_for_text "Confirm" 180
  wait_for_text "Load Profile" 30
  snapshot "${prefix}-02-confirm"

  adb -s "$SERIAL" shell am start \
    -a "$ACTION_CONFIRM" \
    -n "$ACTIVITY" >/dev/null
  wait_for_load_proof "$prefix" 90
  sleep 2
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

echo "[focus-load-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
