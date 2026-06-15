#!/usr/bin/env bash
# Focused Android export-artifact validator for VAL-SET-006/007/008/015.
#
# Drives the password-gated Copy Profile / Copy Share buttons on a
# sign-ready bob profile (typically captured during the earlier
# `mobile-signer-runtime-restoring-readiness-fix` and
# `mobile-onboard-error-path-hardening-fix` runs). The Android API 35
# emulator refuses `adb shell cmd clipboard get-text`, so the proof
# relies on the app-internal paste-back path that
# VAL-SIGNER-017 also depends on:
#
#   1. Tap Settings → Copy Profile → fill the export password → confirm.
#   2. Navigate to Load Profile → Import → tap the field → tap
#      btn_paste_package → capture a redacted uiautomator dump.
#   3. Same leg for Copy Share.
#
# Preconditions:
#   * Emulator-5554 booted with the current `app-debug.apk` installed.
#   * Demo stack running on ws://10.0.2.2:8194.
#   * A sign-ready bob profile already on the device.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APPS="$ROOT/apps/igloo-mobile"

APK="$APPS/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
SERIAL="emulator-5554"
RELAY="ws://10.0.2.2:8194"

EVIDENCE_DIR="$APPS/library/evidence/mobile-export-artifact-validation/android"
mkdir -p "$EVIDENCE_DIR"
echo "[focus-export-android $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

EXPORT_PASSWORD="validator-export-pwd-001"

# Pre-flight
[ -f "$APK" ] || { echo "[focus-export-android] missing $APK; run 'just android-full' first" >&2; exit 1; }
adb -s "$SERIAL" get-state >/dev/null 2>&1 \
  || { echo "[focus-export-android] emulator-5554 not booted" >&2; exit 1; }
adb -s "$SERIAL" shell toybox nc -z 10.0.2.2 8194 \
  || { echo "[focus-export-android] relay unreachable from emulator; run make demo-start first" >&2; exit 1; }

snapshot() {
  local tag="$1"
  adb -s "$SERIAL" shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  # Redact long text fields in the dump.
  if [ -f "$EVIDENCE_DIR/hierarchy-${tag}.xml" ]; then
    python3 - <<PYEOF
import re
path = "$EVIDENCE_DIR/hierarchy-${tag}.xml"
with open(path) as f:
    data = f.read()
data = re.sub(r'text="([^"]{50,})"', lambda m: f'text="[REDACTED-{len(m.group(1))}chars]"', data)
data = re.sub(r'content-desc="([^"]{50,})"', lambda m: f'content-desc="[REDACTED-{len(m.group(1))}chars]"', data)
with open("${EVIDENCE_DIR}/redacted-hierarchy-${tag}.xml", "w") as f:
    f.write(data)
PYEOF
  fi
  echo "[focus-export-android snapshot $(date +%H:%M:%S)] ${tag}"
}

# 1. Launch (no clear, to keep the bob profile).
adb -s "$SERIAL" shell am force-stop "$APP_ID" 2>/dev/null || true
sleep 1
adb -s "$SERIAL" shell am start -n "$APP_ID/com.frostr.igloo.MainActivity" >/dev/null
sleep 3
snapshot "01-launch"

# 2. Replay each export leg separately so paste-back captures the
#    current clipboard slot. Adb cmd clipboard get-text is unsupported
#    on Android API 35; we let the app's paste affordance do the work
#    and capture the redacted dump.
cat > "$EVIDENCE_DIR/focus-export-profile.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: focus export profile (android)
tags: ["flow", "mobile-export-artifact-flow-validation-unblocker"]
---
- assertVisible:
    text: Igloo
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 15000
- tapOn:
    id: "tab_settings"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_copy_profile"
    timeout: 10000
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
    text: "${EXPORT_PASSWORD}"
- tapOn:
    id: "input_export_password_confirm"
- eraseText: 64
- inputText:
    id: "input_export_password_confirm"
    text: "${EXPORT_PASSWORD}"
- tapOn:
    id: "btn_export_confirm"
- waitForAnimationToEnd
- tapOn:
    text: "Cancel"
    optional: true
- tapOn:
    id: "btn_back_dashboard"
YAML

adb -s "$SERIAL" shell am force-stop "$APP_ID" 2>/dev/null || true
sleep 1
adb -s "$SERIAL" shell am start -n "$APP_ID/com.frostr.igloo.MainActivity" >/dev/null
sleep 3
maestro --device "$SERIAL" test "$EVIDENCE_DIR/focus-export-profile.yaml" \
  -e EXPORT_PASSWORD="$EXPORT_PASSWORD" \
  --debug-output "$EVIDENCE_DIR/profile-maestro-debug" 2>&1 | tail -10 || true
snapshot "02-export-profile"

# 3. Capture the clipboard contents via paste-back into a known app
#    text field. We navigate to Load Profile → Import then tap
#    btn_paste_package and capture the redacted dump.
cat > "$EVIDENCE_DIR/focus-pasteback-profile.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: paste back profile export (android)
tags: ["flow", "mobile-export-artifact-flow-validation-unblocker"]
---
- tapOn:
    text: Load Profile
- scrollUntilVisible:
    element:
      id: "tile_load_import"
    timeout: 15000
- tapOn:
    id: "tile_load_import"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 15000
- tapOn:
    id: "input_package"
