# ADR-003: Runtime Status and Events

## Status

Accepted

## Current Source of Truth

Current runtime-status and hosted-runtime contract details live in `docs/PROTOCOL.md` and `docs/ARCHITECTURE.md`.

## Context

Hosted clients needed a stable signer-owned contract for current state, readiness, and incremental updates.

## Decision

The hosted runtime contract is centered on:
- `runtime_status()` as the canonical current-state read model
- `drain_runtime_events()` as the incremental update stream
- `prepare_sign()` and `prepare_ecdh()` as hosted operation-prep APIs
- `wipe_state()` as the signer-owned reset primitive

## Consequences

- `runtime_status()` should be the recovery source of truth after resume or process restart
- drained events are useful for responsiveness but are not authoritative after host suspension
- extension hosts should not treat snapshots as the primary readiness surface
