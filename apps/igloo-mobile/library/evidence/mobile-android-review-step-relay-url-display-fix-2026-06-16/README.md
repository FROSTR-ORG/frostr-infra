# mobile-android-review-step-relay-url-display-fix Evidence

## Summary

The Android Compose `CreateKeysetReviewScreen` (Step 3 of 4 in the
Create Keyset wizard) used to render the relay URL `ws://127.0.0.1:8194`
— the iOS-Simulator localhost literal the shared Rust core pre-fills
into `KeysetFlowState.relays` — even when the user clearly saw and
accepted the platform-correct `ws://10.0.2.2:8194` on the prior Device
Profile step. The mismatch violated VAL-CREATE-008 ("each displayed
value exactly matches what was entered or generated") and silently
guaranteed every Android wizard run took its first signer-start with
the iOS-Simulator relay URL as a stale prefix in `accepted_profile_id`'s
relay list.

`mobile-android-create-keyset-wizard-relay-url-fix` (commit `ee7234e`)
added a Compose-side override that rewrote the iOS localhost prefill to
`RelayDefaults.DEFAULT` for display. That fix changed what the Device
Profile form *displayed* but never *synced back* to the actor's
`keyset.relays`. The Review screen reads `keysetState.relays`
straight from the actor, so it kept rendering the stale prefill.

This follow-up adds a one-shot actor sync on first composition of the
`CreateKeysetDeviceProfileScreen`. Whenever the Compose-side override
fires, we dispatch `AppAction.CreateKeysetUpdateRelays([RelayDefaults.DEFAULT])`
so the actor carries the platform-correct value into the Review step
(and beyond, into Distribute and the persisted profile).

iOS Compose does not need this sync: the actor's iOS-Simulator
localhost prefill IS its platform-correct value, so the override's
trigger condition (`actor relays == [ws://127.0.0.1:8194] || empty`)
never fires in practice. The iOS app's existing source-of-truth flow
through `relaysText` and `manager.state.keyset.relays` continues
working unchanged.

## Source verification

`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`

- `CreateKeysetDeviceProfileScreen` (line `~2057`):
  - New `LaunchedEffect(Unit)` dispatches
    `AppAction.CreateKeysetUpdateRelays([RelayDefaults.DEFAULT])` once
    on first composition whenever the Compose override fired (i.e.
    `initialRelays == [RelayDefaults.DEFAULT]` and the actor relays
    were either empty or `[ws://127.0.0.1:8194]`).
  - The condition matches the same shape as the display override so
    that user-typed relay lists survive the sync untouched.

`apps/igloo-mobile/android/app/src/test/java/com/frostr/igloo/RelayDefaultsTest.kt`

- Three new tests pin the sync contract:
  - `create_keyset_wizard_sync_after_device_profile_ios_prefill` —
    actor prefill `[ws://127.0.0.1:8194]` syncs to
    `[RelayDefaults.DEFAULT]` once the override fires.
  - `create_keyset_wizard_sync_after_device_profile_empty_actor` —
    empty actor relays also sync to `[RelayDefaults.DEFAULT]`.
  - `create_keyset_wizard_sync_preserves_user_relays` —
    user-typed relay lists survive the sync; only the iOS prefill
    shape triggers the rewrite.

`apps/igloo-mobile/rust/src/updates.rs`

- `AppAction::CreateKeysetUpdateRelays` is unchanged — already
  unconditionally sets `next.keyset.relays = value.clone();`. The
  Rust core accepts the platform-correct value with no schema/validation
  churn, so no Rust code change is needed for this fix.

## Live Android emulator verification

Fresh-install flow executed end-to-end on the Android emulator
`rmp_api35` (debug app id `com.frostr.igloo.dev`):

1. `adb shell pm clear com.frostr.igloo.dev` — start from a clean hub.
2. `adb shell am start -n com.frostr.igloo.dev/com.frostr.igloo.MainActivity`
   — open the app.
3. Tap "Create / Rotate Keyset" hub tile.
4. Tap "Create New Keyset" mode tile.
5. Tap `input_group_name` and type `test-review-relay-fix`.
6. Tap `btn_generate` at the form's threshold `2`, count `3` defaults.
7. Wait ~30s for Argon2id keygen to land on the Device Profile step.

Device Profile uiautomator dump (saved next to this README as
`device-profile-step-uiautomator.xml`):

```
text="ws://10.0.2.2:8194" resource-id="input_relays"
text="test-review-relay-fix" resource-id="input_device_name"
text="Continue to Review"
```

8. Tap "Continue to Review" button (around `(540, 2147)`).

Review step uiautomator dump (saved next to this README as
`review-step-post-fix-uiautomator.xml`):

```
text="Review" subtitle="Step 3 of 4"
text="Profile Name"
text="test-review-relay-fix"
text="Device Share Public Key"        sharing pubkey 93890f76748c4a67...
text="Group Public Key"               group pubkey 09adb6923d084384...
text="Relays"
text="ws://10.0.2.2:8194"             <-- the platform-correct Android alias
                                       (was: ws://127.0.0.1:8194 before this fix)
text="Accept and Continue"
```

The Review step now displays the same `ws://10.0.2.2:8194` the user
saw on Device Profile — VAL-CREATE-008 parity is restored on Android.
The pre-fix expectation per the validator (Review step showing
`ws://127.0.0.1:8194`) is no longer reproducible end-to-end from a
fresh install.

## Build / static / test verification

Run from the repo root after sourcing `~/.config/frostr/rmp-mobile-env.zsh`:

- `cd apps/igloo-mobile/rust && cargo fmt --check`
  — exit `0`. No Rust formatting changes (the fix lives entirely in
  Compose + the unit-test mirror).
- `cd apps/igloo-mobile/rust && cargo clippy --workspace -- -D warnings`
  — exit `0`. No Rust clippy warnings.
- `cd apps/igloo-mobile/rust && cargo test --workspace -- --test-threads=9`
  — exit `0`. **152 passed; 0 failed; 0 ignored** (matches the
  152-pass baseline captured by
  `mobile-android-create-keyset-wizard-relay-url-fix`).
- `cd apps/igloo-mobile/android && ./gradlew :app:testDebugUnitTest --tests com.frostr.igloo.RelayDefaultsTest`
  — exit `0`. **10 passed; 0 failed; 0 ignored** (3 pre-existing
  default-constant tests + 4 pre-existing wizard override tests
  + 3 new sync tests). `test-results.xml` captures the run.
- `cd apps/igloo-mobile/android && ./gradlew :app:assembleDebug`
  — exit `0`. Gradle result: **BUILD SUCCESSFUL**. The same
  pre-existing AGP/compileSdk 35 minSdk 26 warnings appear; this fix
  adds no new warnings.

## iOS parity preservation

`apps/igloo-mobile/ios/Sources/ContentView.swift` `CreateKeysetDeviceProfileView`
is untouched: the iOS shell still pre-fills
`relaysText = manager.state.keyset.relays.joined(separator: "\n")` on
`onAppear`. iOS continues to receive `ws://127.0.0.1:8194` from the
actor, which IS the iOS-Simulator host-loopback value. The sync
LaunchedEffect's condition `actorNeedsReset =
keysetState.relays.isEmpty() || keysetState.relays == [ws://127.0.0.1:8194]`
will fire on iOS too, but `displayIsAndroidDefault = (initialRelays
== [RelayDefaults.DEFAULT])` is false because iOS has no Compose-side
override in the first place (`initialRelays` is always
`keysetState.relays`). So iOS Compose never dispatches an UpdateRelays
that disagrees with its shell state.

## Caveats

- The previous fix
  (`mobile-android-create-keyset-wizard-relay-url-fix`) intentionally
  kept the Android-side override inside Compose and the Rust core
  neutral, exactly as documented in the feature's own README. This
  follow-up respects that ownership split: the Rust core still emits
  `default_relay_url() == "ws://127.0.0.1:8194"` after
  `CreateKeysetGenerationSuccess` and the Compose shell still owns
  the platform-correct rewrite via the Android `RelayDefaults.DEFAULT`
  and the new sync dispatch.
- The Android emulator run was a fresh install (`pm clear` first);
  no pre-existing profiles from earlier onboarding or create-keyset
  runs were carried into the wizard. A re-run with a profile already
  stored would also work because re-entry into the Device Profile
  screen happens with the synced relay already present on the actor,
  so `actorNeedsReset` is false and the dispatch is correctly a no-op.
- No secrets, package strings, passwords, or share material are
  captured in this evidence directory beyond what the wizard already
  surfaces in plaintext to the user (the device profile name
  `test-review-relay-fix`, which is what the user typed; the ASTERISK
  for share pubkey is the wizard's own ellipsis-truncated display
  for VAL-CREATE-008 parity with the bearing
  accessibility-value/copy affordance for full retrieval).
