#!/usr/bin/env bash
# Verifies the mobile-android-hub-profile-row-routing-fix end-to-end on
# the Android emulator. Onboards bob and carol with distinct labels so the
# hub has two stored-profile rows, then exercises hub-row tap -> dashboard
# identity parity. Evidence lands in
# apps/igloo-mobile/library/evidence/mobile-android-hub-profile-row-routing-fix-2026-06-16/.

set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-android-hub-profile-row-routing-fix-2026-06-16"
mkdir -p "$EVIDENCE_DIR"

ONBOARD_BOB="$ROOT/.tmp/test-harness/onboard-bob.txt"
BOB_PWD_FILE="$ROOT/.tmp/test-harness/onboard-bob.password.txt"
ONBOARD_CAROL="$ROOT/.tmp/test-harness/onboard-carol.txt"
CAROL_PWD_FILE="$ROOT/.tmp/test-harness/onboard-carol.password.txt"

BOB_PKG=$(tr -d '\r\n' < "$ONBOARD_BOB")
BOB_PWD=$(tr -d '\r\n' < "$BOB_PWD_FILE")
CAROL_PKG=$(tr -d '\r\n' < "$ONBOARD_CAROL")
CAROL_PWD=$(tr -d '\r\n' < "$CAROL_PWD_FILE")

DEVICE=emulator-5554
PKG=com.frostr.igloo.dev
RELAY="ws://10.0.2.2:8194"

# Device name labels for hub rows: bob -> test-r2, carol -> test-cross-003.
# These mirror the validator's notation in the bug description to make the
# evidence grep-able for follow-up validators.
BOB_LABEL="test-r2"
CAROL_LABEL="test-cross-003"

log() { printf "\n=== %s ===\n" "$*"; }

dump() {
  adb -s "$DEVICE" exec-out uiautomator dump /sdcard/window_dump.xml >/dev/null
  adb -s "$DEVICE" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/$1" >/dev/null
}
shot() {
  adb -s "$DEVICE" shell screencap -p > "$EVIDENCE_DIR/$1"
}

# --------------------------------------------------------------------------
# Python helpers used inline.
# --------------------------------------------------------------------------
PYSCRIPT_TAP_ID=$(mktemp -t tap-id-XXXXXX)
cat > "$PYSCRIPT_TAP_ID" <<'PYEOF'
import re, html, subprocess, sys
id_wanted = sys.argv[1]
device = sys.argv[2]
sub = subprocess.run(["adb","-s",device,"exec-out","uiautomator","dump","/sdcard/window_dump.xml"], capture_output=True)
subprocess.run(["adb","-s",device,"pull","/sdcard/window_dump.xml","/tmp/d.xml"], capture_output=True)
text = open("/tmp/d.xml").read()
unesc = html.unescape(text)
candidates = re.findall(r'resource-id="' + re.escape(id_wanted) + r'"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', unesc)
if not candidates:
    print("NOT_FOUND", file=sys.stderr); sys.exit(2)
x1, y1, x2, y2 = map(int, candidates[0])
cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
print(f"{cx} {cy}")
PYEOF

PYSCRIPT_TAP_LABEL=$(mktemp -t tap-label-XXXXXX)
cat > "$PYSCRIPT_TAP_LABEL" <<'PYEOF'
import re, html, subprocess, sys
label = sys.argv[1]
device = sys.argv[2]
sub = subprocess.run(["adb","-s",device,"exec-out","uiautomator","dump","/sdcard/window_dump.xml"], capture_output=True)
subprocess.run(["adb","-s",device,"pull","/sdcard/window_dump.xml","/tmp/d.xml"], capture_output=True)
text = open("/tmp/d.xml").read()
unesc = html.unescape(text)
# Find every profile_row_X node bounds.
rows = re.findall(r'resource-id="(profile_row_[a-f0-9]+)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', unesc)
# Find the label text node bounds.
lbl = re.search(r'<node[^>]*text="' + re.escape(label) + r'"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', unesc)
if not rows or not lbl:
    sys.exit(2)
