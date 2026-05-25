# Follow-ups

## 2026-05-25 — after Paper welcome label sync and UI workflow cleanup

### Loose ends
- [ ] Push the new root and submodule commits once review is complete (effort: S) — root is ahead of `origin/master` by six commits and `repos/igloo-paper`, `repos/igloo-ui`, and `repos/igloo-pwa` are each ahead by one commit.
- [ ] Document the three UI workflows in a repo-owned guide under `dev/docs/` or `dev/plans/` (effort: M) — `repos/igloo-paper/docs/mcp-edit-workflow.md:16` covers live Paper MCP edits, but does not yet cover choosing between Paper-to-export, export-to-UI screenshot alignment, and dual Paper+UI edits.
- [ ] Create a `frostr-paper-ui-workflows` skill that dispatches agents to the right Paper/UI workflow (effort: M) — the user wants agents to select the correct workflow instead of rediscovering the process each session.

### Issues discovered, not fixed
- [ ] Investigate why full `make igloo-paper-sync` refreshed unrelated dashboard screenshots and non-Welcome reference HTML during a Welcome label change (effort: M) — accepting generated drift is sometimes correct, but unrelated churn makes Paper review noisier.
- [ ] Add progress logging or per-artboard context to `repos/igloo-paper/scripts/paper_mcp.py:84` screenshot export (effort: S) — the retry/context patch helped, but a long timeout still should identify the current artboard before failing.
- [ ] Decide whether onboarding should expose a device-name field again or whether tests should stop passing a label to `onboardPwaDevice` (effort: M) — `test/igloo-pwa/support/ui.ts:66` still accepts `label`, but the current UI no longer uses it and the rotation test now expects `Onboarded Device`.

### Adjacent improvements
- [ ] Extract repeated distribution-card setup into a Playwright helper (effort: M) — `test/igloo-pwa/specs/app-shell.spec.ts:24` and `test/igloo-pwa/specs/rotation-create.spec.ts:52` now duplicate the create-package, QR, and mark-distributed sequence.
- [ ] Add a focused visual comparison report for Paper screenshot versus PWA capture pairs (effort: L) — the current loop relies on manual `view_image` inspection after `npm --prefix test run test:e2e:igloo-pwa:visual`, which works but is hard to audit later.
- [ ] Add a guard or doc note for the scratch WASM ESM `package.json` behavior in `scripts/prepare-browser-wasm.sh:120` (effort: S) — the fix is small and validated, but future refactors could remove it without realizing Node needs the wasm-pack `.js` files treated as ESM.
- [ ] Broaden `scripts/igloo-pwa-dev.sh:65` handling for multiple listeners on port 1430 (effort: S) — the script intentionally prompts for the first PID, but a clearer multi-PID message would help when stale dev servers stack up.

### Future scope
- [ ] Add a workflow command or script that runs the whole Paper-to-PWA alignment loop and writes an artifact bundle under `dev/reports` (effort: L) — this would make the screenshot comparison loop repeatable across Welcome, Onboard, Create, and future screens.

## 2026-05-23 — after split-lane WASM guard implementation

### Loose ends
- [ ] Commit or merge the pending `hard-cut-test-harness-followups` changes after review (effort: S) — the implementation is validated but currently remains uncommitted in the feature branch.
- [ ] Exercise the negative visual-manifest path by temporarily pointing one `paperReference` at a missing screenshot before final commit (effort: S) — `test/scripts/check-pwa-visual-manifest.mjs:79` now enforces existence when `igloo-paper` is populated, but only the passing path has been run so far.

### Adjacent improvements
- [ ] Replace or supplement the grep-based checks in `test/scripts/check-browser-wasm-harness-contracts.sh:25` with a small fixture-backed shell test (effort: M) — the new routine guard is fast, but string assertions can be brittle when equivalent code is refactored.
- [ ] Add `test:guards:wasm:strict` guidance to release-facing docs such as `dev/docs/RELEASE.md` if maintainers should run it outside the full `make test-release` matrix (effort: S) — `test/README.md` documents the split, but release docs still primarily point at `make test-release`.
- [ ] Consider splitting the strict TypeScript pilot into named configs once `test/tsconfig.strict-support.json:11` grows beyond visual/reference specs (effort: M) — the single strict pilot is still manageable, but it now mixes shared helpers, fixtures, and selected specs.

## 2026-05-23 — after agent docs and test-harness cleanup

### Issues discovered, not fixed
- [ ] Make `scripts/reset.sh:23` treat an unavailable Docker daemon as an explicit skip instead of printing a permission-denied error during `make repo-reset` (effort: S) — reset succeeded, but the noisy Docker failure makes cleanup look less healthy than it is.
- [ ] Add cleanup traps to `test/scripts/check-test-prebuild-nonmutating.sh:32` so per-run `.tmp/test-prebuild-nonmutating-*` directories are removed after successful guard runs (effort: S) — repeated WASM guard runs left scratch directories until `make repo-reset` cleared them.

### Adjacent improvements
- [ ] Extend `test/scripts/check-pwa-visual-manifest.mjs:67` to verify that each `paperReference` file exists when `repos/igloo-paper` is populated (effort: M) — the new visual manifest guard validates path shape, but not stale or missing Paper screenshots.
- [ ] Gradually expand `test/tsconfig.strict-support.json:11` beyond support helpers into selected spec files once the current helper strictness stays stable (effort: M) — strict mode is now wired in, but the first pass intentionally keeps the blast radius narrow.

### Future scope
- [ ] Decide whether browser WASM validation should use a cached fixture lane for routine guards and reserve full `wasm-pack` rebuilds for release validation (effort: L) — the current guard is accurate, but it needs unrestricted execution in this sandbox because `wasm-opt` cannot run under the restricted profile.
