# Igloo Mobile Recovery Handoff

Date: 2026-06-15

## Bottom Line

The Droid mission and created code were not really lost. The live workspace app
directory was missing, but Factory preserved the mission ledger, session JSONL,
structured edits, source snapshots, and proof evidence. The app has been
reconstructed under:

`/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile`

## Recovery Sources

- Factory mission:
  `/Users/plebdev/.factory/missions/078e41eb-f422-44ff-aa08-27f952236dcf`
- Factory session:
  `/Users/plebdev/.factory/sessions/-Users-plebdev-Desktop-Projects-frostr-infra/078e41eb-f422-44ff-aa08-27f952236dcf.jsonl`
- Structured replay log:
  `/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/replay-structured-edits.log`
- Latest proof evidence restored from:
  `/Users/plebdev/.factory/missions/078e41eb-f422-44ff-aa08-27f952236dcf/library/evidence/mobile-ios-signer-peer-refresh-liveness-proof`
- Latest proof evidence copied to:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-ios-signer-peer-refresh-liveness-proof`

Key source snapshots used to restore full iOS surface:

- `ContentView.swift`:
  `/Users/plebdev/.factory/snapshots/content/a7/91eef3007a6f6955aa88735244a41c304a7947e567fa64589442b4d6af2cda`
- `AppManager.swift`:
  `/Users/plebdev/.factory/snapshots/content/e4/0dcdf7768558d5df1dbed56ce82d60a6ad8cd6de657fb975833f7c44341189`
- `ProfileStorageManager.swift`:
  `/Users/plebdev/.factory/snapshots/content/90/e615e3c0cc91f21f145810cd124a3de4a5e4718328f88ba92b7508cb947b6e`

## What Was Restored

- Recreated base `frostr-infra` checkout from `FROSTR-ORG/frostr-infra`.
- Initialized the submodules required for the mobile app and Bifrost-backed
  Rust build.
- Recreated the RMP scaffold for `apps/igloo-mobile`.
- Replayed Factory structured edits for `apps/igloo-mobile`, `services.yaml`,
  and `services/igloo-demo/entrypoint.sh`.
- Restored full iOS UI source from Factory snapshots, including onboarding,
  load-profile, dashboard, signer runtime, permissions, settings, diagnostics,
  and paste/native text support.
- Restored latest iOS manager/storage snapshots and patched compatibility for
  the regenerated Rust bindings.
- Regenerated UniFFI Swift/Kotlin bindings, iOS xcframework, and Android JNI
  libraries.
- Copied the latest peer-refresh liveness proof evidence into the app library.

## Verification

All commands below passed on 2026-06-15 from
`/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile` unless noted.

- `source ~/.config/frostr/rmp-mobile-env.zsh && just rebind`
  - Passed.
  - Rebuilt host Rust library, Swift bindings, Kotlin bindings, iOS
    `IglooMobileCore.xcframework`, and Android native libraries.
- `source ~/.config/frostr/rmp-mobile-env.zsh && just ios-build`
  - Passed.
  - Xcode result: `BUILD SUCCEEDED`.
  - Remaining output is Swift deprecation/exhaustiveness warnings only.
- `source ~/.config/frostr/rmp-mobile-env.zsh && just android-full`
  - Passed.
  - Gradle result: `BUILD SUCCESSFUL`.
  - Remaining output is the known AGP/compileSdk 35 compatibility warning and
    Gradle deprecation notice.
- `cd android && ./gradlew :app:testDebugUnitTest`
  - Passed.
  - Gradle result: `BUILD SUCCESSFUL`.
- `cd rust && source ~/.config/frostr/rmp-mobile-env.zsh && cargo test --workspace`
  - Passed.
  - 170 tests passed: 8 unit, 19 signer runtime, 143 state machine.
  - 5 live-stack tests were intentionally ignored.
- `source ~/.config/frostr/rmp-mobile-env.zsh && just doctor`
  - Passed.
  - Output: `ok: doctor checks passed`.

## Continuation Update — 2026-06-17

Cross-flow persistence is no longer pending. The mobile app now persists real
onboarded material across native secure storage, restores signer settings from
stored material, and keeps durable Settings/Permissions edits across real
force-quit/relaunch cycles on both platforms.

Focused validators added:

- `just focus-cross-flow-ios`
- `just focus-cross-flow-android`

Latest passing evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-cross-flow-persistence-ios-2026-06-17-115938`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-cross-flow-persistence-android-2026-06-17-123602`

Additional validation passed on 2026-06-17:

- `cargo fmt --all --check`
- `cargo test --workspace`
- `cargo clippy --workspace -- -D warnings`
- `cargo test --test rotate_share_flow`
- `cargo test --test state_machine_tests create_keyset`
- `just focus-ios-keyset`
  - Evidence:
    `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-ios-keyset-debug-url-scheme-2026-06-17-124842`
- live relay regression:
  `cargo test --test onboard_live_relay -- --ignored --nocapture live_relay_bob_onboard_material_starts_signer_and_test_sign_succeeds`
- `just ios-build`
- `./gradlew :app:assembleDebug :app:testDebugUnitTest`

Export artifact validation is now closed on both native shells. Focused
validators fresh-install the debug app, onboard real bob material through
diagnostics-gated automation, export `bfprofile1` / `bfshare1`, and verify
both artifacts with the Rust decoder.

Latest passing evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-ios-2026-06-17-133650`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-android-2026-06-17-133851`

Load Profile artifact validation is now closed on both native shells. The
focused validators fresh-install the debug app, feed the latest exported
`bfprofile1` into Import and `bfshare1` into Recover, confirm the loaded
profile, and require a native private-storage proof containing `stored=yes`.
The `bfshare1` recovery leg also proves the normal native
`PublishProfileBackup` path: Rust emits the update with empty `material_json`,
and each shell reloads stored profile material by `profile_id` before
publishing the encrypted kind-10000 relay backup.

Latest passing evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-ios-2026-06-17-133802`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-android-2026-06-17-134104`

Additional validation for this backup/load closure:

- `just ios-build`
- `./gradlew :app:assembleDebug :app:testDebugUnitTest`
- `just focus-ios-export`
- `just focus-ios-load-artifacts`
- `just focus-android-export`
- `just focus-android-load-artifacts`

Create-keyset native proof is now closed on Android as well as iOS. Android
has a debug-intent counterpart to the iOS `igloo://test-create-keyset` driver:
it dispatches the Rust diagnostics keyset action, stores the generated creator
profile, sets active material, starts the signer, publishes the backup side
effect, auto-finishes to Dashboard, and writes a private `stored=yes` proof.

