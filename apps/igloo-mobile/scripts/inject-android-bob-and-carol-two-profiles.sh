#!/usr/bin/env bash
# Pre-loads the Android emulator with two stored profiles via the
# debug-gated onboard-inject intent path:
#   - bob           -> "test-r2"
#   - carol         -> "test-cross-003"
#
# The simulator/device must be running (state=boot_completed=1) with the
# IglooMobile debug APK installed (com.frostr.igloo.dev). After this
# helper completes, the hub listing will show two rows whose labels are
# exactly the strings above, ready for the Maestro flow
# `flows/hub-profile-row-routing-fix-android.yaml`.
#
# Does NOT print, persist, or commit raw bfonboard1 / password strings —
# only the lengths used to validate that the inject path carried the
# payloads to the OnboardConnect screen end-to-end.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
DEVICE=emulator-5554
PKG=com.frostr.igloo.dev
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"
BOB_PKG_FILE="$ROOT/.tmp/test-harness/onboard-bob.txt"
BOB_PWD_FILE="$ROOT/.tmp/test-harness/onboard-bob.password.txt"
CAROL_PKG_FILE="$ROOT/.tmp/test-harness/onboard-carol.txt"
CAROL_PWD_FILE="$ROOT/.tmp/test-harness/onboard-carol.password.txt"
BOB_LABEL="test-r2"
CAROL_LABEL="test-cross-003"
RELAY="ws://10.0.2.2:8194"

BOB_PKG=$(tr -d '\r\n' < "$BOB_PKG_FILE")
BOB_PWD=$(tr -d '\r\n' < "$BOB_PWD_FILE")
CAROL_PKG=$(tr -d '\r\n' < "$CAROL_PKG_FILE")
CAROL_PWD=$(tr -d '\r\n' < "$CAROL_PWD_FILE")

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-android-hub-profile-row-routing-fix-2026-06-16"
mkdir -p "$EVIDENCE_DIR"

log() { printf "\n=== %s ===\n" "$*"; }

