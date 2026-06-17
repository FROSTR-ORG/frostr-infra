# User Testing

Testing surface, validation prerequisites, tool recipes, and resource guidance
for Igloo Mobile validators.

## Continuation Update - 2026-06-17

This file was restored from the original Factory mission after the app tree was
reconstructed. Older round notes below are intentionally preserved as validator
history, but several blockers they mention are now closed in this checkout:

- Cross-flow persistence is green on iOS and Android via
  `just focus-cross-flow-ios` and `just focus-cross-flow-android`.
- Export and Load Profile artifact validators are green on both shells via
  `just focus-ios-export`, `just focus-android-export`,
  `just focus-ios-load-artifacts`, and `just focus-android-load-artifacts`.
- Create Keyset has iOS URL-scheme and Android debug-intent proof.
- Rotate Share has native/live proof on both shells.
- QR scan/paste fallback and Create Keyset QR display/decode are green on both
  shells.
- Cross-platform keyset/rotation interop has fresh Rust byte-contract proof in
  `library/evidence/mobile-cross-platform-keyset-and-rotation-interop-2026-06-17-150201/`.

Use `library/RECOVERY-HANDOFF.md` as the live mission ledger before treating a
historic blocker below as current.

---

## Validation Surface

Validate through the real native apps:
- **iOS Simulator:** debug bundle id `com.frostr.igloo.dev`.
- **Android emulator:** AVD `rmp_api35`, debug app id `com.frostr.igloo.dev`.
- **Demo stack:** relay + alice co-signer on port `8194`.

All contract assertions must pass on both iOS and Android unless the assertion
explicitly spans both devices or names one platform.

## Validation Prerequisites

Source env first:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
```

Start and verify demo stack:

```bash
cd /Users/plebdev/Desktop/Projects/frostr-infra
DEV_RELAY_PORT=8194 make demo-start
DEV_RELAY_PORT=8194 make demo-onboard
python3 -c "import socket; s=socket.create_connection(('127.0.0.1',8194),2); s.close()"
```

Relay URLs:
- iOS Simulator: `ws://127.0.0.1:8194`
- Android emulator: `ws://10.0.2.2:8194`

Real onboard credentials:
- `make demo-onboard` prints bob/carol `bfonboard1` packages and passwords.
- Use distinct identities per device when both devices are online at once.

## Onboarding Flow Validation Recipe

Onboarding assertions require the live demo relay and alice co-signer. Do not
accept local package decode, fake group keys, shell/FFI stubs, or package-byte
material as proof.

Generate credentials from the repo root:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
cd /Users/plebdev/Desktop/Projects/frostr-infra
DEV_RELAY_PORT=8194 make demo-start
DEV_RELAY_PORT=8194 make demo-onboard
```

Use bob on iOS and carol on Android so simultaneous validation has distinct
shares:

```bash
cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile
maestro --device <ios-udid> test \
  -e ONBOARD_PACKAGE="$(cat ../../.tmp/test-harness/onboard-bob.txt)" \
  -e ONBOARD_PASSWORD="$(tr -d '\r\n' < ../../.tmp/test-harness/onboard-bob.password.txt)" \
  -e RELAY_URL="ws://127.0.0.1:8194" \
  flows/onboard-ios.yaml \
  --debug-output /tmp/igloo-mobile-maestro-onboard-ios

maestro --device emulator-5554 test \
  -e ONBOARD_PACKAGE="$(cat ../../.tmp/test-harness/onboard-carol.txt)" \
  -e ONBOARD_PASSWORD="$(tr -d '\r\n' < ../../.tmp/test-harness/onboard-carol.password.txt)" \
  -e RELAY_URL="ws://10.0.2.2:8194" \
  flows/onboard-android.yaml \
  --debug-output /tmp/igloo-mobile-maestro-onboard-android
```

Before running onboarding flows, prove each device has a freshly installed app
from the current build. Uninstall/install on Android, install the current
DerivedData `.app` on iOS, launch `com.frostr.igloo.dev`, and capture a
hierarchy/screenshot after tapping `Onboard Device`. The expected path is:

```text
Hub -> OnboardEntry (btn_connect_entry) -> OnboardConnect (input_package)
```

Onboarding Maestro flows should use credentials from `.tmp/test-harness` or
explicit `-e` variables supplied by the command. Do not depend on missing local
scripts or hardcoded `bfonboard1` packages from previous demo-stack runs.

Before Maestro, run a no-UI decode gate using the app's Rust/frostr-utils path
against current `.tmp/test-harness` files. Expected evidence should show both
bob and carol decode successfully, with package length `690`, password length
`32`, share secret length `64`, peer pubkey length `64`, and at least one
relay. If the decode gate fails, regenerate credentials with `make demo-stop`,
`make demo-start`, and `make demo-onboard` before testing the UI.

For text entry, tap the actual field selector, clear existing content, then
paste long secrets via clipboard:

```yaml
- tapOn:
    id: "input_package"
- eraseText: 1000
- setClipboard: "${ONBOARD_PACKAGE}"
- pasteText

- tapOn:
    id: "input_password"
- eraseText: 64
- setClipboard: "${ONBOARD_PASSWORD}"
- pasteText

- tapOn:
    id: "input_relay_url"
