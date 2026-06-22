# God-File Decomposition Playbook

**Created:** 2026-06-22 · **Status:** living tracker (update the table as files land)

This is a **standing playbook**, not a one-shot plan. It carries the R2 god-file
decomposition (audit 2026-06-19, `dev/BACKLOG.md` "R2 — God-file decomposition")
across many sessions. The intended loop:

1. Pick the **next** file from the tracker (top-down — they are risk-ordered).
2. Execute that file's section + the shared ground rules below.
3. Run the gates, commit in the submodule, bump the pointer, **tick the tracker
   here** (box + commit hash + date).
4. **Reset the session context** and start fresh on the next file.

One file per session. Each section is self-contained so a cold session needs only
this doc + the repo.

---

## Status tracker

Risk-ordered; do top-down. The `→` dependency must be respected.

| # | File | LOC* | Risk | Safety net | Status |
|---|------|------|------|-----------|--------|
| 1 | `igloo-ui/src/components/flows/CreateFlow.tsx` | ~1727 | Low | strong (`test/CreateFlow.test.tsx`) | ☑ done 2026-06-22 — igloo-ui 25a6e6e, parent bd5f463 |
| 2 | `igloo-pwa/src/lib/store.tsx` | ~1912 | Medium | R6.3 done ✓ | ◐ in progress — stage 1 done 2026-06-22 (igloo-pwa 5ef3d6e, parent eabfd3b); stages 2–4 remain |
| 3 | `igloo-pwa/src/App.tsx` (→ after #2) | ~1693 | Medium | R6.3 done ✓ | ☐ not started |
| 4 | `igloo-home/src/App.tsx` | ~2120 | Medium | R6.4 done ✓ | ☐ not started |
| 5 | `igloo-shared/src/wasm-bridge-node.ts` | ~1662 | **High** | R6.5 done ✓ | ☐ not started |
| 6 | `igloo-chrome/src/pages/Onboarding.tsx` (optional) | ~487 | Low-Med | R6.2 done ✓ | ☐ not started |

\* LOC drifts as work lands — re-`wc -l` when you start a file.

**To tick:** `☑ done <YYYY-MM-DD> — <submodule> <hash>, parent <hash>`.

### What changed since the audit (read this)

The audit said "add the R6 failure-path tests **before** splitting" several of
these. **Those safety nets now exist** (landed 2026-06-21/22):

- **R6.2** chrome cipher tests (`profile-blob.test.ts`) → unblocks #6.
- **R6.3** pwa adapter + store decrypt-failure tests → unblocks #2/#3.
- **R6.4** home adversarial Rust + frontend-banner tests → unblocks #4.
- **R6.5** bridge-node sign/ECDH failure-drain tests + real-WASM package KATs
  → de-risks #5's `connect`-mode split (still the highest-risk file — keep it staged).

So every file below has its named pre-req safety net in place. You still **add
characterization tests for any new pure helper you extract** (see ground rules).

---

## Shared ground rules (apply to EVERY file)

**1. Behavior-preserving, structural-only.** A decomposition commit moves code and
re-exports it — no logic changes. `git diff` should read as cut/paste + import
rewiring. If you spot a bug while moving (this is common — the R6 work found
swallowed guards and retained secrets), **fix it in a SEPARATE commit** so the
structural diff stays pure and reviewable.

**2. Characterize first.** Before moving a seam, confirm the file's safety-net test
is green. For any **pure** helper you lift into a `lib/*.ts` neighbor, add a unit
test in the same commit (the extraction is only "safe" once the moved logic is
pinned). Don't move React-bearing view code without the existing render test
covering it.

**3. Locate by symbol, not line number.** Line numbers in the backlog and below are
stale the moment the first split lands. `grep -n "functionName"` to find the
current seam.

**4. Preserve public surfaces.** Consumers import through package barrels /
entrypoints. The split must keep every exported name resolvable:
- `igloo-ui` is consumed **all-source via `src/index.ts`** — re-export the new
  files so `src/index.ts` is byte-for-byte unchanged (or only gains/keeps the same
  names). Hosts must not need an import rewrite.
- `igloo-shared` resolves via `exports["."] = "./src/index.ts"` — same rule.
- For app-internal files (`igloo-pwa`/`igloo-home` `App.tsx`, `store.tsx`), keep
  the component/hook's external contract (props, exported store hook) identical.

**5. Per-repo gate before committing:**
- TS repos: `npm --prefix repos/<repo> run test` (typecheck + vitest) — or
  `npx tsc --noEmit && npx vitest run` from the repo if there's no aggregate script
  (igloo-shared has `test:typecheck` via `tsc` + `test:unit` via vitest).
- Rust (igloo-home `src-tauri`): `cargo test --features test-server` + `cargo clippy`.

**6. Workflow — no new PRs (`[[workflow-no-new-prs]]`).** Commit **inside the
submodule** first (focused subject + the `Co-Authored-By` trailer), then from the
parent run `make verify` and `make bump-pointers MSG="…" DRY_RUN=1` → for real.
Nothing is pushed; work stays on `dev`.

**7. Commit shape.** One structural commit per file (plus a separate bugfix commit
if you found one, plus the characterization-test additions — which can ride with
the extraction commit since they pin it). Then the parent pointer bump.

**8. When done with a file:** tick the tracker above, then reset context.

---

## 1 · igloo-ui `CreateFlow.tsx` (Low risk — do first)

**Why first:** best payoff/risk. The safety net (`test/CreateFlow.test.tsx`)
imports the components **through the barrel** and survives a re-export-preserving
split, so this is mechanical.

**Seams (7 + types):** generate · rotate · local-save · distribution ·
onboard-import · recover · onboard-handshake.

**Target structure:**
```
src/components/flows/create/
  index.ts          // thin re-export of every CreateFlow* component
  types.ts          // shared prop/types
  generate.tsx
  rotate.tsx
  local-save.tsx
  distribution.tsx
  onboard-import.tsx
  recover.tsx
  onboard-handshake.tsx
```
Delete `flows/CreateFlow.tsx`; point `src/components/flows/CreateFlow` imports at
the new `create/index.ts` (or rename the import path in `src/index.ts` while
keeping the **same exported names**).

**Preserve:** every `CreateFlow*` name currently re-exported from
`src/index.ts` (grep `CreateFlow` in `src/index.ts` — ~15 names:
`CreateFlowTaskBanner`, `CreateFlowGenerateCard`, `CreateFlowSharePicker`,
`CreateFlowLocalSaveCard`, `CreateFlowShareSelection`, `CreateFlowProfileSetup`,
`CreateFlowReviewPanel`, `CreateFlowDistributionCards`,
`CreateFlowDistributionSection`, …). The 31-entry public barrel must be unchanged.

**Steps:** (a) confirm `CreateFlow.test.tsx` green; (b) move each seam's
component(s) into its file, shared types into `types.ts`; (c) `create/index.ts`
re-exports all; (d) repoint `src/index.ts`'s `from './components/flows/CreateFlow'`
to `'./components/flows/create'`. (e) Also resolve the lone `eslint-disable` noted
in the audit if it lands in a moved chunk — but as a **separate** commit if it's a
real change.

**Verify:** `npm --prefix repos/igloo-ui run test`; `CreateFlow.test.tsx` green
unchanged is the proof. Spot-check a consuming host renders (e.g.
`make screenshot STATE=... CLIENT=pwa`).

**Done when:** file deleted, barrel unchanged, all tests green, pointer bumped.

---

## 2 · igloo-pwa `store.tsx` (Medium — staged; do before #3)

**Safety net:** R6.3 store-error-routing + adapter decrypt tests exist ✓. Keep them
green throughout — they pin the riskiest decrypt journeys.

**Seams (8 slices):** hydration/normalization · drafts · secrets · create · import ·
onboard · rotate · recover/dashboard.

**Stage it — start mechanical, end at journeys:**
1. ✅ **DONE 2026-06-22 (igloo-pwa 5ef3d6e, parent eabfd3b).** Pure
   hydration/normalization lifted into `lib/store-hydrate.ts` (defaultDrafts,
   createDefaultDraftSecrets, createDefaultState, ensureDistributionForm/
   PasswordSlot, normalizeLoadedState[FromStorage]) + `test/frontend/
   store-hydrate.test.ts` pinning the default-state shape and the rehydration
   sanitization rules. store.tsx 2178→1912, suite 78→88 green. `normalizePeerKey`
   + `readProfileGroupName` were left in store.tsx (peer/profile concern, not
   hydration) — candidates for a later pure-helper slice.
2. **`updateDraft`/`updateSecret` collapse** (R3.2): the ~25 near-identical
   `updateXForm`/`updateXPassword` methods collapse to two generic setters. This
   materially shrinks the file. (Cross-ref R3.2 in BACKLOG.)
3. **Re-key the action `useMemo`** off stable dispatchers instead of whole `state`
   (find the big actions `useMemo` and its dep array) — reduces churn, prep for
   slicing.
4. **Journey slices last** (`loadBfProfile`/import, `connectOnboardingPackage`/
   onboard, rotate, create) — these touch decrypt; they are covered by R6.3 now, so
   move them only after 1–3, one journey per commit if it helps review.

**Preserve:** the `useStore()` hook contract + `StoreProvider`. Consumers
(`App.tsx`, tests) must not change imports.

**Verify:** `npm --prefix repos/igloo-pwa run test` after each stage.

**Done when:** store.tsx is a thin composition of slice modules; the public hook is
unchanged; full pwa suite green.

---

## 3 · igloo-pwa `App.tsx` (Medium — AFTER #2)

**Why after store:** each view's props settle once the store is sliced.

**Partial progress already:** `src/lib/dashboard-view.ts` exists and already holds
the pure key/summary derivers (`toDashboardKey`, `deriveMemberLabel`,
`deriveGroupSummary`, `deriveExportSummary`). **Extend it**, don't recreate it.

**Seams:** ~16 `renderX` closures + the remaining view-model derivers.

**Steps:**
1. Move the still-inline **`deriveSignerDashboardView` + `derivePolicyDashboardView`**
   (React-free view-model builders) into `lib/dashboard-view.ts` with unit tests.
2. Promote the 16 `renderX` closures (`renderLanding`, `renderCreateGenerate`,
   `renderLoadImport`, `renderOnboard*`, `renderRotate*`, `renderRecover*`,
   `renderDashboard`, …) into `src/views/*.tsx` (new dir; pwa has none yet),
   passing store values + handlers as props.
3. Reduce the `activeView` switch to a thin router that selects a view component.

**Preserve:** the default-exported `App` component contract; `main.tsx` unchanged.

**Verify:** `npm --prefix repos/igloo-pwa run test`; the existing `App.test.tsx`
render assertions are the safety net.

**Done when:** App.tsx is a router shell; views live in `src/views/`; derivers in
`lib/dashboard-view.ts`; suite green.

---

## 4 · igloo-home `App.tsx` (Medium)

**Safety net:** R6.4 frontend-banner + Rust adversarial tests exist ✓.

**Seam order — pure parsers first, then views:**
1. **Characterize the `extract*` parsers** (`extractRuntimePeers`,
   `extractPeerPermissionStates`, `extractPendingOperations`,
   `extractPendingApprovals`) — they're pure → pull into `src/lib/runtime-status.ts`
   with unit tests. Lowest-risk independently-testable seam; do first.
2. **Lift the 7 views into `src/pages/`** following the existing
   `src/pages/CreatePage.tsx` precedent: `LoadProfilePage`, `RecoverKeyPage`,
   `OnboardConnectPage` + `OnboardSavePage`, `DashboardPage` (and the remaining
   views). Pass state + handlers as props.

**Watch for latent bugs** here — this session's R6.4 fix found guard errors being
swallowed by `void handleX()` call sites. If a moved handler has the same shape,
fix it in a **separate** commit.

**Preserve:** the default-exported `App`; the Tauri command wiring stays in
`lib/api.ts` (unchanged).

**Verify:** `npm --prefix repos/igloo-home run test` (typecheck + vitest). No Rust
changes expected; if you touch `src-tauri`, also `cargo test --features test-server`.

**Done when:** parsers in `lib/runtime-status.ts` (tested), views in `src/pages/`,
App.tsx a shell; suite green.

---

## 5 · igloo-shared `wasm-bridge-node.ts` (HIGH risk — keep staged)

**Highest risk:** every host's signing path routes here; `emit`/`emitLog` side
effects thread through `pumpRuntime`. R6.5 now covers the sign/ECDH failure drains
and real package KATs ✓, which de-risks but does **not** make this mechanical.

**Do now (pure extractions, one test per extraction):**
- `requestOnboardResponse` (the onboard-response builder) → its own module + test.
- the **device-config builder** → its own module + test.
- `buildProfileBootstrap` → its own module + test.
- (already split historically: `runtime-pump.ts` holds the pending-command
  correlation + completion parsers — extend that pattern.)

**Defer until you've added more coverage:** the `connect`-mode split
(`bootstrapPersisted` / `bootstrapProfile` / `bootstrapOnboarding`). The file's
header comment asserts it's "not separable without a behavior-changing rewrite" —
respect that. R6.5 covers the drains, but the 4 bootstrap modes still lack direct
unit coverage; add mode-dispatch tests before splitting `connect`.

**Preserve:** `BrowserBridgeNode`'s public method surface + the
`createWasmBridgeRuntime`/loader exports from `src/index.ts`.

**Verify:** `cd repos/igloo-shared && npx tsc --noEmit && npx vitest run` (155+
tests incl. `wasm-bridge-node.test.ts` + the KATs).

**Done when:** the named pure pieces are extracted + tested; `connect`-mode split
either landed with new coverage or explicitly re-deferred here with a note.

---

## 6 · igloo-chrome `Onboarding.tsx` (optional; smallest)

**Safety net:** R6.2 cipher tests (`profile-blob.test.ts`) exist ✓ — the C2 gate the
audit named is satisfied.

**Seams:** connect · save · import · activate · unlock · delete (6 flows sharing one
`error` slot) + 6 bare-string password slices.

**Split into:** `OnboardConnect` / `ImportProfile` / `UnlockProfile` / `ProfileList`
under `src/pages/` (or a `pages/onboarding/` subdir). Give each flow its own error
+ password state rather than the shared slots.

**Verify:** `npm --prefix repos/igloo-chrome run test` (the unit suites; the crypto
path is real via jsdom WebCrypto per R6.2).

**Done when:** the monolith is per-flow; suites green. Lowest priority — fold in only
after #1–#4 if appetite remains.

---

## Per-file completion ritual (copy each time)

```
# inside the submodule
git -C repos/<repo> add -A && git -C repos/<repo> commit   # focused structural subject
# from parent
make verify
make bump-pointers MSG="Decompose <file>: <seams>" DRY_RUN=1   # preview
make bump-pointers MSG="Decompose <file>: <seams>"             # for real
# then: tick the tracker row above (☑ + hashes + date), commit dev/plans + dev/BACKLOG, reset context
```

Also flip the matching `dev/BACKLOG.md` "R2" row to done with the hash when a file
lands, so the backlog and this playbook stay in sync.