Latest passing evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-ios-keyset-debug-url-scheme-2026-06-17-124842`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-android-keyset-debug-intent-2026-06-17-134743`

Additional validation for this create-keyset closure:

- `just ios-build`
- `./gradlew :app:assembleDebug :app:testDebugUnitTest`
- `just focus-android-keyset`

Rotate Share native/live proof is now closed on both native shells. The
focused validators fresh-install the debug app, onboard bob through the live
demo relay, rotate to carol's same-group `bfonboard1` package, confirm
replacement, require a native private-storage proof with
`profile_changed=true`, and verify the post-replace Dashboard renders the
preserved device label, rotated short id, and rotated share pubkey. The core
regression suite now also asserts that `RotateShareReplace` updates
`dashboard.profile_info` / Settings from the rotated identity and that preview
resolution keeps the active profile label instead of adopting a generic package
label.

Latest passing evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-ios-rotate-share-2026-06-17-141642`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-android-rotate-share-2026-06-17-140702`

Additional validation for this Rotate Share closure:

- `cargo test --test rotate_share_flow`
- `just ios-full`
- `just focus-ios-rotate-share`
- `just android-full`
- `./gradlew :app:testDebugUnitTest`
- `just focus-android-rotate-share`

QR scan/display is now closed on both native shells. The scan/paste fallback
validators prove the Onboard Connect QR scanner affordance falls back to a
pasteable package field when simulator camera hardware is unavailable, then
continues through the real connect/save/dashboard path. The display validators
fresh-install the debug app, drive Create Keyset to Distribute, seed the
per-share package password through diagnostics-gated field actions, tap the
real QR button, require the native QR modal payload/image, and decode the
rendered screenshot with `zbarimg` to prove a `bfonboard1` QR is scannable.