- eraseText: 64
- inputText: "ws://10.0.2.2:8194"
```

Do not tap labels as a proxy for focusing fields. Android Compose fields must
be standard/focusable controls with `testTagsAsResourceId` exposed so Maestro
can target them by id. Do not use inline `inputText: { id, text }` for
onboarding package/password entry unless the exact Maestro version and runtime
behavior have been proven. Do not append over prefilled relay URL defaults.
Do not assume Maestro 2.6.0 expands `${VAR}` inside `setClipboard` or
`pasteText`; workers observed literal `${VAR}` being pasted. If long package
or password entry needs runtime credentials, use a proven pre-run clipboard or
scripted credential-loading path from current `.tmp/test-harness` outputs and
verify the app did not receive literal variable names. Never commit hardcoded
demo packages, passwords, or secret-like fixture values in flow YAML.

Android long credential transport is currently blocked through Maestro 2.6.0
and raw adb text entry: `setClipboard` plus `pasteText` can fail with
`io.grpc.StatusRuntimeException: DEADLINE_EXCEEDED`, `inputText` can hit the
same driver timeout, and `adb shell input text` truncates far below the
690-character `bfonboard1` package length. Do not spend another validation
retry on those transport paths for VAL-ONBOARD. Use or implement an app-owned,
debug-gated Android injection/preload path that accepts package, password,
relay, and optional device name from current `.tmp/test-harness` credentials,
updates the normal OnboardConnect state, records only lengths/redacted status,
and then continues through the normal Connect/review/save flow.
On iOS, Maestro `launchApp.env` does not set app process environment variables;
it only supplies Maestro flow variables. To activate debug-gated app behavior,
prelaunch with `xcrun simctl launch` and `SIMCTL_CHILD_<NAME>=<value>`, then
run a Maestro flow that does not call `launchApp`, or use an XCUITest target
with `XCUIApplication.launchEnvironment`.
Use `SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 xcrun simctl launch ...`, not an
`--env` flag. Maestro device-name detection can become flaky after extended
iOS simulator use; if names disappear, target the RMP iPhone 15 UDID directly
or restart Simulator once before rerunning a bounded gate.
If Maestro reports that Java/JRE is missing, source
`~/.config/frostr/rmp-mobile-env.zsh` and set
`JAVA_HOME=/opt/homebrew/opt/openjdk@17` before rerunning the bounded gate.
If `xcrun simctl launch` is unavailable even though Simulator is installed,
use `/Applications/Xcode.app/Contents/Developer/usr/bin/simctl` directly.

Known limitation and current workaround: iOS Simulator Maestro/XCUITest has
truncated full 690-character `bfonboard1` entry in SwiftUI `TextEditor` during
onboarding validation. Commit `353d02e` updates iOS onboarding flows to use the
product `btn_paste_package` affordance and handle the iOS paste permission
dialog. Future onboarding retries should start from that path rather than
reworking long-package entry unless regression evidence shows it broke.
iOS 26.5 Simulator may suppress the paste permission dialog or show `Allow`
instead of `Allow Paste`; flows should tolerate either and must not fail solely
because the paste dialog is absent.
Commit `8656f9f` bounds the iOS package `TextEditor` height so full packages
scroll within the field instead of pushing `btn_connect` outside Maestro's
reachable viewport. Use `flows/shared/ios-pre-connect-state.yaml` for the
focused pre-connect reachability check before debugging Swift dispatch.

Additional known harness limitation: the debug `igloo://test-inject` URL
scheme is the preferred focused iOS onboarding diagnostic path after
`6023f735`, because it bypasses fragile long-text paste automation while still
exercising `rust.onboard()`. Maestro can locate and tap `btn_paste_package`,
but the Swift paste button action closure may not fire under automation. Treat
that as Maestro/XCUITest tap-action harness friction unless manual simulator
tapping also fails. For focused onboarding diagnostics, prefer
`igloo://test-inject` with redacted runtime credentials, or preload the macOS
clipboard with `pbcopy` and manually tap the product paste button. Do not log
package/password bytes, and do not open product paste or Swift observation work
solely because the Maestro tap action did not fire.

Current onboarding follow-up state after `6023f735`: iOS valid-credential
onboarding return is proven through the URL-scheme diagnostic path. Valid bob
`igloo://test-inject` reaches `OnboardReview` in about 10 seconds on RMP iPhone
15, and wrong-password still produces a visible redacted error. The fixed Rust
boundary requires constructing `tokio::time::timeout(_, _)` inside the
`runtime.block_on(async { ... })` future, not before entering the Tokio
runtime. URL-scheme relay query parameters must be URL-encoded raw relay values
only, for example `relay=ws%3A%2F%2F127.0.0.1%3A8194`; do not base64-encode the
relay. Current state after `505b32a`: focused gates prove iOS URL-scheme valid
bob reaches `OnboardReview`, iOS URL-scheme wrong-password is visible and
recoverable, the normal iOS product UI `btn_connect` path now reaches
`OnboardReview` through real UI selectors, Android DebugIntent current carol
reaches `OnboardReview`, and Android Save-to-Dashboard no longer crashes after
`d150c9b`, and Android first dashboard header identity is fixed by `71bb520`.
Commit `81dd156` captures the current per-assertion evidence matrix and makes
the focused gates canonical for `VAL-ONBOARD` under current iOS Maestro
limitations. Do not loop on full `flows/onboard-ios.yaml` hangs at
`btn_connect` if the focused iOS manual UI, iOS URL-scheme, iOS wrong-password,
Android DebugIntent, Rust tests, live relay tests, and iOS/Android builds remain
green.
For the iOS focused manual gate, use `run-focus-ios-manual-connect.sh`; it may
use debug-only sandboxed `Documents/igloo_test_creds.json` to compensate for
Maestro iOS 26.5 SecureField/TextView input timing, while still driving real
product UI selectors and not logging package/password material.

Signer console validation after `8687982`: Android Start transitions to Signer
Running and shows an RFC-3339 INFO event-log row; iOS/Android Start/Stop/Ping
side-effect reconcilers are wired to real FFI calls; iOS diagnostics URL
bootstrap can save OnboardReview to Dashboard and the focused iOS
save/start/ping gate passes. On iOS 26.5 Simulator, use the committed focused
scripts and prefer visible text selectors such as `Start`, `Stop`, `Refresh`,
and `Test Ping` when SwiftUI button resource ids do not materialize. The iOS
Debug simulator may use the DEBUG + simulator-only file-storage fallback if
Keychain returns `errSecMissingEntitlement`; this is expected validation
infrastructure, while release/device builds keep using Keychain.

Current onboarding-and-runtime user testing blocker after round 1: if a fresh
onboarded profile shows `Signer Running` + `Relay Connected` but remains in
`Restoring...` for more than 60 seconds, capture screenshot, hierarchy,
visible event log rows, relay reachability, and alice/demo service health, then
stop peer-dependent signer/load checks for that platform. Continue independent
ONBOARD, SHELL, and LOAD navigation/error-path assertions that do not require
peer readiness or exported runtime material. After the restoring fix feature
lands, rerun signer validation in smaller groups: (1) ONBOARD/SHELL
independent paths, (2) SIGNER readiness/peer/ping/event-log paths, and (3)
LOAD/CROSS paths that depend on bfprofile1/bfshare1 exports or multiple stored
profiles. Serialized alice-offline assertions such as `VAL-ONBOARD-014` still
require service-control-log evidence and must not run concurrently with other
relay-mutating tests.

