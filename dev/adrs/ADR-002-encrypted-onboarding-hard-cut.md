# ADR-002: Encrypted Onboarding Hard Cut

## Status

Accepted

## Current Source of Truth

Current onboarding protocol details live in `docs/PROTOCOL.md`.

## Context

The onboarding flow needed a single secure model instead of mixed plaintext and compatibility behavior.

## Decision

The current onboarding model is a hard cut:
- provisioning assembles encrypted `bfonboard`
- password is required
- onboarding packages are consume-time artifacts only
- successful onboarding persists signer/runtime state, not the imported package

## Consequences

- no legacy plaintext onboarding path should be reintroduced
- browser hosts should not rely on stored onboarding packages for recovery
- docs and tests should model onboarding as consume-and-bootstrap, not package persistence
