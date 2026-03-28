# Architecture Guidance

Use this document to evaluate whether a change fits the current system design.

## Preferred Shape

- put signer logic in `bifrost-rs`
- keep browser hosts thin
- keep infra responsible for cross-repo orchestration and browser E2E

## Healthy Changes

- adding signer-owned APIs for state, readiness, reset, or protocol behavior
- simplifying host code by replacing browser-side inference with signer-owned status
- moving cross-repo browser tests into top-level infra
- keeping shell-managed profile and secret storage concerns in `igloo-shell`

## Drift Signals

- browser code deriving signer truth from local heuristics when signer APIs already exist
- duplicate runtime logic across host and signer
- protocol decisions being implemented only in UI code
- cross-repo browser tests being added back into submodules
- `bifrost-rs` learning about shell vault layout or shell profile storage semantics

## Review Prompts

- does this logic belong in the signer core or only in the host?
- is a host-side heuristic compensating for a missing signer API?
- is a new test in the correct repo for the behavior it verifies?