After `1cfe8ce`, the focused iOS Restoring proof script
`apps/igloo-mobile/scripts/run-focus-ios-signer-restoring-readiness-live-proof.sh`
proves fresh bob onboarding reaches Sign Ready within 60 seconds, peer rows are
populated, Test Ping adds event-log activity, and Stop→Start returns to Sign
Ready. Validator reruns can reuse its committed Maestro YAMLs and evidence
directory as a recipe. On iOS 26.5, the Test Operation card can land just below
the visible scroll window; before asserting or tapping `Refresh` / `Test Ping`,
use `swipe: DOWN` plus `scrollUntilVisible` for `signer_status_card` or raise
the wait to 30 seconds so the button is fully on-screen before the tap.

For iOS signer peer liveness and Refresh verification after `c1f0b47f`, use the
debug URL + diagnostics save-to-dashboard path from the focused Restoring proof
rather than the long-text `onboard-ios.yaml` form entry path. Required captures:
pre-refresh peer rows, post-refresh peer rows, post-refresh event log, post-Test
Ping rows, and a Stop→Start recovery capture. The non-running demo peer must
stay offline/known across all captures, while live alice remains online/ready
after Refresh.

For iOS diagnostic gates after `081459e`, first prove the current app is
installed on the target simulator: build, install, run
`xcrun simctl get_app_container <udid> com.frostr.igloo.dev app`, and inspect
the installed `Info.plist` for `CFBundleURLSchemes` containing `igloo`.
If a helper script checks the installed plist, the scheme is nested under
`CFBundleURLTypes`, for example `CFBundleURLTypes:0:CFBundleURLSchemes`. Do not
let a missing top-level `CFBundleURLSchemes` path abort an otherwise valid
URL-scheme gate.
For `igloo://test-inject`, use a fully formed URL with encoded
package/password query parameters and URL-encoded relay. A bare
`igloo://test-inject` URL is not a valid onboarding proof. If `simctl openurl`
returns `LSApplicationWorkspaceErrorDomain` error 115 after install and scheme
proof, treat it as simulator/app-registration infrastructure and do not
classify Swift observation.

Encoding is strict for the debug URL:
- `package`: base64-encode the raw `bfonboard1` package string, then include
  the base64 text as the query value.
- `password`: include the 32-hex password as a URL-encoded raw string; do not
  base64-encode it unless the app source changes.
- `relay`: URL percent-encode the raw relay URL, for example
  `ws%3A%2F%2F127.0.0.1%3A8194`; do not base64-encode the relay.
- Evidence should record URL length and decoded lengths only. Never persist the
  raw package, password, decrypted share, or private key material.

When `xcrun simctl openurl` opens `igloo://test-inject`, iOS Simulator may show
the system confirmation dialog `Open in Igloo Mobile?`. This is simulator
security behavior, not product evidence. Tap `Open` once, or add a Maestro
conditional tap for `Open` if the dialog appears; the simulator generally
remembers the choice on later opens.

Maestro `list-devices` can omit iOS while direct UDID targeting still works.
Prefer `maestro --device <RMP iPhone 15 UDID> hierarchy`; if direct UDID
targeting also fails, restart Simulator/CoreSimulator once and return as
infrastructure. On iOS, `input_package` is a `NativeTextView`/`UITextView`.
XCUITest must query `app.textViews["input_package"]` or
`app.descendants(matching: .any)["input_package"]`, not only
`app.textFields["input_package"]`. If OnboardEntry to OnboardConnect appears
to fail, capture screenshot and hierarchy immediately after `btn_connect_entry`
and verify selector type before declaring a product navigation defect.

Do not rely on Mac `/tmp` for simulator app reads. `/tmp/igloo_test_auto.json`
and `/tmp/igloo_test_package.txt` are not accepted unless written inside the
app simulator container or proven readable by the app. Prefer URL-scheme
injection or XCUITest `launchEnvironment`/`UIPasteboard`.
Later evidence from cross-flow signing paths reported Android reaching save but
not Dashboard. The next onboarding retry must capture hierarchy and app state
after Save before classifying that as a product navigation bug versus a
Maestro wait/retry flake.

## Cross-Flow Persistence Validation

Cross-flow restart validation must preserve app data and secure storage. Do not
use `clearState: true` or `clearKeychain: true` for `VAL-CROSS-002`,
`VAL-CROSS-006`, or `VAL-CROSS-010`; use real termination/relaunch mechanisms
such as `simctl terminate` or `adb force-stop`.

`VAL-CROSS-010` requires two distinct stored profiles on one device.
Single-profile restart evidence is insufficient. `VAL-CROSS-007` requires real
exported/imported/recovered `bfprofile1` and `bfshare1` artifacts, never
placeholder package strings.

Evidence must redact package strings and passwords, but capture full group and
share public keys where the contract requires exact comparisons. For
offline-provisioner checks, serialize the flow and stop only alice/igloo-demo,
then restart it before retrying. Capture `service-control-log` evidence.

## Device Recipes

### iOS

Boot:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
xcrun simctl boot "RMP iPhone 15" || true
open -a Simulator
```

Build/install/launch explicitly from app root (preferred over `rmp run` if the
runner ever computes `.dev.dev`):

```bash
cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile
xcodebuild -project ios/IglooMobile.xcodeproj -scheme IglooMobile -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=RMP iPhone 15' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
# Install the built IglooMobile.app from DerivedData, then:
xcrun simctl launch booted com.frostr.igloo.dev
```

Screenshot:

```bash
xcrun simctl io booted screenshot /tmp/igloo-mobile-ios.png
```

Hierarchy:

```bash
maestro hierarchy > /tmp/igloo-mobile-ios-hierarchy.json
```

Shutdown:

```bash
xcrun simctl shutdown "RMP iPhone 15" || true
xcrun simctl shutdown booted || true
osascript -e 'tell application "Simulator" to quit' || true
```

If shutdown by simulator name prompts or blocks in a delegated session, use the
booted device/UDID form (`xcrun simctl shutdown booted` or
`xcrun simctl shutdown <udid>`) and note the cleanup attempt in the handoff.

### Android

Boot:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
emulator -avd rmp_api35 -no-snapshot-save >/tmp/igloo-mobile-rmp_api35.log 2>&1 &
adb -s emulator-5554 wait-for-device
until [ "$(adb -s emulator-5554 shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
```

Build/install/launch explicitly from app root:

```bash
cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile
just android-full
cd android
adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 shell am start -n com.frostr.igloo.dev/com.frostr.igloo.MainActivity
```

Screenshot and hierarchy:

```bash
adb -s emulator-5554 exec-out screencap -p > /tmp/igloo-mobile-android.png
adb -s emulator-5554 shell uiautomator dump /sdcard/window.xml
adb -s emulator-5554 pull /sdcard/window.xml /tmp/igloo-mobile-android-window.xml
```

Relay reachability from Android:

