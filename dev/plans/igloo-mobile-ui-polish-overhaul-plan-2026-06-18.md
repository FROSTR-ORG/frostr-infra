# Plan: igloo-mobile UI polish overhaul

Living plan for a minimal but high-impact native UI/UX polish pass across
`apps/igloo-mobile` on iOS and Android.

## Goal

Make the current native mobile app feel intentionally designed, consistent, and
close to the `igloo-ui` product language without importing or depending on
`igloo-ui` directly.

This is a native parity pass, not a rewrite:

- keep the Rust TEA state machine and navigation behavior unchanged unless a
  polish slice proves a small behavior bug
- keep SwiftUI and Jetpack Compose as thin renderers over `AppState`
- preserve existing accessibility identifiers and Maestro selectors
- verify each slice on both iOS and Android
- use `igloo-ui` as reference material only: tokens, component vocabulary,
  hierarchy, and interaction contracts

## Execution update: 2026-06-18

Completed the first high-impact implementation cut:

- built native iOS and Android primitives for panel surfaces, action rows,
  icon tiles, press feedback, and status/action affordances
- polished the landing hub, empty profile state, stored profile rows, dashboard
  header, dashboard tabs, signer status card, identity/key rows, signer
  controls, settings relay rows, settings maintenance actions, save/logout
  actions, and shared flow headers
- preserved the existing Rust state machine, navigation model, and public
  Maestro selectors; Android gained missing parity selectors for dashboard tabs,
  signer status, refresh, and test ping
- kept `igloo-ui` and `igloo-paper` as references only; no runtime imports or
  package dependencies were added

Verification completed after the implementation cut:

```bash
cargo test --manifest-path apps/igloo-mobile/rust/Cargo.toml --workspace
npm --prefix test run test:guards
cd apps/igloo-mobile/android && ./gradlew :app:testDebugUnitTest
cd apps/igloo-mobile && just ios-build
cd apps/igloo-mobile && just android-assemble
cd apps/igloo-mobile && just focus-cross-flow-ios
cd apps/igloo-mobile && just focus-cross-flow-android
cd apps/igloo-mobile && just focus-ios-export
cd apps/igloo-mobile && just focus-android-export
cd apps/igloo-mobile && just focus-ios-load-artifacts
cd apps/igloo-mobile && just focus-android-load-artifacts
cd apps/igloo-mobile && just focus-ios-rotate-share
cd apps/igloo-mobile && just focus-android-rotate-share
cd apps/igloo-mobile && just focus-ios-qr-display
cd apps/igloo-mobile && just focus-android-qr-display
```

Fresh-state hub validation also passed on both the booted `RMP iPhone 15`
simulator and Android `emulator-5554` with `flows/hub-validation.yaml`.

Evidence folders from the focused smoke run:

- `apps/igloo-mobile/library/evidence/mobile-cross-flow-persistence-ios-2026-06-18-093915`
- `apps/igloo-mobile/library/evidence/mobile-cross-flow-persistence-android-2026-06-18-094403`
- `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-ios-2026-06-18-095028`
- `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-android-2026-06-18-095028`
- `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-ios-2026-06-18-095208`
- `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-android-2026-06-18-095209`
- `apps/igloo-mobile/library/evidence/mobile-ios-rotate-share-2026-06-18-095253`
- `apps/igloo-mobile/library/evidence/mobile-android-rotate-share-2026-06-18-095253`
- `apps/igloo-mobile/library/evidence/mobile-ios-qr-display-2026-06-18-095506`
- `apps/igloo-mobile/library/evidence/mobile-android-qr-display-2026-06-18-095505`

## Current baseline

`apps/igloo-mobile` is a Rust Multiplatform app:

- Rust core: `apps/igloo-mobile/rust`
- iOS shell: `apps/igloo-mobile/ios/Sources/ContentView.swift`
- iOS tokens: `apps/igloo-mobile/ios/Sources/Theme.swift`
- Android shell: `apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`
- Android tokens: `apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/theme/Theme.kt`
- validation: `just` build targets, Rust tests, Android unit tests, Maestro
  flows, focused validators, and evidence under `apps/igloo-mobile/library/evidence`

Observed polish opportunities:

- Android and iOS share token names, but many primitives are still inline in the
  large native UI files.
- iOS has better platform iconography through SF Symbols; Android still uses
  text glyphs such as `[K]`, `[L]`, `[+]`, `>`, and emoji-like delete glyphs.
- Both platforms use many hard stroked panels. This preserves structure, but
  the hierarchy reads heavy, especially on dashboard screens.
- Typography is mono-heavy on Android and large relative to available phone
  width. The app looks secure, but sometimes less calm and scannable than
  `igloo-ui`.
