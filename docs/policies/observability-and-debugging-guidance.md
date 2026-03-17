# Observability and Debugging Guidance

## Current Direction

- structured logs and diagnostics should be the default
- signer-owned status and events should drive host state
- E2E failure bundles should make stalled tests easy to localize

## Healthy Changes

- improving signer-owned status/event surfaces
- keeping logs structured and bounded
- preserving failure-only artifacts in E2E
- making background/offscreen/browser diagnostics correlate cleanly

## Drift Signals

- free-form ad hoc logging replacing structured events
- browser code guessing runtime state instead of reading signer-owned status
- tests depending on manual log inspection because artifacts are incomplete

## Review Prompts

- does this add a new source of truth for runtime state outside the signer?
- are logs safe, structured, and useful when the runtime is degraded?
- will a stalled live E2E be easy to localize from artifacts?