```bash
adb -s emulator-5554 shell toybox nc -z 10.0.2.2 8194
```

Relay reachability from iOS Simulator:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
xcrun simctl boot "RMP iPhone 15" || true
xcrun simctl bootstatus "RMP iPhone 15" -b
xcrun simctl spawn "RMP iPhone 15" /usr/bin/nc -vz 127.0.0.1 8194
```

Do not claim the iOS Simulator needs a physical device or tunnel for
`ws://127.0.0.1:8194` unless this simulator-context command fails with captured
output.

Shutdown:

```bash
adb -s emulator-5554 emu kill || true
```

## Maestro Recipes

When both devices are booted, always select the target device explicitly.

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
maestro --device <ios-udid> test flows/<flow>.yaml --debug-output /tmp/igloo-mobile-maestro-ios
maestro --device emulator-5554 test flows/<flow>.yaml --debug-output /tmp/igloo-mobile-maestro-android
maestro --device <ios-udid> hierarchy > /tmp/igloo-mobile-ios-hierarchy.txt
maestro --device emulator-5554 hierarchy > /tmp/igloo-mobile-android-hierarchy.txt
```

`--device` / `--udid` is a global Maestro option and should appear before the
subcommand for consistency, though `maestro test --device ...` is also accepted
by Maestro 2.6.0. Always source the env first so Maestro sees JDK 17.

The debug id is exactly `com.frostr.igloo.dev`. Flows must target that id. If
any runner reports `com.frostr.igloo.dev.dev`, do not accept it; use or fix the
explicit platform commands above.

If Maestro starts on SpringBoard or the Android launcher, fix app foregrounding
before interpreting assertions. Use a fresh platform launch, then capture
hierarchy or foreground-app evidence:

```bash
adb -s emulator-5554 shell am start -W -n com.frostr.igloo.dev/com.frostr.igloo.MainActivity
adb -s emulator-5554 shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
xcrun simctl launch booted com.frostr.igloo.dev
maestro --device <device> hierarchy > /tmp/igloo-mobile-foreground-hierarchy.txt
```

Flows should either use the working hub-validation launch/link pattern or an
explicit `launchApp` step before first assertions. Do not claim a product
failure or pass while Maestro is attached to the launcher/SpringBoard.

Maestro 2.6.0 does not support `maestro hierarchy --format json`; invoke
`maestro hierarchy` directly and redirect stdout. Shared flows may contain
platform-specific steps. In particular, `hub-validation.yaml` includes
VAL-SHELL-014 Android system-back parity (`pressKey: back`), which is
Android-only and should be skipped, filtered, or treated as an expected
non-iOS step by iOS validators.

## Evidence Artifacts

- `screenshot(ios)` / `screenshot(android)`: PNG from simctl/adb or Maestro.
- `hierarchy-dump`: Maestro hierarchy JSON on iOS; uiautomator XML on Android.
- `clipboard-output`: captured platform clipboard read or a paste-back
  transcript into a known test field.
- `qr-decode-output`: decoder stdout or decoded payload artifact from a
  screenshot of the QR display modal. See `## QR Decode Recipe` below for the
  exact `zbarimg` invocation.
- `demo-harness-output`: make/demo/devtools transcript proving relay/co-signer
  behavior.
- `service-control-log`: transcript showing serialized or isolated start/stop
  of demo relay/alice for assertions that mutate shared services.

## QR Decode Recipe

VAL-QR-001 requires verifying that the QR displayed in the Create Keyset
Distribute step's QR modal decodes to the same `bfonboard1` payload string
shown in the modal's payload text. Capture the modal screenshot with
`simctl`/`adb`, then decode it with the `zbarimg` CLI. `zbar` is a stable
zxing equivalent that ships with a single binary and reads both PNG and the
binary `stdout` formats used by `simctl io screenshot`.

Install (one-time, machine-local):

```bash
brew install zbar
```

Decode the QR from a device screenshot to a single-line string on stdout:

```bash
# Take the screenshot first.
xcrun simctl io booted screenshot /tmp/igloo-mobile-qr.png     # iOS
adb -s emulator-5554 exec-out screencap -p > /tmp/igloo-mobile-qr.png  # Android

# Decode — emits `--raw` text per detected symbol (one line per symbol). Filter
# to the bfonboard1 envelope; the validator runs this from the same shell.
zbarimg --quiet --raw /tmp/igloo-mobile-qr.png | grep -E '^bfonboard1'
```

Capture the stdout into the `qr-decode-output` evidence artifact. The
resulting line should:

1. start with `bfonboard1`
2. be a single contiguous bech32m string (no embedded whitespace)
3. match the modal's `qr_payload_text` accessibility value (when truncated
   visually, the modal's full payload is in the accessibility value, not the
   rendered label)
4. decrypt successfully with the package password used to produce the
   share (decode via `frostr-utils`/`bifrost-codec`)

Cropping the PNG before decoding improves accuracy when the screenshot
contains multiple artifacts (status chips, payload text, etc.). ImageMagick
recipe:

```bash
# Crop to the QR bitmap region on iPhone 15 / rmp_api35 (rough center).
# Adjust numbers per device resolution if the layout shifts.
convert /tmp/igloo-mobile-qr.png -crop 320x320+200+400 /tmp/igloo-mobile-qr-crop.png
zbarimg --quiet --raw /tmp/igloo-mobile-qr-crop.png | grep -E '^bfonboard1'
```

When `zbar` is unavailable on the validator's machine, the documented
fallback is `npx zxing-cli` (zxing via npm). Do not depend on zxing-cli in
CI because the npm-resolution time + cold cache can violate the 60-second
per-assertion budget; `zbarimg` is the canonical recipe.

The same recipe is used on Android; `adb exec-out screencap -p` already
returns PNG so no conversion is required before `zbarimg`.

## Shared-Service Isolation

Assertions that stop/restart the relay or alice co-signer, mutate backup events,
or require cross-device rotation must run in a serialized critical section or
against a per-validator isolated demo stack/port. Capture `service-control-log`.

Backup assertions must use before/after relay queries filtered by the
share-derived backup author.

## Validation Concurrency

Readiness measurement:
- Machine: 128 GB RAM, 18 CPU cores.
- Android emulator: roughly 5.1 GB RSS and ~0.25 core idle.
- iOS simulator: roughly 2-4 GB incremental.
- Maestro adds negligible persistent cost.

Classification:
- **Max concurrent mobile validators: 2** (one iOS, one Android).
- Use lower concurrency (1) for serialized shared-service assertions.
- Do not run two validators that mutate the same demo relay/alice instance at
  once.

