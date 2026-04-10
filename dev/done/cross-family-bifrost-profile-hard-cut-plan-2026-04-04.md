# Cross-Family Hard-Cut Plan: Shared Profile Domain in `bifrost-rs`

## Summary
Do a multi-phase hard-cut migration that removes `igloo-shell-core` as the shared application backend and replaces it with one shared Rust domain layer in `bifrost-rs`.

Target end state:
- `bifrost-core`
  - protocol, crypto, canonical runtime types, validation, package wire types
- `bifrost-app`
  - runtime/bootstrap/daemon/signer orchestration
- new shared profile domain crate in `bifrost-rs`
  - profile manifests
  - encrypted profile metadata and secret-reference rules
  - package import/export/recovery/onboarding flows
  - relay-profile management
  - backup publish/fetch workflows
  - typed domain results/errors
- new WASM facade for that domain crate
  - used by `igloo-pwa` and `igloo-chrome`
- host adapters
  - native adapters for `igloo-shell` and `igloo-home`
  - browser adapters for `igloo-pwa` and `igloo-chrome`

Chosen default:
- put shared profile/package/encrypted profile/onboarding behavior in a new `bifrost-rs` crate, not in `bifrost-core`
- keep platform differences in adapters only
- make `igloo-shell` and `igloo-home` consumers of the shared domain layer, not owners of duplicated product logic

## Target Architecture

### New shared crate
Create a new crate in `repos/bifrost-rs/crates/`, for example `bifrost-profile`.

This crate should own:
- profile manifest models and validation
- relay-profile models and mutation rules
- encrypted profile metadata, secret-reference contracts, and unlock requirements
- package preview/import/export/recovery/onboarding domain logic
- backup publish/fetch workflows
- typed request/result/error models used by native and browser hosts

This crate should not own:
- low-level crypto/protocol primitives already in `bifrost-core`
- live runtime/bridge/daemon lifecycle already in `bifrost-app`
- direct filesystem, Tauri, Chrome storage, IndexedDB, or env-var assumptions

### Adapter model
Define adapter traits or service interfaces for:
- manifest/profile storage
- encrypted profile/blob storage
- relay-profile storage
- time/id generation
- optional network publish/fetch for profile backup workflows
- optional runtime/bootstrap lookup hooks where domain flows need runtime context

Chosen default:
- domain crate APIs are storage-agnostic and async where needed
- native/browser hosts implement adapters; the domain crate contains product rules only

### WASM exposure
Add a dedicated WASM-facing package for the new domain crate, separate from the current signer/runtime bridge surface.

Chosen default:
- create a separate crate/package such as `bifrost-profile-wasm`
- expose typed command/result functions for profile/package/onboarding flows
- do not merge this API into the existing runtime bridge surface in a way that mixes concerns

## Migration Phases

### Phase 0. Freeze ownership and compatibility goals
Hard decisions for the full migration:
- `igloo-shell-core` stops being the shared application backend
- `igloo-home` stops importing broad `igloo_shell_core::shell::*` product logic
- browser hosts stop duplicating profile/package/onboarding business rules in TypeScript
- CLI/Tauri/extension/PWA user-facing behavior should remain stable where practical during migration

Compatibility defaults:
- command names and user-visible flows remain stable unless a later cleanup explicitly changes them
- wire/package formats stay backward compatible during the migration
- storage schemas may be wrapped by adapters first and migrated later only if necessary

### Phase 1. Create the shared profile domain crate in `bifrost-rs`
Build the new crate and move the shared product logic out of `igloo-shell-core`.

Move into the new crate:
- profile manifests and profile mutation rules
- relay-profile management
- encrypted profile metadata and secret-reference behavior
- package preview/import/export/recovery logic
- onboarding/finalize/recovery domain flows
- backup publish/fetch domain orchestration

Do not move:
- CLI prompt/output behavior
- Tauri/window/tray behavior
- Chrome/background routing behavior
- direct filesystem or browser-storage code

Implementation rule:
- this phase should introduce `bifrost-profile` as the new source of truth while preserving current behavior through temporary compatibility shims in `igloo-shell-core`

### Phase 2. Add native adapters and migrate `igloo-shell`
Make `igloo-shell` consume the new domain crate through native adapters.

Scope:
- add filesystem-backed adapters for profiles, relay profiles, encrypted profile metadata, and package artifacts
- update `igloo-shell-core` so its public shell functions become orchestration wrappers over `bifrost-profile` plus `bifrost-app`
- keep CLI behavior stable
- progressively reduce `igloo-shell-core` until it becomes CLI-oriented composition instead of domain ownership

Chosen default:
- keep `igloo-shell-core` temporarily as a facade during the migration
- after migration, decide whether to keep it as a thin shell composition crate or collapse it further

