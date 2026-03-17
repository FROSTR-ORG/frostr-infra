# FROSTR Architecture

This document is the living architecture spec for the current FROSTR workspace.

Architectural rationale stays in `docs/adrs/`. Current repo boundaries and host ownership rules live here.

## System Roles

- `bifrost-rs` is the signer/service core.
- `igloo-shell` is the operator shell surface over the shared host layer from `bifrost-rs`.
- `igloo-chrome` is a browser host and operator/provider surface over that signer.
- `frostr-infra` owns cross-repo orchestration, demo environments, and browser E2E harnesses.

## Core Design

### `bifrost-rs`

- Owns threshold signing, ECDH, nonce lifecycle, peer capability, and runtime readiness.
- Keeps bridge crates embeddable and in-process.
- Exposes signer-owned control and status APIs such as:
  - `runtime_status()`
  - `readiness()`
  - `prepare_sign()`
  - `prepare_ecdh()`
  - `drain_runtime_events()`
  - `wipe_state()`
- Treats `runtime_status()` as the canonical host read model.
- Treats drained runtime events as incremental updates, not the recovery source of truth.

### `igloo-shell`

- Owns CLI, TUI, relay, keygen, `bfshare` / `bfonboard` / `bfprofile` operator flows, and shell-owned runtime E2E flows.
- Uses a daemon-capable `bifrost-app` host layer rather than reimplementing signer orchestration.
- Owns the operator-facing profile/vault workflow and shell manuals.

### `bifrost-app`

- Owns the native host/runtime bootstrap layer over `bifrost-bridge-tokio`.
- Is the correct home for daemon RPC, event streaming, and graceful shutdown support used by `igloo-shell`.
- Must not turn `bifrost-bridge-tokio` itself into a daemon-only API.

### `igloo-chrome`

- Hosts the signer runtime through the MV3 background service worker and offscreen document.
- Uses background as the control plane.
- Uses offscreen as the runtime host boundary.
- Uses options/popup/prompt pages as UI surfaces only.
- Must not reimplement signer logic or derive readiness from browser-side heuristics when signer-owned APIs already exist.
- Must not depend on shell-specific daemon transport or shell-managed profile storage.

### `frostr-infra`

- Owns cross-repo Playwright coverage and any browser-level tests that span multiple repos.
- Owns the Docker demo harness used for manual onboarding and live pairing tests.
- Provides the top-level architecture, ADR, and guidance docs that apply across submodules.

## Runtime and Persistence

- Onboarding packages are consume-time inputs, not steady-state runtime state.
- After onboarding, the signer/runtime snapshot and signer metadata are the persisted source of truth.
- `igloo-chrome` should persist browser-owned state only as needed to restore the hosted signer runtime.
- Snapshot exports are for persistence and diagnostics, not the primary UI readiness model.

## Host Boundary

- `bifrost-rs` owns:
  - signer state
  - peer capability
  - readiness
  - runtime reset semantics
  - protocol validation
- `bifrost-app` owns:
  - native host bootstrap
  - daemon request/response/event transport
  - graceful native runtime shutdown
- `igloo-chrome` owns:
  - extension lifecycle
  - provider permissions and prompts
  - browser storage wiring
  - operator UI
  - background/offscreen orchestration
- `igloo-shell` owns:
  - profile management
  - encrypted local vault
  - daemon lifecycle UX
  - CLI and TUI UX

## Testing Layer

- Unit/integration coverage belongs in the repo that owns the logic.
- Browser-host integration and cross-repo flows belong in top-level `test/`.
- Live E2E should reuse shared worker fixtures when possible and reserve isolated startup for tests that truly require fresh one-time onboarding material.
