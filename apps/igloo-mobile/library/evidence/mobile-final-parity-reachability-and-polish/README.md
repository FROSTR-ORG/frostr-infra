# mobile-final-parity-reachability-and-polish

Final full-parity audit against the igloo-pwa 16-view inventory. This tree
holds the cited evidence and supporting navigation scripts for the
parity-polish milestone's `VAL-CROSS-003` fulfillment.

## Contents

| Path | Purpose |
|------|---------|
| `library/parity/CROSS-003-16-view-reachability.md` | Per-view reachability matrix mapping the 16 contract views to the concrete Rust `Screen` variant, native view identifier, hub entry path, and distinguishing selectors. |
| `library/parity/final-polish-cleanup-notes.md` | Orchestrator-note cleanup evidence: iOS `ContentView.swift` switch warnings, iOS post-restart dashboard header identity, Android Settings icon+text parity, Android `peers_json` parsing scope, lingering `971e4d2` evidence-dirty refresh, Maestro flow platform filtering. |
| `flows/cross-parity-16-view-reachability.yaml` | Maestro flow that visits every view through real navigation from the hub. No deep link, no debug URL scheme, no app intent. |
| `flows/cross-parity-android-system-back.yaml` | Android-only companion flow for `VAL-SHELL-014` system-back parity. Never run on iOS validators; the iOS validator flow contains zero `pressKey: back` steps. |

## Supporting audit process

1. Walk every parity view through real navigation (no app intents).
2. Capture distinguishing content for each view (text or
   accessibility identifier) in the Maestro hierarchy dump.
3. Confirm back-stack navigation exits through the same in-app
   affordance anchored at `id: btn_back`.
4. On Android, validate that the system-back control (`pressKey: back`)
   reaches the same destination — separate flow file ensures iOS
   validators never see that step.
5. Surface any perceptual gaps (text-only vs icon+text) as cosmetic
   parity polish rather than hard blockers; upgrade to `non_blocking`
   in the discoveredIssues table for traceability.

## Why these flows live next to the existing `hub-validation.yaml`

`hub-validation.yaml` already covers the parity inventory's hub-baseline
assertions (`VAL-SHELL-001` through `VAL-SHELL-011` plus `VAL-SHELL-010`),
and it explicitly notes that `VAL-SHELL-014` is Android-only via a
documented comment block. The new parity flows are layered on top:

* `cross-parity-16-view-reachability.yaml` covers the parity-inventory
  reachability assertions (`VAL-CROSS-003`).
* `cross-parity-android-system-back.yaml` covers the platform-specific
  Android back assertion (`VAL-SHELL-014`).
* `hub-validation.yaml` continues to handle the shared
  `VAL-SHELL-001..011` plus `VAL-SHELL-010` shell-baseline assertions.

## Current status after June 17 continuation

The original Round 5 snapshot below predated the June 17 continuation. The
blocking signer/export/load/cross-device items it listed now have focused
evidence elsewhere in `library/evidence/`:

- Signer restore/readiness, peer refresh, copy/ping, event log, and start/stop
  behavior: `mobile-ios-signer-peer-refresh-liveness-proof`,
  `mobile-android-signer-restoring-readiness-fix-2026-06-16`, and related
  signer evidence folders.
- Export and Load Profile artifact validators: latest
  `mobile-export-artifact-validation-*` and `mobile-load-profile-artifacts-*`
  folders.
- Cross-flow persistence: latest `mobile-cross-flow-persistence-*` folders.
- Rotate Share and cross-platform keyset/rotation interop: latest
  `mobile-ios-rotate-share-*`, `mobile-android-rotate-share-*`, and
  `mobile-cross-platform-keyset-and-rotation-interop-2026-06-17-150201`.
- QR scan/display: latest `mobile-qr-scan-display-*`,
  `mobile-ios-qr-display-*`, and `mobile-android-qr-display-*`.

The remaining parity-polish surface is therefore bookkeeping and refresh:
rerun the reachability flows when a validator requests fresh screenshots, and
keep known testing-infrastructure limitations in `library/user-testing.md`.
None of the historic Round 5 gaps block `VAL-CROSS-003` reachability in the
current app-local mission ledger.

## Refresh command

To regenerate this evidence tree after a content-rebuild of the apps:

```bash
# 1. Run `make demo-start` + `make demo-onboard` upstream.
cd /Users/plebdev/Desktop/Projects/frostr-infra
DEV_RELAY_PORT=8194 make demo-start
DEV_RELAY_PORT=8194 make demo-onboard

# 2. Build both platforms.
cd apps/igloo-mobile
just android-full
xcodebuild -project ios/IglooMobile.xcodeproj -scheme IglooMobile -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=RMP iPhone 15' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

# 3. Install + run the parity flows (note: requires boot of both devices
#    and demo credentials — see `library/user-testing.md`).
maestro --device <ios-udid-or-RMP iPhone 15> test flows/cross-parity-16-view-reachability.yaml --debug-output /tmp/parity-ios
maestro --device emulator-5554 test flows/cross-parity-16-view-reachability.yaml --debug-output /tmp/parity-android
maestro --device emulator-5554 test flows/cross-parity-android-system-back.yaml --debug-output /tmp/parity-android-android-system-back
```

The resulting `--debug-output` directories contain hierarchy dumps and
screenshots that the validator can re-attach to the
`VAL-CROSS-003` validation contract as proof of reachability.