ly = (int(lbl.group(2)) + int(lbl.group(4))) // 2
best = None
best_dist = 10**9
for rid, x1, y1, x2, y2 in rows:
    cy = (int(y1) + int(y2)) // 2
    dist = abs(cy - ly)
    if dist < best_dist:
        best = (rid, (int(x1) + int(x2)) // 2, cy, dist)
        best_dist = dist
cx, cy = best[1], best[2]
print(f"{cx} {cy} {best[0]}")
PYEOF

tap_id() {
  python3 "$PYSCRIPT_TAP_ID" "$1" "$DEVICE"
}
tap_label() {
  python3 "$PYSCRIPT_TAP_LABEL" "$1" "$DEVICE"
}
issue_tap() {
  local cx cy
  if IFS=' ' read -r cx cy; then
    log "[tap] ${1} center=($cx, $cy)"
    adb -s "$DEVICE" shell input tap "$cx" "$cy"
  fi
}

# --------------------------------------------------------------------------
# Step 0: clean device.
# --------------------------------------------------------------------------
log "step 0: pm clear + cold launch"
adb -s "$DEVICE" shell pm clear "$PKG" >/dev/null
sleep 1
adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 2
dump 00-launch-hub-empty.xml
shot 00-launch-hub-empty.png

onboard_via_inject() {
  local pkg="$1"; local pwd="$2"; local label="$3"
  log "onboarding ${label}"
  adb -s "$DEVICE" shell am start \
    -a com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD \
    -n "$PKG/com.frostr.igloo.MainActivity" \
    --es package "$pkg" --es password "$pwd" \
    --es relay "$RELAY" --es device_name "$label" >/dev/null
  sleep 4
  dump "inject-${label}-post-1.xml"
  # Tap OnboardConnect.btn_connect. Use uiautomator-discovered bounds.
  tap_id "btn_connect" | issue_tap "btn_connect"
  sleep 5
  dump "inject-${label}-post-2.xml"
  # On review screen, type/confirm and save.
  tap_id "btn_save_device" | issue_tap "btn_save_device"
  sleep 4
  dump "after-save-${label}.xml"
  shot "after-save-${label}.png"
}

log "step 1: onboard ${BOB_LABEL}"
onboard_via_inject "$BOB_PKG" "$BOB_PWD" "$BOB_LABEL"

log "step 2: back to hub"
tap_id "btn_back_dashboard" | issue_tap "btn_back_dashboard"
sleep 2
dump 02-hub-after-r2.xml

log "step 3: onboard ${CAROL_LABEL}"
onboard_via_inject "$CAROL_PKG" "$CAROL_PWD" "$CAROL_LABEL"

log "step 4: back to hub (with both rows)"
tap_id "btn_back_dashboard" | issue_tap "btn_back_dashboard"
sleep 2
dump 04-hub-both-rows.xml
shot 04-hub-both-rows.png

# Sanitize: scrub the bfonboard1 / password strings from any captured dumps
# so the evidence directory only retains redacted lengths for layout proof.
python3 - "$EVIDENCE_DIR" "$BOB_PKG" "$BOB_PWD" "$CAROL_PKG" "$CAROL_PWD" <<'PYEOF'
import os, sys, re
evdir = sys.argv[1]
secrets = [s for s in sys.argv[2:6] if s]
for name in os.listdir(evdir):
    if not name.endswith('.xml') and not name.endswith('.png'):
        continue
    path = os.path.join(evdir, name)
    if name.endswith('.xml'):
        data = open(path).read()
        for s in secrets:
            data = data.replace(s, f'[REDACTED_LEN_{len(s)}]')
        open(path, 'w').write(data)
    elif name.endswith('.png'):
        # On screenshot, package material may appear in the input field
        # briefly. The Compose injected fields autofill from the
        # InjectOnboardCredentials action — text is held in the field but
        # only for the connect screen; once OnboardHandshake begins, the
        # field text is preserved until save. Skip trusting screenshot
        # content; rely on hierarchy dumps for evidence.
        pass
PYEOF

# Helper: assert visible text
assert_text_in() {
  local needle="$1"; local file="$2"
  if grep -q "text=\"$needle\"" "$EVIDENCE_DIR/$file"; then
    log "[assert_text_in] FOUND '$needle' in $file"
  else
    log "[assert_text_in] MISSING '$needle' in $file"
    return 1
  fi
}

# Verify both rows exist.
assert_text_in "$BOB_LABEL" 04-hub-both-rows.xml
assert_text_in "$CAROL_LABEL" 04-hub-both-rows.xml

log "step 5: tap ${BOB_LABEL} -> dashboard must show ${BOB_LABEL}"
tap_label "$BOB_LABEL" | issue_tap "row $BOB_LABEL"
sleep 3
dump 05-after-tap-r2.xml
shot 05-after-tap-r2.png
assert_text_in "$BOB_LABEL" 05-after-tap-r2.xml
if ! python3 -c "
import re, html
data = open('$EVIDENCE_DIR/05-after-tap-r2.xml').read()
hdr = re.search(r'resource-id=\"dashboard_header_title\"[^>]*text=\"([^\"]+)\"', html.unescape(data))
if not hdr: raise SystemExit('no header title')
if hdr.group(1) != '$BOB_LABEL':
    print(f'header title: {hdr.group(1)} (expected ${BOB_LABEL})', file=__import__('sys').stderr)
    raise SystemExit(1)
"; then
  log "FAIL: dashboard header title is NOT ${BOB_LABEL} after tapping ${BOB_LABEL}'s row"
  exit 1
fi

log "step 6: back to hub"
tap_id "btn_back_dashboard" | issue_tap "btn_back_dashboard"
sleep 2

log "step 7: tap ${CAROL_LABEL} -> dashboard must show ${CAROL_LABEL}"
tap_label "$CAROL_LABEL" | issue_tap "row $CAROL_LABEL"
sleep 3
dump 07-after-tap-cross-003.xml
shot 07-after-tap-cross-003.png
assert_text_in "$CAROL_LABEL" 07-after-tap-cross-003.xml
if ! python3 -c "
import re, html
data = open('$EVIDENCE_DIR/07-after-tap-cross-003.xml').read()
hdr = re.search(r'resource-id=\"dashboard_header_title\"[^>]*text=\"([^\"]+)\"', html.unescape(data))
if not hdr: raise SystemExit('no header title')
if hdr.group(1) != '$CAROL_LABEL':
    print(f'header title: {hdr.group(1)} (expected ${CAROL_LABEL})', file=__import__('sys').stderr)
    raise SystemExit(1)
"; then
  log "FAIL: dashboard header title is NOT ${CAROL_LABEL} after tapping ${CAROL_LABEL}'s row"
  exit 1
fi

log "step 8: back to hub"
tap_id "btn_back_dashboard" | issue_tap "btn_back_dashboard"
sleep 2

log "step 9: tap ${BOB_LABEL} again -> dashboard must swap back to ${BOB_LABEL}"
tap_label "$BOB_LABEL" | issue_tap "row $BOB_LABEL again"
sleep 3
dump 09-after-tap-r2-again.xml
shot 09-after-tap-r2-again.png
assert_text_in "$BOB_LABEL" 09-after-tap-r2-again.xml
if ! python3 -c "
import re, html
data = open('$EVIDENCE_DIR/09-after-tap-r2-again.xml').read()
hdr = re.search(r'resource-id=\"dashboard_header_title\"[^>]*text=\"([^\"]+)\"', html.unescape(data))
if not hdr: raise SystemExit('no header title')
if hdr.group(1) != '$BOB_LABEL':
    print(f'header title: {hdr.group(1)} (expected ${BOB_LABEL})', file=__import__('sys').stderr)
    raise SystemExit(1)
"; then
  log "FAIL: dashboard header title swapped to wrong profile"
  exit 1
fi

log "step 10: redacted summary"
cat > "$EVIDENCE_DIR/redacted-summary.txt" <<EOF
scenario: mobile-android-hub-profile-row-routing-fix
device: emulator-5554 (API 35)
relay: ws://10.0.2.2:8194 (demo-stack)
redacted: package/password bytes replaced with [REDACTED_LEN_N] tokens

results:
  step 1 onboard test-r2:       OK
  step 3 onboard test-cross-003: OK
  step 4 hub has both rows:    $( grep -q 'text="'"$BOB_LABEL"'"' "$EVIDENCE_DIR/04-hub-both-rows.xml" && grep -q 'text="'"$CAROL_LABEL"'"' "$EVIDENCE_DIR/04-hub-both-rows.xml" && echo OK || echo FAIL )
  step 5 tap ${BOB_LABEL}  -> ${BOB_LABEL}:        OK
  step 7 tap ${CAROL_LABEL} -> ${CAROL_LABEL}:        OK
  step 9 tap ${BOB_LABEL} again -> ${BOB_LABEL}:     OK

artifact listing:
EOF
ls -1 "$EVIDENCE_DIR" | sed 's/^/  /' >> "$EVIDENCE_DIR/redacted-summary.txt"

echo
cat "$EVIDENCE_DIR/redacted-summary.txt"
echo
echo "=== ALL CHECKS PASSED ==="
