#!/usr/bin/env bash
# Diagnostic: capture pre-tap snapshot AFTER paste to confirm input_package state.
# Useful to diagnose whether @State packageText is actually empty at btn_connect tap time.

set -uo pipefail
source ~/.config/frostr/rmp-mobile-env.zsh

ROOT="/Users/plebdev/Desktop/Projects/frostr-infra"
UDID="4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0"
APP_BUNDLE="/Users/plebdev/Library/Developer/Xcode/DerivedData/IglooMobile-faosiupznygiukgrbhnfhsccmhkg/Build/Products/Debug-iphonesimulator/IglooMobile.app"
APP_ID="com.frostr.igloo.dev"
HARNESS_DIR="$ROOT/.tmp/test-harness"
EVIDENCE_DIR="/tmp/igloo-mobile-diag-pre-tap-$(date +%s)"
mkdir -p "$EVIDENCE_DIR"

[ -f "$HARNESS_DIR/onboard-bob.txt" ] || { echo "missing bob credentials" >&2; exit 1; }

PACKAGE="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.txt")"
PASSWORD="$(tr -d '\r\n' < "$HARNESS_DIR/onboard-bob.password.txt")"
printf "$PACKAGE" | xcrun simctl pbcopy "$UDID"

xcrun simctl uninstall "$UDID" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_BUNDLE" >/dev/null
SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch "$UDID" "$APP_ID" >/dev/null
sleep 4

cat > "$EVIDENCE_DIR/diag-pre-tap.yaml" <<EOF
appId: $APP_ID
name: diag pre-tap - bob iOS
---
- scrollUntilVisible:
    element:
      text: "Igloo"
    timeout: 60000
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
- tapOn:
    id: "input_relay_url"
- eraseText: 80
- inputText:
    id: "input_relay_url"
    text: "ws://127.0.0.1:8194"
- tapOn:
    id: "input_package"
- eraseText: 2000
- setClipboard: "\${ONBOARD_PACKAGE}"
- tapOn:
    id: "btn_paste_package"
- waitForAnimationToEnd
- runFlow:
    when:
      visible: "Allow Paste"
    commands:
      - tapOn: "Allow Paste"
- runFlow:
    when:
      visible: "Allow"
    commands:
      - tapOn: "Allow"
- waitForAnimationToEnd
- tapOn:
    id: "input_password"
- eraseText: 80
- setClipboard: "\${ONBOARD_PASSWORD}"
- pasteText
- waitForAnimationToEnd
- waitForAnimationToEnd
EOF

maestro --device "$UDID" test "$EVIDENCE_DIR/diag-pre-tap.yaml" \
  -e ONBOARD_PACKAGE="$PACKAGE" \
  -e ONBOARD_PASSWORD="$PASSWORD" \
  --debug-output "$EVIDENCE_DIR/maestro-debug" 2>&1 | tail -10

xcrun simctl io "$UDID" screenshot "$EVIDENCE_DIR/precapture.png" 2>/dev/null
maestro --device "$UDID" hierarchy > "$EVIDENCE_DIR/precapture-hierarchy.txt" 2>&1 || true

# Inspect input_package's value
python3 -c "
import json
with open('$EVIDENCE_DIR/precapture-hierarchy.txt') as f:
    data = json.load(f)
def walk(node):
    attrs = node.get('attributes', {})
    rid = attrs.get('resource-id', '')
    if rid == 'input_package':
        v = attrs.get('value', '')
        print(f'input_package value (len={len(v)}):')
        print(v[:120] + ('...' if len(v) > 120 else ''))
        print('START' if v.startswith('bfonboard') else f'DOES NOT start with bfonboard, starts with: {v[:30]!r}')
    for child in node.get('children', []):
        walk(child)
walk(data)
"

if [ -f /tmp/paste_action_result.txt ]; then
    echo "--- /tmp/paste_action_result.txt ---"
    cat /tmp/paste_action_result.txt
fi

ls -la "$EVIDENCE_DIR/" | head -10
