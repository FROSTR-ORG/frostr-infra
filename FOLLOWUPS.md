# Follow-ups

## 2026-05-30 — after the test-system hard-cut refactor

### Loose ends
- [ ] Convert the igloo-chrome e2e specs to the page-object model (effort: M) — the
  tightened `check-e2e-selector-contracts.sh` scopes the role/label/placeholder/class bans
  to `test/igloo-pwa/specs` because chrome specs (`dashboard.spec.ts`, `provider.spec.ts`,
  `rotation-update.spec.ts`, …) still use raw interaction locators. Build
  `test/igloo-chrome/support/pages/*` reusing the shared registry keys, then broaden the
  guard to chrome. (igloo-chrome **unit** tests are already fixed and green.)
- [ ] Decide whether the `@live` two-device specs should run in CI and confirm the live
  onboard handshake there (effort: M) — see "Issues discovered" below.

### Issues discovered, not fixed
- [ ] The live two-device onboard handshake does not complete in the local sandbox
  (effort: L) — `onboarding.spec.ts` / `rotation-create.spec.ts` drive the full flow
  (inviter on dashboard + recipient pasting a bfonboard package over a local relay), but the
  recipient's "Onboarding Complete" never arrives within 60s against the sandbox relay. The
  specs are now fully page-object-driven and tagged `@live` (excluded from the deterministic
  fast lane); they need a real relay / CI to verify whether this is a sandbox-relay limitation
  or a genuine runtime regression. **This means the full onboarding handshake is currently
  exercised by spec code but not verified green anywhere local — confirm in CI.**
- [ ] The jsdom-28 `--localstorage-file` Node warning is benign but noisy across unit runs
  (effort: S) — it fires before the setup shim installs; suppress via a vitest pool/Node-option
  tweak if the noise matters.
- [ ] `playwright test --grep @demo --list` for igloo-chrome errors with
  "Cannot find package 'igloo-shared'" (effort: S) — pre-existing chrome-e2e Node resolution
  gap surfaced while wiring `@demo` discovery; the demo lane runs under docker/CI where it's
  set up, but `--list` outside that context fails. Add the igloo-shared resolution (alias/paths)
  to the chrome config or document the CI-only constraint.

### Adjacent improvements
- [ ] Give the QR-package modal and the onboard "Apply"/connect surfaces explicit copy that
  matches a test-id (effort: S) — the onboard-connect submit is labeled "Next Step" while the
  helper history assumed "Apply Onboarding Package"; the test-id (`onboard-connect-submit`)
  now decouples it, but the label drift is worth reconciling with Paper.
- [ ] Remove the now-stale pre-existing `test/scripts/test-run-sh.sh` WIP from the working tree
  or land it (effort: S) — it is the only remaining dirty parent file and predates this work.

## 2026-05-30 — after WS4 Paper sync, WS5 verify, and e2e spec alignment

### Loose ends
- [ ] Fix `rotation-create.spec.ts` secondary-device isolation so the live onboard handshake completes (effort: M) — after the Finish Setup + label alignment, the test reaches the secondary onboard but `openFreshPwaPage(browser)`'s context shows the seeded "Source Device 1" returning Welcome instead of a clean entry hero, so `onboardPwaDevice` never reaches the onboard screen (times out on "Apply Onboarding Package"). Likely `browser.newContext()` inheriting a global `storageState` from `test/igloo-pwa/playwright.config.ts`; pass an empty `storageState` (or clear localStorage) for the fresh page. The spec's label/structure alignment is staged but left uncommitted until the handshake passes. `app-shell.spec.ts` is fully aligned and green.

### Adjacent improvements
- [ ] Add an e2e assertion that the distributor's share card flips to **Onboarded** after a real peer onboarding (effort: M) — exercises the WS3d onboard-complete event end-to-end; depends on the rotation-create isolation fix above.
- [ ] Give distribution cards a stable test id (effort: S) — `app-shell.spec.ts` now locates the first card positionally because the packaged card no longer renders a password field; a `data-test-id` per share card would make the create/rotation specs less brittle and unblock consolidating the duplicated create→distribute setup already tracked in earlier sections.

