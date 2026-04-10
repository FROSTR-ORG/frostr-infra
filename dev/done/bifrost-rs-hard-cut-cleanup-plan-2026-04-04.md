# Hard-Cut Cleanup Plan for `bifrost-rs`

## Summary
Do a behavior-preserving internal cleanup of `bifrost-rs` focused on the control plane and runtime bootstrap layer.

Goals:
- split the `bifrost-app` host/runtime monoliths into explicit modules
- make daemon/control protocol responses more strongly typed
- centralize signer/bootstrap lifecycle so downstream hosts stop re-implementing bridge startup
- improve testability of runtime, daemon, and diagnostics paths

This pass should not change wire behavior for existing callers unless a compatibility break is explicitly chosen later.

## Why This Matters
- [crates/bifrost-app/src/host.rs](/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/host.rs) is 1777 lines and currently mixes protocol types, client transport, daemon server logic, command execution, bridge startup, and tests.
- [crates/bifrost-app/src/runtime.rs](/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/runtime.rs) is 749 lines and currently mixes config schema/defaults, state storage, locking, encrypted persistence, and signer bootstrap.
- The same runtime boot logic is effectively repeated by downstream hosts like `igloo-home` in [src-tauri/src/session.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session.rs).

## Key Changes

### 1. Split `bifrost-app` host into explicit modules
Keep `host.rs` as a thin facade or barrel only. Move implementation into `crates/bifrost-app/src/host/`.

Target split:
- `protocol.rs`
  - `ControlCommand`
  - `ControlRequest`
  - `ControlResponse`
  - typed response payloads
- `client.rs`
  - `DaemonClient`
  - request/request_ok transport helpers
- `daemon.rs`
  - `run_resolved_daemon`
  - socket server lifecycle
  - shutdown coordination
- `handlers.rs`
  - command execution for status, diagnostics, sign, ecdh, onboarding, config, wipe
- `logging.rs`
  - tracing init
  - default log filter policy
- `types.rs`
  - daemon transport config
  - diagnostics snapshot types

Rules:
- command routing should not live next to Unix socket IO
- `serde_json::Value` should be limited to genuine dynamic payloads, not used as the default response type
- test modules should move next to the implementation they cover instead of remaining embedded in one giant file

### 2. Split runtime bootstrap and persistence
Move `runtime.rs` implementation into `crates/bifrost-app/src/runtime/`.

Target split:
- `config.rs`
  - `AppConfig`
  - `ResolvedAppConfig`
  - `AppOptions`
  - defaults and serde schema
- `store.rs`
  - `EncryptedFileStore`
  - file-lock and persistence helpers
- `health.rs`
  - state inspection
  - run markers
  - health reports
- `bootstrap.rs`
  - `load_or_init_signer_resolved`
  - resolve/load bootstrap sequence
- `paths.rs`
  - state path normalization and file naming helpers

Rules:
- config/defaults should not share a file with crypto persistence
- signer bootstrap should be callable as a focused library API by downstream hosts
- begin/complete run marker logic should be isolated from config parsing

### 3. Introduce typed control response payloads
Replace the current mostly-JSON-shaped command results with typed response enums/structs.

Priority commands:
- `Status`
- `RuntimeStatus`
- `RuntimeDiagnostics`
- `Readiness`
- `ReadConfig`
- `RuntimeMetadata`
- `PeerStatus`

Rules:
- keep command names stable for now
- `ControlResponse` may still carry tagged JSON at the outermost layer if needed, but handler internals should return typed payload structs first
- downstream users such as `igloo-shell` should consume typed helper APIs where possible instead of manually unpacking raw JSON

### 4. Centralize signer/bridge startup for downstream hosts
Create one explicit runtime bootstrap entrypoint in `bifrost-app` that downstream consumers can call instead of reconstructing the sequence locally.

Target responsibility:
- accept resolved config plus store
- load/init signer
- start bridge with config
- return a typed runtime session/bootstrap result

This should become the preferred path for:
- `bifrost-app` daemon startup
- `igloo-home` session startup
- any future desktop/extension hosts

### 5. Improve test seams
Add focused unit and integration coverage around:
- host protocol encode/decode
- daemon request handling
- runtime bootstrap success/failure
- encrypted state persistence
- run marker health transitions

Shift away from giant file-local tests and toward module-local test coverage.

## Public APIs / Interface Changes
- No required end-user CLI or signer behavior changes in this pass.
- Internal module layout changes substantially.
- Stronger typed APIs may be added in `bifrost-app` for downstream hosts, while existing public exports remain available during the refactor.

## Test Plan
- `cargo test -p bifrost-app`
- `cargo test -p bifrost-bridge-tokio`
- `cargo test -p bifrost-signer`
- workspace `cargo test`
- targeted daemon/control integration coverage for:
  - config reads and updates
  - readiness and diagnostics
  - sign/ecdh failure paths
  - wipe/shutdown flows

## Acceptance Criteria
- `host.rs` and `runtime.rs` stop being primary implementation monoliths
- daemon transport, command handling, and protocol typing are clearly separated
- runtime bootstrap is reusable by downstream hosts without copy-pasted lifecycle logic
- control responses are more strongly typed internally
- test coverage exists at the new module seams

## Assumptions and Defaults
- Preserve current daemon command names and core signer behavior.
- Prefer incremental internal hard cuts over an immediate external protocol redesign.
- Use this cleanup to make later host-side simplification in `igloo-shell` and `igloo-home` easier.
