# Igloo Mobile

FROSTR iOS and Android signing clients with full `igloo-pwa` parity.
Built as a [Rust Multiplatform (RMP)](https://github.com/nickthecook/rmp) app: a shared Rust core drives state, navigation, and the FROSTR signing runtime; thin native shells (SwiftUI / Jetpack Compose) render the UI and execute platform-specific commands.

- **Mission**: Build iOS + Android FROSTR signing clients with full `igloo-pwa` parity.
- **Location**: `apps/igloo-mobile/` in the `frostr-infra` workspace.
- **Demo relay**: port `8194` (see `make demo-start` in the workspace root).

---

## Architecture

The app follows **The Elm Architecture (TEA)**:

| Layer | Responsibility | Technology |
|-------|----------------|------------|
| **Rust core** (`rust/`) | Single source of truth: application state, actions, navigation router, FROSTR signing runtime, Nostr relay communication | Rust, UniFFI 0.31, `tokio`, `bifrost-rs` |
| **iOS shell** (`ios/`) | Receives `AppState` snapshots, renders UI, forwards user input as actions | SwiftUI, Xcode |
| **Android shell** (`android/`) | Receives `AppState` snapshots, renders UI, forwards user input as actions | Jetpack Compose, Gradle |
| **FFI bridge** | UniFFI generates Swift + Kotlin bindings from the Rust crate | `uniffi-bindgen` |

The Rust core owns the entire screen stack (`Router` / `Screen` variants), so both platforms share identical navigation semantics. Shells are stateless renderers: they receive full `AppState` snapshots (with a monotonic `rev` guard for staleness detection) and map them to native views.

### Rust core modules

- `state.rs` — top-level `AppState` and `rev` counter
- `router.rs` — `Screen` variants (16 reachable views, hub + flows + dashboard tabs)
- `state/hub.rs` — landing hub, stored profile list, profile status
- `state/keyset.rs` — Create Keyset wizard state (4-step flow)
- `state/load_profile.rs` — Load Profile flow (Import / Recover / Confirm)
- `state/onboarding.rs` — Onboard Device handshake state
- `state/dashboard.rs` — Dashboard: signer runtime, permissions matrix, settings
- `state/rotate_share.rs` — Rotate Share flow

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Shared core | Rust 2021 edition, `tokio` async runtime |
| FFI | UniFFI 0.31.0 (Swift + Kotlin bindings) |
| Signing / Nostr | `bifrost-rs` crates (`bifrost-core`, `bifrost-signer`, `bifrost-app`, `bifrost-bridge-tokio`, `bifrost-codec`) |
| iOS shell | SwiftUI, Xcode, `IglooMobileCore.xcframework` |
| Android shell | Jetpack Compose (BOM 2024.06.00), Gradle 8.x, `ndkVersion 28.2.13676358`, `minSdk 26` |
| QR rendering | `zxing-core` (Android), native Swift (iOS) |
| Secure storage | Keychain (iOS), `EncryptedSharedPreferences` / Keystore (Android) |
| Relay WebSocket | `tokio-tungstenite` with `rustls-tls-webpki-roots` |

---

## Project Structure

```
apps/igloo-mobile/
├── rust/                    # Shared Rust core (crate: igloo-mobile-core)
│   ├── src/
│   │   ├── lib.rs           # UniFFI exports, FFI action handler
│   │   ├── state.rs         # AppState root
│   │   └── state/           # Per-flow state modules
│   └── tests/               # Workspace integration + unit tests
├── ios/                     # SwiftUI shell
│   ├── IglooMobile.xcodeproj
│   ├── Bindings/            # UniFFI-generated Swift FFI
│   └── Frameworks/          # IglooMobileCore.xcframework
├── android/                 # Jetpack Compose shell
│   └── app/src/main/...     # Kotlin UI + UniFFI Kotlin bindings
├── flows/                   # Maestro validation flows (YAML)
├── scripts/                 # Build, test, and diagnostic helpers
├── library/
│   ├── evidence/            # Screenshots, hierarchy dumps, test logs
│   ├── parity/              # 16-view reachability audit docs
│   └── *.md                 # Handoff notes, export recipes
├── justfile                 # Curated build commands (just ios-build, just android-full)
├── rmp.toml                 # RMP project configuration
└── Cargo.toml / Cargo.lock  # Rust workspace root
```

---

## Setup

### Prerequisites

1. **Rust toolchain** — install via rustup (not Homebrew). The workspace `rust-toolchain.toml` pins the required stable target set.
2. **Xcode** — iOS 17+ SDK, iPhone Simulator. `xcodebuild` and `xcodegen` must be on `PATH`.
3. **Android SDK** — API 35, NDK `28.2.13676358`, `cargo-ndk` for cross-compilation.
4. **RMP CLI** — `rmp` handles binding generation and simulator/device runs.
5. **Maestro** — for running automated UI validation flows (optional, for QA).
6. **Demo relay** — `make demo-start` from the workspace root (defaults to auto-picking a free port; `8194` is the usual default).

### Environment

Some build commands expect the RMP mobile environment:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
```

This sets up Android SDK paths, NDK variables, and any repo-local toolchain overrides.

---

## Build

### iOS

```bash
# Fast path (for day-to-day iteration)
source ~/.config/frostr/rmp-mobile-env.zsh && just ios-build

# Full pipeline (host build → bindings → cross-compile → xcframework → xcodegen → build)
just ios-full
```

The `ios-full` recipe runs:
1. `rust-build-host` — builds `igloo-mobile-core` for the host (required for `uniffi-bindgen`)
2. `ios-gen-swift` — regenerates Swift bindings
3. `ios-rust` — cross-compiles for `aarch64-apple-ios` and `aarch64-apple-ios-sim`
4. `ios-xcframework` — packages static libs into `IglooMobileCore.xcframework`
5. `ios-xcodeproj` — regenerates the Xcode project with `xcodegen`
6. `ios-build` — builds the iOS app for the simulator

### Android

```bash
# Fast path
just android-full
```

The `android-full` recipe runs:
1. `rust-build-host` — host build for binding generation
2. `gen-kotlin` — regenerates Kotlin bindings via `uniffi-bindgen`
3. `android-rust` — cross-compiles for `arm64-v8a`, `armeabi-v7a`, `x86_64` into `jniLibs/`
4. `android-assemble` — assembles the debug APK with Gradle

### Rebuild bindings only (all platforms)

```bash
just rebind
```

---

## Test

### Rust workspace tests

```bash
cd rust
cargo test --workspace
```

Runs the Rust workspace tests covering:
- State machine transitions (`state_machine_tests`)
- Backup publication and recovery round-trips (`backup_publication_and_recovery`)
- Cross-platform keyset interop (`cross_platform_keyset_interop`)
- Onboarding against live and offline relays (`onboard_live_relay`, `onboard_provisioner_offline`)
- Export recipe flows (`export_recipe`)
- Signer runtime recovery (`signer_runtime_recovery`)
- Rotate share flows (`rotate_share_flow`)
- Create-keyset diagnostics (`diagnostics_create_keyset`)

### Maestro UI flows

Maestro YAML flows live in `flows/` and validate end-to-end navigation across both platforms:

```bash
# Example: validate the landing hub
maestro test flows/hub-validation.yaml

# Example: onboard iOS device (with diagnostic output)
maestro test flows/onboard-ios-diagnostic.yaml

# Example: 16-view parity reachability
maestro test flows/cross-parity-16-view-reachability.yaml
```

Platform-specific flows are named accordingly (`*-ios.yaml`, `*-android.yaml`). Shared flows use `appId: com.frostr.igloo.dev`.

### Focused cross-flow persistence validators

The focused validators exercise the full first-launch-to-signature journey,
real force-quit/relaunch persistence, durable Settings/Permissions edits, and
two-profile identity isolation (`VAL-CROSS-001`, `VAL-CROSS-002`,
`VAL-CROSS-006`, `VAL-CROSS-010`).

They require the demo relay/onboard credentials, a booted target, and a current
debug app build:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-cross-flow-ios
just focus-cross-flow-android
```

Each run writes screenshots, hierarchies, generated Maestro flows, and logs
under `library/evidence/mobile-cross-flow-persistence-*/`.

### Cross-platform interop evidence

The canonical cross-platform byte-contract suite exercises the shared Rust
package codec, keyset generation, share verification, and rotation primitives
embedded by both native shells (`VAL-CROSS-005`, `VAL-CROSS-008`):

```bash
cargo test --manifest-path rust/Cargo.toml --test cross_platform_keyset_interop -- --nocapture
cargo test --manifest-path rust/Cargo.toml --test rotate_share_flow -- --nocapture
```

Fresh evidence is captured under
`library/evidence/mobile-cross-platform-keyset-and-rotation-interop-2026-06-17-150201/`.

### Focused create-keyset validator

The iOS focused create-keyset validator exercises the DEBUG-gated
`igloo://test-create-keyset` path and asserts that the generated profile lands
on a Dashboard identity surface:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-ios-keyset
just focus-android-keyset
```

The Android focused create-keyset validator uses a DEBUG-only intent to drive
the same Rust diagnostics action and requires a native `stored=yes` proof plus
a Dashboard hierarchy containing the generated device identity.

Evidence is written under `library/evidence/mobile-ios-keyset-debug-url-scheme-*/`
and `library/evidence/mobile-android-keyset-debug-intent-*/`.

### Focused export artifact validators

The focused export validators fresh-install the debug app, onboard real bob
material, export `bfprofile1` / `bfshare1`, and verify both artifacts with the
Rust decoder:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-ios-export
just focus-android-export
```

Evidence is written under `library/evidence/mobile-export-artifact-validation-*/`.

### Focused Load Profile artifact validators

Run these immediately after fresh export validation to prove both exported
artifact shapes load through the native product flows:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-ios-load-artifacts
just focus-android-load-artifacts
```

Each validator feeds the latest exported `bfprofile1` into Import and
`bfshare1` into Recover, confirms the loaded profile, and writes
`stored=yes` proof under `library/evidence/mobile-load-profile-artifacts-*/`.
The recovery leg also proves the encrypted relay backup publish/recover
round-trip used by `VAL-BACKUP-*`.

### Focused Rotate Share validators

The focused Rotate Share validators drive a live demo-relay replacement:
onboard bob, connect a same-group carol `bfonboard1` package, confirm
replacement, and assert both the native storage proof and final Dashboard
identity show the rotated profile:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-ios-rotate-share
just focus-android-rotate-share
```

Evidence is written under `library/evidence/mobile-*-rotate-share-*/`.

### Focused QR display validators

The focused QR display validators drive Create Keyset to Distribute, prepare
one non-local share row through diagnostics-gated field actions, tap the real
QR button, assert the native QR modal payload/image, and decode the screenshot
with `zbarimg`:

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
just focus-ios-qr-display
just focus-android-qr-display
```

Evidence is written under `library/evidence/mobile-*-qr-display-*/`.

### Android unit tests

```bash
cd android
./gradlew :app:testDebugUnitTest
```

These run local JVM tests for JSON parsing helpers (e.g., `PollStatusParse` timestamp null handling) without requiring an emulator.

---

## Features

| Feature | Description | Validation |
|---------|-------------|------------|
| **Landing Hub** | Three entry tiles: Create Keyset, Load Profile, Onboard Device | `VAL-SHELL-002` through `VAL-SHELL-006` |
| **Create Keyset Wizard** | 4-step flow: Generate → Device Profile → Review → Distribute | `VAL-CREATE-001` through `VAL-CREATE-015` |
| **Load Profile** | Import (`bfprofile1` package), Recover, Confirm | `VAL-LOAD-*` |
| **Onboard Device** | Handshake with demo relay via `bfonboard1` package | `VAL-ONBOARD-*` |
| **Dashboard** | Signer, Permissions, Settings tabs with runtime controls | `VAL-DASH-*` |
| **Signer Runtime** | Start / Stop / Ping / Refresh peers; event logging with RFC3339 timestamps | live proofs in `library/evidence/` |
| **Settings / Maintenance** | Relay management, profile export, share rotation | `VAL-ROTATE-*` |
| **QR Scan + Paste Fallback** | Scan `bfprofile1`/`bfonboard1` QR codes; paste fallback when camera unavailable | `VAL-QR-*` |
| **Relay Backup** | Publish encrypted kind-10000 backup to Nostr relays; recover from backup | `VAL-BACKUP-*` |
| **Cross-Flow Persistence** | First-launch signing, force-quit restore, durable settings/permissions, and multi-profile identity isolation | `just focus-cross-flow-ios`, `just focus-cross-flow-android` |
| **Cross-Platform Interop** | Keysets and profiles created on iOS load correctly on Android and vice versa | `cross_platform_keyset_interop` tests |

---

## Known Limitations

We document these honestly so new contributors understand the current testing and debug-path constraints.

1. **iOS Maestro 2.6.0 + SwiftUI automation gap**
   Maestro cannot reliably tap SwiftUI `Button` elements or enter text into `TextField` in this project. Automated UI testing on iOS relies on hierarchy inspection, coordinate taps, and URL scheme injection rather than standard Maestro `tapOn` / `inputText` commands. Documented in `library/user-testing.md` with platform-specific recipes.

2. **Android Compose `Button` `onClick` not triggerable via `adb`**
   Maestro and `adb`-based automation cannot directly fire Compose `Button` click lambdas in some views. This is a testing-infrastructure limitation, not a product bug; manual tapping and accessibility-based navigation work correctly in production builds.

3. **Focused validators use debug-only harness hooks**
   The iOS and Android cross-flow validators use diagnostics-gated URL/intent hooks for credential injection and settings persistence. Release builds do not include these entry points, and normal UI-based onboarding/settings paths remain the product surface.

4. **Some validator assertions are blocked by testing infrastructure**
   A subset of Maestro validation assertions fail due to automation limitations (e.g., element visibility timing on animated transitions) rather than actual product defects. These are tracked per-flow with `❌` screenshots and manual verification notes in `library/evidence/`.

---

## Evidence and Documentation

| Directory / File | Contents |
|------------------|----------|
| `library/evidence/` | Screenshots, hierarchy dumps (`*.json` / `*.xml`), Maestro run logs, and per-fix proof directories |
| `library/parity/CROSS-003-16-view-reachability.md` | Canonical 16-view parity inventory: every reachable screen, its Rust `Screen` variant, SwiftUI / Compose view name, hub entry path, and Maestro selector |
| `library/parity/final-polish-cleanup-notes.md` | Post-parity cleanup tracking |
| `library/export-recipe.md` | Export and backup handoff recipes |
| `library/RECOVERY-HANDOFF.md` | Recovery flow implementation notes |
| `library/user-testing.md` | Platform gotchas, Maestro recipes, and automation workarounds |
| `flows/` | 40+ Maestro validation flows covering hub, create, load, onboard, signer, export, and cross-flow persistence |
| `scripts/` | Helper scripts for credential injection, artifact verification, clipboard management, and focused test runs |

---

## Quick Reference

```bash
# Setup / doctor
rmp doctor

# Build everything
just ios-full          # iOS
just android-full      # Android

# Run Rust tests
cd rust && cargo test --workspace

# Start the demo relay stack (from workspace root)
cd ../.. && make demo-start

# Run a Maestro flow
maestro test flows/hub-validation.yaml

# Run focused cross-flow persistence validators
just focus-cross-flow-ios
just focus-cross-flow-android

# Run focused iOS create-keyset validator
just focus-ios-keyset
just focus-android-keyset

# Run focused artifact + rotate validators
just focus-ios-export
just focus-android-export
just focus-ios-load-artifacts
just focus-android-load-artifacts
just focus-ios-rotate-share
just focus-android-rotate-share
```

---

## Related Docs

- Workspace root: `../../README.md`
- FROSTR system manual: `../../docs/INDEX.md`
- Workspace engineering docs: `../../dev/README.md`
- Test harness docs: `../../test/README.md`
- `bifrost-rs` signing core: `../../repos/bifrost-rs/`
- `igloo-pwa` web client (parity target): `../../repos/igloo-pwa/`