## 2026-05-27 — after hard-cut Create flow implementation

### Loose ends
- [ ] Review and commit the multi-repo branch state across root, `repos/igloo-paper`, `repos/igloo-ui`, `repos/igloo-pwa`, `repos/bifrost-rs`, `repos/igloo-shared`, and `repos/igloo-chrome` (effort: M) — this implementation is validated but spans several submodules plus refreshed WASM artifacts, so commit ordering and submodule pointers need a deliberate pass.
- [ ] Decide what to do with the pre-existing untracked `dev/plans/igloo-ui-remaining-paper-sync-hard-cut-plan-2026-05-25.md` before final staging (effort: S) — it still appears in root status and should be either intentionally added, archived, or left out of this branch.

### Issues discovered, not fixed
- [ ] Investigate the PWA visual web-server `NO_COLOR` / `FORCE_COLOR` warning around `test/igloo-pwa/playwright.config.ts:14` (effort: S) — the visual lane still prints the warning even though the config deletes both env keys, and `repos/igloo-pwa/CHANGELOG.md:15` says it was fixed.
- [ ] Investigate the Vitest `--localstorage-file` warning in `repos/igloo-pwa` unit tests (effort: S) — every PWA unit run reports the warning before tests pass, which adds noise to otherwise clean validation output.

