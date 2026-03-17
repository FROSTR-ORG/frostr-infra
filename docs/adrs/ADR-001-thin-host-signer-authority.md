# ADR-001: Thin Host, Signer Authority

## Status

Accepted

## Context

The browser host and the signer core had begun to duplicate readiness, peer-state, and runtime-control logic.

## Decision

`bifrost-rs` is the authority for signer state, readiness, peer capability, and runtime reset semantics.

Hosted clients such as `igloo-chrome`:
- host the signer
- surface signer state
- route provider and operator actions
- do not reimplement signer logic

## Consequences

- `igloo-chrome` should stay thin.
- signer-owned APIs should be preferred over browser-side heuristics.
- future work that moves signer logic back into the host should be treated as architectural drift.
