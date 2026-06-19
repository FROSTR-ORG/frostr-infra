# Cross-Platform E2E Matrix

Last updated: 2026-06-19

This matrix tracks Android/iOS flows that should stay aligned as the UI polish
work lands. Keep evidence under `library/evidence/` and prefer native-built
packages from one platform consumed by the other.

## P0 Smoke

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| iOS QR package -> Android QR fallback onboard -> Android Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | GAP | Historical pass: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-18-150948/ios-to-android`. Current revalidation fails after Android reaches `Sign Ready`: Test Sign times out. Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-19-093331/ios-to-android/signer-proof/sign`. |
| Android QR package -> iOS QR fallback onboard -> iOS Test Sign/ECDH | `just focus-cross-platform-onboard-signer` | PARTIAL | iOS QR fallback onboard now passes after direct password entry. Evidence: `library/evidence/mobile-cross-platform-onboard-signer-2026-06-19-083744/android-to-ios-rerun-password-entry`. Full iOS Test Sign/ECDH still needs rerun after the Android recipient timeout is resolved. |
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
| Android runtime error resilience | `maestro --device emulator-5554 test flows/runtime-errors-android.yaml` | Flow repaired, blocked by profile seed | Flow syntax was updated for Maestro 2.6.0 (`takeScreenshot`, valid document shape, wrapper scripts). Runtime execution now reaches app UI; deeper phases require deterministic `carol` profile seeding. |
| iOS runtime error resilience | `maestro --device <UDID> test flows/runtime-errors-ios.yaml` | Flow repaired, blocked by profile seed | Flow syntax was updated for Maestro 2.6.0 (`takeScreenshot`, valid document shape, wrapper scripts). Runtime execution proves rapid navigation stability, then requires deterministic `bob` profile seeding. Evidence: `library/evidence/mobile-cross-platform-runtime-errors-2026-06-19-083552`. |

## P2 Polish Hardening

| Flow | Command | Status | Notes |
| --- | --- | --- | --- |
| Cross-platform visual screenshot + accessibility/layout proof | `just focus-cross-platform-visual-a11y` | PASS | Evidence: `library/evidence/mobile-cross-platform-visual-a11y-2026-06-19-073219`; captures hub, entry, dashboard, and settings on both shells with iOS `accessibility-large` content size and Android `font_scale=1.3`. |
| Cross-platform reinstall/upgrade migration | `just focus-cross-platform-upgrade-migration` | PASS | Evidence: `library/evidence/mobile-cross-platform-upgrade-migration-2026-06-19-073842`; creates persisted profiles/settings, reinstalls the same latest bundle/APK without clearing app state, and verifies device/settings survival on both shells. |
| Release diagnostic guard | `just focus-cross-platform-release-diagnostic-guard` | PASS | Evidence: `library/evidence/mobile-cross-platform-release-diagnostic-guard-2026-06-19-074206`; builds Android/iOS release artifacts and verifies debug package IDs, debug intent filters, and iOS diagnostic URL strings do not leak into release surfaces. |
| QR display + no-camera scan fallback handoff | `just focus-cross-platform-qr-permission-fallback` | PASS | Evidence: `library/evidence/mobile-cross-platform-qr-permission-fallback-2026-06-19-082741`; runs QR display decode on both shells, then verifies no-camera scan fallback controls hand a pasted `bfonboard1` payload back to the Connect form on iOS and Android. |
| Cross-platform E2E hardening lanes 6-10 umbrella | `just focus-cross-platform-e2e-6-10` | BLOCKED | Blocked by runtime-error profile seeding and the current live signer timeout tracked in P0. Individual lanes 6-9 pass. |

## Follow-Ups

- Keep the manual onboard proof as a control lane whenever a new failure looks
  like relay/provisioner health rather than UI behavior.
- Lane 5 persistence now uses diagnostics-created local keysets and focuses on
  storage/settings/two-profile identity. Live signer Test Sign/ECDH remains
  covered by lane 3's bidirectional cross-platform onboard proof.
- Lanes 6-10 are the UI-polish hardening lanes. Treat their evidence as a
  regression-review artifact: screenshots are not pixel-golden, but each run
  captures the surfaces a human should inspect when visual polish changes.
- Current live signer gap: Android recipient from an iOS-created QR package
  reaches `Sign Ready`, but Test Sign fails with `operation timed out`.
  Revalidation tried both platform-local relay URLs and shared host relay
  `ws://192.168.1.179:8194`; source iOS logs show `startSigner` returning true.
  Next step is instrumenting the source/recipient runtime event path to explain
  why the request does not complete.
