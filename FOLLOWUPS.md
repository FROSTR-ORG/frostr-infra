# Follow-ups

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