- eraseText: 4000
- scrollUntilVisible:
    element:
      id: "btn_paste_package"
    timeout: 10000
- tapOn:
    id: "btn_paste_package"
- waitForAnimationToEnd
- tapOn:
    text: "Allow"
    optional: true
- waitForAnimationToEnd
YAML
maestro --device "$SERIAL" test "$EVIDENCE_DIR/focus-pasteback-profile.yaml" \
  --debug-output "$EVIDENCE_DIR/pasteback-profile-debug" 2>&1 | tail -5 || true
snapshot "03-pasteback-profile"

# Read the dumped value from pasteback via the on-screen text. The text
# field shows the redacted hierarchy dump; we only emit length + prefix.
PKG_LEN=$(python3 - <<PYEOF
import re, os
xml_path = "$EVIDENCE_DIR/hierarchy-03-pasteback-profile.xml"
if not os.path.exists(xml_path):
    print("missing")
else:
    with open(xml_path) as f:
        data = f.read()
# Find a text node whose content-desc or text contains a string of length 690-2000
m = re.search(r'text="([a-z0-9]{50,4000})"', data)
if not m:
    m = re.search(r'text="(\[REDACTED-[0-9]+chars\])"', data)
    if m:
        print(m.group(1))
    else:
        print("no_long_text")
else:
    raw = m.group(1)
    if raw.startswith("[REDACTED-"):
        print(raw)
    else:
        print(f"prefix={raw[:12]};length={len(raw)}")
PYEOF
)
echo "[focus-export-android RESULT $(date +%H:%M:%S)] bfprofile_pasteback=${PKG_LEN}"

# 4. Repeat for Copy Share.
adb -s "$SERIAL" shell am force-stop "$APP_ID" 2>/dev/null || true
sleep 1
adb -s "$SERIAL" shell am start -n "$APP_ID/com.frostr.igloo.MainActivity" >/dev/null
sleep 3

cat > "$EVIDENCE_DIR/focus-export-share.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: focus export share (android)
tags: ["flow", "mobile-export-artifact-flow-validation-unblocker"]
---
- assertVisible:
    text: Igloo
- scrollUntilVisible:
    element:
      id: "tab_settings"
    timeout: 15000
- tapOn:
    id: "tab_settings"
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: "btn_copy_share"
    timeout: 10000
- tapOn:
    id: "btn_copy_share"
- waitForAnimationToEnd
- assertVisible:
    id: "input_export_password"
- tapOn:
    id: "input_export_password"
- eraseText: 64
- inputText:
    id: "input_export_password"
    text: "${EXPORT_PASSWORD}"
- tapOn:
    id: "input_export_password_confirm"
- eraseText: 64
- inputText:
    id: "input_export_password_confirm"
    text: "${EXPORT_PASSWORD}"
- tapOn:
    id: "btn_export_confirm"
- waitForAnimationToEnd
YAML
maestro --device "$SERIAL" test "$EVIDENCE_DIR/focus-export-share.yaml" \
  -e EXPORT_PASSWORD="$EXPORT_PASSWORD" \
  --debug-output "$EVIDENCE_DIR/share-maestro-debug" 2>&1 | tail -10 || true
snapshot "04-export-share"

cat > "$EVIDENCE_DIR/focus-pasteback-share.yaml" <<'YAML'
appId: com.frostr.igloo.dev
name: paste back share export (android)
tags: ["flow", "mobile-export-artifact-flow-validation-unblocker"]
---
- tapOn:
    text: Load Profile
- scrollUntilVisible:
    element:
      id: "tile_load_import"
    timeout: 15000
- tapOn:
    id: "tile_load_import"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 15000
- tapOn:
    id: "input_package"
- eraseText: 4000
- scrollUntilVisible:
    element:
      id: "btn_paste_package"
    timeout: 10000
- tapOn:
    id: "btn_paste_package"
- waitForAnimationToEnd
- tapOn:
    text: "Allow"
    optional: true
- waitForAnimationToEnd
YAML
maestro --device "$SERIAL" test "$EVIDENCE_DIR/focus-pasteback-share.yaml" \
  --debug-output "$EVIDENCE_DIR/pasteback-share-debug" 2>&1 | tail -5 || true
snapshot "05-pasteback-share"

SHARE_LEN=$(python3 - <<PYEOF
import re, os
xml_path = "$EVIDENCE_DIR/hierarchy-05-pasteback-share.xml"
if not os.path.exists(xml_path):
    print("missing")
else:
    with open(xml_path) as f:
        data = f.read()
m = re.search(r'text="([a-z0-9]{50,4000})"', data)
if not m:
    m = re.search(r'text="(\[REDACTED-[0-9]+chars\])"', data)
    if m:
        print(m.group(1))
    else:
        print("no_long_text")
else:
    raw = m.group(1)
    if raw.startswith("[REDACTED-"):
        print(raw)
    else:
        print(f"prefix={raw[:12]};length={len(raw)}")
PYEOF
)
echo "[focus-export-android RESULT $(date +%H:%M:%S)] bfshare_pasteback=${SHARE_LEN}"

# 5. Final summary.
cat > "$EVIDENCE_DIR/summary.txt" <<EOF
export_password_length=${#EXPORT_PASSWORD}
bfprofile_pasteback=${PKG_LEN}
bfshare_pasteback=${SHARE_LEN}
EOF

echo "[focus-export-android RESULT $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -40