### Adjacent improvements
- [ ] Add focused tests for `optionalSigningKeyBytes` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` (effort: S) — Rust covers splitting an existing key and the UI covers the field, but the PWA nsec/hex decoding bridge has no direct test.
- [ ] Decide whether `Launch Signer` should be disabled until every remote share is marked `Done` (effort: S) — the current implementation leaves it enabled so users can enter the signer immediately, but the distribution cards now expose completion state.
- [ ] Extract the repeated Create flow Playwright setup across `test/igloo-pwa/specs/app-shell.spec.ts`, `test/igloo-pwa/specs/rotation-create.spec.ts`, and `test/igloo-pwa/specs/welcome-visual.spec.ts` (effort: M) — the new Select Share / Save Profile path is repeated in several specs and will be easy to drift.
- [ ] Add a small regression test for `repos/igloo-paper/scripts/update_usage_coverage.py` (effort: M) — the command is now part of the Paper workflow, but only the manifest pruning and verifier-count helpers have direct script-level tests.

### Open questions
- [ ] Confirm whether the UI copy for `Existing Private Key (optional)` should explicitly mention 64-character hex as well as nsec (effort: S) — `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` accepts both formats, while the Paper/user-facing label emphasizes nsec.
- [ ] Confirm default peer permissions for new remote shares (effort: S) — `repos/igloo-pwa/src/lib/store.tsx` initializes each remote share with `sign`, `ecdh`, `ping`, and `onboard` enabled, which is permissive and may need product confirmation.

### Future scope
- [ ] Run and archive a visual comparison report with `npm --prefix test run test:visual:report` after design review (effort: M) — the capture lane passed, but the Paper-to-PWA screenshot review artifact is still the next useful review deliverable.
- [ ] Consider a smaller routine WASM validation path for sandboxed agent runs (effort: L) — `wasm-opt` still requires escalation for full browser WASM refresh/build work, which is accurate but slows routine iteration.

## 2026-05-27 — after Create flow Paper redesign

### Loose ends
- [ ] Review and commit the `repos/igloo-paper` export changes, then commit the parent workspace pointer and `test/igloo-pwa/visual-manifest.json` update (effort: S) — this session left validated work on branch `paper-create-flow-update`, but no commits were made.

### Issues discovered, not fixed
- [x] Make `make igloo-paper-sync` run Python with bytecode disabled or clean `__pycache__` before verification (effort: S) — the first sync failed because generated Python caches under `repos/igloo-paper/scripts/` violated the verifier’s cache-artifact guard.
- [x] Teach the Paper export workflow to remove stale generated screen directories when artboards are deleted or renamed (effort: M) — deleting `Generation Progress`, `Distribution Completion`, and renamed shared screens required manual directory cleanup before manifest verification could pass.
- [x] Replace or wrap the hard-coded `artboard-map.json` count checks in `repos/igloo-paper/scripts/verify.py:190` with a less brittle update path (effort: M) — deleting two mapped screens and adding one new screen required manually changing the expected total and screen count.
- [x] Add a documented command for regenerating `design/tokens/usage-coverage.json` from current exports (effort: M) — strict drift coverage had to be regenerated manually after the new Paper nodes introduced and removed prototype-only colors and typography pairs.

### Adjacent improvements
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:40` with a “renaming or deleting artboards” checklist (effort: S) — the current workflow lists files to update when adding artboards, but not stale export cleanup, visual-manifest updates, or manifest rebuild order.
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:55` to recommend `PYTHONDONTWRITEBYTECODE=1 make igloo-paper-sync` until the command handles caches itself (effort: S) — this avoids a known verifier failure mode during Paper sync.
- [x] Add a note in `dev/docs/WORKFLOWS.md` that Paper screen renames may require `test/igloo-pwa/visual-manifest.json` updates (effort: S) — the guard caught stale Paper screenshot paths only after the old exports were removed.

### Open questions
- [x] Decide what the final `Next Step` on `Distribute Shares` should do now that Distribution Completion is removed (effort: S) — the final action is now `Launch Signer` and transitions directly to the signer dashboard.

### Future scope
- [x] Update `igloo-ui` / `igloo-pwa` implementation to match the new four-step Paper design (effort: L) — this pass wires the four-step flow through `igloo-ui` and `igloo-pwa`.

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

## 2026-05-28 — after wiring the threshold key-recovery flow

### Loose ends
- [ ] Commit the `recover_secret_key_from_shares` binding in `repos/bifrost-rs/crates/bifrost-bridge-wasm/src/lib.rs` (effort: S) — it is woven into extensive pre-existing `bifrost-rs` WIP (frostr-utils, bifrost-app, signer, router) and was intentionally left uncommitted to avoid fragmenting that work; the consuming repos already vendor the built wasm, so the source change should land with the rest of the bifrost-rs WIP.
- [ ] Wire encrypted export on the Recover Private Key screen (effort: M) — the "Encrypt Key" checkbox + password/confirm fields render for design fidelity, but `RecoverPrivateKeyView` in `repos/igloo-pwa/src/App.tsx` currently saves the plaintext nsec; password-encrypted save/QR is not implemented.

### Issues discovered, not fixed
- [ ] `load-recover` (single-bfshare profile download) is now orphaned (effort: S) — dropping the import `load-choice` screen removed its only entry point in `repos/igloo-pwa/src/App.tsx`; either remove the dead view or give it a dedicated entry.
- [ ] Recover "Collect Shares" reuses `RotateKeysetPanel` with an inert "Source Profile" dropdown (effort: M) — it diverges from Paper `49W` ("Share #1 this device validated" + paste); build a tailored recover collect-shares panel. Until then `recover-collect-shares` legitimately stays `needs-work` in the visual manifest.

### Adjacent improvements
- [x] Design a capture path for the `recover-success` visual entry (effort: M) — resolved 2026-05-29 via a DEV-only `window.__IGLOO_TEST_RECOVERED_KEY__` injection seam (`import.meta.env.DEV`-gated, fake nsec, stripped from prod) that `test/igloo-pwa/specs/recover-visual.spec.ts` sets through `page.addInitScript`.
- [ ] Auto-include the unlocked device's own share in recover/rotate Collect Shares (effort: M) — both flows are currently paste-only; matching Paper's "Share #1 (this device) validated" affordance would save users from pasting their own device share.

### Future scope
- [ ] Reconcile the Welcome Flow-Section board's secondary-CTA labels with the canonical screens (effort: S) — the board embeds read "New Keyset" / "Import Device Profile" / "Onboard" vs the canonical "Generate New Keyset" / "Import Existing Device" / "Onboard New Device".
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — the next planned focus after the recover flow and screenshot review.

## 2026-05-29 — after Alert adoption, Encrypt Key, and Recover-from-Share removal

### Issues discovered, not fixed
- [ ] Bring `repos/igloo-chrome` current with the redesigned `igloo-ui` API (effort: L) — `npx tsc --noEmit` surfaces pre-existing drift unrelated to this work: `AppHeader` has no `title`/`subtitle` props (`App.tsx`, `Dashboard.tsx`, `Signer.tsx`, `Onboarding.tsx`, `popup.tsx`), `igloo-ui` no longer exports `OperatorMethodPermissionOverride`/`OperatorPolicyOverrideValue` (`components/options/PermissionsPanel.tsx`), `StoredProfileCardModel` now requires `shortId` (`Onboarding.tsx`), and `PermissionsPanel`/`Signer` prop shapes changed. The extension was never migrated alongside igloo-pwa.
- [ ] Fix the `repos/igloo-chrome` vitest environment so unit tests run locally (effort: S) — all 24 files fail at `vitest.setup.ts:7` with `localStorage.clear is not a function` despite `environment: 'jsdom'`; this blocks local validation, so the (symbol-clean) Recover-from-Share removal in the extension still needs a CI run to confirm green.
- [ ] Adopt `PasswordField` (the igloo-ui reveal-toggle input) in `repos/igloo-chrome` import/onboard forms (effort: S) — they still use plain `type="password"` inputs; naturally part of the chrome alignment above.

### Loose ends
- [ ] Land the accumulated multi-session work in coherent per-repo commits (effort: M) — three uncommitted layers now stack across the submodules (the needs-work hard-cut, this follow-up cut, and the Paper export). Order: `igloo-shared` → `igloo-ui` → `igloo-pwa` + `igloo-chrome` → `igloo-paper` → parent. Commit the `repos/igloo-paper` 67-file diff as its own "Paper export refresh (SVG serialization normalization + Alerts contents/contract)" checkpoint so the intent reads clearly; keep pre-existing parent WIP (`app-shell.spec.ts`, `rotation-create.spec.ts`, `test-run-sh.sh`) out of the feature commits.
- [ ] Commit the `repos/bifrost-rs` WIP (recover binding + `signing_key32` / `CreateKeysetConfig::new()` cleanup) (effort: M) — still the one deliberately-uncommitted submodule carried from the original handoff.
- [ ] Remove the stale `recoverProfileForm` (and legacy `recoverForm`) seed keys from `test/igloo-pwa/specs/app-shell.spec.ts` (effort: S) — harmless (the store ignores unknown drafts) but dead after the Recover-from-Share removal; clean up when that pre-existing WIP is resolved.

### Future scope
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — still the next planned major surface; no audit done yet (carried from prior sessions).

## 2026-05-29 — after Create-Keyset stepper + relay refinements (WS1/WS2)

(Active-plan WS3–WS5 are the next phase and tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Adjacent improvements
- [ ] Validate relay input in the new `RelayList` (`repos/igloo-ui/src/components/flows/CreateFlow.tsx`) before adding (effort: S) — the "Add Relay" field currently accepts any string and only dedupes; reuse the existing relay normalizer (`normalizeRelays` / `normalizeRelayUrls` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`) to require `wss://` and surface an inline error, instead of failing later at profile creation.
- [ ] Clear stale per-URL ping state when a relay is removed in `RelayList` (effort: S) — ping results are kept in component state keyed by URL and not pruned on delete, so removing then re-adding the same URL shows the old status until it re-pings.
- [ ] Add a unit test for `pingRelay` + `RelayList` ping/status behavior (effort: S) — mock `WebSocket` to cover ok/failed/timeout and the auto-ping-on-add path; there is no coverage of the new relay-connectivity code yet.