- Dashboard, Settings, and flow screens duplicate surface, field, button, and
  row treatments instead of using native primitives.

## Boundary rules

- Do not import `repos/igloo-ui` into mobile app builds.
- Do not import `repos/igloo-paper` into mobile app builds.
- Treat `repos/igloo-ui/src/tokens/design-tokens.*` and exported components as
  reference material only.
- If token drift is addressed, use a parent-owned script or app-local generated
  constants, not a runtime package dependency.
- Keep screenshots and generated smoke evidence under `.tmp/` or
  `apps/igloo-mobile/library/evidence/`.

## Design reference map

Use these `igloo-ui` concepts as the source vocabulary:

| igloo-ui reference | Native mobile equivalent to build or align |
| --- | --- |
| `Button`, `IconButton` | `IglooButton`, `IglooIconButton`, tactile press feedback |
| `Card`, `ContentCard` | `IglooPanel`, `IglooInsetPanel`, `IglooActionRow` |
| `HostEntryTile` | native hub entry tile with real platform icons |
| `StoredProfilesLandingCard` | stored profile row/card with actions and status |
| `StepIndicator` | native step progress strip with active/completed states |
| `StatusDot`, `StatusBadge` | unified status badge with dot + label |
| `OperatorDashboardTabs` | mobile-adapted segmented dashboard navigation |
| `OperatorSignerPanel` | denser signer status, identity, peers, log sections |
| `OperatorSettingsPanel` | structured settings sections and maintenance rows |
| `ExportPackageModal`, `QrPayloadModal` | native modal surfaces with matching hierarchy |

## Polish principles to apply

- Concentric radii: nested rounded surfaces must account for padding.
- Prefer soft depth and tint changes over repeated hard borders where depth is
  the purpose; keep real dividers as dividers.
- Minimum hit area: 44x44 pt/dp for touch targets.
- Press feedback: subtle scale to `0.96` where native platform behavior allows
  it without interfering with Maestro.
- Use specific transitions and native interruptible animation APIs.
- Dynamic numbers and timers use tabular numeric treatment where supported.
- Headings should wrap cleanly; avoid one-word orphan lines on key screens.
- Icons should be platform-native and optically centered.
- Disabled states must read intentional, not merely faded.

## TDD and verification shape

Use vertical slices. Do not write a large test suite ahead of implementation.

For each slice:

1. RED: add or run the smallest public-interface check that protects the slice.
   Prefer existing Maestro flows, UI tests, Android unit tests, or a small token
   parity/unit test. Do not test private rendering helpers.
2. GREEN: make the smallest native UI change that passes the check and preserves
   selectors.
3. REFACTOR: extract duplication into native primitives only after the slice is
   green on both platforms.
4. VERIFY: capture before/after screenshots and run the relevant smoke lane.

Tests should assert behavior and accessibility surface:

- the same view is reachable
- the same action dispatches
- the same selector exists
- disabled controls are disabled for users, not only styled
- entered values, copied packages, saved settings, and navigation still work

Visual review is required, but screenshot inspection complements behavior tests;
it does not replace them.

## Implementation slices

### Slice 0: baseline evidence

No UI changes.

- Capture current iOS and Android launch/dashboard/settings screenshots.
- Run cheap build/test checks to confirm the starting point.
- Record known automation limitations from `library/user-testing.md`.
- Decide whether screenshots live in `.tmp/mobile-ui-polish-baseline-*` or a
  dated evidence folder.

Suggested checks:

```bash
cd apps/igloo-mobile
cargo test --manifest-path rust/Cargo.toml --workspace
cd android && ./gradlew :app:testDebugUnitTest
```

### Slice 1: native design primitive layer

Create or consolidate small native primitives on both platforms:

- `IglooPanel`
- `IglooActionRow`
- `IglooButton`
- `IglooIconButton`
- `IglooTextField` / `IglooSecureField`
- `IglooStatusBadge`
- `IglooStepProgress`
- `IglooSectionHeader`

Keep these primitives shallow at the call site and deep internally. They own
radii, padding, hit area, disabled state, press feedback, and status styling.

First target:

- migrate hub tiles and empty profile row only
- preserve `tile_create_keyset`, `tile_load_profile`, `tile_onboard_device`,
  and `empty_profiles_state`

### Slice 2: landing hub and stored profiles

Align mobile `HostEntryTile` and stored profile treatments to the `igloo-ui`
welcome/host language.

High-impact changes:

- Android: replace `[K]`, `[L]`, `[+]`, `>`, and delete glyphs with real vector
  or Material icons.
