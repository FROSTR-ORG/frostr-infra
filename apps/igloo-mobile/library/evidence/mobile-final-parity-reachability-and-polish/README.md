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

## What parity gaps are NOT closed by this milestone

Per the validation-state.json snapshot from Round 5, several
signer-state assertions are still blocked on the iOS signer Start
regression and the Android signer `Restoring...` deadlock. Those
gaps belong to follow-up features (`mobile-signer-runtime-restoring-readiness-fix`,
`mobile-export-artifact-flow-validation-unblocker`):

* `VAL-SIGNER-002` through `VAL-SIGNER-013` iOS side (blocked by signer Start).
* `VAL-SIGNER-004` through `VAL-SIGNER-009` peer onboarding (stuck in Restoring).
* `VAL-PERM-002` through `VAL-PERM-013` policy-matrix rendering
  (tied to `VAL-SIGNER-004` readiness).
* `VAL-LOAD-001` through `VAL-LOAD-019` batch (depends on Signer/Export pipelines).
* `VAL-CROSS-004` through `VAL-CROSS-005` (cross-device assertions requiring
  both platforms sign-ready).

None of these gaps block `VAL-CROSS-003` reachability (the views
themselves are reachable, their signer-dependent content is not).

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
maestro --device <ios-udid-or-RMP iPhone 15> test flows/cross-parity-android-system-back.yaml --debug-output /tmp/parity-android-system-back
maestro --device emulator-5554 test flows/cross-parity-16-view-reachability.yaml --debug-output /tmp/parity-android
maestro --device emulator-5554 test flows/cross-parity-android-system-back.yaml --debug-output /tmp/parity-android-android-system-back
```

The resulting `--debug-output` directories contain hierarchy dumps and
screenshots that the validator can re-attach to the
`VAL-CROSS-003` validation contract as proof of reachability.
