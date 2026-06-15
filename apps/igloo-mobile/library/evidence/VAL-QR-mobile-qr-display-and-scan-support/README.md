# mobile-qr-display-and-scan-support evidence

This evidence directory supports the `mobile-qr-display-and-scan-support`
feature for the igloo-mobile `keyset-lifecycle` milestone. The feature
implements the QR affordances used by the mobile flows:

- **QR display** for bfonboard distribution with screenshot-decodable payload
  (Create Keyset Distribute step's QrCodeModal on iOS + QrDialog / QrImage on
  Android — already covered by the prior Create Keyset feature commit
  `3a3ceba` and re-validated here).
- **Scan entry** on the OnboardDevice connect screen with graceful
  degradation when the device has no working rear camera.
- **Paste fallback** in the scan entry that completes the same flow path
  end-to-end (mobile-qr-display-and-scan-support).

## Captured artifacts

| File | Source | Notes |
|------|--------|-------|
| `ios-hub.png` | iOS RMP iPhone 15, Maestro screenshot | Fresh hub after install + launch. |
| `ios-scan-fallback.png` | iOS RMP iPhone 15 via Maestro run | iOS QR scanner sheet in the camera-unavailable fallback branch — `qr_scan_camera_unavailable_title` / `input_qr_fallback_package` / `btn_qr_paste_clipboard` / `btn_qr_scan_back` all visible. |
| `android-hub.png` | rmp_api35 via adb screencap | Fresh hub after install + launch. |
| `android-scan-fallback.png` | rmp_api35 via adb screencap | Android QrScannerDialog rendering the camera-unavailable fallback branch with manual entry field, "Paste from Clipboard", and a "Use This Package" confirmation. |
| `android-dashboard.png` | rmp_api35 via adb screencap | Dashboard arrived through the QR paste-fallback → Connect → handshake → Save path (`flows/qr-scan-android.yaml`). |
| `android-save-result.png` | rmp_api35 via Maestro run | Intermediate Save → Dashboard screenshot captured during the QR paste-fallback flow. |

## Maestro flow files

`apps/igloo-mobile/flows/qr-scan-android.yaml` and
`flows/qr-scan-ios.yaml` exercise the QR paste-fallback end-to-end against a
real demo relay (`ws://127.0.0.1:8194` on iOS, `ws://10.0.2.2:8194` on
Android) using bob credentials from `make demo-onboard`. Both flows
operate on the `com.frostr.igloo.dev` debug app id and use the standard
`ONBOARD_PACKAGE` / `ONBOARD_PASSWORD` / `RELAY_URL` Maestro `-e` flags
for runtime credential loading.

## How to re-run

```bash
# Start the demo stack once.
source ~/.config/frostr/rmp-mobile-env.zsh
DEV_RELAY_PORT=8194 make demo-start
DEV_RELAY_PORT=8194 make demo-onboard

# Rebuild the app + reinstall onto both simulators.
cd apps/igloo-mobile
just android-full              # cross-compile + assembleDebug
./tools/xcode-run xcodebuild build \
  -project ios/IglooMobile.xcodeproj -scheme IglooMobile \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/IglooMobile-*/Build/Products/Debug-iphonesimulator/IglooMobile.app
adb -s emulator-5554 install -r android/app/build/outputs/apk/debug/app-debug.apk

# Run the focused QR scanner / paste-fallback gates.
cd apps/igloo-mobile
BOB_PKG=$(cat /Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness/onboard-bob.txt)
BOB_PWD=$(cat /Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness/onboard-bob.password.txt)

maestro --device 4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0 \
  test flows/qr-scan-ios.yaml \
  -e ONBOARD_PACKAGE="$BOB_PKG" \
  -e ONBOARD_PASSWORD="$BOB_PWD" \
  -e RELAY_URL="ws://127.0.0.1:8194"

maestro --device emulator-5554 \
  test flows/qr-scan-android.yaml \
  -e ONBOARD_PACKAGE="$BOB_PKG" \
  -e ONBOARD_PASSWORD="$BOB_PWD" \
  -e RELAY_URL="ws://10.0.2.2:8194"
```

## Screenshot-decode recipe

The `library/user-testing.md` QR Decode Recipe covers `zbarimg` decoding of
the QrCodeModal / QrDialog screenshot. Run on
`apps/igloo-mobile/library/evidence/VAL-CREATE-015-*` etc. to confirm the
display bits remain screenshot-decodable.

## Secret safety

No secrets, package bytes, passwords, decrypted shares, or key material
are persisted in this directory. The Maestro flow files use Maestro `-e`
runtime credential loading; the captured screenshots only contain public
identity elements (device name, short profile id, public keys) which are
non-secret by FROSTR convention.