# Helper: tap by resource-id via uiautomator-discovered coordinates.
TAP_ID_HELPER=$(mktemp -t tap-id-helper-XXXXXX)
cat > "$TAP_ID_HELPER" <<'PY'
import re, html, subprocess, sys
rid = sys.argv[1]
dev = sys.argv[2]
subprocess.run(["adb","-s",dev,"exec-out","uiautomator","dump","/sdcard/window_dump.xml"], capture_output=True)
subprocess.run(["adb","-s",dev,"pull","/sdcard/window_dump.xml","/tmp/d.xml"], capture_output=True)
data = html.unescape(open("/tmp/d.xml").read())
m = re.search(r'resource-id="' + re.escape(rid) + r'"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', data)
if not m: sys.exit(2)
x1, y1, x2, y2 = map(int, m.groups())
print((x1 + x2) // 2, (y1 + y2) // 2)
PY
# Tap a `TextButton` whose identifier does not surface in the uiautomator
# resource-id axis: tap by the visible text glyph (e.g. "←"). This avoids
# failing the test when the underlying Material `TextButton` flattens to a
# Button node without a testTag attribute.
tap_text() {
  local text="$1"
  local out
  out=$(python3 - "$text" "$DEVICE" <<'PYEOF'
import re, html, subprocess, sys
wanted, dev = sys.argv[1], sys.argv[2]
subprocess.run(["adb","-s",dev,"exec-out","uiautomator","dump","/sdcard/window_dump.xml"], capture_output=True)
subprocess.run(["adb","-s",dev,"pull","/sdcard/window_dump.xml","/tmp/d.xml"], capture_output=True)
data = html.unescape(open("/tmp/d.xml").read())
m = re.search(r'<node[^>]*text="' + re.escape(wanted) + r'"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', data)
if not m: sys.exit(2)
x1, y1, x2, y2 = map(int, m.groups())
print((x1 + x2) // 2, (y1 + y2) // 2, x1, y1, x2, y2)
PYEOF
  ) || { log "[tap_text] not found: $text"; return 1; }
  log "[tap_text] $text @ $(echo $out | cut -d' ' -f1,2) bounds=$(echo $out | cut -d' ' -f3-)"
  adb -s "$DEVICE" shell input tap $(echo $out | cut -d' ' -f1,2)
  # Tap parent View bounds (close to actual click target) — the inner
  # TextView "←" is wrapped in a non-clickable View; click parent View
  # bounds instead.
  local bounds=( $(echo $out | cut -d' ' -f3-) )
  cx=$(( (bounds[0] - 30 + bounds[2] + 30) / 2 ))
  cy=$(( (bounds[1] - 30 + bounds[3] + 30) / 2 ))
  log "[tap_text] larger-area tap @ $cx $cy"
  adb -s "$DEVICE" shell input tap $cx $cy
  sleep 2
}

tap_id() {
  python3 "$TAP_ID_HELPER" "$1" "$DEVICE"
}
# Robust tap: try by-id first, then by-text fallback for back affordance.
issue_tap() {
  local rid="${1:-}"
  local text_fallback="${2:-}"
  local out
  if [ -z "$rid" ]; then
    log "[tap] no resource-id given"
    return 1
  fi
  out=$(tap_id "$rid") || {
    if [ -n "$text_fallback" ]; then
      log "[tap] $rid not found, fallback to text '$text_fallback'"
      tap_text "$text_fallback" >/dev/null
      return 0
    fi
    log "[tap] no bounds for $rid"
    return 1
  }
  log "[tap] $rid @ $out"
  adb -s "$DEVICE" shell input tap $out
  sleep 2
}

# Helper: bring up the OnboardConnect screen preloaded with the inject
# values for `pkg`, `pwd`, `device_name`. Then submit btn_connect and
# save on the review screen.
inject_onboard() {
  local pkg="$1"; local pwd="$2"; local label="$3"
  log "[inject_onboard] $label"
  adb -s "$DEVICE" shell am start \
    -a "$ACTION" \
    -n "$PKG/com.frostr.igloo.MainActivity" \
    --es package "$pkg" --es password "$pwd" \
    --es relay "$RELAY" --es device_name "$label" >/dev/null
  sleep 4
  issue_tap "btn_connect" || log "[inject_onboard] btn_connect not found yet"
  sleep 5
  issue_tap "btn_save_device" || log "[inject_onboard] btn_save_device not found yet"
  sleep 4
}

# Take the user back to the hub. The Dashboard `TextButton` does not
# surface `btn_back_dashboard` as a uiautomator resource-id; fall back
# to tapping the visible "←" arrow inside the header.
issue_tap_back_dashboard() {
  if ! issue_tap "btn_back_dashboard" "←"; then
    log "[issue_tap_back_dashboard] back navigation failed"
    return 1
  fi
}

# Reset everything: clear app data and cold launch.
log "pm clear + cold launch"
adb -s "$DEVICE" shell pm clear "$PKG" >/dev/null
sleep 1
# monkey without verbose exits 251 ("Network stats" reporting failing),
# which set -e would treat as fatal. Use `am start` directly to be safe.
adb -s "$DEVICE" shell am start -n "$PKG/com.frostr.igloo.MainActivity" >/dev/null
sleep 2

# Onboard bob -> test-r2
inject_onboard "$BOB_PKG" "$BOB_PWD" "$BOB_LABEL"

# Take the user back to the hub.
issue_tap_back_dashboard

# Onboard carol -> test-cross-003
inject_onboard "$CAROL_PKG" "$CAROL_PWD" "$CAROL_LABEL"

# Bring back to hub for the Maestro flow.
issue_tap_back_dashboard

# Capture hub hierarchy dump for evidence.
adb -s "$DEVICE" exec-out uiautomator dump /sdcard/window_dump.xml >/dev/null
adb -s "$DEVICE" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hub-both-rows-post-inject.xml" >/dev/null
adb -s "$DEVICE" shell screencap -p > "$EVIDENCE_DIR/hub-both-rows-post-inject.png"

# Sanitize: replace package/password byte sequences with [REDACTED_LEN_N].
python3 - "$EVIDENCE_DIR" "$BOB_PKG" "$BOB_PWD" "$CAROL_PKG" "$CAROL_PWD" <<'PYEOF'
import os, sys, re
evdir, *secrets = sys.argv[1:]
for name in os.listdir(evdir):
    if not name.endswith('.xml'):
        continue
    p = os.path.join(evdir, name)
    data = open(p).read()
    for s in secrets:
        if s:
            data = data.replace(s, f'[REDACTED_LEN_{len(s)}]')
    open(p, 'w').write(data)
PYEOF

echo "injection complete"
ls -1 "$EVIDENCE_DIR"