## Flow Validator Guidance: iOS Simulator

**Isolation:** The iOS Simulator is a self-contained device. Validators working
on iOS share no state with Android validators. All walking-skeleton shell
assertions are read-only hub interactions -- no mutations to profiles, relay,
or shared services. iOS validators can run concurrently with Android
validators without interference.

**Boundaries:**
- Only use the `RMP iPhone 15` simulator (UDID discoverable via `xcrun simctl list`).
- App bundle id: `com.frostr.igloo.dev`.
- Do not start/stop the demo stack (shared service). Shell assertions do not
  touch the relay.
- Do not terminate or modify the Android emulator.

**Resources off-limits:**
- Do not touch services/ or Docker containers (demo stack is shared).
- Do not uninstall or modify the Android app.
- Do not use simulator devices other than `RMP iPhone 15`.

**Assertion grouping:** All walking-skeleton SIMULATOR assertions (VAL-SHELL-001
through VAL-SHELL-011 except VAL-SHELL-014 which is Android-only) are tested
on iOS. The existing `hub-validation.yaml` Maestro flow covers many of them;
supplement with direct `simctl`/`maestro` commands for theme/typography
screenshots and relaunch.

## Flow Validator Guidance: Android Emulator

**Isolation:** The Android emulator (`rmp_api35`, serial `emulator-5554`) is a
self-contained device. Validators working on Android share no state with iOS
validators. All walking-skeleton shell assertions are read-only hub
interactions.

**Boundaries:**
- Only use `emulator-5554` (AVD `rmp_api35`).
- App id: `com.frostr.igloo.dev`.
- Do not start/stop the demo stack.
- Do not terminate or modify the iOS simulator.

**Resources off-limits:**
- Do not touch services/ or Docker containers.
- Do not uninstall or modify the iOS app.
- Do not use other AVDs.

**Assertion grouping:** All walking-skeleton EMULATOR assertions (VAL-SHELL-001
through VAL-SHELL-014) are tested on Android. VAL-SHELL-014 (Android system
back) is Android-only per contract. The existing `hub-validation.yaml` Maestro
flow covers core navigation; supplement with direct `adb`/`maestro` commands
for theme/typography screenshots and relaunch.

## Secret-Safe Evidence Collection Recipe

When a feature must prove form-field population (package, password, relay URL)
without committing secrets to evidence, use this sanitized evidence pattern:

### Android (uiautomator)

```bash
# Capture hierarchy dump
adb -s emulator-5554 shell uiautomator dump /sdcard/window.xml
adb -s emulator-5554 pull /sdcard/window.xml /tmp/window.xml

# Sanitize with Python: replace package/password content with length tokens
python3 -c "
import re, sys
xml = open('/tmp/window.xml').read()
# Replace any text longer than 20 chars with its length
xml = re.sub(r'text=\"([^\"]{21,})\"', lambda m: f'text=\"[REDACTED-{len(m.group(1))}chars]\"', xml)
open('/tmp/window-sanitized.xml', 'w').write(xml)
"
```

### iOS (Maestro hierarchy)

```bash
maestro --device <udid> hierarchy > /tmp/hierarchy.json

# Sanitize: replace long text values with length tokens
python3 -c "
import json, re, sys
data = json.load(open('/tmp/hierarchy.json'))
# Flatten hierarchy and redact long values
def redact(node):
    if 'text' in node and len(str(node['text'])) > 20:
        node['text'] = f'[REDACTED-{len(str(node["text"]))}chars]'
    if 'children' in node:
        for child in node['children']:
            redact(child)
redact(data)
json.dump(data, open('/tmp/hierarchy-sanitized.json', 'w'), indent=2)
"
```

### Evidence Content Requirements

For a credential-injection or form-fill feature, sanitized evidence must show:
- **Input fields present**: hierarchy confirms `input_package`, `input_password`,
  `input_relay_url` exist with non-empty, redacted content
- **Length tokens**: redacted content shows the expected package length (690 for
  bfonboard1) and password length (32 for demo passwords)
- **Action enabled**: the submit button (e.g., `btn_connect`) is `enabled=true`
  after fields are populated
- **No secret leakage**: no raw package string, password, or share secret
  appears anywhere in the evidence

Store sanitized evidence under `apps/igloo-mobile/library/evidence/<feature-id>/`.
Reference the exact paths in the handoff verification section.

## OSLog Evidence Sanitization

When capturing iOS Simulator OSLog output as evidence, the app subsystem log
may contain privacy-redacted fields (e.g., `<private>` for sensitive values)
that can trigger false positives in secret-detection shields. The OSLog privacy
system automatically redacts values that cross process boundaries unless
explicitly opted out.

Sanitization technique:
1. Capture with: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.frostr.igloo"' --style compact > evidence.log`
2. Replace all `<private>` tokens with length-only placeholders: `<private>` → `[redacted]`
3. Verify no raw package strings, passwords, or share secrets appear
4. Only capture lengths (e.g., `pkg_length=690`) and non-sensitive fields

```bash
sed 's/<private>/[redacted]/g' evidence.log > evidence-sanitized.log
```

## Diagnostic URL Handler Pattern (iOS Maestro Workaround)

When Maestro cannot reliably tap a SwiftUI `Button` on the iOS Simulator
(see `ONBOARD-IOS-MAESTRO-LIMITATION.md` for the broader button tap-reachability
limitation), a debug-gated custom URL scheme handler can bypass SwiftUI tap
routing by driving Rust state-machine actions directly.

Pattern:
1. Register a URL scheme in `App.swift`'s `onOpenURL` handler
2. Gate the handler with `#if DEBUG` and a runtime diagnostics flag
3. Make the Rust action a hard no-op when preconditions aren't met
4. Invoke via `xcrun simctl openurl booted "igloo://<action>?<params>"` from Maestro or scripts

Example (save-to-dashboard):
```swift
.onOpenURL { url in
    #if DEBUG
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "igloo",
          components.host == "test-save-to-dashboard",
          manager.isOnboardDiagnosticsEnabled else { return }
    let deviceName = components.queryItems?
        .first(where: { $0.name == "device_name" })?.value ?? "Test Device"
    manager.testOnboardSaveToDashboard(deviceName: deviceName)
    #endif
}
```

This pattern uses `xcrun simctl openurl` as the Maestro step instead of
`tapOn`. The URL handler must drive the exact same Rust state machine chain
as the user-typed button action — no shortcuts or stubs.

## Flow Validator Guidance: iOS Simulator (onboarding-and-runtime)