- iOS: tighten entry tile typography and spacing to match Android after icon fix.
- Both: reduce mono-heavy emphasis, improve subtitle wrapping, tune card height,
  and make profile row actions visually distinct from row navigation.

Smoke:

```bash
maestro test flows/hub-validation.yaml
maestro test flows/cross-parity-16-view-reachability.yaml
```

Run on both platforms where the flow supports it.

### Slice 3: dashboard chrome

Polish `DashboardHeader` and `DashboardTabBar` on both platforms.

High-impact changes:

- make the tab treatment feel more like a native segmented dashboard control
  while preserving `tab_signer`, `tab_permissions`, and `tab_settings`
- improve back affordance hit area and optical alignment
- reduce the heavy horizontal rule feel
- keep the profile title and short id visible and stable for validators

Smoke:

```bash
just focus-ios-keyset
just focus-android-keyset
maestro test flows/cross-parity-16-view-reachability.yaml
```

### Slice 4: signer dashboard content

Align the operator surface to `OperatorSignerPanel` while staying phone-native.

High-impact changes:

- unify `SignerStatusCard`, `ProfileIdentityBlock`, and copied-key rows
- make the primary runtime action visually dominant but not oversized
- use status dot + badge patterns for stopped/running/degraded/readiness
- make copy controls at least 44x44 and visually lighter
- tighten peers, event log, pending ops, and test operation cards
- apply tabular numeric treatment to counters, timestamps, and nonce badges

Smoke:

```bash
just focus-cross-flow-ios
just focus-cross-flow-android
```

If runtime changes are not touched, this is still the right public smoke lane
because it proves real dashboard operation after onboarding and restore.

### Slice 5: settings and maintenance

Align Settings to `OperatorSettingsPanel`.

High-impact changes:

- structured sections: Signer Identity, Signer Settings or Advanced, Relay List,
  Maintenance, Save, Logout
- native action rows for Copy Profile, Copy Share, Rotate/Replace Share
- consistent text fields and number fields
- clearer save-blocked state while signer is stopped
- consistent export password prompt across platforms

Smoke:

```bash
just focus-ios-export
just focus-android-export
just focus-ios-load-artifacts
just focus-android-load-artifacts
just focus-ios-rotate-share
just focus-android-rotate-share
```

### Slice 6: create, load, onboard, rotate flows

Polish the multi-step flow surfaces using the same primitives.

High-impact changes:

- consistent `ScreenHeader`, step progress, task cards, form fields, and review
  rows
- improve QR modal and scanner fallback affordances
- make error banners consistent and calm
- ensure keyboard/focus behavior stays usable on both platforms

Smoke:

```bash
maestro test flows/cross-parity-16-view-reachability.yaml
just focus-ios-qr-display
just focus-android-qr-display
just focus-ios-rotate-share
just focus-android-rotate-share
```

### Slice 7: final cross-platform verification

Run the full smoke matrix for both platforms.

Minimum final verification:

```bash
cd apps/igloo-mobile
cargo test --manifest-path rust/Cargo.toml --workspace
cd android && ./gradlew :app:testDebugUnitTest
cd ..
just ios-full
just android-full
just focus-cross-flow-ios
just focus-cross-flow-android
just focus-ios-export
just focus-android-export
just focus-ios-load-artifacts
just focus-android-load-artifacts
just focus-ios-rotate-share
just focus-android-rotate-share
just focus-ios-qr-display
just focus-android-qr-display
```

Also refresh screenshots for:

- landing hub empty state
- landing hub with stored profile
- dashboard signer stopped
- dashboard signer running/sign-ready
- permissions tab
- settings tab
- export password prompt
- create distribute QR modal
- rotate preview

## Acceptance criteria

- Both platforms still build.
- Existing Rust state tests and Android JVM tests pass.
- Existing critical Maestro selectors are preserved.
- Landing, dashboard, settings, create, load, onboard, rotate, export, and QR
  paths smoke successfully on iOS and Android.
- Screenshots show Android and iOS sharing the same Igloo visual language while
  respecting native platform affordances.
- No runtime dependency on `igloo-ui` or `igloo-paper` is introduced.
- Any validation gap caused by known simulator/Maestro limitations is documented
  with a screenshot, hierarchy dump, and clear explanation.

## First recommended hard cut

Start with Slices 0 through 2 only:

1. lock the visual baseline
2. introduce the primitive layer through hub tiles
3. polish landing hub and stored profiles on iOS and Android
4. smoke with hub validation and 16-view reachability

This gives the app an immediate first-screen lift, proves the primitive pattern,
and keeps blast radius small before touching dashboard/runtime-heavy surfaces.
