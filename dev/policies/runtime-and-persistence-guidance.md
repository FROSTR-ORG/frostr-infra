# Runtime and Persistence Guidance

## Current Model

- onboarding packages are import artifacts
- runtime snapshots and signer metadata are the persistent runtime source of truth
- hosted clients should restore from signer/runtime state, not from onboarding packages

## Preferred Changes

- clarify signer-owned readiness and restore behavior
- improve reset semantics through signer APIs such as `wipe_state()`
- keep persistence boundaries explicit between signer-owned state and host-owned storage

## Review Prompts

- does this change reintroduce onboarding-package persistence as a recovery path?
- is snapshot data being used as a diagnostics/persistence surface or as an accidental readiness API?
- does the host own only storage wiring, or is it starting to own signer semantics?