**Isolation:** iOS Simulator `RMP iPhone 15` (UDID `4EB37CCF-B55C-4DD4-A4EE-F3AA623BA5C0`).
Uses bob identity from demo harness. Does not share state with Android validators.
Onboarding touches the shared demo relay but bob and carol use distinct shares
in the same 2-of-3 keyset so both can operate concurrently.

**Boundaries:**
- App bundle id: `com.frostr.igloo.dev`.
- Relay URL: `ws://127.0.0.1:8194`.
- Use `SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1` for debug-gated onboarding injection.
- Do not start/stop the demo stack unless assertion requires it (VAL-ONBOARD-014).
- Do not terminate or modify the Android emulator.

**Credentials:** Source from `/tmp/igloo-ios-bob-creds.env`:
- Bob's `bfonboard1` package (690 chars) and password (32 hex chars)
- Can also use `igloo://test-inject` URL scheme for focused diagnostics

**Known limitations:**
- iOS Maestro may not tap `btn_paste_package` reliably; prefer URL-scheme injection for onboarding.
- iOS `TextEditor` height has been bounded; use `flows/shared/ios-pre-connect-state.yaml` for pre-connect checks.
- For signer console, prefer visible text selectors (`Start`, `Stop`, `Refresh`, `Test Ping`).

**Assertions:** VAL-ONBOARD-001 through 016 (except 012 is skipped), VAL-LOAD-001 through 019,
VAL-SHELL-007, 012, 013, 015, 016, VAL-SIGNER-001 through 018, VAL-CROSS-004, 009.
Test each on iOS Simulator only. The Android subagent handles the other platform.
Each assertion passes on iOS when its contract conditions are met on this platform.

## Flow Validator Guidance: Android Emulator (onboarding-and-runtime)

**Isolation:** Android emulator `rmp_api35` (serial `emulator-5554`).
Uses carol identity from demo harness. Does not share state with iOS validators.

**Boundaries:**
- App id: `com.frostr.igloo.dev`.
- Relay URL: `ws://10.0.2.2:8194`.
- Use debug-gated Android injection/preload path for long credential transport
  (Maestro 2.6.0 `setClipboard`+`pasteText` can fail with DEADLINE_EXCEEDED on Android).
- Do not start/stop the demo stack unless assertion requires it.
- Do not terminate or modify the iOS simulator.

**Credentials:** Source from `/tmp/igloo-android-carol-creds.env`:
- Carol's `bfonboard1` package (690 chars) and password (32 hex chars)
- Android DebugIntent can inject credentials via app-owned debug path

**Known limitations:**
- Android long credential transport is blocked through Maestro 2.6.0.
  Use app-owned, debug-gated Android injection/preload path for onboarding.
- For signer console, use `testTagsAsResourceId` exposed by Compose.

**Assertions:** Same set as iOS subagent but tested on Android emulator only.
VAL-SHELL-014 (Android system back) was already passed in walking-skeleton; not in scope here.

## Wind-Down Checklist

Before handoff, stop anything the worker started unless the feature explicitly
needs it running:

```bash
adb -s emulator-5554 emu kill || true
xcrun simctl shutdown "RMP iPhone 15" || true
osascript -e 'tell application "Simulator" to quit' || true
```

Leave unrelated OrbStack containers and off-limits ports untouched.

## Round 2 Discovered Knowledge (onboarding-and-runtime)

### Docker Container Naming

The alice co-signer container is named `frostr-infra-igloo-demo-1` (Docker
Compose naming), not `igloo-demo`. Use:

```bash
docker stop frostr-infra-igloo-demo-1  # stop alice
DEV_RELAY_PORT=8194 make demo-start     # restart alice
```

For `VAL-ONBOARD-014`, keep the relay process reachable while stopping only
the alice/igloo-demo co-signer. The expected user-facing result is an explicit
onboarding/provisioner failed state within 45 seconds, no stored profile, and a
same-session retry succeeding after `DEV_RELAY_PORT=8194 make demo-start`.
Capture a `service-control-log` showing alice stop, relay reachability, alice
restart, and retry success. A silent return to hub without an error message is
not sufficient evidence for the explicit failure-state requirement.

### iOS Simulator Clipboard Isolation

`xcrun simctl pbpaste` reads the iOS Simulator clipboard, which is SEPARATE
from the macOS clipboard (`pbcopy`/`pbpaste`). Sentinel values set via `pbcopy`
do not appear in `simctl pbpaste` output. For VAL-SIGNER-017 (copyable keys),
the copy affordance tap must be verified through app-internal paste-back rather
than `simctl pbpaste`.

### Android API 35 Clipboard Limitation

`adb shell cmd clipboard get-text` is not supported on Android API 35 emulator.
For VAL-SIGNER-017, do not stop at hierarchy-only proof if a paste-back path is
available. Tap the copy affordance, navigate to a safe non-secret text input
such as a Load Profile package field or a dedicated validation paste field, use
the platform paste action, and capture sanitized hierarchy proving a 64-hex
public key was pasted. If no app-internal paste target is reachable, record the
hierarchy-only limitation and do not use unsupported direct clipboard reads as
evidence.

### Device Name Auto-Fill on iOS

The iOS review/save screen auto-fills the device name field to `"Onboarded
Device"`. To test VAL-ONBOARD-010 (empty-name rejection), the field must be
manually cleared. The Android review screen shows a placeholder `"Device name"`
and requires explicit entry.

### Android Emulator Loopback Isolation

`ws://127.0.0.1` from the Android emulator refers to the EMULATOR's own
loopback, not the host. For unreachable relay tests (VAL-ONBOARD-007), use
`ws://10.0.2.2:9` to get a host-port timeout scenario. `ws://127.0.0.1:9`
produces a connection-refused on the emulator itself, which may behave
differently.

### Signer Console Scroll Behavior

On both platforms, the signer console's peer list, event log, and pending
operations sections are below the initial viewport. Use `swipe UP` (scroll
down) or `scrollUntilVisible` to reveal them. The Test Operation / Test Ping
card can land below the visible window; scroll down before asserting or tapping
`Refresh` / `Test Ping`.

### Copy Profile / Copy Share Password Gate

The Settings tab's Copy Profile and Copy Share actions are password-gated for
export encryption. Without completing the password prompt, clipboard values
remain unchanged. A focused flow for exporting bfprofile1/bfshare1 via the
password-gated copy workflow is needed before LOAD assertions can proceed.
The export flow should:

