# Cross-Platform E2E Matrix

Last updated: 2026-06-18

This matrix tracks Android/iOS flows that should stay aligned as the UI polish
work lands. Keep evidence under `library/evidence/` and prefer native-built
packages from one platform consumed by the other.

## P0 Smoke

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| iOS QR package -> Android QR fallback onboard -> Android Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | PASS | Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-18-150948/ios-to-android` |
| Android QR package -> iOS QR fallback onboard -> iOS Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | PASS | Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-18-150948/android-to-ios` |
| iOS QR package -> Android manual Connect onboard | `just focus-cross-platform-manual-onboard` | PASS | Evidence: `library/evidence/mobile-cross-platform-manual-onboard-2026-06-18-152952/ios-to-android-manual` |
| Android QR package -> iOS manual Connect onboard | `just focus-cross-platform-manual-onboard` | BLOCKED | iOS package `TextEditor` keeps first-responder focus; password input lands in `input_package` instead of `input_password`. Evidence: `library/evidence/mobile-cross-platform-manual-onboard-2026-06-18-152952/android-to-ios-manual` |

## P1 Persistence And Identity

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android profile persistence, relaunch, two-profile identity isolation | `just focus-cross-flow-android` | Existing validator | Use after UI/layout changes that touch hub, dashboard, settings, or permissions. |
| iOS profile persistence, relaunch, two-profile identity isolation | `just focus-cross-flow-ios` | Existing validator | Use after UI/layout changes that touch hub, dashboard, settings, or permissions. |
| Cross-platform QR onboard persistence | `just focus-cross-platform-onboard-signer` | Covered in P0 | The signer proof launches the recipient app after onboard with `clearState: false`, reopens the stored profile, and starts the signer. |

## P1 Import / Export / Recover

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android export artifact validation | `just focus-android-export` | Existing validator | Validates `bfprofile1` / `bfshare1` export artifacts. |
| iOS export artifact validation | `just focus-ios-export` | Existing validator | Validates `bfprofile1` / `bfshare1` export artifacts. |
| Android load/import/recover with exported artifacts | `just focus-android-load-artifacts` | Existing validator | Should be run after export/import UI changes. |
| iOS load/import/recover with exported artifacts | `just focus-ios-load-artifacts` | Existing validator | Should be run after export/import UI changes. |

## P2 Operational Parity

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android rotate-share replacement | `just focus-android-rotate-share` | Existing validator | Pair with iOS rotate when rotate UI changes. |
| iOS rotate-share replacement | `just focus-ios-rotate-share` | Existing validator | Pair with Android rotate when rotate UI changes. |
| Android runtime error resilience | `maestro --device emulator-5554 test flows/runtime-errors-android.yaml` | Existing flow | Run when navigation, error cards, or recovery UX changes. |
| iOS runtime error resilience | `maestro --device <UDID> test flows/runtime-errors-ios.yaml` | Existing flow | Run when navigation, error cards, or recovery UX changes. |

## Follow-Ups

- Fix iOS manual Connect keyboard/focus behavior so `input_password` can be
  focused reliably after pasting a package into `input_package`.
- Once fixed, rerun `just focus-cross-platform-manual-onboard` and update the
  blocked Android -> iOS manual row to PASS.
- Consider an umbrella local smoke command after the manual iOS gap is fixed:
  QR+signer, manual onboard, persistence Android, persistence iOS.
