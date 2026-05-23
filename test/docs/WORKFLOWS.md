# Test Workflows

This document is the test-specific workflow guide for agents and contributors.
Use [`../README.md`](../README.md) for the command reference.

## Choosing A Test Lane

Start with the narrowest lane that covers the changed surface:

- PWA changes: run PWA guards, PWA typecheck, and the relevant PWA Playwright
  slice.
- Chrome changes: run Chrome guards, Chrome typecheck, and the relevant Chrome
  Playwright slice.
- Home changes: run Home guards, Home typecheck, and the Home E2E wrapper.
- Shared browser runtime or WASM changes: run the routine browser-WASM guard,
  the strict browser-WASM guard, and the affected browser client lanes.
- Cross-client behavior changes: run the explicit cross-client PWA lane.
- Demo-harness changes: run the demo smoke or demo E2E lane.
- Release-facing coordinated changes: escalate to the root release matrix.

Use full workspace validation when a change crosses ownership boundaries or
changes shared harness behavior.

## Client-Scoped Validation

Scoped lanes should not require unrelated client submodules.

Minimal submodule sets:
- PWA: `repos/bifrost-rs`, `repos/igloo-shared`, `repos/igloo-ui`, and
  `repos/igloo-pwa`
- Chrome: `repos/bifrost-rs`, `repos/igloo-shared`, `repos/igloo-ui`, and
  `repos/igloo-chrome`
- Home: `repos/igloo-shared`, `repos/igloo-ui`, and `repos/igloo-home`

If a PWA-only test requires `repos/igloo-chrome`, or a Chrome-only test requires
`repos/igloo-pwa`, treat that as harness drift unless the test is explicitly
marked cross-client.

## Browser WASM

Routine validation must keep browser-WASM checks scratch-based and
client-neutral, without requiring a full `wasm-pack` rebuild.

- Use `npm --prefix test run test:guards:wasm` for the routine harness
  contract check.
- Use `npm --prefix test run test:guards:wasm:strict` for scratch build and
  sync validation.
- Use `FROSTR_TEST_SKIP_STRICT_WASM=1` only when an agent sandbox cannot run
  `wasm-opt` and the skip is recorded in final notes.
- Use strict tracked checks only when auditing reproducibility against tracked
  artifacts.
- Use `make browser-wasm-refresh` only when intentionally updating tracked
  browser-WASM artifacts.

macOS sandboxed command runners can fail inside `wasm-pack` at the `wasm-opt`
step with `Operation not permitted`. When that happens, rerun only the affected
WASM guard outside the sandbox and record the rerun in the final notes.

## Visual Iteration

Visual PWA tests write screenshots under `./.tmp/visual/igloo-pwa/`.

When aligning implementation to Paper designs:
- compare the rendered PWA screenshot to the corresponding Paper reference
- update `test/igloo-pwa/visual-manifest.json` when captures or reference
  mappings change
- keep captures under `./.tmp/visual/igloo-pwa/`, not tracked-looking paths
- prefer one bounded screen or flow per iteration loop

Run `npm --prefix test run test:guards:visual` after changing visual capture
names, outputs, viewport dimensions, statuses, or Paper reference mappings.
The visual guard also runs a `.tmp` fixture that proves missing Paper
references fail when Paper reference checks are required.

PWA scoped CI uploads visual artifacts for review.

## Guard Maintenance

When changing test workflows or public test commands:
- update [`../README.md`](../README.md)
- update this file
- update command-surface and workflow guards when the documented surface changes
- keep selector contracts helper-owned instead of duplicating fragile selectors
  in specs

Run:

```bash
npm --prefix test run test:guards:docs
npm --prefix test run test:guards:workflows
npm --prefix test run test:guards:wasm
npm --prefix test run test:guards:wasm:strict
npm --prefix test run test:guards:visual
```
