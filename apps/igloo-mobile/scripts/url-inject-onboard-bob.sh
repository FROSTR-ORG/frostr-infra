#!/usr/bin/env bash
# Focused diagnostic flow that:
# 1. Cold-installs app on RMP iPhone 15
# 2. Uses Maestro to navigate Hub -> OnboardEntry -> OnboardConnect
# 3. Invokes xcrun simctl openurl with valid bob credentials
# 4. Captures screenshots/hierarchy before and after the URL scheme injection
# 5. Waits long enough to verify the OnboardReview transition (not a 300s hang)
#
# This is a one-shot diagnostic; not a permanent test flow.
set -euo pipefail

source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
EVIDENCE_DIR="/tmp/igloo-mobile-evidence-onboardfix-$(date +%s)"
mkdir -p "$EVIDENCE_DIR"

UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_ID="com.frostr.igloo.dev"
APP_BUNDLE="/Users/plebdev/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"

echo "[diag $(date +%H:%M:%S)] evidence: $EVIDENCE_DIR"

# 1. Cold install: uninstall + install + verify Info.plist
xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$APP_ID" app)
# URL scheme is nested under CFBundleURLTypes : CFBundleURLTypes : 0 : CFBundleURLSchemes.
# PlistBuddy traversal:
#   Print :CFBundleURLTypes returns Array { Dict { CFBundleURLSchemes = Array { ... } } }
#   Print :CFBundleURLTypes:0:CFBundleURLSchemes returns just the schemes.
URL_SCHEMES=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "$CONTAINER/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Print :CFBundleURLSchemes" "$CONTAINER/Info.plist" 2>/dev/null \
  || echo "igloo")
echo "$URL_SCHEMES" > "$EVIDENCE_DIR/url-scheme.txt"
echo "[diag $(date +%H:%M:%S)] installed; url-schemes captured to url-scheme.txt"

# 2. Construct URL with current redacted bob credentials.
# The relay query parameter is URL-encoded only (NOT base64) — Swift's
# igloo://test-inject handler expects the raw relay URL string, see
# ios/Sources/App.swift::onOpenURL.
PACKAGE_B64=$(cat "$ROOT/.tmp/test-harness/onboard-bob.txt" | python3 -c "import sys, base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())")
PASSWORD=$(tr -d '\r\n' < "$ROOT/.tmp/test-harness/onboard-bob.password.txt")
RELAY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('ws://127.0.0.1:8194'))")
URL="igloo://test-inject?package=${PACKAGE_B64}&password=${PASSWORD}&relay=${RELAY_ENC}"
echo "[diag $(date +%H:%M:%S)] url length=${#URL}; relay_decoded_value=ws://127.0.0.1:8194"

# 3. Prelaunch app to hub; maestro will navigate to OnboardConnect
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null 2>&1
sleep 3

# 4. Navigate Hub -> OnboardEntry -> OnboardConnect via Maestro (skipping package input).
# We use the existing flows that exercise just navigation is too script-heavy;
# instead, use a tiny inline Maestro flow that performs the navigation, then we
# inject the URL scheme and observe the result.
cat > "$EVIDENCE_DIR/navigate-pre-inject.yaml" <<EOF
appId: $APP_ID
name: navigate-pre-inject
---
- assertVisible:
    text: "Igloo"
- tapOn:
    text: "Onboard Device"
- scrollUntilVisible:
    element:
      id: "btn_connect_entry"
    timeout: 20000
- tapOn:
    id: "btn_connect_entry"
- scrollUntilVisible:
    element:
      id: "input_package"
    timeout: 20000
- assertVisible:
    id: "input_package"
- assertVisible:
    id: "input_password"
- assertVisible:
    id: "btn_connect"
EOF

maestro --device "$UDID" test "$EVIDENCE_DIR/navigate-pre-inject.yaml" \
  --debug-output "$EVIDENCE_DIR/maestro-pre-inject" 2>&1 | tail -10

# 5. Capture pre-injection state
xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/pre-inject-onboard-connect.png" 2>/dev/null

# 6. Inject URL scheme (passes credentials + relay)
echo "[diag $(date +%H:%M:%S)] invoking openurl with valid bob at $(date +%H:%M:%S)"
xcrun simctl openurl "$UDID" "$URL" 2>&1 | head

# 7. Wait for handshake to complete (Rust live test passed in ~7s for bob)
sleep 12

# 8. Capture post-injection state (hierarchy + screenshot).
# We expect EITHER OnboardReview (input_device_name visible) for valid creds,
# OR a concrete onboard_error label for wrong/redacted creds.
xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/post-inject-12s.png" 2>/dev/null
# Maestro 2.6.0 uses a global --device flag for the hierarchy subcommand.
# `maestro hierarchy --device $UDID` is rejected with "Unknown options" so
# we hoist the flag before the subcommand.
maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/post-inject-hierarchy.txt" 2>&1 || true

echo "[diag $(date +%H:%M:%S)] post-injection capture done"

# 9. Look for evidence of success (input_device_name) or error (onboard_error)
if grep -q "input_device_name" "$EVIDENCE_DIR/post-inject-hierarchy.txt" 2>/dev/null; then
    echo "[RESULT $(date +%H:%M:%S)] SUCCESS: OnboardReview reached (input_device_name visible)"
elif grep -q "onboard_error" "$EVIDENCE_DIR/post-inject-hierarchy.txt" 2>/dev/null; then
    echo "[RESULT $(date +%H:%M:%S)] FAILURE: onboard_error shown (concrete outcome)"
elif grep -q "onboard_password\|input_password" "$EVIDENCE_DIR/post-inject-hierarchy.txt" 2>/dev/null; then
    echo "[RESULT $(date +%H:%M:%S)] FAILURE: still on OnboardConnect after 12s (no-review no-error)"
else
    echo "[RESULT $(date +%H:%M:%S)] UNKNOWN: see hierarchy dump"
    head -50 "$EVIDENCE_DIR/post-inject-hierarchy.txt" 2>/dev/null
fi

echo "[diag $(date +%H:%M:%S)] done; evidence in $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/" | head -20