### Loose ends
- [ ] Decide the fate of the now-redundant `RelayInput` component (`repos/igloo-ui/src/components/ui/relay-input.tsx`) (effort: S) — it predates and overlaps the new `RelayList`; either remove it or consolidate so there's one relay-entry component.

## 2026-05-29 — after Distribute-Shares redesign + onboard-complete event (WS3)

(WS4 Paper sync and WS5 full verify/visual re-capture are the next phase, tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Loose ends
- [ ] Commit the `repos/bifrost-rs` WS3d change with the re-vendored wasm (effort: M) — `CompletedOperation::OnboardServed` (signer `lib.rs:1713`), the bridge-wasm `CompletedOperationJson::OnboardServed` variant, and the bridge-tokio kind arm land in the existing bifrost-rs WIP; the rebuilt `bifrost_bridge_wasm_bg.wasm` is now modified (binary-only; JS/.d.ts unchanged) in all three of `repos/{igloo-pwa,igloo-shared,igloo-chrome}/public/wasm` and must be committed coherently with the Rust source.
- [ ] Remove the dead `.igloo-create-local-share-card` CSS rules in `repos/igloo-ui/src/styles.css` (effort: S) — the local-share card was removed in WS3b but its style rules remain (grouped into shared selectors); cleanest to drop during the WS4 Paper sync that rewrites that area.

### Adjacent improvements
- [ ] Add store-level unit tests for the new distribute lifecycle in `repos/igloo-pwa/src/lib/store.tsx` (effort: M) — `distributeShare` (`prepare/copy/qr/save/mark/cancel/revert`), `startDistributionClient`/`stopDistributionClient`, and `finishSetup` (snapshot-persist → stop → purge secrets → locked Welcome) have no direct coverage; App.test only walks the happy path to Finish Setup.
- [ ] Add coverage for the onboard-complete wiring (effort: M) — `parseOnboardServedCompletion` (`repos/igloo-shared/src/browser-runtime-core.ts`) and the store's peer→share→`onboarded` mapping (prefix-normalized `share_public_key` match) are untested; a bridge-wasm Rust test asserting the `{"OnboardServed":{request_id,peer_pubkey32_hex}}` JSON shape would also lock the serde contract the TS parser depends on.
- [ ] Replace the native `window.confirm` undelivered-shares guard in `renderCreateDistribute` (`repos/igloo-pwa/src/App.tsx`) with a styled modal (effort: S) — the rest of the app uses dedicated modals (e.g. `WelcomeDeleteModal`); the raw `confirm()` is inconsistent and is also why `App.test` has to stub `window.confirm`.
- [ ] Make `OnboardingClientCard`'s peer count meaningful (effort: S) — it currently shows `store.peerPermissionStates.length`, which can read 0 until peers are observed; consider sourcing the count from the runtime snapshot/remaining shares so the summary reflects the live session.
- [ ] Prune stale per-URL ping state is already tracked for `RelayList`; verify the same component-state-keyed-by-URL pattern in the distribute flow does not leak after `cancel`/`revert` (effort: S) — the distribute cards key drafts/results by `member_idx` (fine), but confirm no orphaned `distributionForms` entries survive a `cancel`.

### Open questions
- [ ] Confirm the `onboarded`-from-`draft` promotion semantics (effort: S) — the onboard-complete handler sets a matched share to `onboarded` even if it had no package (no prior `packaged`/`delivered`), materializing a result entry; the plan's assumption said "auto-promotes from any non-Draft state." Current behavior favors never dropping a real onboard signal — confirm that's desired.
- [ ] Confirm the File System Access save semantics (effort: S) — `saveTextToFile` (`repos/igloo-pwa/src/lib/store.tsx`) advances a share to `saved` on a confirmed `showSaveFilePicker` write and keeps status on user-cancel, but the anchor-download fallback (unsupported browsers) optimistically marks `saved` without a write confirmation.
