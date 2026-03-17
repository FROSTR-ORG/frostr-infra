# ADR-005: Shell Daemon Over `bifrost-app`

## Status

Accepted

## Context

The hard-cut `igloo-shell` V2 surface needs a long-lived per-profile daemon for CLI and TUI workflows, but the repo already has a layered runtime stack in `bifrost-rs`:

- `bifrost-signer` owns signer state and protocol logic
- `bifrost-router` owns runtime coordination and request lifecycle
- `bifrost-bridge-tokio` owns the async in-process bridge
- `bifrost-app` owns the host/runtime bootstrap layer

We need to add daemon lifecycle, typed RPC, and event streaming without creating a second shell-specific runtime path that bypasses the router or talks to the signer directly.

## Decision

The shell daemon is implemented as a `bifrost-app` host layer over the existing Tokio bridge/runtime stack.

The live runtime path is:

- `igloo-shell` profile and vault layer
- `bifrost-app` daemon host layer
- `bifrost-bridge-tokio::Bridge`
- `bifrost-router`
- `bifrost-signer`

`igloo-shell` is responsible for:

- managed profile storage
- encrypted local vault and unlock flow
- daemon lifecycle from the shell UX
- CLI and TUI presentation

`bifrost-app` is responsible for:

- starting a runtime from resolved bootstrap material
- serving typed control requests
- serving typed runtime events
- graceful shutdown and persistence coordination

`igloo-shell` must not invoke `bifrost-signer` directly for live operations such as sign, ecdh, ping, onboard, readiness, peer status, or runtime status.

## Consequences

- there is one runtime execution model for shell-hosted operations
- router behavior, readiness, pending operations, and nonce handling stay authoritative in `bifrost-rs`
- daemon-specific code is reusable by non-shell native hosts if needed later
- shell work focuses on profile/vault/operator UX instead of duplicating runtime orchestration
- changes to daemon RPC or event transport should be made in `bifrost-app`, not in ad hoc shell code
