# ADR-004: Cross-Repo E2E Ownership

## Status

Accepted

## Context

Browser and live-runtime tests had drifted into submodules even when they depended on multiple repos and infra-owned harnesses.

## Decision

Cross-repo browser E2E lives in top-level `test/` inside `frostr-infra`.

That includes:
- Playwright harness code
- live signer fixtures
- Docker demo harness integration
- cross-repo runtime and provider flows

## Consequences

- submodule repos should keep their own unit/integration coverage
- infra owns the browser-level integration layer when it spans multiple repos
- future cross-repo E2E should not be reintroduced into individual submodules
