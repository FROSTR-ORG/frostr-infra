# mobile-android-hub-profile-row-routing-fix

Validator report: tapping the hub row for one stored profile sometimes opened a
different stored profile's dashboard (the row's `profile_id` did not match
the dashboard's `profile_id`). Root cause: the Android Compose hub iteration
was a bare `for (profile in manager.state.hub.profiles)` loop without a
stable `key(...)` block, so the captured `profile` in each row's openProfile
lambda drifted relative to the visible row when the hub list grew or
re-ordered. The iOS shell's `ForEach(..., id: \.profileId)` already pinned
this; the Android shell did not.

## Fix

`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`:

```kotlin
for (profile in manager.state.hub.profiles) {
    key(profile.profileId) {
        ProfileRowView(
            profile = profile,
            onClick = { manager.openProfile(profileId = profile.profileId) },
            onDelete = { manager.requestDeleteProfile(profileId = profile.profileId) }
        )
    }
}
```

Each `key(...)` block pins the slot-table key to the actual `profile.profiled`,
so the lambda captured for the row at any list position always carries the
profile the user can see in that row. Matches iOS `ForEach(..., id: \.profileId)`.

A new Rust regression test pins the OpenProfile -> Dashboard routing
contract on the actor side: `open_profile_routes_to_dashboard_with_matching_identity`
in `apps/igloo-mobile/rust/tests/state_machine_tests.rs`. Test simulates
profile A → B → A taps against the actor and asserts the
`dashboard.profile_info.{profile_id, device_name}` round-trips exactly
with the dispatched `AppAction::OpenProfile.profile_id`. With this in place,
any future shell-side cross-contamination regression will surface as a
visible Compose identity mismatch.

## Verification (live demo-stack)

Pre-load:
- `bash apps/igloo-mobile/scripts/inject-android-bob-and-carol-two-profiles.sh`
  → onboards bob as `test-r2` (short id `f1e748b7`) and carol as
  `test-cross-003` (short id `4a36d42d`) on emulator-5554 against the live
  demo relay at `ws://10.0.2.2:8194`.

Sequence captured in this directory:

| File | Step | Observation |
|------|------|-------------|
| `hub-both-rows-post-inject.xml` / `.png` | Hub after both onboards | Two profile rows present, labels `test-r2` and `test-cross-003`, hub short ids `f1e748b7` and `4a36d42d` |
| `05-tap-test-r2.xml` / `.png` | Tap `test-r2` row | Dashboard `dashboard_header_subtitle` = `f1e748b7` (test-r2's profile_id short) |
| `06-tap-test-cross-003.xml` / `.png` | Tap `test-cross-003` row | Dashboard `dashboard_header_subtitle` = `4a36d42d` (test-cross-003's profile_id short) |
| `07-tap-test-r2-again.xml` / `.png` | Tap `test-r2` again | Dashboard `dashboard_header_subtitle` swaps back to `f1e748b7` (no cross-contamination) |

Redaction: any captured `bfonboard1q…` package string or 32-char password
bytes in the dump are replaced with `[REDACTED_LEN_N]` tokens.

## Scope and non-goals

- The `dashboard_header_title` text shows `Onboarded Device` because the
  baked-in `device_name` field in `OnboardProfileMaterial` material bytes
  (returned by `rust.onboard()`) is the package-default and not the
  user-typed `input_device_name`. This is a separate issue from the row
  routing bug and belongs to a follow-up `VAL-ONBOARD-008 identity-name`
  parity fix; not addressed here because the feature scope is row tap ->
  profile_id routing, which is fully verified.
- iOS Maestro onboarding and the Android debug intent have documented
  iOS-blocked manual-UI limitations; the row-routing verification on
  Android uses the debug intent + `adb shell input tap` because that path
  is what produces two stored-profile rows on the device today.

## Redacted-input summary

Stored under `redacted-summary.txt`:

```
scenario: mobile-android-hub-profile-row-routing-fix
device: emulator-5554 (API 35)
relay: ws://10.0.2.2:8194 (demo-stack)
redacted: package/password bytes replaced with [REDACTED_LEN_N] tokens
```

## Run command

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile
just android-full
bash scripts/inject-android-bob-and-carol-two-profiles.sh
# adb-driven row tap verification (in this README) writes evidence here.
```
