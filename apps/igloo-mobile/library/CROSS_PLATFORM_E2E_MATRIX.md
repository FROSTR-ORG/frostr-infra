# Cross-Platform E2E Matrix

Last updated: 2026-06-19

This matrix tracks Android/iOS flows that should stay aligned as the UI polish
work lands. Keep evidence under `library/evidence/` and prefer native-built
packages from one platform consumed by the other.

## P0 Smoke

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| iOS QR package -> Android QR fallback onboard -> Android Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | PASS | Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-18-150948/ios-to-android` |
| Android QR package -> iOS QR fallback onboard -> iOS Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | PASS | Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-18-150948/android-to-ios` |
| iOS QR package -> Android manual Connect onboard | `just focus-cross-platform-manual-onboard` | PASS | Evidence: `library/evidence/mobile-cross-platform-manual-onboard-2026-06-18-152952/ios-to-android-manual` |
| Android QR package -> iOS manual Connect onboard | `just focus-cross-platform-manual-onboard` | PASS | Evidence: `library/evidence/mobile-cross-platform-manual-onboard-2026-06-18-205112/android-to-ios-manual` |
| Cross-platform E2E lanes 1-5 umbrella | `just focus-cross-platform-e2e-1-5` | PASS | Evidence: `library/evidence/mobile-cross-platform-e2e-1-5-2026-06-19-031231`; lanes 1-5 passed with native rotate-share packages and native-created persistence profiles. |

## P1 Persistence And Identity

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android profile persistence, relaunch, two-profile identity isolation | `just focus-cross-flow-android` | PASS | Evidence: `library/evidence/mobile-cross-flow-persistence-android-2026-06-19-033753`; uses diagnostics-created native keyset profiles for settings persistence and two-profile isolation. |
| iOS profile persistence, relaunch, two-profile identity isolation | `just focus-cross-flow-ios` | PASS | Evidence: `library/evidence/mobile-cross-flow-persistence-ios-2026-06-19-033408`; uses diagnostics-created native keyset profiles for settings persistence and two-profile isolation. |
| Cross-platform QR onboard persistence | `just focus-cross-platform-onboard-signer` | Covered in P0 | The signer proof launches the recipient app after onboard with `clearState: false`, reopens the stored profile, and starts the signer. |
| Cross-platform wrong-password failure -> fresh-package recovery | `just focus-cross-platform-failure-recovery` | PASS | Evidence: `library/evidence/mobile-cross-platform-failure-recovery-2026-06-19-032738`; proves visible wrong-password errors and valid retry dashboard save on both shells. |

## P1 Import / Export / Recover

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android export artifact validation | `just focus-android-export` | PASS | Evidence: `library/evidence/mobile-export-artifact-validation-android-2026-06-19-031501`; validates `bfprofile1` / `bfshare1` export from a diagnostics-created local keyset. |
| iOS export artifact validation | `just focus-ios-export` | PASS | Evidence: `library/evidence/mobile-export-artifact-validation-ios-2026-06-19-031336`; validates `bfprofile1` / `bfshare1` export from a diagnostics-created local keyset. |
| Android load/import/recover with iOS exported artifacts | `EXPORT_DIR=<ios-export> just focus-android-load-artifacts` | PASS | Evidence: `library/evidence/mobile-load-profile-artifacts-android-2026-06-19-031617`; uses shared relay `ws://192.168.86.129:8194` for recovery. |
| iOS load/import/recover with Android exported artifacts | `EXPORT_DIR=<android-export> just focus-ios-load-artifacts` | PASS | Evidence: `library/evidence/mobile-load-profile-artifacts-ios-2026-06-19-031542`; uses shared relay `ws://192.168.86.129:8194` for recovery. |

## P2 Operational Parity

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Android rotate-share replacement | `just focus-android-rotate-share` | PASS | Evidence: `library/evidence/mobile-android-rotate-share-2026-06-19-031922`; replacement package is generated natively from Create Keyset distribution. |
| iOS rotate-share replacement | `just focus-ios-rotate-share` | PASS | Evidence: `library/evidence/mobile-ios-rotate-share-2026-06-19-031649`; replacement package is generated natively from Create Keyset distribution. |
| Android runtime error resilience | `maestro --device emulator-5554 test flows/runtime-errors-android.yaml` | Existing flow | Run when navigation, error cards, or recovery UX changes. |
| iOS runtime error resilience | `maestro --device <UDID> test flows/runtime-errors-ios.yaml` | Existing flow | Run when navigation, error cards, or recovery UX changes. |

## Follow-Ups

- Keep the manual onboard proof as a control lane whenever a new failure looks
  like relay/provisioner health rather than UI behavior.
- Lane 5 persistence now uses diagnostics-created local keysets and focuses on
  storage/settings/two-profile identity. Live signer Test Sign/ECDH remains
  covered by lane 3's bidirectional cross-platform onboard proof.
