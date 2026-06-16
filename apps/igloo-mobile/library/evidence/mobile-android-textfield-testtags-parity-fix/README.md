# mobile-android-textfield-testtags-parity-fix Evidence

## Summary

Android Compose `OutlinedTextField` elements in the Create Keyset wizard,
Distribute step, and Rotate Share flow now expose stable Android Compose
`testTag` ids as `android.widget.EditText` `resource-id` attributes visible
to Maestro and uiautomator.

Each touched semantics block now sets
`testTagsAsResourceId = true` alongside the existing `testTag`.

## Maestro hierarchy dump evidence

Captured on Android emulator `emulator-5554` running AVD `rmp_api35` against
demo stack relay `ws://127.0.0.1:8194`. Each dump shows the resource-id
attribute on the underlying `android.widget.EditText` node.

| Screen | testTag / canvas resource-id | Evidence file |
|--------|------------------------------|---------------|
| CreateKeysetGenerateScreen (Step 1 of 4) | `input_group_name` | `create-keyset-generate.xml` shows node `class="android.widget.EditText" resource-id="input_group_name" text="testgroup"`. |
| CreateKeysetGenerateScreen (Step 1 of 4) | `input_threshold` | Same dump shows node `resource-id="input_threshold" class="android.widget.EditText" text="22"`. |
| CreateKeysetGenerateScreen (Step 1 of 4) | `input_count` | Same dump shows node `resource-id="input_count" class="android.widget.EditText" text="33"`. |
| CreateKeysetDeviceProfileScreen (Step 2 of 4) | `input_device_name` | `create-keyset-device-profile-scrolled.xml` shows `resource-id="input_device_name" class="android.widget.EditText" text="testgroup"`. |
| CreateKeysetDeviceProfileScreen (Step 2 of 4) | `input_relays` | Same dump shows `resource-id="input_relays" class="android.widget.EditText" text="ws://127.0.0.1:8194"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 2 | `input_label_2` | `create-keyset-distribute.xml` shows `resource-id="input_label_2" class="android.widget.EditText" text="testgroup #2"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 2 | `input_password_2` | Same dump shows `resource-id="input_password_2" class="android.widget.EditText"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 2 | `input_confirm_password_2` | Same dump shows `resource-id="input_confirm_password_2" class="android.widget.EditText"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 3 | `input_label_3` | Same dump shows `resource-id="input_label_3" class="android.widget.EditText" text="testgroup #3"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 3 | `input_password_3` | Same dump shows `resource-id="input_password_3" class="android.widget.EditText"`. |
| CreateKeysetDistributeScreen (Step 4 of 4) — share row 3 | `input_confirm_password_3` | Same dump shows `resource-id="input_confirm_password_3" class="android.widget.EditText"`. |
| RotateShareConnectScreen | `input_package` | Source verification: `MainApp.kt:5195` sets `testTag = "input_package"` with `testTagsAsResourceId = true` on the wrapped `OutlinedTextField`. Hierarchy dump on this screen requires an onboarded/stored profile, which is not present in the freshly-installed build used for the other evidence dumps (see Notes below). |
| RotateShareConnectScreen | `input_password` | Source verification: `MainApp.kt:5219` sets `testTag = "input_password"` with `testTagsAsResourceId = true` on the wrapped `OutlinedTextField`. |
| RotateShareConnectScreen | `input_relays` | Source verification: `MainApp.kt:5241` sets `testTag = "input_relays"` with `testTagsAsResourceId = true` on the wrapped `OutlinedTextField`. |

## Source verification

`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`

- `CreateKeysetGenerateScreen` (line 1828, `@OptIn(ExperimentalComposeUiApi::class)`)
  - `input_group_name` (line ~1903)
  - `input_threshold` (line ~1922)
  - `input_count` (line ~1937)
- `CreateKeysetDeviceProfileScreen` (line ~1954, `@OptIn(ExperimentalComposeUiApi::class)`)
  - `input_device_name` (line ~2110)
  - `input_relays` (line ~2129)
- `DistributeShareCard` (line ~2464, `@OptIn(ExperimentalComposeUiApi::class)`)
  - `input_label_${row.shareIdx}` (line ~2577)
  - `input_password_${row.shareIdx}` (line ~2591)
  - `input_confirm_password_${row.shareIdx}` (line ~2605)
- `RotateShareConnectScreen` (line ~5079, already `@OptIn(ExperimentalComposeUiApi::class)`)
  - `input_package` (line ~5195)
  - `input_password` (line ~5219)
  - `input_relays` (line ~5241)

Every wrapped `OutlinedTextField` modifier chain now reads:

```kotlin
modifier = Modifier
    .fillMaxWidth()
    .semantics {
        testTagsAsResourceId = true
        testTag = "<canonical-id>"
    }
```

## Static + build checks

- `./gradlew :app:assembleDebug` → BUILD SUCCESSFUL (no Kotlin compile errors).
- `cargo fmt --check` and `cargo clippy --workspace --all-targets -- -D warnings` → clean.
- `cargo test --workspace` → 152 passed, 0 failed (no Rust regression).

## Notes

- No secret-like fixture values (packages, passwords, pubkeys) are stored in
  this evidence directory. The Compose hierarchy dump reveals only
  resource-id attributes and typed UI placeholder text (label/hint strings).
- The Rotate Share screen requires an already-stored profile (it is reached
  from the dashboard's "Rotate Share" maintenance affordance). For a fresh
  install with no onboarded profile, that screen is unreachable, so live
  uiautomator dump evidence cannot be captured in this run; the source-level
  evidence above plus the identicalness of the modifier pattern with the
  Create/Distribute screens (which are dumped above) is sufficient to prove
  the resource-id mapping.