Latest passing scan/paste fallback evidence:

- iOS + Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-qr-scan-display-2026-06-17-142509`

Latest passing QR display evidence:

- iOS:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-ios-qr-display-2026-06-17-145345`
- Android:
  `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-android-qr-display-2026-06-17-145739`

Additional validation for this QR closure:

- `cargo fmt --manifest-path rust/Cargo.toml --all --check`
- `cargo test --manifest-path rust/Cargo.toml --test diagnostics_create_keyset -- --nocapture`
- `cargo test --manifest-path rust/Cargo.toml --test state_machine_tests qqr -- --nocapture`
- `just ios-build`
- `./gradlew :app:assembleDebug`
- `./gradlew :app:testDebugUnitTest`
- `just focus-ios-qr-display`
- `just focus-android-qr-display`

Cross-platform interop has fresh post-native-change proof. The refreshed
evidence reruns the canonical `VAL-CROSS-005` / `VAL-CROSS-008` Rust byte
contract after the June 17 native storage, QR, and rotate-share changes:
`bfonboard1` packages round-trip across the iOS-shaped and Android-shaped
Rust paths, group public keys survive rotation, all share public keys rotate,
and rotated packages verify only against the rotated group.

Latest passing evidence:

- `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-cross-platform-keyset-and-rotation-interop-2026-06-17-150201`

Additional validation for this interop refresh:

- `cargo fmt --manifest-path rust/Cargo.toml --all --check`
- `cargo test --manifest-path rust/Cargo.toml --test cross_platform_keyset_interop -- --nocapture`
- `cargo test --manifest-path rust/Cargo.toml --test rotate_share_flow -- --nocapture`
- `cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets -- -D warnings`

User testing validator guidance has been restored to the reconstructed app
tree and current-status-prefaced at:

- `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/user-testing.md`

The restored guide preserves the original Factory validator history, recipes,
platform gotchas, and secret-safe evidence rules. A 2026-06-17 continuation
note at the top points validators back to this handoff before treating older
round blockers as current.

Bridge events-length dedupe follow-up remains green. The Rust actor still
tracks the highest shell-supplied `events_len`, emits exactly one safe INFO row
when the bridge count advances, dedupes unchanged polls, and recovers if a
bridge restart lowers the counter before a later advancement.

Additional validation for this bridge-events refresh:

- `cargo test --manifest-path rust/Cargo.toml --test signer_runtime_recovery events_len -- --nocapture`
  - 3 passed, 0 failed.
- `cargo test --manifest-path rust/Cargo.toml --test signer_runtime_recovery -- --nocapture`
  - 24 passed, 0 failed, 1 ignored live-demo concurrency test.

Final parity/polish is closed as an app-local ledger item. The 16-view parity
inventory, final polish notes, and parity evidence README now point at current
June 17 evidence instead of stale Round 5 blockers. The remaining parity work
is refresh-only: rerun the reachability Maestro flows if a validator requests
fresh screenshots after a content rebuild.

Updated parity docs:

- `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/parity/CROSS-003-16-view-reachability.md`
- `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/parity/final-polish-cleanup-notes.md`
- `/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/library/evidence/mobile-final-parity-reachability-and-polish/README.md`

Post-completion hardening sweep also passed on 2026-06-17:

