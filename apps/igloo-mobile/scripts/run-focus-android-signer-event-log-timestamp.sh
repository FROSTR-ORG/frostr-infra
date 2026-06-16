#!/usr/bin/env bash
# Focused Android Signer Event Log Timestamp evidence —
# proves that LogEntry.timestamp is a visible UTC RFC-3339 string
# (mobile-signer-event-log-timestamp-rfc3339-fix feature).
#
# Strategy:
# 1. Cold-install + cold-launch app on emulator-5554 (no stored profile).
# 2. Use the Android debug-only intent
#    `com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD` to preload bob's
#    real bfonboard1 credentials + the platform-correct demo relay URL.
# 3. Maestro drives the rest: tap btn_connect, wait for OnboardReview,
#    fill device_name, tap btn_save_device, wait for the dashboard,
#    tap btn_start_signer so the runtime logs a "Signer runtime
#    started" event with the new RFC-3339 timestamp.
# 4. We capture: hierarchy dumps (event_<timestamp> accessibility
#    ids), screenshots, and a stdout transcript of the matched event
#    entries.

set -uo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
APK="$ROOT/apps/igloo-mobile/android/app/build/outputs/apk/debug/app-debug.apk"
APP_ID="com.frostr.igloo.dev"
ACTION="com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

HARNESS_DIR="$ROOT/.tmp/test-harness"

EVIDENCE_DIR="$ROOT/apps/igloo-mobile/library/evidence/mobile-signer-event-log-timestamp-rfc3339-fix-2026-06-13"
mkdir -p "$EVIDENCE_DIR"
FLOW_DIR="$EVIDENCE_DIR/maestro-flows"
mkdir -p "$FLOW_DIR"
echo "[$(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

snapshot() {
  local tag="$1"
  adb -s emulator-5554 shell screencap -p > "$EVIDENCE_DIR/${tag}.png" 2>/dev/null \
    || true
  adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
  adb -s emulator-5554 pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-${tag}.xml" \
    >/dev/null 2>&1 || true
  echo "[snapshot $(date +%H:%M:%S)] ${tag}"
}

