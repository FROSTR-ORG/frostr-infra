# ADR-006: Bridge Transport Boundaries for Tokio, WASM, and Mobile

## Status

Accepted

## Context

The V2 shell introduces a daemon-capable native host model. At the same time, the workspace already has multiple host environments:

- native shell and future native apps using Tokio
- browser hosts using `bifrost-bridge-wasm`
- potential mobile hosts on Android or iOS

We need to avoid turning the Tokio bridge into a daemon-only interface or forcing browser/mobile hosts into a shell-specific transport model.

## Decision

Daemon transport is a host-layer concern above the bridge, not a responsibility of the bridge itself.

The transport boundary is:

- `bifrost-bridge-tokio` remains an embeddable in-process async bridge
- `bifrost-bridge-wasm` remains an embeddable in-process browser bridge
- daemon RPC and event transport live in `bifrost-app`

For mobile:

- native mobile hosts may embed `bifrost-bridge-tokio` directly
- a mobile-specific wrapper may be added later for lifecycle or FFI ergonomics
- no separate mobile bridge is required by the shell daemon decision alone

For browser:

- `bifrost-bridge-wasm` does not adopt Unix sockets, daemon lifecycle, or shell-managed storage assumptions
- WASM should align with shared runtime concepts and data shapes where practical

## Consequences

- the shell daemon does not reduce the usefulness of `bifrost-bridge-tokio` for native apps
- browser and mobile hosts avoid shell-specific transport coupling
- shared runtime semantics should be normalized at the type/API level, not by forcing one transport model onto every host
- future mobile work can focus on host lifecycle and FFI rather than rethinking signer orchestration
