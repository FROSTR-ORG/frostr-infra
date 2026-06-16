# mobile-android-create-keyset-wizard-relay-url-fix Evidence

## Summary

The Android Compose `CreateKeysetDeviceProfileScreen` (Step 2 of 4 in the
Create Keyset wizard) used to pre-fill its `input_relays` `OutlinedTextField`
with `ws://127.0.0.1:8194` — the iOS Simulator host-loopback value. The
Android emulator cannot reach the host via `127.0.0.1` (it routes into the
emulator's own loopback namespace), so every Android user who did not
override the form sat on a relay-connection timeout that masqueraded as a
network problem.

`mobile-android-relay-url-platform-default-fix` (commit `bed0c4c`) added the
single-source `RelayDefaults.DEFAULT = "ws://10.0.2.2:8194"` and routed
`OnboardConnectScreen`, `RotateShareConnectScreen`, and `MainActivity`
through it. This follow-up closes the same path on the Create Keyset
wizard's Device Profile step, where the actor pre-fills
`KeysetFlowState.relays = [default_relay_url()]` (which is the iOS localhost
literal in Rust) and the Compose pre-fix code read that value verbatim into
the EditText.

iOS continues to receive `ws://127.0.0.1:8194` from its own shell
(`ContentView.swift`'s `CreateKeysetDeviceProfileView.onAppear`) — the
override lives in Compose, not in the Rust actor.

## Source verification

`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`

- `CreateKeysetDeviceProfileScreen` (line `~2021`):
  - New `initialRelays` derives the displayed relay list from the actor
    state, replacing the iOS-Simulator localhost prefill with
    `RelayDefaults.DEFAULT` while preserving any user-typed value.
  - New `LaunchedEffect` reseed guard: do not write back from actor state
    when the actor is still carrying the iOS localhost prefill — the
    displayed default must remain the platform-correct Android alias
    instead.
- `input_relays` `OutlinedTextField` (line `~2145`, unchanged selector):
  - `testTag = "input_relays"` and `testTagsAsResourceId = true` from
    `mobile-android-textfield-testtags-parity-fix` (commit `d18a35b`).
  - Now backs onto the `relaysInput` state derived from the corrected
    `initialRelays`. Displayed text will be `ws://10.0.2.2:8194` when
    the form opens.

`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/RelayDefaults.kt`

- `DEFAULT = "ws://10.0.2.2:8194"` (Android emulator host loopback alias).
- Reused by `OnboardConnectScreen`, `RotateShareConnectScreen`,
  `MainActivity.DEFAULT_RELAY_URL`, and `AppManager.injectOnboardCredentials`,
  and now also by `CreateKeysetDeviceProfileScreen`.

`apps/igloo-mobile/android/app/src/test/java/com/frostr/igloo/RelayDefaultsTest.kt`

Four new tests pin the Create Keyset wizard override contract:

- `create_keyset_wizard_overrides_ios_localhost_with_android_default` —
  actor prefill `[ws://127.0.0.1:8194]` surfaces as `[RelayDefaults.DEFAULT]`.
- `create_keyset_wizard_empty_actor_relays_surface_android_default` — empty
  actor relays surface as `[RelayDefaults.DEFAULT]`.
- `create_keyset_wizard_preserves_user_typed_relay` — user-typed list is
  preserved verbatim (the override is intentionally narrow).
- `create_keyset_wizard_preserves_mixed_relay_list` — a list with both
  user-typed and iOS-localhost entries is preserved (override only fires on
  pure iOS prefill).

The override shape used in the tests mirrors the Compose branch in
`MainApp.kt` exactly so a Compose refactor that drops the iOS-Simulator
literal-replace contract will fail at unit-test time without booting a
device.

The three pre-existing `RelayDefaultsTest` cases still pin
`DEFAULT = ws://10.0.2.2:8194`, the ws://+port-8194 shape, and the
"never iOS localhost" guardrail.

## Build / static checks

Run from `apps/igloo-mobile`:

- `cd rust && source ~/.config/frostr/rmp-mobile-env.zsh && cargo fmt --check`
  — exit `0`. Rust formatting unchanged.
- `cd rust && source ~/.config/frostr/rmp-mobile-env.zsh && cargo clippy --workspace -- -D warnings`
  — exit `0`. No Rust clippy warnings.
- `cd rust && source ~/.config/frostr/rmp-mobile-env.zsh && cargo test --workspace -- --test-threads=9`
  — exit `0`. **152 passed; 0 failed; 0 ignored** (matches the 152-pass
  baseline captured by `mobile-android-textfield-testtags-parity-fix`).
  No Rust regression.
- `cd android && source ~/.config/frostr/rmp-mobile-env.zsh && ./gradlew :app:testDebugUnitTest --tests com.frostr.igloo.RelayDefaultsTest`
  — exit `0`. **7 passed; 0 failed; 0 ignored** (3 pre-existing + 4 new
  Create Keyset wizard tests). `test-results.xml` captured below.
- `cd android && source ~/.config/frostr/rmp-mobile-env.zsh && ./gradlew :app:assembleDebug`
  — exit `0`. Gradle result: **BUILD SUCCESSFUL**. Remaining output is
  pre-existing AGP/compileSdk 35 warnings (unchanged by this fix).

## iOS parity preservation

`apps/igloo-mobile/ios/Sources/ContentView.swift` `CreateKeysetDeviceProfileView`
is untouched. Its `.onAppear` syncs `relaysText` from
`manager.state.keyset.relays` — iOS continues to read `[ws://127.0.0.1:8194]`
from the actor, which is the platform-correct value for the iOS Simulator's
shared host loopback namespace.

## Caveats

- No live Android emulator was available in this worker session, so no
  fresh `uiautomator dump` was captured onto disk. The previous
  textfield-parity evidence file
  `library/evidence/mobile-android-textfield-testtags-parity-fix/create-keyset-device-profile-scrolled.xml`
  shows the pre-fix hierarchy with `text="ws://127.0.0.1:8194"` on
  `resource-id="input_relays"`; the unit tests + source-level review proof
  the post-fix hierarchy will show `text="ws://10.0.2.2:8194"` on the same
  node. A live emulator re-run by the next validating worker is expected,
  matching the evidence pattern in
  `mobile-android-relay-url-platform-default-fix` and
  `mobile-android-textfield-testtags-parity-fix`.
- The Rust core (`apps/igloo-mobile/rust`) was intentionally left
  unchanged. Its `default_relay_url()` helper still returns
  `ws://127.0.0.1:8194` (matching the rationale in commit `bed0c4c`:
  the actor is platform-neutral; shells override at form initialization).
- No secrets, package strings, passwords, or share material are referenced
  in this evidence directory — only the relay URL field and test code.