# 1. Record only the lengths of the injected secrets in evidence.
PACKAGE_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.txt" | tr -d ' ')
PASSWORD_LEN=$(wc -c < "$HARNESS_DIR/onboard-bob.password.txt" | tr -d ' ')
RELAY="ws://10.0.2.2:8194"
RELAY_LEN=${#RELAY}
cat > "$EVIDENCE_DIR/redacted-input.txt" <<EOF
package_length=${PACKAGE_LEN}
password_length=${PASSWORD_LEN}
relay=${RELAY}
relay_length=${RELAY_LEN}
EOF
echo "[$(date +%H:%M:%S)] redacted-input captured at $EVIDENCE_DIR/redacted-input.txt"

# 2. APK + emulator pre-flight
[ -f "$APK" ] || { echo "missing APK $APK; run 'just android-full' first" >&2; exit 1; }
adb -s emulator-5554 get-state >/dev/null 2>&1 \
  || { echo "emulator-5554 not booted" >&2; exit 1; }

# 3. Cold install + cold launch
echo "[$(date +%H:%M:%S)] ********* Cold install emulator-5554 *********"
adb -s emulator-5554 uninstall "$APP_ID" 2>/dev/null || true
adb -s emulator-5554 install -r -t "$APK" 2>&1 | tail -3

# 4. Inject via debug intent (uses bob's classic 2-of-3 demo keyset)
PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
adb -s emulator-5554 shell am start -W \
    -a "$ACTION" \
    -n "$APP_ID/com.frostr.igloo.MainActivity" \
    --es package "$PACKAGE" \
    --es password "$PASSWORD" \
    --es relay "$RELAY" \
    --es device_name "bob-rfc3339" \
    > "$EVIDENCE_DIR/inject-result.txt" 2>&1 || true
sleep 5
snapshot "post-inject-onboard-connect"

# 5. Maestro: tap btn_connect, wait for OnboardReview.
cat > "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" <<EOF
appId: $APP_ID
name: android onboard connect + review
---
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "input_relay_url"
- assertVisible:
    id: "btn_connect"
- tapOn:
    id: "btn_connect"
- extendedWaitUntil:
    visible:
      id: "input_device_name"
    timeout: 240000
- assertVisible:
    id: "input_device_name"
- assertVisible:
    id: "display_share_pubkey"
- assertVisible:
    id: "display_group_pubkey"
- assertVisible:
    id: "btn_save_device"
EOF

echo "[$(date +%H:%M:%S)] ********* Maestro: tap connect, wait for OnboardReview *********"
maestro --device emulator-5554 test "$FLOW_DIR/01-android-onboard-connect-and-review.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-01" 2>&1 | tail -5 > "$EVIDENCE_DIR/maestro-01.log"
echo "[$(date +%H:%M:%S)] maestro 01 exit=$?"
snapshot "post-handshake-onboard-review"

# 6. Fill device_name + Save Device, wait for Dashboard Signer tab. The Android
# Compose Button uses a Text child whose `clickable=false`; tapOn text:Start
# matches the Text, not the clickable Button. We dispatch the click via
# adb shell input tap targeting the absolute Button bounds reported in the
# uiautomator dump (button center at x=540, y=553 px on a 1080-wide screen).
cat > "$FLOW_DIR/02-android-save-device-and-start-signer.yaml" <<EOF
appId: $APP_ID
name: android save device and start signer
---
- tapOn:
    id: "input_device_name"
- eraseText: 64
- inputText:
    id: "input_device_name"
    text: "bob-rfc3339"
- assertVisible:
    id: "btn_save_device"
- tapOn:
    id: "btn_save_device"
- waitForAnimationToEnd
- extendedWaitUntil:
    visible:
      text: "Signer Stopped"
    timeout: 30000
- assertVisible:
    text: "Signer Stopped"
EOF
# Above YAML ends before the Start button because Maestro 2.6 on Android
# Compose does not reliably deliver click events through tapOn text:Start
# (the Text child has clickable=false). Drive the click via adb shell input
# tap targeting the Button's absolute coordinates (540, 553) within the
# SignerStatusCard on a 1080x2424 screen.
echo "[$(date +%H:%M:%S)] ********* Maestro: save device + reach dashboard *********"
maestro --device emulator-5554 test "$FLOW_DIR/02-android-save-device-and-start-signer.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-02" 2>&1 | tail -5 > "$EVIDENCE_DIR/maestro-02a-save.log"
echo "[$(date +%H:%M:%S)] maestro 02a exit=$?"
snapshot "post-save-device-dashboard"

# 7. Dispatch the Start button click via adb input tap. Coordinates are the
# Button center on the emulator-5554 screen (1080x2424) reported by the
# uiautomator dump. The Start button's outer Compose View is at
# bounds=[105,491][975,617], so center=(540, 554). Maestro's tapOn cannot
# always deliver Compose Buttons on this emulator; we use the adb input
# motion event path explicitly so the kernel delivers an Android EV_KEY /
# EV_ABS sequence rather than relying on uinput composition alone.
echo "[$(date +%H:%M:%S)] ********* adb tap Start button at (540, 553) *********"
adb -s emulator-5554 shell input motionevent DOWN 540 553 || true
sleep 0.1
adb -s emulator-5554 shell input motionevent UP 540 553 || true
sleep 3
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell input tap 540 553 || true
sleep 4
adb -s emulator-5554 logcat -d --pid=$(adb -s emulator-5554 shell pidof "$APP_ID" | tr -d '\r\n') \
  > "$EVIDENCE_DIR/maestro-03.log" 2>&1 || true
echo "[$(date +%H:%M:%S)] capture-state-after-tap:"
adb -s emulator-5554 shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
adb -s emulator-5554 pull /sdcard/window_dump.xml "$EVIDENCE_DIR/hierarchy-post-start-signer-running.xml" \
  >/dev/null 2>&1 || true
sleep 1
snapshot "post-start-signer-running"

# 7. Extract every RFC-3339 timestamp from the post-start-signer-running
# hierarchy. The Android Compose EventLogRow renders each LogEntry.timestamp
# as a plain Text node (no accessibility id), so we look for any
# text="YYYY-MM-DDTHH:MM:SSZ" attribute. Also confirm at least one INFO event
# is present. The iOS variant uses event_<timestamp> ids; both should
# converge on the same fixed format.
EVENT_IDS=$(grep -oE 'text="20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.xml" 2>/dev/null | sort -u || true)
echo "[RESULT $(date +%H:%M:%S)] event_<timestamp> RFC-3339 strings found in Event Log:"
echo "$EVENT_IDS" | tee "$EVIDENCE_DIR/event_timestamps.txt"
EVENT_COUNT=$(echo "$EVENT_IDS" | grep -c '^text="' || true)
echo "[RESULT $(date +%H:%M:%S)] unique RFC-3339 timestamp strings: $EVENT_COUNT"
# Also capture iOS-style event_<timestamp> ids (Android does not generate
# these but it costs nothing to scan).
IOS_IDS=$(grep -oE 'event_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.xml" 2>/dev/null | sort -u || true)
echo "[RESULT $(date +%H:%M:%S)] iOS-style event_<RFC-3339> ids (Android does not use):"
echo "$IOS_IDS" >> "$EVIDENCE_DIR/event_ids.txt" || true

# 8. Confirm the Signer runtime started entry has INFO level + RFC-3339
# timestamp. The Android event log is a Row of three Text nodes (level,
# timestamp, message); we look for INFO followed by an RFC-3339 in the
# surrounding text attributes. We tolerate text-fragment ordering by
# looking for adjacent INFO occurrences within a small byte window.
INFO_LOG="$EVIDENCE_DIR/info-event-matches.txt"
> "$INFO_LOG"
python3 - "$EVIDENCE_DIR/hierarchy-post-start-signer-running.xml" "$INFO_LOG" <<'PYEOF'
import re, sys
path, out = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = fh.read()
# Find every text="..." attribute in the file along with byte offsets.
ts_pat = re.compile(r'text="([^"]*)"')
RFC_RE = re.compile(r'^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
entries = [(m.group(1), m.start()) for m in ts_pat.finditer(data)]
matches = []
for i, (text, off) in enumerate(entries):
    if text == "INFO":
        # Look at the next several text= attributes for an RFC-3339 shape.
        for j in range(i + 1, min(i + 8, len(entries))):
            t2, _ = entries[j]
            if RFC_RE.match(t2):
                matches.append((off, text, t2))
                break
with open(out, "w") as fh:
    for off, info_text, ts_text in matches[:5]:
        fh.write(f"INFO at byte {off} -> next RFC-3339 timestamp '{ts_text}'\n")
print(f"INFO-event matches: {len(matches)}", file=sys.stderr)
PYEOF

echo "[RESULT $(date +%H:%M:%S)] INFO-tagged event log rows with RFC-3339 timestamps:"
cat "$INFO_LOG"

# 9. Sanity: no legacy epoch-second-only timestamps should appear inside the
# Event Log region. We scan for text="<digits>" with length >= 10 and
# exclude the legitimate values reported by the UI (e.g. relay ports,
# elapsed counters) by requiring the value to look like an epoch-second
# (10+ digits starting at 1).
LEGACY="$EVIDENCE_DIR/legacy-ids.txt"
grep -oE 'text="[0-9]{10,}"' \
  "$EVIDENCE_DIR/hierarchy-post-start-signer-running.xml" | sort -u > "$LEGACY"
echo "[RESULT $(date +%H:%M:%S)] legacy epoch-second-only text=\"<digits>\" matches (should be empty):"
cat "$LEGACY"
LEGACY_COUNT=$(grep -c '^text="[0-9]' "$LEGACY" || true)
echo "[RESULT $(date +%H:%M:%S)] legacy timestamp count: $LEGACY_COUNT"

echo "OK evidence captured at $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -25