### Phase 3. Migrate `igloo-home` to the new domain layer
Replace `igloo-home`’s direct dependence on `igloo-shell-core` product behavior.

Scope:
- add an `igloo-home` adapter/service boundary that depends on `bifrost-profile` and `bifrost-app`
- move profile/package/encrypted profile/onboarding flows in `profiles.rs`, `app/commands.rs`, and session startup helpers to that boundary
- replace shell-owned DTO leakage with `igloo-home`-owned internal service contracts where useful
- keep Tauri commands and TCP test commands stable

Chosen default:
- `igloo-home` continues to use `bifrost-app` directly for runtime/session control
- the new domain crate replaces `igloo-shell-core` for profile/package/onboarding behavior

### Phase 4. Add browser adapters and WASM facade
Make the same shared product logic available to `igloo-pwa` and `igloo-chrome`.

Scope:
- implement browser storage/network adapters for the managed domain layer
- expose a typed WASM API for:
  - profile list/read/update/remove
  - relay-profile list/update/default
  - package preview/import/export/recovery
  - onboarding/finalize flows
  - backup publish/fetch flows
- keep runtime/signer flows on the existing bridge/runtime side

Chosen default:
- `igloo-pwa` and `igloo-chrome` consume the new managed WASM API for profile/package/onboarding behavior
- they continue using the runtime bridge/WASM surface separately for signer/runtime operations

Important boundary rule:
- do not collapse runtime and profile-domain APIs into one undifferentiated WASM surface

### Phase 5. Remove the old ownership model
After native and browser consumers are migrated:
- remove or heavily reduce the shared-domain role of `igloo-shell-core`
- delete compatibility wrappers that only forward to the new domain crate
- consolidate tests around the new domain crate and adapter layers

End-state acceptance:
- shared product behavior exists once in `bifrost-rs`
- adapter implementations are the only family-specific duplication
- `igloo-shell`, `igloo-home`, `igloo-pwa`, and `igloo-chrome` all consume the same domain logic

## Public APIs / Interfaces / Types

### New shared Rust APIs
Add a new public domain API surface in `bifrost-rs` for:
- profile and relay-profile operations
- package preview/import/export/recovery
- onboarding/finalize flows
- backup publish/fetch
- typed result/error contracts

Chosen default:
- public APIs are typed and command-oriented
- avoid exposing raw internal storage structs directly as the stable API

### New adapter interfaces
Define explicit traits/interfaces for:
- profile manifest store
- encrypted profile metadata/blob store
- relay-profile store
- backup transport
- time/id generation

### New WASM APIs
Expose the profile-domain API through a dedicated WASM package:
- typed input/output models
- browser-safe adapter-backed execution
- no direct desktop-path or env assumptions

### Compatibility expectations
- current package formats remain stable
- current runtime bridge contracts remain separate
- CLI/Tauri/extension/PWA command surfaces may wrap the new APIs, but should avoid protocol churn during migration

## Test Plan

### Shared domain crate
- unit tests for:
  - profile manifest validation and mutation rules
  - relay-profile rules and default-selection behavior
  - encrypted profile metadata and secret-reference validation
  - package preview/import/export/recovery flows
  - onboarding/finalize/backup domain behavior
- adapter-contract tests using in-memory fake stores/transports

### Native hosts
- `igloo-shell`:
  - workspace `cargo test`
  - regression tests proving CLI output/flags stay stable while using the new domain layer
- `igloo-home`:
  - `cargo test --manifest-path repos/igloo-home/src-tauri/Cargo.toml`
  - `npm test`
  - `npm run test:visual`
  - `npm --prefix test run test:e2e:igloo-home`
  - regression tests proving Tauri commands and TCP test commands preserve current success/error envelopes

### Browser hosts
- WASM-level tests for profile-domain APIs with browser-like fake adapters
- `igloo-pwa` and `igloo-chrome` tests proving:
  - profile/package/onboarding flows use the managed WASM API
  - runtime flows still use the runtime bridge API
  - no duplicate business-rule implementations remain in host TypeScript

### Cross-family acceptance
- the same fixture scenarios should pass for native and browser hosts where behavior is intended to match
- no normal host flow should depend on `igloo-shell-core` as a shared backend after migration

## Assumptions and Defaults
- This is an alpha-stage architectural hard cut; large internal moves are acceptable.
- DRY is the priority: shared product behavior should live once in Rust.
- `bifrost-core` should remain low-level; the new managed/domain crate belongs in the `bifrost-rs` workspace but not in the `core` crate.
- Platform-specific storage/network behavior should exist only in adapters.
- `igloo-shell-core` may remain temporarily as a migration facade, but not as the long-term owner of shared product behavior.