1. Open a Sign Ready dashboard profile and navigate to Settings.
2. Tap Copy Profile or Copy Share.
3. Wait for the export password prompt and fill password plus confirmation if
   the platform requires both fields.
4. Tap the export confirmation button and wait for success feedback.
5. Paste the clipboard into a safe app text field or other validator-owned
   paste-back target.
6. Capture redacted evidence with only package type, prefix (`bfprofile1` or
   `bfshare1`), length, and password-gate state. Do not commit raw package
   bytes, export passwords, decrypted shares, or private key material.
7. Reuse the exported artifacts immediately for LOAD import/recover, delete
   and re-import, mixed-origin profile, and CROSS multi-profile assertions.

### Android DebugIntent Credential Injection

Android long credential transport (690-char bfonboard1) is confirmed blocked
through Maestro 2.6.0 (`setClipboard`+`pasteText` fails with
DEADLINE_EXCEEDED) and `adb shell input text` (truncates). The app-owned,
debug-gated `DebugIntent` injection path is the ONLY working path. Use:

```bash
adb -s emulator-5554 shell am start -n com.frostr.igloo.dev/com.frostr.igloo.MainActivity \
  --es onboard_package "$CAROL_PKG" \
  --es onboard_password "$CAROL_PWD" \
  --es relay_url "ws://10.0.2.2:8194" \
  --es device_name "carol-android-test"
```

### Known Product Issues (Round 2)

1. **VAL-ONBOARD-015 - Duplicate onboarding not rejected.** Re-onboarding an
   already-stored identity reaches the review/save screen without rejection.
   Save Device silently fails without error message on both platforms. The
   VAL-LOAD-008 parity guard does not fire during onboarding.

2. **VAL-ONBOARD-007 - Android unreachable relay hangs.** On Android, a
   handshake against an unreachable relay hangs indefinitely in "Connecting..."
   state with no error surfaced within 45s. The app does not time out.

3. **VAL-SIGNER-008 - iOS transient Online for non-running peer.** On iOS,
   carol (non-running peer) briefly showed "Online" with non-zero incoming
   nonces in the first capture after signer start. Later captures showed
   carol offline as expected.

4. **VAL-SIGNER-010 - iOS Refresh disconnects peers.** On iOS, manual Refresh
   caused both peers (including live alice) to go Offline instead of updating
   timestamps or adding log entries.

### Restoring Fix Confirmed (Round 2)

Commits `971e4d2` (Rust signer material persistence) and `1cfe8ce` (iOS live
proof) resolve the Round 1 "stuck in Restoring" blocker. Fresh onboarded
profiles on both platforms reach Sign Ready:
- iOS: ~20 seconds
- Android: ~35 seconds

Peer discovery works, alice reaches Live/Online, stop/restart recovery clean,
and auto-ping bootstrap populates nonce inventory.


## Keyset-Lifecycle Round 1 Discovered Knowledge

### Create Keyset Wizard Automation

The Create Keyset wizard (Generate -> Device Profile -> Review -> Distribute) is
a 4-step sequential flow. On Android, the full wizard was exercised successfully
through Review accept and Distribute step. Key observations:

- The wizard entry from hub first shows a "Choose an action" screen with
  "Create New Keyset" and "Rotate Existing Keyset" options before the Generate
  step. This intermediate screen is NOT in the igloo-pwa 16-view inventory.
- Generate step defaults: threshold=2, total keys=3 (correct per contract).
- Share picker on Device Profile shows 3 shares with distinct pubkeys.
- Back navigation preserves state within a session (Android PASS).
- Profile materialization happens at Review accept; leaving Distribute without
  Finish keeps the profile on hub with full identity.

### CRITICAL: Android Default Relay URL is Platform-Inappropriate

The Create Keyset wizard Device Profile step pre-fills the relay URL as
ws://127.0.0.1:8194 on ALL platforms. This is the iOS Simulator address.
On the Android emulator, 127.0.0.1 refers to the EMULATOR'S loopback, not
the host. The correct address is ws://10.0.2.2:8194.

**Impact:** This blocks ALL relay-dependent functionality on Android:
- Signer cannot connect to the shared relay
- Backup kind-10000 events are never published (relay confirmed empty)
- Peer discovery fails (no co-signer reachable)
- Cross-device communication impossible

**Evidence:** Direct relay query after keyset creation on Android found ZERO
events of any kind. The relay WebSocket handshake succeeds but no events exist.

**Fix needed:** The relay URL defaulting logic must be platform-aware. On Android
emulator, default to ws://10.0.2.2:8194. On iOS Simulator, default to
ws://127.0.0.1:8194. Or make the relay URL user-editable on the Device Profile
step and always require explicit entry.

### iOS Maestro + SwiftUI Automation Gap (iOS 26.5 + Maestro 2.6.0)

Maestro 2.6.0 has fundamental limitations on iOS 26.5 Simulator:
- TextField text entry: inputText and pasteText appear to complete but the
  app state does not reflect entered values.
- Button taps: tapOn reports COMPLETED but the SwiftUI Button action closure
  does not fire. Affects all wizard buttons (Generate, Accept, Finish).
- Hierarchy capture: intermittent timeout issues on iOS 26.5.

**Impact:** All iOS assertions requiring form interaction (22+ CREATE, 14
ROTATE, 3 QR) are blocked. Only read-only assertions can pass.

**Workaround options (NOT yet implemented):**
1. Debug URL scheme for keyset creation (like igloo://test-inject for
   onboarding): igloo://test-create-keyset?group_name=X&threshold=2&count=3
2. XCUITest launchEnvironment-based debug injection for keyset wizard
3. Manual testing on physical device

### Android Compose TextField Automation Gap

Android Compose TextField / OutlinedTextField elements lack
testTagsAsResourceId -- all resource-ids are empty except btn_back.
This makes reliable adb/Maestro text entry impossible:
- adb shell input text appends rather than replaces
- adb shell input keyevent 67 (DEL) does not consistently clear Compose fields

**Workaround:** Maestro point-based tapping for buttons works. Text entry only
works on fresh install with empty fields (appending behavior).

### Nostr Relay Query Recipe

To query the dev relay for kind-10000 backup events, use websocat (brew install
websocat) or Python websocket-client. Example query:
["REQ","backup-check",{"kinds":[10000]}]

### Distribution Step Password Entry

Distribute step Copy/QR/Save buttons are disabled (enabled=false) until both
password fields are non-empty and confirm matches. This is a deliberate
strengthening over igloo-pwa (which permits empty package passwords).

### Create Keyset Flow Validator Guidance (Android)