- `just doctor`
- `cargo test --manifest-path rust/Cargo.toml --workspace`
  - 254 passed, 0 failed, 10 ignored live/demo/diagnostic tests.
- `cargo fmt --manifest-path rust/Cargo.toml --all --check`
- `bash -n` over focused validator scripts and artifact helpers.
- `cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets -- -D warnings`
- `just ios-build`
- `just android-full`
- `./gradlew :app:testDebugUnitTest`
- `git diff --check`
- `npm --prefix test run test:guards`

Note: `just android-full` regenerates the UniFFI Kotlin binding with the
generator's whitespace style. The current working tree keeps the new binding
fields check-clean, and `./gradlew :app:testDebugUnitTest` was rerun after the
cleanup.

## Mission State At Recovery

Factory `features.json` showed:

- 69 total features.
- 57 completed.
- 10 pending.
- 2 cancelled.

Latest completed proof feature:

- `mobile-ios-signer-peer-refresh-liveness-proof`

Pending features at the time the mission was recovered:

- Export artifact validation.
- User testing validator.
- Bridge events length follow-up.
- Cross-flow persistence. Completed in the 2026-06-17 continuation above.
- Create-keyset flow.
- QR scan/display. Completed in the 2026-06-17 QR closure above.
- Rotate-share flow.
- Relay backup roundtrip.
- Cross-platform interop.
- Final parity and polish.

Current pending features after the 2026-06-17 final parity/polish refresh:

- None in the app-local handoff ledger. The workspace-level docs guard is green
  after initializing the pinned `repos/igloo-chrome` submodule via HTTPS.

## Caveats For Droid

- The recovered mission ledger said create-keyset and rotate-share were
  placeholders. As of the 2026-06-17 continuation, targeted Rust tests cover
  those state machines, create-keyset has iOS + Android native proof, and
  Rotate Share has iOS + Android native/live proof.
- Later Rust snapshots in the Factory content store were internally skewed
  against each other. The final Rust code is the coherent replay-reconstructed
  state that passes the full non-live Rust test suite, not a blind latest-file
  snapshot batch.
- Live relay tests were not run in this recovery pass; their test files are
  present and intentionally ignored by default because they require the live
  demo stack.

## Recommended Droid Starting Point

Continue from this checkout and treat any next mission work as a fresh scoped
change. Before changing behavior, re-run:

```sh
source ~/.config/frostr/rmp-mobile-env.zsh
cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile
just doctor
cargo test --workspace --manifest-path rust/Cargo.toml
just ios-build
just android-full
cd android && ./gradlew :app:testDebugUnitTest
```

When touching profile persistence, signer startup, Settings, Permissions, or
hub inventory behavior, also run:

```sh
just focus-cross-flow-ios
just focus-cross-flow-android
```

When touching create-keyset URL-scheme diagnostics or iOS keyset profile
creation, also run:

```sh
just focus-ios-keyset
```

When touching Rotate Share replacement, profile identity, or rotated backup
behavior, also run:

```sh
cargo test --test rotate_share_flow
just focus-ios-rotate-share
just focus-android-rotate-share
```

When touching QR scan/display behavior, also run:

```sh
cargo test --manifest-path rust/Cargo.toml --test state_machine_tests qqr -- --nocapture
cargo test --manifest-path rust/Cargo.toml --test diagnostics_create_keyset -- --nocapture
just focus-ios-qr-display
just focus-android-qr-display
```

When touching cross-platform package bytes, keyset rotation, or bfonboard
interop behavior, also run:

```sh
cargo test --manifest-path rust/Cargo.toml --test cross_platform_keyset_interop -- --nocapture
cargo test --manifest-path rust/Cargo.toml --test rotate_share_flow -- --nocapture
```

When touching signer runtime polling, event-log rows, or bridge status
deduplication, also run:

```sh
cargo test --manifest-path rust/Cargo.toml --test signer_runtime_recovery -- --nocapture
```