For future Android validation runs:
1. Launch app to hub, tap "Create / Rotate Keyset"
2. On "Choose an action" screen, tap "Create New Keyset"
3. Generate step: use Maestro point-based taps for button interaction
4. For Distribute password entry: blocked until Compose TextFields get
   testTagsAsResourceId or a debug URL scheme is added
5. For relay queries: use Python websocket-client or websocat from host to
   ws://127.0.0.1:8194

### Flow Validator Guidance: iOS Simulator (keyset-lifecycle)

**Isolation:** Same as onboarding-and-runtime. iOS-only, uses bob.

**Known limitations:**
- ALL form-interaction assertions blocked by iOS Maestro SwiftUI limitations.
- No debug URL scheme for Create Keyset wizard (unlike onboarding).
- websocat must be installed for relay queries.

### Flow Validator Guidance: Android Emulator (keyset-lifecycle)

**Isolation:** Same as onboarding-and-runtime. Android-only, uses carol.

**Known limitations:**
- CRITICAL: Default relay URL is ws://127.0.0.1:8194 (wrong for Android).
  Validators must manually edit to ws://10.0.2.2:8194 on Device Profile step.
- Compose TextFields lack testTagsAsResourceId; text entry unreliable.
- Relay has zero events currently (Android app cannot publish due to URL issue).

## Keyset-Lifecycle Round 2 Discovered Knowledge

### Fix Status Summary

| Fix | Status | Details |
|-----|--------|---------|
| Android relay URL (bed0c4c) | PARTIAL | OnboardConnectScreen and RotateShareConnectScreen use `RelayDefaults.DEFAULT` (ws://10.0.2.2:8194). But Create Keyset wizard Device Profile step sources from Rust core `default_relay_url` (ws://127.0.0.1:8194), which was left unchanged. |
| Android testTags (d18a35b) | CONFIRMED | All documented testTags exposed: `input_group_name`, `input_threshold`, `input_count`, `input_device_name`, `input_relays`, `input_label_<idx>`, `input_password_<idx>`, `input_confirm_password_<idx>`. `adb shell input text` works for appending to empty fields. |
| iOS debug URL scheme (c5bfcf6) | PARTIAL | `igloo://test-create-keyset` successfully bypasses Maestro limitations for keyset creation endpoint. Unblocks 5 CREATE assertions. But bypasses ALL intermediate wizard steps and does NOT auto-start signer. |

### iOS URL Scheme Usage

The `igloo://test-create-keyset` URL scheme bypasses Maestro SwiftUI limitations:

```bash
# Launch with diagnostics enabled
SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1 xcrun simctl launch booted com.frostr.igloo.dev

# Create keyset via URL scheme
xcrun simctl openurl booted "igloo://test-create-keyset?group_name=TestKeyset&threshold=2&count=3&device_name=TestDevice&relay=ws%3A%2F%2F127.0.0.1%3A8194"
```

Parameters: `group_name`, `threshold` (≥2), `count` (≥threshold), `device_name`, `relay` (URL-encoded).
Invalid params (threshold > count, threshold < 2) are rejected inline by the Rust actor.
Valid params auto-generate keyset, select first share as local, accept Review, store profile via Keychain, and land on dashboard.

**Known gaps:**
- Bypasses all intermediate wizard steps (Device Profile, Review, Distribute) — 13 CREATE assertions blocked.
- Signer is NOT auto-started (Maestro confirms "Signer Stopped"). Profile stored but no relay connection.
- A companion `igloo://test-start-signer` URL would unblock backup/peer testing.
- A granular URL scheme with step-pause capability would unblock intermediate-step assertions.

Focused script at `apps/igloo-mobile/scripts/run-focus-ios-keyset-debug-url-scheme.sh`.
Committed Maestro flow at `apps/igloo-mobile/flows/keyset-create-url-scheme-ios.yaml`.

### Android testTags Confirmed Working

All documented Compose `testTagsAsResourceId` are now exposed. Use these IDs for Maestro/adb text entry:

```
CreateKeysetGenerateScreen:     input_group_name, input_threshold, input_count
CreateKeysetDeviceProfileScreen: input_device_name, input_relays
CreateKeysetDistributeScreen:   input_label_<idx>, input_password_<idx>, input_confirm_password_<idx>
RotateShareConnectScreen:       input_package, input_password, input_relays
```

`adb shell input text` works for appending to empty fields. Cannot replace existing text (Compose DEL keyevent handling inconsistent). For the wizard relay URL field (pre-filled), manual clearing is blocked — use platform-correct defaults instead.

### Android R2 Blockers

**P0 — Incomplete relay URL fix:** The Create Keyset wizard Device Profile step still shows `ws://127.0.0.1:8194` (iOS) on Android. Need to either override in Android shell at Device Profile init or pass platform-correct default from shell to Rust core.

**P0 — Debug intent onboarding regression:** `adb shell am start --es onboard_package ...` no longer creates stored profiles. App returns to empty hub after injection. Previously worked in R1 and onboarding-and-runtime rounds. All stored-profile-dependent testing blocked.

**P1 — Compose Button onClick not triggerable via adb:** Distribute step Copy/QR/Save buttons show `enabled=true` in hierarchy but `adb input tap` at clickable parent coordinates produces no effect. Accessibility action-based triggering (e.g., `adb shell input keyevent KEYCODE_ENTER` on focused button) may work as alternative.

### iOS R2 Blockers

**Maestro SwiftUI tap limitations persist:** Tab switching, tile navigation, and button taps from non-dashboard screens remain unreliable on iOS 26.5.

**URL scheme signer gap:** Signer stays "Stopped" after URL scheme creation. No relay connection → no backups, no peer discovery. A companion `igloo://test-start-signer` URL would unblock this.

**Relay empty:** The dev relay at `ws://127.0.0.1:8194` has zero events of any kind. Either volatile storage or no device has published events. Backup assertions blocked until relay event persistence is confirmed.

### Combined R1+R2 Assertion Status

After R2: 5 CREATE assertions now pass (VAL-CREATE-003, 004, 010, 018, 019 newly passing on iOS via URL scheme). Remaining 39 assertions still blocked or failed. Key remaining blockers:
1. Android wizard relay URL still `ws://127.0.0.1:8194` (incomplete fix)
2. Android debug intent onboarding regression (new in R2)
3. iOS Maestro SwiftUI limitations (persistent)
4. iOS URL scheme bypasses intermediate steps (by design)
5. iOS URL scheme doesn't auto-start signer (gap)
6. Android Compose button onClick not triggerable (new finding)
