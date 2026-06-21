# Backlog

Curated, forward-looking follow-up work for the `frostr-infra` workspace.
Completed work and the verbatim historical log live in
[`HISTORY.md`](./HISTORY.md); active multi-step plans live in
[`plans/`](./plans).

Format: one item per line, `- [ ] (effort: S|M|L) <summary> — <area> · <link/notes>`.
Group by area. When an item is finished, move a one-line summary to
`HISTORY.md` and delete it here. Dates are absolute (`YYYY-MM-DD`).

> Migration note (2026-06-10): items below were triaged out of the former root
> `FOLLOWUPS.md`. Some may already be resolved by later work — verify against
> the codebase before picking one up. Trivial test-refactor micro-items from the
> 2026-05 sessions were left in the `HISTORY.md` archive rather than carried here.

## Shared-UI consolidation (audit 2026-06-19)

Mirrored from [`docs/UI-AUDIT.md`](./docs/UI-AUDIT.md) (consumption audit, full
detail there). Design fixed by
[ADR-014](./adrs/ADR-014-unified-shared-ui-consumption.md) (unified shared-UI
consumption, **Accepted 2026-06-19**) — see it for sequencing constraints and
rejected alternatives. Remediation is unblocked; start with P0. Goal: one UI,
consumed identically by every client. **Hard cut** (alpha): every item deletes the
old path in the same change — no deprecation aliases, compat shims, dual paths, or
flags; no client left on the old model. Priorities: P0 = remove the consumption
footgun; P1 = visual seam + component convergence; P2 = cleanup.

- [x] (effort: L) **DONE (2026-06-19) — P0 — Consumption contract + Tailwind preset,
  atomic hard cut.** Landed: igloo-ui ships `tailwind.preset.js` (canonical tokens) +
  source `styles.css`; pwa/home/chrome all resolve igloo-ui JS+CSS from source via the
  preset (postcss-import entry, fonts rebased); igloo-ui `dist` build + exports + the
  `make igloo-ui-styles`/`igloo-ui-watch` band-aids deleted; orphaned build refs purged
  from the test harness; `make verify` green. Per-client renders verified from source.
  One coordinated change across `igloo-ui` + pwa + chrome + home (+ parent pointer
  bump), because no client may lag onto the old prebuilt path:
  - Resolve `igloo-ui` + `igloo-shared` (JS **and** CSS) from `src` via a single
    shared Vite resolution config across all three clients; **delete** the
    `igloo-ui/styles.css`→`dist` alias — ADR-014 (a).
  - Ship `igloo-ui/tailwind.preset.js` (theme tokens + plugins) + consumable source
    `styles.css`; give pwa/home a `tailwind.config` using the preset (chrome already
    self-builds) — ADR-014 (b).
  - **Delete** `igloo-ui`'s `dist` build script + prebuilt artifact; repoint its
    `package.json` `main`/`module`/`types`/`exports` at `src` — ADR-014 (b).
  - **Delete** the `make igloo-ui-styles` prerequisite (added 2026-06-19 as an
    interim symptom fix) and the `igloo-ui-watch` target — Makefile · ADR-014 (b).
- [x] (effort: M) **DONE (2026-06-19) — P1 — Shared visual/dev seam (option A).**
  Added `igloo-shared/testing/dev-fixtures` (canonical seeded profile +
  `RuntimeStatusSummary`); pwa/chrome/home all build their `dashboard-running` fixture
  from it; **fixed home** — it was stuck on "Starting signer…/Loading…" because its
  fixture seeded a malformed `runtime_status` with no `peers[]` that `parseRuntimeStatus`
  rejected; now renders the running dashboard (verified). Plan:
  `dev/plans/shared-visual-seam-p1c-plan-2026-06-19.md`; landed as pointer bump 1bca660.
  _Option A only_: shared fixture DATA, not a full seam merge — param/scenario-name
  unification (pwa/chrome `?__frostr_dev=` vs home `?__igloo_visual=`) was deliberately
  deferred (see follow-up below).
- [ ] (effort: S) **P1 follow-up — unify the dev-scenario param + scenario names** across
  the three clients (the deferred "option C": one `?__frostr_dev=` param + shared
  scenario registry, retire home's `?__igloo_visual=`). Has test-lane blast radius
  (home's visual specs reference the old param) — its own task · clients + test/ ·
  added 2026-06-19.
- [ ] (effort: S) **P1c follow-up — extend the shared fixture to the other scenarios.**
  `igloo-shared/testing/dev-fixtures` only covers `dashboard-running`; pwa/chrome still
  build `dashboard-stopped` / `onboarding` from local fixtures. Lift those too so every
  seeded state is single-sourced — igloo-shared + clients · added 2026-06-19.
- [ ] (effort: S) **P1c follow-up — polish the dev-fixtures nits** flagged in review:
  annotate `FIXTURE_SIGNER_SETTINGS: SignerSettings` (matches `FIXTURE_READINESS`);
  comment that the peer keys are synthetic + the 3-member group structure
  (idx 0/self-1/2); rename pwa's `_fixtureRuntimeStatus` (the `_` reads as unused);
  fix chrome dev-scenario's comment that says "cast" where there is none —
  igloo-shared/testing/dev-fixtures.ts + pwa/chrome dev-scenario.ts · added 2026-06-19.
- [x] (effort: S) **DONE (2026-06-19) — P1 — pwa adopts shared `OperatorDashboardTabs`.**
  Retired pwa's local `igloo-dashboard-nav` (`renderDashboardNav()` + `index.css` rules);
  pwa now renders the same boxed tabs below the header as home/chrome, with its
  dirty-settings guard preserved via `onChangeTab`. **No igloo-ui change needed** — the
  component already emits the `dashboard-tab-${key}` test-ids pwa's E2E specs require
  (the planned per-tab `testId` extension was unnecessary). igloo-pwa aca9d71; e2e 6/6.
- [x] (effort: M) **DONE (2026-06-20) — P1 — Shared `Checkbox` primitive.** Added
  `igloo-ui` `Checkbox` (emits the existing `igloo-toggle-row` markup); migrated the
  5 `igloo-toggle-row` toggles (pwa settings ×3 incl. the `settingsAutoOpenToggle`
  testid; home ×2). igloo-ui 576b35c · pwa 9f79aa7 · home daf4498.
- [ ] (effort: S) **P1 follow-up — migrate pwa's recovery "Encrypt Key" toggle to
  `Checkbox`.** Deferred from the Checkbox pass: it uses a DISTINCT defined class
  `igloo-recover-encrypt-toggle` (not `igloo-toggle-row`), so a clean migration needs
  a `Checkbox` variant whose row class REPLACES the base (current `rowClassName` is
  additive). Either add that variant or restyle — repos/igloo-pwa + igloo-ui · added 2026-06-20.
- [x] (effort: M) **DONE (2026-06-20) — P1 — Inline alerts routed through shared `Alert`.**
  Migrated the 8 genuine alert banners (home ×2 — also fixing the undefined
  `igloo-shell-alert` class; chrome ×6 across popup/Onboarding/runtime-state-sections),
  excluding badges/code-boxes/field-errors/empty-states. **No `Alert` API change needed** —
  the existing `danger`/`warning`/`default` tones + optional `title` covered every site
  (the planned `info`/`dismissible`/title-less additions were unnecessary). home daf4498 · chrome 3d0f36a.
- [ ] (effort: S) **P2 — Lift accidental view-model duplicates** (`toDashboardKey`,
  a single `buildPendingOperationRows`), **deleting every local copy**; adopt the
  unused `runtimePeerPermissionStatesToPolicyDashboardView`; keep host-specific glue
  local — igloo-ui/igloo-shared + clients · ADR-014 (e).
- [ ] (effort: S) **P2 — Delete dead `DesktopAppShell`** (and re-evaluate
  `ManagedProfilesPanel`) — igloo-ui · ADR-014 (d).

P0 follow-ups (surfaced during the 2026-06-19 P0 execution):

- [ ] (effort: M) **Guard the consumption contract** — add a `test:guards` check
  that fails if any client reintroduces an `igloo-ui/dist` reference, an
  `igloo-ui run build` / `build:ui` script, a local `theme.extend` in a client
  `tailwind.config`, or diverges the shared `@import "../../igloo-ui/src/styles.css"`
  CSS entry — test/ guards · keeps ADR-014's "consumed identically" hard cut from
  silently regressing (P0 showed how easily a dist/build ref creeps back into
  scripts/specs) · added 2026-06-19.
- [ ] (effort: S) **Reconcile the two parallel UI audits** — `dev/docs/UI-AUDIT.md`
  (ADR-014 consumption audit) vs the concurrent `dev/audit/findings/*-2026-06-19.md`
  + `workspace-audit-synthesis-2026-06-19.md` / the "Anti-slop front-end audit"
  section above — dedupe so there aren't two divergent UI-audit records · dev/ docs ·
  added 2026-06-19.
- [ ] (effort: S) (unsure) **Document igloo-ui's source-only resolution constraint**
  — `package.json` `main`/`types`/`exports` now point at `src/index.ts`, so igloo-ui
  only resolves under a TS-aware bundler (Vite/esbuild/vitest); note this in
  igloo-ui's README so a future Node/plain-JS consumer doesn't trip over it ·
  repos/igloo-ui · added 2026-06-19.
- [x] (effort: M) **DONE (2026-06-19) — P0 regression — chrome's local `npm run typecheck`
  was red.** Root cause was a version skew: chrome pinned `@types/react@18.3.26` +
  `csstype@3.1.3` while igloo-ui (and home) use `18.3.28` + `csstype@3.2.3`; under P0
  all-source consumption chrome's tsc type-checked igloo-ui source and hit the
  incompatible csstype CSSProperties → ~18 errors. Fixed by bumping chrome's
  `@types/react` to `^18.3.31` (pulls `csstype@3.2.3`, matching igloo-ui/home). chrome's
  local typecheck + the gate + build all green. Confirmed chrome-only: pwa has no local
  typecheck script, home's was already clean (same versions) · igloo-chrome 0d59395.
- [ ] (effort: M) (pre-existing) **Dev-scenario seams ship inert in prod bundles.**
  The `dev-scenario`/`visualMode` fixtures appear in all three clients' production
  bundles (verified pre-existing: present at pre-P1c base too). pwa/chrome gate at
  runtime via `import.meta.env.DEV`/`?__frostr_dev=` but the code isn't DCE'd;
  home's `visualMode` is **not** DEV-gated at all. Harmless (runtime-gated → never
  activates in prod) but unclean + a few KB of dead weight. Restructure the seams so
  the fixtures tree-shake (and DEV-gate home's visualMode) · clients · added 2026-06-19.
- [x] (effort: L) **DONE (2026-06-20) — P1 — Unified landing across all three clients.**
  Root cause of the recurring "home shows old UI" report: home + chrome never adopted
  the shared `WelcomeEntryHero`/`WelcomeReturningHero` that pwa uses — they still rendered
  the old `StoredProfilesLandingCard` + `HostEntryTile` grid. (Hid for 5 sessions because
  verification only screenshotted `dashboard-running`, never the landing.) Generalized the
  igloo-ui heroes to be host-adapted (`productLabel`/`tagline`/`footer` + declarative
  `primaryAction`/`secondaryActions` + per-profile `canRotate`/`canRecover`/`canDelete`;
  empty meta fields omitted host-agnostically), migrated pwa (prop-shape only), home, and
  chrome onto them + the shared `WelcomeUnlock`/`WelcomeDeleteModal`, added home's missing
  header logo, and hard-cut `StoredProfilesLandingCard` + `HostEntryTile`. `make verify`
  green; 3-app visual convergence confirmed. Design + plan:
  `dev/plans/landing-unification-shared-welcome-2026-06-20-{design,plan}.md`. Pointer bumps
  45f9d57→4571a47 (igloo-ui 576b35c→6eecffc, pwa →e6e8ae2, home →44c0889, chrome →043e863).
- [ ] (effort: S) **chrome: dead `activatingProfileId`/`deletingProfileId` + no row in-flight
  feedback.** After the landing migration these are write-only (the old card read them for
  `loadDisabled`/"Loading…/Deleting…"); the shared hero's Unlock/Delete buttons have no
  busy/disabled state (the unlock modal carries `submitting`, so this is minor). Remove the
  dead state or wire row-level busy feedback · repos/igloo-chrome · added 2026-06-20.
- [ ] (effort: S) **home: per-profile ⋮ Rotate doesn't seed rotate mode.** `onRotate` lands on
  the `create` view with `createForm.mode` still `'new'` and no source profile — user must
  re-pick Rotate + source manually. pwa routes Rotate to a dedicated `rotate-connect` view;
  give home the equivalent · repos/igloo-home · added 2026-06-20.
- [ ] (effort: S) **Sweep orphaned igloo-ui landing leftovers.** Post hard-cut, `StoredProfileCardModel`
  (`src/models/view-models.ts`, re-exported in `index.ts`) + the `storedProfileEntry`/
  `storedProfileLoad`/`storedProfileUnlockSubmit` e2e test ids have zero consumers across
  all repos + the harness (design-scoped-out of the landing change). Remove them ·
  repos/igloo-ui · added 2026-06-20.
- [ ] (effort: S) **chrome: Onboard/Import forms opened from the returning hero have no
  collapse/cancel.** `showOnboard`/`showImport` are one-way booleans — once a returning user
  reveals a form there's no way to dismiss it short of reload (not a regression; the old
  always-visible layout had no cancel either). Add a cancel/collapse affordance ·
  repos/igloo-chrome · added 2026-06-20.

## Anti-slop front-end audit (2026-06-19)

Graduated from the front-end anti-slop audit run under
[`audit/findings/`](./audit/findings/) (synthesis:
[`workspace-audit-synthesis-2026-06-19.md`](./audit/findings/workspace-audit-synthesis-2026-06-19.md);
per-target reports `igloo-{shared,ui,pwa,chrome,home}-audit-2026-06-19.md`). 53
findings (12H/25M/16L) across the five TS front-end targets; `bifrost-rs` /
`igloo-shell` / `igloo-paper` excluded this pass. Every item below carries its
rule ID + `file:line` evidence and traces to a finding. Buckets are the
synthesis remediation buckets R1–R6. **Sequencing** (synthesis "Suggested
sequence"): R5-C1 (leak-now) → R6-C2 (chrome cipher tests) → **R1 quality gate**
→ R3 dedup → R2 splits → R4 dead-surface at the release cut. Land R1's format
sweep *alone, first* so the later diffs are pure structure. This overlaps the
2026-06-13 "Code-health audit" items (god files, formatter) — those two entries
are the prior, coarser capture of R1+R2; close them out as these land.

### Hard-cut sweep status (2026-06-21)

A first **hard-cut sweep** executed the mechanically-safe, behavior-preserving
subset (parent pointer-bump `a698a57`; 15 submodule commits; `make verify` green).

**Landed:**
- **Dead code (R4):** deleted the four orphan `igloo-ui` flow components + barrel
  exports + tests (`CreateImportPanel`/`DesktopAppShell`/`ManagedProfilesPanel`/
  `RecoveryWorkspace`, ~734 LOC — also closed the ui-side plaintext-nsec leak),
  `readNumber` (`igloo-pwa`), and the no-op `introMessage` prop. `LEG-04`.
- **Dedup (R3):** `toErrorMessage` six forks → one exported `igloo-shared` helper;
  `downloadText` three copies → one `igloo-ui` helper. `CQ-04`.
- **Rename (R3/`RS-01`):** chrome `profileKey` → `profileFingerprint` /
  `profileIdKey` (code identifiers only; the `profile_key` log-field strings are
  left untouched as an observability contract).
- **Type/const hygiene:** dropped four redundant pwa runtime-status `as` casts
  (`CQ-03`); named the chrome snapshot-retry constants + shared device-config
  literals (`CQ-06`).
- **Correctness:** chrome `sessionKeyB64!` null-guard bug-fix — a cleared session
  no longer hands a null key into the decrypt path (`CQ-03`).
- **Docs:** `igloo-shared` README package-flow references fixed (`DOC-02`).

**Declined — R1 (quality gate), 2026-06-21.** The maintainer dropped the
Prettier/ESLint/knip/coverage adoption as "churn for no benefit" (the repos are
already consistently hand-formatted). R1.0–R1.4 are retained for record only — do
not re-propose.

**Deferred to a focused follow-up** (these turned out *not* to be
behavior-preserving mechanical cuts):
- **UI presentational pass** — the pubkey/timestamp formatter consolidation
  (separators `…` vs `...` and truncation thresholds genuinely differ → a
  canonical-style decision), the `useSensitiveReveal` hook extraction (timer/state
  risk), and the onboard "My Signing Key" / "2/3" / "Share #0" misleading-literal
  removal (`RS-06`, ui #4 / pwa #10 — needs a neutral-state redesign + visual review).
- **Barrel curation (`ARC-04`)** — pwa `local-adapter` `export *` → named list;
  chrome's five `export * from 'igloo-shared'` aliases are an import-rewiring
  refactor, not a one-file edit.
- **Changelog/version hygiene (`DOC-06`)** — folded into the release process
  (`dev/docs/RELEASE.md`) with the version bump.
- **R2 splits, crypto/KDF, R5 secret-threading, poll→subscribe, R6 tests** —
  unchanged; out of the hard-cut sweep's scope by design.

### R1 — Quality gate — DECLINED 2026-06-21 (retained for record)

Aggregates `AES-06`/`DOC-06` from all five targets (synthesis C10). A
ready-to-execute spec; a future session runs it as-is. Land the Prettier sweep
**first and alone** (it touches many files — never tangle it with logic diffs),
then the lint/knip/coverage ratchets, then wire into `make verify` + PR CI with a
**"no NEW violations"** ratchet (existing volume is large; do not hard-fail on the
baseline).

- [ ] (effort: S) **R1.0 — Prettier baseline, isolated format sweep.** Add a
  shared root `.prettierrc` (+ `.prettierignore` excluding `dist/`, `wasm/`,
  vendored blobs) the five leaves extend; add `prettier` devDep + a `format` /
  `format:check` npm script per leaf. Run `prettier --write` per repo and commit
  **each repo's sweep as its own isolated commit** with no other change, so the
  reformat never tangles with a logic diff. Evidence: `AES-06` — no
  `.prettierrc*`/`.eslintrc*`/`eslint.config.*` in any of
  `igloo-ui/package.json:1-60`, `igloo-shared/package.json` (no prettier dep),
  `igloo-pwa/` (no config), `igloo-chrome/package.json`, `igloo-home/` —
  workspace · synthesis C10/R1. **Do this before R2.**
- [ ] (effort: M) **R1.1 — ESLint flat config per target
  (`eslint.config.js`).** Exact packages: `eslint`, `typescript-eslint` (its
  `recommendedTypeChecked` preset, with `parserOptions.projectService`),
  `eslint-plugin-react-hooks` (rules-of-hooks + exhaustive-deps),
  `eslint-plugin-import` (`import/order` + `import/no-cycle`). Enable
  `@typescript-eslint/no-unused-vars`, `@typescript-eslint/no-floating-promises`,
  `@typescript-eslint/no-explicit-any`. This also retires the stale
  `eslint-disable` in `igloo-ui/.../CreateFlow.tsx` that suppresses a rule with no
  ESLint present. Add a `lint` npm script per leaf. Evidence: `AES-06` (same
  no-config sites as R1.0); `LEG-04` unused-vars would catch dead
  `readNumber` (`igloo-pwa/src/App.tsx:281-288`) + `introMessage`
  (`igloo-ui/src/components/flows/OperatorSignerPanel.tsx:19-21`) — workspace ·
  synthesis C10/R1.
- [ ] (effort: M) **R1.2 — `knip` per repo (dead exports/files/deps).** Add
  `knip` devDep + a `knip` npm script per leaf with a per-repo `knip.json`. It is
  the enforcement net for R4: it flags the four orphan igloo-ui flow exports and
  the unused `PeerList`/`PeerPolicy` barrel entries. Evidence: `LEG-04` —
  `igloo-ui/src/index.ts:179,202,208,231` (orphan flow exports),
  `igloo-ui/src/index.ts:118-119` (`PeerList`/`PeerPolicy`) — workspace ·
  synthesis C7/R1.
- [ ] (effort: M) **R1.3 — vitest v8 coverage ratchet.** Add
  `@vitest/coverage-v8`; set `coverage.provider: 'v8'` + a per-repo baseline
  threshold (measure current, set threshold at-or-just-below it) used as a
  **ratchet, not a hard cliff** — fail only on regression below baseline. Pairs
  with R6 (raising the floor is how the adversarial tests get enforced).
  Evidence: render-only blind spot named in `TST-02`/`TST-05` across all five —
  workspace · synthesis C4/R1.
- [ ] (effort: M) **R1.4 — Wire-up + ratchet.** Per leaf expose
  `lint` / `format:check` / `knip` npm scripts; fold them into `make verify`
  (`scripts/verify.sh`) and the PR CI `client-scoped-validation` jobs. Establish
  the **"no NEW violations"** ratchet (baseline the existing count; gate only on
  net-new) given existing volume. Convert each frozen
  version + perpetual `[Unreleased]` changelog to a release-bumped process tied to
  `dev/docs/RELEASE.md`. Evidence `DOC-06`: `igloo-ui/package.json:13` (`0.0.0`) +
  `CHANGELOG.md:7`; `igloo-shared/package.json:3` (`0.1.0`) + `CHANGELOG.md:7`
  (2026-03-27); `igloo-chrome/package.json:4` (`0.3.0`) + `CHANGELOG.md:7`;
  `igloo-home/package.json` + `src-tauri/tauri.conf.json` (`0.2.0`) +
  `CHANGELOG.md:7-16` — workspace · synthesis C10/R1.

### R2 — God-file decomposition (ranked; synthesis R2 table reproduced)

The C3 monoliths (`ARC-01`/`ARC-02`). **Not one batch** — payoff/risk/safety-net
differ per file. For each RECOMMEND-NOW file, write the named characterization
tests to pin behavior *first*, then extract along the listed seams; DEFER files
record seams + rationale. Land **after R1.0** so diffs are pure structure.

- [ ] (effort: M) **RECOMMEND NOW — `igloo-ui/src/components/flows/CreateFlow.tsx`
  (1727 LOC, 6 seams, Low risk).** Seams: generate / rotate / local-save /
  distribution / onboard-import / recover / onboard-handshake. Safety-net is
  **good and already in place** — `test/CreateFlow.test.tsx` (786 LOC) imports
  through the barrel and survives a re-export-preserving split, so the split is
  mechanical: split into `flows/create/{generate,rotate,local-save,distribution,
  onboard-import,recover,onboard-handshake}.tsx` + a `create/types.ts`, re-export
  from a thin `flows/create/index.ts` so the public barrel
  (`igloo-ui/src/index.ts:143-178`, 31 entries) is unchanged. Best payoff/risk
  ratio; do first. Rule `ARC-01` · evidence `CreateFlow.tsx:1-1727` —
  igloo-ui · synthesis R2 row 1.
- [ ] (effort: L) **RECOMMEND NOW (seam-first) — `igloo-home/src/App.tsx`
  (2086 LOC, 7 views, Medium risk).** Characterize FIRST: the `extract*` parsers
  (`extractRuntimePeers`/`extractPeerPermissionStates`/`extractPendingOperations`/
  `extractPendingApprovals`, `App.tsx:341-452`) are pure → pull into a tested
  `lib/runtime-status.ts` with unit tests, the low-risk independently-testable
  seam, *before* moving views. Then lift the 7 views into `src/pages/` following
  the existing `CreatePage.tsx:1-201` precedent (`LoadProfilePage`,
  `RecoverKeyPage`, `OnboardConnectPage`+`OnboardSavePage`, `DashboardPage`).
  Current net is thin: `App.test.tsx` (292 LOC) renders shell + peer-refresh, no
  flow handler unit-covered — so add R6-C4 home adversarial tests before touching
  the unlock/onboard/rotate handlers. Rule `ARC-01` · evidence
  `igloo-home/src/App.tsx:1-2086` — igloo-home · synthesis R2 row 4.
- [ ] (effort: L) **RECOMMEND NOW (staged) — `igloo-pwa/src/lib/store.tsx`
  (2161 LOC, 8 slices, Medium risk).** Start with the mechanical, safe slices:
  the pure hydration/normalization (`store.tsx:312-456`) + the
  `updateDraft`/`updateSecret` collapse of ~25 methods (R3.2). Re-key the action
  `useMemo` off stable dispatchers, not whole `state` (`store.tsx:715-2146`, dep
  array `:2145`). **Add the R6 import/onboard adversarial decrypt tests
  (`store.tsx:1557-1596`, `:1664-1706`) BEFORE touching those journey slices** —
  the riskiest decrypt boundaries are happy-path-only today. Rule `ARC-01` —
  igloo-pwa · synthesis R2 row 2.
- [ ] (effort: M) **RECOMMEND NOW (after store.tsx) — `igloo-pwa/src/App.tsx`
  (1719 LOC, 16 `renderX` + 10 derivers, Medium risk).** Move the
  `derive*DashboardView` functions (`App.tsx:145-235`) into a React-free
  `lib/dashboard-view.ts` neighbor (unit-testable) FIRST, then promote the 16
  `renderX` closures (`App.tsx:461-1604`) to `views/*.tsx` and make the
  `activeView` switch (`App.tsx:1692-1708`) a thin router. Do after the store
  split so each view's props are settled. Rule `ARC-01`/`ARC-02` — igloo-pwa ·
  synthesis R2 row 5.
- [ ] (effort: L) **DEFER (extract pure helpers only) —
  `igloo-shared/src/wasm-bridge-node.ts` (1656 LOC, 6 seams, HIGH risk, THIN
  net).** Every host's signing path routes here; `emit`/`emitLog` side effects
  throughout `pumpRuntime` (`:1399-1544`); header asserts "not separable without a
  behavior-changing rewrite." No unit coverage of the 4 bootstrap modes /
  sign / ECDH / ping / pump dispatch. **Extract only the already-pure pieces now**
  — `requestOnboardResponse` (`:1177-1360`), the device-config builder
  (`:414-432`), `buildProfileBootstrap` (`:1133-1175`) — each with a test added
  per extraction; **defer** the `connect`-mode split (`:365-557`) into
  `bootstrapPersisted`/`Profile`/`Onboarding` until the R6 failure-path tests
  exist. Rule `ARC-01` — igloo-shared · synthesis R2 row 3.
- [ ] (effort: M) **DEFER — `igloo-chrome/src/pages/Onboarding.tsx` (471 LOC, 6
  flows sharing one `error` slot).** Connect / save / import / activate / unlock /
  delete (`Onboarding.tsx:111-225`) + 6 bare-string password slices
  (`:50-66`). Smaller + lower-traffic than the others; 24 unit suites but the
  crypto path is mocked (C2). **Fold into the per-flow split AFTER R6-C2's cipher
  tests land** so the unlock flow can be split with real coverage. Split into
  `OnboardConnect`/`ImportProfile`/`UnlockProfile`/`ProfileList`. Rule
  `ARC-02` — igloo-chrome · synthesis R2 row 6.

### R3 — Dedup & divergence (each duplicate names BOTH sites)

C6 (`CQ-04`/`ARC-05`/`ARC-06`/`RS-01`). Several are the seams the R2 splits
need — interleave with R2.

- [ ] (effort: S) **R3.1 — One `toErrorMessage`; delete the 4 forks + pwa's
  5th.** Canonical: `igloo-shared/src/runtime-internal.ts:81` (richest — also
  reads `.error`/`.reason`). Delete/redirect:
  `igloo-shared/src/browser-profile/save/common.ts:14` (fallback required) and
  `igloo-shared/src/browser-profile/session-orchestration/warning.ts:3` (returns
  `string | null` — express `?? undefined` at the call site, don't fork the
  return type); `igloo-pwa/src/App.tsx:99-113` (`formatUiError` — fold its
  `JSON.stringify` branch into a thin UI wrapper) and
  `igloo-pwa/src/lib/page-runtime-host.ts:138-145` (consume the shared export).
  Rule `CQ-04` — igloo-shared + igloo-pwa · synthesis C6.
- [ ] (effort: S) **R3.2 — Collapse the ~25 `updateXForm`/`updateXPassword`
  draft updaters into one `updateDraft`/`updateSecret` pair.** The secret/
  persistable partition must be enforced in **one** place + asserted by one test.
  Evidence `igloo-pwa/src/lib/store.tsx:758-1132` + the secret-routing variants
  `:1139-1147,1548-1556,1719-1727`. Rule `CQ-04`/`RS-02`. (Also shrinks R2's
  store.tsx materially.) — igloo-pwa · synthesis C6.
- [ ] (effort: S) **R3.3 — Resolve the two `PeerPolicy` types + unify peer-data
  models toward `buildPeerReadinessRows`.** Two same-named, structurally-divergent
  public types bridged by `as` casts: `igloo-shared/src/wasm-bridge-node.ts:108-113`
  (loose, index-signature; `fetchPeers` returns ui-shape via `as PeerPolicy` at
  `:732,738`) vs `igloo-ui/src/components/ui/peer-list.tsx:7-19` (structured). Have
  igloo-shared return a typed `RuntimePeerStatus[]`/permission read model and let
  the ui projection build from it (removing the index signature + casts). And the
  TWO parallel peer-permission normalizers re-modeling one wire shape:
  `igloo-home/src/lib/dashboard-view.ts:18-41` + inline `extract*`
  (`igloo-home/src/App.tsx:341-440`) vs `igloo-pwa/src/lib/types.ts:54-66` +
  `igloo-pwa/src/lib/local-adapter/common.ts:124-207` — promote one normalizer
  into igloo-shared/igloo-ui (the canonical `buildPeerReadinessRows` projection,
  `igloo-ui/src/adapters/runtime-view-models.ts`) both hosts consume. Also retire
  the unused dual peer model `igloo-ui/src/models/view-models.ts:77-98`
  (`PeerReadinessRowModel`) vs `peer-list.tsx` `PeerPolicy` — pick
  `OperatorSignerPanel.PeerRow` (`OperatorSignerPanel.tsx:187-303`) as canonical.
  Rule `ARC-06`/`ARC-05`/`CQ-04` — igloo-shared + igloo-ui + igloo-home +
  igloo-pwa · synthesis C6.
- [ ] (effort: S) **R3.4 — One `lib/format.ts` for pubkey-truncation +
  epoch-normalization.** Four truncators at three widths + a copy-pasted
  seconds/ms heuristic (named-constant the `10_000_000_000` threshold):
  `igloo-ui/src/adapters/runtime-view-models.ts:386-387` (`6/4`) + `:416-418`;
  `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:323-325` (`6/4`);
  `igloo-ui/src/components/flows/CreateFlow.tsx:853-857` (`shortKey`, `10/6` —
  same name different width, `RS-01`);
  `igloo-ui/src/components/ui/peer-list.tsx:29` (`14/8`) + `:31-41`;
  `igloo-ui/src/components/flows/ManagedProfilesPanel.tsx:37` (third ts
  convention, no guard). Add `truncatePubkey`/`formatEpoch`. Rule
  `CQ-04`/`RS-01`/`CQ-06` — igloo-ui · synthesis C6.
- [ ] (effort: S) **R3.5 — One shared `downloadText` + error-coercion util;
  collapse the low-level hex/relay helpers.** `downloadText` lives in 3 repos:
  `igloo-home/src/App.tsx:198-208`, `igloo-chrome/.../SettingsPanel.tsx:75,134,
  158,175`, `igloo-pwa/src/lib/file-save.ts` — one home in igloo-shared. Plus the
  twice-defined divergent primitives: `normalizeHex32`
  (`igloo-shared/src/runtime-internal.ts:110` vs `browser-profile/core/keys.ts:12`,
  trailing-period text diverges), `hexToBytes` (`runtime-internal.ts:118` any
  even-length vs `keys.ts:3` 32-byte-only — opposite acceptance sets, name into
  `hexToBytes32`), `normalizeRelays` (`relay-transport.ts:20` `{relays,errors}` vs
  `rotation.ts:63` throws — build the throw shape on the canonical result). Rule
  `CQ-04` — igloo-shared + all hosts · synthesis C6.
- [ ] (effort: S) **R3.6 — Rename chrome's triple-`profileKey` by meaning.**
  `igloo-chrome/src/background/utils.ts:36-51` (group+relays fingerprint →
  `profileFingerprint`) vs `igloo-chrome/src/lib/runtime-host/helpers.ts:18-20`
  (lowercased id → `profileIdKey`) vs the `SignerSession.profileKey` field
  (`igloo-chrome/src/lib/runtime-host/controller.ts:69,72,116`, third meaning).
  Feeds cache keys (`controller.ts:179`) + `profile_key` log fields — a mix-up is
  a silent session-reuse/dedup bug. Rule `RS-01`/`CQ-04` — igloo-chrome ·
  synthesis C6.

### R4 — Dead-surface removal (each with its removal trigger)

C7 (`LEG-04`). **Trigger: at the next release cut, if no host imports it** —
enforced by R1.2 knip.

- [ ] (effort: S) **R4.1 — Delete the four orphan igloo-ui flow components +
  barrel exports + tests (~734 LOC).** Zero host consumers (cross-repo grep):
  `CreateImportPanel.tsx:1-361`, `ManagedProfilesPanel.tsx:1-164`,
  `RecoveryWorkspace.tsx:1-92`, `DesktopAppShell.tsx:1-117` (the last is actively
  misleading — igloo-home uses `HostFlowShell`, `igloo-home/src/App.tsx:19,1508`,
  not it); barrel entries `igloo-ui/src/index.ts:179,202,208,231`. **Resolve the
  R5-C1 nsec leak inside `CreateImportPanel` BEFORE deciding its fate — or delete
  it and the leak goes with it.** Trigger: no host import by the next release cut.
  Rule `LEG-04` — igloo-ui · synthesis C7/R4.
- [ ] (effort: S) **R4.2 — Delete the unused `PeerList`/`PeerPolicy` primitive**
  (only `test/ui/peer-list.test.tsx` + `test/axe/primitives.test.tsx` render it)
  once `OperatorSignerPanel.PeerRow` is confirmed canonical (R3.3). Barrel
  `igloo-ui/src/index.ts:118-119`; type+renderer
  `igloo-ui/src/components/ui/peer-list.tsx:7-19,71-261`. Trigger: R3.3 picks the
  canonical model. Rule `LEG-04` — igloo-ui · synthesis C7/R4.
- [ ] (effort: S) **R4.3 — Delete dead `introMessage` prop** (declared
  "retained for API compatibility … no longer rendered," not destructured, no
  caller): `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:19-21`. Rule
  `LEG-04` — igloo-ui · synthesis C7/R4.
- [ ] (effort: S) **R4.4 — Delete dead `readNumber`** (zero callers; `tsc` stays
  green only because `noUnusedLocals` is off — also enable it):
  `igloo-pwa/src/App.tsx:281-288`. Rule `LEG-04` — igloo-pwa · synthesis C7/R4.

### R5 — Secret hygiene (thread `Secret<T>`/`SecretBytes`; unmask the nsec)

C1 + C5 + C8 (`SEC-01`/`SEC-03`/`RS-06`). The C1 leak leads the whole audit
sequence.

- [x] (effort: S) **DONE (2026-06-21) — R5.1 — C1 (leak-NOW): mask the recovered
  nsec in all three recovery UIs.** On verification the leak was already closed:
  the igloo-ui `CreateImportPanel` was deleted (R4.1), and home + pwa already
  masked by default (home via `SensitiveTextarea`, pwa via a reveal toggle). The
  remaining gap — pwa showed a 10-char prefix (`nsec1` + ~5 key chars) — is now
  masked to the bech32 HRP alone (`igloo-pwa` `3646fd1`). Regression net added
  under R6.1 below. The original (now-stale) finding: a full root private key
  rendered in a bare `<dd>` while the
  *less* sensitive package JSON beside it is wrapped in `SensitiveTextarea` —
  inverted threat model, in a "tested" component:
  `igloo-ui/src/components/flows/CreateImportPanel.tsx:300-301` (vs `:304,320`
  masked). Same bare nsec at `igloo-home/src/App.tsx:1719-1740` and in pwa React
  state (`igloo-pwa/src/App.tsx:469,538-541`). Route through
  `SensitiveField`/`SensitiveTextarea`. **Land first** + pair with the R6.1
  mask assertion as the regression net. Rule `SEC-01` — igloo-ui + igloo-home +
  igloo-pwa · synthesis C1/R5.
- [ ] (effort: M) **R5.2 — C5: thread `Secret<T>`/`ShareSecretHex` through
  rotation/recovery + decide the snapshot-wire `seckey` policy.** Discipline
  stops at the onboarding boundary (wrapped: `wire/onboarding.ts:18`) but
  rotation/recovery pass bare `string[]` and return bare nsec:
  `igloo-shared/src/rotation.ts:78-84,87-96,150-157` (inputs `shareSecrets:
  string[]`), `:139-173` (`BrowserRecoveredKey { nsec; signingKeyHex }` bare);
  bare snapshot `seckey` at `igloo-shared/src/wire/runtime.ts:240,251,262`
  (wrap, or write a one-line exemption rationale at `:238`). Wrapping at the
  shared boundary propagates to the unwrapped consumers
  (`igloo-pwa/.../local-adapter/profile-generate.ts`,
  `igloo-chrome/.../background/router-profiles.ts`). Rule `SEC-01` — igloo-shared
  + consumers · synthesis C5/R5.
- [ ] (effort: M) **R5.3 — C2-half: keep chrome's derived master key
  non-extractable; pass the `CryptoKey` handle, not a base64 string.**
  `igloo-chrome/src/lib/profile-blob.ts:89` (`extractable: true`) + `:107`
  (`exportSessionKey`) deliberately serialize the blob's unlock key to bare
  base64, which then persists as a plain string (`extension/storage.ts:159-186`,
  `runtime-service/types.ts:17` `SignerSession.sessionKeyB64`) and is
  reconstructed every `runtime-status` tick (`snapshot-persistence.ts:25-34`,
  decrypt→reencrypt of the share plaintext). Thread the `CryptoKey` through
  `SignerSession`; separate the snapshot-stamp path so a tick doesn't round-trip
  the share plaintext. (KDF-home decision is in R6.2's "then de-divergence.")
  Rule `SEC-03`/`SEC-01` — igloo-chrome · synthesis C2/R5.
- [ ] (effort: S) **R5.4 — Minimal JS transient-secret helper for the browser/
  Tauri frontends.** Frontends hold passphrases/nsec/share-passwords as
  un-zeroizable bare `string`: `igloo-pwa/src/lib/types.ts:171,187,294-303`,
  `igloo-pwa/src/lib/store.tsx:124,1007-1035`; `igloo-home/src/App.tsx:598-600`
  (+ landing/onboard/save/load draft passphrases). A shared "transient secret"
  convention (prefer `Uint8Array` so it can be `.fill(0)`-wiped; centralize
  lifetime/length discipline) serves both. Plus add the missing scrub-on-leave
  test (R6.4). Rule `SEC-01` — igloo-pwa + igloo-home + igloo-shared · synthesis
  C5/R5.
- [ ] (effort: S) **R5.5 — C8: replace fabricated onboard-handshake metadata
  with parsed values or a neutral state.** The panel hardcodes `"My Signing
  Key"`, `"2/3"`, and `Share #0`
  (`igloo-ui/src/components/flows/CreateFlow.tsx:1541-1542,1554,1563`) and the PWA
  passes the literals during a LIVE handshake
  (`igloo-pwa/src/App.tsx:1069-1070,1092-1093`) — a 3/5 keyset is shown "2/3" as
  fact, masking a wrong-package mistake. Make `keysetName`/`thresholdLabel`/
  `shareIndex` required (or render only when supplied); parse from the package or
  show a neutral "Validating package…". Rule `RS-06`/`DOC-05` — igloo-ui +
  igloo-pwa · synthesis C8/R5.
- [ ] (effort: S) **R5.6 — Clipboard secret has no auto-clear; copy/remask
  duplicated.** Reveal auto-remasks at 30s but `copyToClipboard` writes the
  secret to the system clipboard with no expiry, and the copy+remask block is
  duplicated verbatim with a magic `30000`:
  `igloo-ui/src/components/ui/sensitive-textarea.tsx:39-43,54,76-84` and
  `sensitive-field.tsx:35-36,49,70-77`. Factor a `useSensitiveReveal` hook (name
  `SENSITIVE_AUTO_MASK_MS`); best-effort clipboard clear or document it. Rule
  `SEC-01`/`CQ-04`/`CQ-06` — igloo-ui · synthesis C1/R5.

### R6 — Testing depth (adversarial/KAT gaps; the render-only blind spot)

C2 + C4 (`TST-02`/`TST-03`/`TST-05`). `make test-fast` is render-only, so a
green pre-push coexists with a broken cipher or bypassed guard — these tests are
the safety net R2's decomposition depends on.

- [~] (effort: S) **PARTIAL (2026-06-21) — R6.1 — Secret-mask/scrub assertions (regression net for
  R5.1).** Assert the generated share + recovered nsec are NOT in the initial DOM
  text (masked by default) and are cleared on view-leave. igloo-ui flow tests are
  render-only (`igloo-ui/test/CreateFlow.test.tsx`,
  `CreateImportPanel.test.tsx:1-43`) — masking is proven only on the primitive in
  isolation (`test/ui/sensitive.test.tsx`), nothing asserts `CreateImportPanel`
  routes the nsec through it (which is why C1 passes green). Home: the
  scrub-on-leave effect (`igloo-home/src/App.tsx:742-748,753-760`) is asserted
  nowhere — `RecoverKey.test.tsx:122-145` asserts the nsec *appears* and stops.
  Rule `TST-02` — igloo-ui + igloo-home · synthesis C4/R6.
  - **DONE (2026-06-21):** the *masking* assertions — home (`RecoverKey.test.tsx`,
    `igloo-home` `a1ecb05`) and pwa (`App.test.tsx`, `igloo-pwa` `3646fd1`) now
    assert the recovered nsec/signing key are not in the DOM until revealed (pwa
    also asserts HRP-only masking).
  - **STILL OPEN:** the *scrub-on-leave* assertions (home `activeView` change +
    pwa 60s/navigate-away clear), and the igloo-ui flow-level mask assertion for
    the generated share.
- [ ] (effort: M) **R6.2 — Direct `profile-blob.test.ts` for chrome + unwrap the
  mocks (HIGHEST value).** The host's only real crypto is `vi.fn()`-mocked out of
  every test (`igloo-chrome/tests/unit/background/profile-service.test.ts:19-20,
  49-50,81-82`) and `profile-blob.ts` has zero direct importer — so PBKDF2
  derivation, AES-GCM round-trip, **wrong-password reject, and GCM-tag-flip
  (single-bit ciphertext flip) are entirely unasserted.** Add: round-trip,
  wrong-password reject, corrupted-ciphertext reject, and a recorded **KAT
  vector** pinning the KDF/cipher params; unwrap the profile-service mocks. Also
  cover the untested reject arms: `provider-execution.ts:18-42` +
  `nostr-provider.ts:78-107`. **Do this BEFORE the R5.3 de-divergence** so the
  security-critical change has a net. Rule `TST-05`/`TST-03`/`TST-02` —
  igloo-chrome · synthesis C2/R6.
- [ ] (effort: M) **R6.3 — Adversarial import/onboard decrypt tests (pwa).** The
  two riskiest trust boundaries decrypt attacker-supplied package text but have
  only happy-path coverage; their `load-error`/`onboard-failed` routing is
  untested: `igloo-pwa/src/lib/store.tsx:1557-1596` (`loadBfProfile`),
  `:1664-1706` (`connectOnboardingPackage`); current tests assert success only
  (`test/frontend/App.test.tsx:726`,
  `test/igloo-pwa/specs/profile-import.spec.ts:9`). Feed corrupted/truncated
  ciphertext + wrong import password → assert the error view + preserved-secret
  cleanup. **Land before splitting store.tsx's import/onboard slices (R2).** Rule
  `TST-02`/`SEC-04` — igloo-pwa · synthesis C4/R6.
- [ ] (effort: M) **R6.4 — Adversarial unlock/onboard/rotate tests (home).**
  Unlock (start-session), onboard-finalize, and rotate-apply have no end-to-end
  frontend test and every existing test asserts success only
  (`igloo-home/test/frontend/App.test.tsx:162-291`, etc.). Mock
  `startProfileSession`/`importProfileFromBfprofile` to reject with each
  `HomeErrorPayload` kind and assert the user-facing banner reaches the operator
  through `run()`/`rethrowHomeError`; assert the confirm-password-mismatch +
  empty-passphrase guards (`igloo-home/src/App.tsx:1046,1118`). Rule
  `TST-02`/`TST-01` — igloo-home · synthesis C4/R6.
- [ ] (effort: M) **R6.5 — Failure-path unit tests for the bridge node
  orchestration (shared), added AS each R2 seam is extracted.** Untested at unit
  layer (only `@live`/E2E — the render-only blind spot): `signNostrEvent`
  verify-fail (`igloo-shared/src/wasm-bridge-node.ts:819-840,835`),
  `nip44Encrypt/Decrypt` on ECDH-command reject (`:842-874`), `pumpRuntime`
  failure-drain rejecting a pending sign (`:1399-1544,1522-1534`). Current suite
  (`wasm-bridge-node.test.ts`) covers construction/emitter/guards/shutdown only.
  Prioritize the ECDH-reject + sign-verify-fail (security-relevant) paths. Rule
  `TST-02` — igloo-shared · synthesis C4/R6 (the safety net for R2 row 3).

### Rust-shell tail (igloo-home-local; alongside R3/R6)

C9 (`ARC-06`/`CQ-02`) — not a front-end bucket but graduated here from the same
run.

- [ ] (effort: S) **Derive the test-dispatch command set from the real
  registration.** The hand-maintained `EXPECTED_DISPATCH_COMMANDS` (24 entries,
  `igloo-home/src-tauri/src/app/test_dispatch.rs:303-331`) is missing 5+ real
  commands incl. the security-relevant `resolve_approval` + `update_peer_policy`
  (+ `list_relay_profiles`, `resolve_close_request`,
  `update_profile_operator_settings`); the real surface is
  `commands.rs:393-668` registered via `bootstrap.rs:79` `generate_handler!`. Make
  one `const COMMANDS: &[&str]` both consume, or assert every `*_command` has a
  dispatch arm. Rule `ARC-06` — igloo-home · synthesis C9.
- [ ] (effort: S) **Funnel `lock().unwrap()` through one poison-mapping helper.**
  25 `.lock().unwrap()` on IPC-reachable paths turn a poisoned mutex into a hard
  backend crash: `igloo-home/src-tauri/src/session/controller.rs:33`,
  `app/commands.rs:233,262,374` (profiles.rs ×6, controller.rs ×6, paths.rs ×3,
  …). Map `PoisonError` → a typed `HomeError` (or `into_inner()` where state is
  consistent) so it surfaces as a renderable error, not a panic. Rule `CQ-02` —
  igloo-home · synthesis C9.

## Test infrastructure remediation (audit 2026-06-17)

Mirrored from [`docs/TEST-AUDIT.md`](./docs/TEST-AUDIT.md) (97 findings, full
detail there). Design fixed by
[ADR-013](./adrs/ADR-013-test-infrastructure-architecture.md) (test infrastructure
architecture, **Accepted 2026-06-17**) — see it for the sequencing constraints and
rejected alternatives. Remediation is unblocked; start with the P0 items.
Priorities: P0 = correctness/coverage risk; P1 = high-friction debt; P2 = clarity.

- [x] (effort: M) **DONE (2026-06-18) — P1 — Repair the drifted pwa `@live` lane**
  (found by the `make test-live` shakedown: 13/15 pwa `@live` specs red, all
  **pre-existing** drift — not from the P1/P2 work). Two root causes, both fixed:
  **(1) dashboard label drift** — the Paper redesign renders the device label
  nowhere on the dashboard, but `expectPwaDashboard` (ui.ts) and the `expectDashboard`
  page object (pages.ts) still asserted `dashboard-root` contains it; dropped the
  assertion (the correct profile is guaranteed by the label-filtered load step).
  **(2) legacy storage key** — `persistedHasSignerName` (settings) and
  `persistedHasDenyOverride` (permissions) polled the retired `igloo-pwa.state.v2`
  key instead of the current `PWA_GLOBAL_STORE_KEY` (the 2026-06-16 store split);
  repointed both at the global store. Validated individually (profile-inventory,
  create-keyset, settings green); full `make test-live` re-run for final
  confirmation. Also fixed the **dangling igloo-ui pointer**: `repos/igloo-ui`
  `fcc0592` (the redesign commit) was local-only — pushed it so recursive
  checkouts / CI resolve again (was the 37s nightly checkout failure) — test/ +
  igloo-ui pointer.
- [x] (effort: S) **DONE (2026-06-18) — Test the test-infra (self-tests).** Added
  unit tests for the shared helpers (`test/shared/process-helpers.unit.ts` via
  `unit.config.ts` + `test:unit:shared`, wired into `test:verify`): idempotent
  `closeChild`, `allocatePort`, register/unregister/reap (hermetic temp registry via
  the new `FROSTR_TEST_PROCESS_REGISTRY_DIR` override). Added adversarial guard
  fixtures: `persist-contract.expect-error.ts` (a defanged contract fails typecheck)
  and `check-harness-guards-negative.sh` (a corrupted WASM stamp must fail the guard;
  wired into `test:guards:full`). Behavioral shakedown (`make test-live`) run: no
  leaked relays (Phase 2 teardown verified); it surfaced the pre-existing `@live`
  drift above — test/.

- [x] (effort: S) **DONE (2026-06-18) — P0 — Gate selector contracts in the global
  per-PR lane.** Added `test:guards:selectors` (cross-client-imports + e2e selector
  contract) to `test:guards`, so the global selector contract now runs in `make
  verify` (`test:verify`), CI `workspace-guards` (`npm run test:guards`), and the
  affected lane — same-PR, not nightly-only. No double-run: `test:guards:full` lists
  the sub-guards individually. Stays "lean guards" (ripgrep, sub-second). `make
  verify` green — test/.
- [x] (effort: S) **DONE (2026-06-18) — P0 #2a — Tag the silent specs + add the
  tag-completeness guard.** Tagged the 11 fully-untagged spec files at the describe
  level (chrome profile-import/rotation-update → `@live` (local relay); chrome
  provider, pwa app-shell/wasm-integrity, ui-showcase reference-screens → `@fast`;
  the 5 home `-live` specs → `@live`). Added `check-spec-primary-tags.sh`
  (`test:guards:tags`) — ≥1 lane tag, `@agent` exempt — wired into `test:guards`
  (per-PR) + `test:guards:full`. Amended ADR-013 "exactly one" → "at least one"
  (demo specs layer). test/.
- [x] (effort: M) **DONE (2026-06-18) — P0 #2b — Gate Chrome e2e in CI + complete the
  fast-lane filter.** Added `test:e2e:igloo-chrome:fast` (+ Playwright install) to the
  chrome `client-scoped-validation` job — closes the audit's headline "Chrome has zero
  per-PR e2e" gap. Completed the fast grep-invert to exclude `@demo` too
  (`@live|@cross-client|@demo|@agent`); `@visual` stays in fast (render-only). Home has
  no `@fast` specs (all `@live`/tauri) so "Home:fast" is N/A; home's per-PR render
  coverage is the `@agent` screenshot tool. `make verify` green. **Deferred (not
  blocking):** explicit per-test `@fast` tag (ADR Q9) — large per-test churn across
  mixed files; the completed grep-invert gives identical gating today — test/ + CI.
- [x] (effort: S) **DONE (2026-06-18) — P0 #3a — Per-affected unit suites in CI.**
  Wired the submodule `test:unit` suites into `client-scoped-validation`: shared+pwa
  (pwa job), chrome (chrome job), home (home job). All green locally (shared 151 /
  pwa 71 / chrome 98 / home 25). — test/ + CI.
- [x] (effort: M) **DONE (2026-06-18) — P0 #3b — `@live` smoke + cargo lib-test;
  document `@cross-client` nightly.** Added a dedicated `@live @smoke` spec per
  client over an **in-process relay** (no Docker/external infra):
  `igloo-pwa/specs/onboarding-smoke.spec.ts` (two-device onboard → both nonce pools
  hydrate / sign-ready; **verified locally** 13s), `igloo-chrome/specs/signing-smoke.spec.ts`
  (onboarded live signer → real provider `signEvent` round-trip, verifies group
  pubkey; **verified locally** 59s), `igloo-home/specs/onboarding-smoke.spec.ts`
  (bfonboard handshake vs a live inviter session; CI-verified only — desktop host).
  New `--grep @smoke` lanes (`test:e2e:igloo-{pwa,chrome,home}:smoke`). **Gating:**
  pwa+chrome smoke run **per-PR** in `client-scoped-validation` (deps already there);
  the home smoke needs tauri+webkit2gtk+xvfb so it's gated **nightly** in
  `release-validation` (home e2e ran in *no* CI lane before — pre-existing gap now
  closed for the smoke). Added `cargo test --lib --workspace` (bifrost-rs) to the
  pwa+chrome per-PR jobs (**verified locally**, 37 tests). Documented `@cross-client`
  as manual/non-gated (README + WORKFLOWS). `make verify` green.
  **Drive-by fix:** `expectPwaSignerSignReady` greped a literal `sign-ready` string
  the Paper-redesigned dashboard no longer renders; re-pointed it at the modern
  "N ready" nonce-pool signal. This un-breaks the 6 other `@live` specs that share
  the helper (onboarding, sign-shell, sign-reload, dashboard-states, approval-queue,
  permissions, pwa-home-pairing) — they were not independently re-run (nightly).
  **Deviations from ADR-013 §(b) (intentional, lean-CI):** home smoke is nightly not
  per-PR; cargo lib-test is bifrost-rs only (igloo-shell is in no per-PR job → stays
  nightly); smoke is wired into the per-client CI jobs, not literally into `make
  verify` (kept render-only/fast). — test/ + CI.
- [ ] (effort: M) **P0 — Enforce WASM provenance** (ADR Q4) — scripts/ + test/.
  **Root cause pinned (2026-06-18):** the test process encrypts with the `.tmp`
  **igloo-shared** scratch WASM (`resolveTestBrowserWasmDir`), but a dist-serving
  spec (chrome-pwa-pairing) decrypts with the pwa **dist** WASM, which vite's
  `resolveWasmSourceDir` copied from a *different* source — the chrome-target
  prebuild refreshes shared+chrome scratch but **not** igloo-pwa, and
  `prepare-browser-wasm.sh` builds one shared WASM then *copies* it per client, so
  the pwa copy can lag. The app's SHA-384 loader then rejects the mismatched WASM →
  cryptic "Incorrect password". NB the `@fast`/dev-server lanes use one consistent
  WASM, so the main gates are NOT exposed — this is specific to dist-serving specs.
  NB2 the ADR's "make prebuild `check` fail-hard because callers continue with
  stale" is inaccurate: `test/shared/test-prebuild.ts` already does check→catch→sync
  (auto-rebuild on stale); fail-hard would *remove* that self-heal. Deliverables:
  **(a) DONE (2026-06-18)** — `test/shared/wasm-provenance.ts` (`assertWasmProvenance`)
  fails fast with a clear SHA-384 mismatch message, wired into the chrome
  global-setup (gates the per-PR chrome lane) + the pwa-dist server in
  chrome-pwa-pairing (the bug site); `make verify` green.
  **(b) DONE (2026-06-18)** — structural: added `pwa` to the chrome lane's
  `prebuild` set in `test-targets.json`, so the full chrome lane (where the
  `@cross-client` pwa-dist specs run) prebuilds pwa → the pwa dist is rebuilt fresh
  from the same shared WASM the test injects → no skew. `fastPrebuild` stays lean
  (chrome only), so the chrome `@fast` lane is unaffected. With (a) as the runtime
  tripwire, the provenance gap is closed. **(c) OPTIONAL follow-up** — expand the
  prebuild stamp to cover the toolchain (wasm-bindgen/build scripts) so a toolchain
  bump invalidates the cache; nice-to-have hardening, not required for correctness.
- [x] (effort: S) **DONE (2026-06-18) — P1 — Expand the WASM stamp** to cover
  toolchain + igloo-shared build inputs. `check-browser-wasm-stamp.sh` now also
  hashes the igloo-shared build driver (`scripts/build-bridge-wasm.sh`) and the
  parent-repo toolchain pin (`check-wasm-toolchain.sh`, which encodes the expected
  wasm-pack version), so a build-script or toolchain bump invalidates the stamp and
  forces a rebuild + re-stamp — test/ + scripts/.
- [x] (decided 2026-06-18) **P1 — Home `@live @smoke` tier: ACCEPT NIGHTLY.** ADR-013
  §(b) wants smoke per affected client per-PR, but the per-PR `home` job has no
  tauri/webkit2gtk/xvfb buildout and adding the full desktop toolchain to every
  home/test/shared PR conflicts with the 2026-06-17 lean-CI cut. Decision: the home
  smoke runs in the nightly `release-validation` job (where the toolchain already
  exists); documented in `test/README.md` tiers. Revisit if home regressions recur.
- [x] (effort: S) **DONE (2026-06-18) — P1 — Add `cargo test --lib` for igloo-shell**
  to a per-PR lane. Added a `shell` job to `client-scoped-validation.yml` (checks out
  bifrost-rs + igloo-shell for the path deps, runs `cargo test --lib --workspace`)
  and added `repos/igloo-shell` to the workflow path triggers (it gated nowhere
  per-PR before). Verified the command locally (7 tests) — CI.
- [ ] (effort: S) **P2 — Re-verify the 6 other `@live` specs** that share
  `expectPwaSignerSignReady` after its P0 #3b drift fix (onboarding, sign-shell,
  sign-reload, dashboard-states, approval-queue, permissions, pwa-home-pairing).
  The fix was validated via the new pwa smoke; the rest run nightly and were not
  individually re-run — confirm green on the next `release-validation` — test/.
- [x] (effort: M) **DONE (2026-06-18) — P1 — Type-enforce fixture seeds against the
  persist allowlist** (`PersistableStoredProfile`, ADR Q7). Added the contract to
  **igloo-shared** (`persist-contract.ts`); igloo-pwa derives `PROFILE_ALLOWED_KEYS`
  from it with a compile-time drift guard; the test harness's `PwaStoredProfileSeed`
  now aliases the shared contract, so a seed setting a non-persisted field (raw
  share, stored password, runtime snapshot) is a **compile error**. Cleaned those
  fields from the shared builder + the manually-built seeds (app-shell /
  dashboard-visual / welcome-visual / recover-visual). `make verify` green —
  igloo-shared + igloo-pwa + test/.
- [~] (effort: M) **P1 — Consolidate seed builders + centralize the test password**
  (one `ProfileSeedInput`, shared test-secrets). **Partial (2026-06-18):** added
  `test/shared/test-secrets.ts` (the 3 canonical passwords, single source) and
  wired the fixture-level definitions (browser-artifacts, chrome seed-crypto, chrome
  live-signer). **Remaining:** swap the ~25 per-spec inline literals to the
  test-secrets imports, add a guard banning inline canonical-password literals (it
  depends on the swap), and unify the chrome/home seed builders under one
  `ProfileSeedInput` (PWA builder already type-enforced) — test/.
- [x] (effort: M) **DONE (2026-06-18) — P1 — Robust process teardown.** Added
  `test/shared/process-lifecycle.ts` (`closeChild` — idempotent SIGTERM→SIGKILL
  escalation, always resolves) wired into local-relay, the home app harness (was
  SIGTERM + 5s with no kill), and the chrome managed relay. Added
  `test/shared/process-registry.ts` + `global-teardown.ts` (a run-scoped PID
  registry reaped by a Playwright `globalTeardown` — never a blanket `pkill`).
  Verified: pwa + chrome smoke pass, no leaked relays — test/.
- [x] (effort: S) **DONE (2026-06-18) — P1 — Unify relay port allocation.** Added
  `test/shared/port-allocation.ts` (`allocatePort` via `listen(0)`); replaced the
  three colliding strategies (local-relay 24k–44k random, chrome live-signer
  18k–28k random, demo-harness `43000+pid`) and folded the home app/harness
  duplicate `listen(0)` helpers onto it — test/.
- [~] (effort: L) **P1 — Unified visual-harness module** (ADR Q3). **Core done
  (2026-06-18):** `test/shared/visual-harness.ts` provides `captureVisual`
  (`.tmp/visual/<client>/<section>/`) and `captureAgentArtifact` (`.tmp/agent/`,
  the documented `make screenshot` contract). Migrated all 10 capture sites — the 7
  pwa `@visual` specs + the pwa/chrome/home `@agent` tools — off their duplicated
  `capture()` helpers. Home already runs on bundled Playwright
  (`playwright-screenshot.config.ts`); no `.mjs` smoke remains. **Remaining:** one
  visual manifest + guard covering chrome + home (today only pwa has
  `visual-manifest.json`) — test/ + igloo-home.
- [x] (effort: M) **DONE (2026-06-18) — P2 — Make `test-targets.json` the single
  source** for affected/prebuild mapping. The path → client mapping now derives
  from the manifest's `paths` via a new `test_client_for_path` lib helper (was
  hardcoded `repos/igloo-{pwa,chrome,home}/*` globs in `test-affected.sh`); the
  `check-test-targets` guard asserts the helper is used and that no per-client repo
  glob is re-hardcoded. Prebuild targets already came from the manifest — test/ +
  scripts/.
- [x] (effort: M) **DONE (2026-06-18) — P2 — Document lanes, env-var schema,
  services, fixture ownership.** Added a lane/coverage matrix to `test/README.md`,
  `test/docs/TEST-ENV-VARS.md` (FROSTR_*/IGLOO_* schema), `services/README.md`
  (dev-relay / igloo-demo / demo), and `test/docs/FIXTURES.md` (seed contract,
  test-secrets, port/lifecycle/visual helpers, per-client fixture entry points) — docs.
- [x] (resolved 2026-06-18) **P2 — Lane semantics + dead-guard audit** (ADR Q9).
  **Dead guards finding corrected:** `check-worktree-unchanged` is NOT dead — it is
  wired via `check-test-prebuild-nonmutating.sh` (`test:guards:wasm:strict`);
  `check-wasm-toolchain` is an intentional manual preflight (`make
  wasm-toolchain-check`, in the doc-command-surface allowlist + AGENTS.md). Neither
  is deleted. **Lane renames deferred (documented instead):** renaming `@fast`/lanes
  is high blast-radius (every spec + grep-inverts + the doc-command-surface
  allowlist + CI + docs) for low value; the new lane/coverage matrix documents the
  honest semantics (`@fast` = render-only) instead. Reopen only if the names cause
  real confusion — test/ + scripts/.

## Design (Paper ↔ runtime)

- [ ] (effort: S) **Promote the `dashboard-signer` visual entry to `aligned`.** Its
  blocking telemetry (per-peer latency, nonce sparkline, SIGN/ECDH/PING capability
  badges) shipped 2026-06-13 and now renders in `OperatorSignerPanel`. Re-shoot /
  re-diff the visual against Paper's `1-signer-dashboard` and update the entry's
  status — `igloo-paper` + the visual lane.
- [ ] (effort: M) Add a **Browser Settings** group to the Paper `502-0` Settings
  artboard so the PWA-only toggles (Remember browser state / Open signer after
  import / Prefer install prompt) are reflected in the design — `igloo-paper` ·
  surfaced 2026-06-09, the only PWA-only Settings section without a Paper counterpart.
- [ ] (effort: S) Edit Paper so the merged **identity/runtime card is
  dashboard-only** — drop the repeated header from the Permissions/Settings
  artboards (`1c-permissions`, `502-0`) to match the runtime (decided 2026-06-09).
- [ ] (effort: S) Add a **Pending Operations** component to the Paper design system
  to match the runtime `OperatorSignerPanel` card (the runtime card already exists)
  — `igloo-paper`. (The runtime "Diagnostics" card was renamed → **Event Log** to
  match Paper on 2026-06-13.)
- [ ] (effort: S) **Sync the Pending Approvals card + tri-state permissions to Paper.**
  The approval queue shipped 2026-06-14: the Pending Approvals card is now interactive
  (Deny / Allow once / Always allow) and the permissions toggle is tri-state
  (allow → ask → deny → unset, with an amber `ask` state). Re-diff Paper's
  `1-signer-dashboard` + permissions artboard against the runtime — `igloo-paper`.

## bifrost-rs / igloo-shared runtime

- [ ] (effort: L) **Signer bring-up perf: ~18s onboard-ready + ~12s per onboard
  export (unsure how reducible).** Measured 2026-06-17 in the Docker demo: the
  docker build is ~1s; the ~40s "hang" is the signer reaching onboard-ready over
  the relay (`wait_for_onboard_ready` polls ~18s) then a relay-coordinated
  `bfonboard` export per recipient (~12s each). The poll-based readiness in
  `repos/igloo-shell` + relay round-trips dominate. Investigate a deterministic
  ready signal and whether the export can avoid/parallelize round-trips. The native
  `make dev` loop (Thread 1) sidesteps this with a persistent keyset, but it's the
  real cost whenever a device is actually onboarded.

- [x] (effort: L) **Peer telemetry — DONE (2026-06-13).** Per-peer latency (ms,
  last + avg), nonce sparkline, and per-method SIGN/ECDH/PING capability badges, end
  to end: `bifrost-signer` PeerStatus (runtime-only RTT + nonce-history rings, ms
  clock) → `runtime_status()` → igloo-shared wire → igloo-ui adapter +
  OperatorSignerPanel (badges + latency + new Sparkline primitive), threaded through
  the pwa / chrome / home dashboards. Spec items (c)→(a)→(b). The `dashboard-signer`
  visual entry's blocking telemetry has landed — promote it toward `aligned`. Spec:
  [`plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md`](./plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md).
- [x] (effort: L) **Interactive signing-approval queue — DONE (2026-06-14).** A new
  `PolicyOverrideValue::Ask` parks inbound requests in a runtime-only queue until the
  operator resolves them (Deny / Allow once / Always allow), end to end across the Rust
  core (`SignerInput::ResolveApproval` + `pending_approvals` in `runtime_status`), the JS
  bridge (`resolve_approval`), and all three dashboards — including igloo-home, whose
  native (bifrost-bridge-tokio) signer gained Tauri `resolve_approval` / `update_peer_policy`
  commands + editable permissions. Spec item (d). Permissions toggle is now tri-state
  (allow→ask→deny→unset). Verified via `make test-live` (sign-shell + tri-state persistence).
- [x] (effort: S) **Document the `Ask` disposition + approval queue — DONE (2026-06-14).**
  Added an "Interactive Approval (`Ask`)" subsection to `docs/PROTOCOL.md`'s peer-permission
  note: the third policy state, the runtime-only park queue, the three resolution paths,
  timeout/restart drop, and per-device-local semantics.
- [x] (effort: M) **Native control-surface / igloo-shell approval parity — DONE (2026-06-14).**
  Added `ResolveApproval` to `bifrost-app`'s control-socket command surface + a
  `DaemonClient::resolve_approval`, and an `igloo-shell runtime resolve-approval` CLI +
  `CliPolicyValue::Ask` (so `policy set-peer-override --value ask` works). `SetPolicyOverride`
  + `runtime status` (with `pending_approvals`) already existed. The shell now reaches the
  queue over the typed control socket rather than only the direct tokio handle.
- [ ] (effort: S) **Approval-queue cleanup: `approval_timeout_secs` runtime-tunability.**
  It is on `DeviceConfig`/`AppOptions` but not `DeviceConfigPatch` or any settings UI, so it
  can't be tuned at runtime. Low value (fixed 300s default is fine) — deferred. (The sibling
  "Always allow" atomicity concern was verified resolved 2026-06-14: all three clients surface
  a partial-failure via their error paths, and resolve-first ordering is correct.)
- [x] (effort: S) **Wire-type drift guard — DONE (2026-06-15).** Kept igloo-ui
  decoupled from igloo-shared (it deliberately copies test setup rather than depend on
  it) and added a compile-time contract instead: igloo-chrome — the one repo that
  depends on both — hosts `src/extension/runtime-types.contract.ts`, which fails
  `tsc --noEmit` when a canonical igloo-shared wire field is not mirrored by chrome's
  local `RuntimeStatusSummary` or igloo-ui's adapter input types (now exported for the
  check). Key-coverage only; intentional skips (chrome's camelCase `StoredPeerPolicy`,
  `onboarding_statuses`) are spelled out as `Omit<>`. The pwa-local minimal mirrors
  remain a smaller smell (not covered).
- [x] (effort: S) **Removed the dead `runtimeStatusToSignerDashboardView` — DONE
  (2026-06-15).** Deleted (no client consumed it; all dashboards use
  `buildPeerReadinessRows`) along with its orphaned `pendingOperationToRow` helper and
  the two DesignAdapters tests.
- [x] (effort: M) **Refactor the onboard→signer handoff to remove the
  capture-then-reinit seam — PWA done (2026-06-13).** The PWA onboard flow now keeps
  the live onboarding node running and *adopts* it as the durable signer (the
  `keepAlive` path on `connectOnboardingPackageAndCaptureProfile` + the
  `SessionController` staged-session slot), removing the capture-snapshot-then-relaunch
  seam and the pwa-local restore plumbing (`startSession` no longer threads a snapshot).
  Rotation keeps the capture-then-shutdown path (it derives a new keyset). — igloo-pwa.
- [ ] (effort: M) **Chrome onboard→signer seam — same collapse for igloo-chrome.**
  `igloo-chrome/.../onboarding-session.ts` still captures a snapshot and shuts the node
  down, but chrome *persists* `runtimeSnapshotJson` in the profile blob (an MV3 service
  worker can be killed/restarted, so it genuinely needs restore-from-persistence). Its
  collapse is a different shape than the PWA's — separate, carefully-reviewed pass. The
  shared bridge `mode:'persisted'` / `restore_runtime` / resilient-restore stays as long
  as chrome relies on it (surfaced 2026-06-13).
- [ ] (effort: S) **Snapshot version tag (fast-path skip on top of the shipped
  restore fallback).** Resilient restore re-bootstraps from packages when a snapshot
  fails to restore, but it still *attempts* the WASM restore first. Stamp a version at
  snapshot write and skip the restore attempt up front on a known mismatch — purely an
  optimization. Now **chrome-only**: the PWA onboard path no longer restores from a
  snapshot (it adopts the live node), so chrome is the sole remaining producer/consumer
  of onboard snapshots. Must stay back-compatible (treat un-versioned snapshots as
  restorable) — igloo-shared + the chrome snapshot write sites (surfaced 2026-06-13).
- [x] (effort: S) **DONE (2026-06-15).** Router Ping-sentinel — `fail_request_and_dispatch`
  now recovers the real op type from `pending_operations[request_id]` (falling back to
  `Ping` only when absent); the `tick` expire / inbound-request sites stay `Ping` as
  adjudicated. Rode the NIP-44 raw-X WASM rebuild — bifrost-rs `c47d76e`.

## igloo-pwa

- [ ] (effort: S) **Gate the dev-scenario seam behind a build flag.** Both
  `repos/igloo-pwa/src/lib/dev-scenario.ts` and
  `repos/igloo-chrome/src/lib/dev-scenario.ts` (`resolveDevScenario`) run in any
  build when `?__frostr_dev=<scenario>` is present. It's harmless (a fake in-memory
  profile, no real keys/signing, no storage writes), but a production build shouldn't
  carry the seam — tree-shake it out of prod. NB: the chrome build has no
  `import.meta.env.DEV` (it sets `NODE_ENV=production`); use a dedicated define
  (e.g. `VITE_IGLOO_VISUAL`) for chrome. (Mirror whatever igloo-home does for
  `resolveVisualScenario`.)
- [ ] (effort: S) **`agent-screenshot.spec.ts` bypasses the page-object selector
  contract.** It uses raw `getByTestId`/`getByRole`, which `check-e2e-selector-
  contracts.sh` flags (de-gated from PRs, but the nightly `test:guards:full` will
  catch it). Exempt `@agent` tool specs from the contract or route them through a
  page object.
- [ ] (effort: S) **Enrich the dev-scenario running fixture / add scenarios.** The
  running fixture has empty `pending_approvals`/`pending_operations`/structured
  `events`, so those dashboard cards render empty in `make screenshot`. Add a sample
  approval + a couple observability events, and more scenarios (permissions,
  settings, create) for broader render-and-verify coverage.

- [ ] (effort: M) **Finish the Paper dashboard alignment.** The 2026-06-16 pass
  aligned the **signer tab** (running + stopped) to Paper via semantic
  `.igloo-dashboard-*` CSS in igloo-ui + a restructured `OperatorSignerPanel`.
  Remaining Paper dashboard surfaces are unchanged: the **Permissions** and
  **Settings** tab bodies, the shared status-header across all three tabs, the
  condition banners, the loading/load-failed state screens, and the export /
  clear-credentials / unsaved-changes / signer-policy-prompt modals — igloo-ui +
  igloo-pwa.
- [ ] (effort: M) **Runtime-injection seam for dashboard @visual capture.** The
  signer dashboard's *running* layout (Peers + capacity bars, Pending Approvals,
  Event Log) can't be captured by the storage-only `@visual` lane because the
  runtime snapshot is in-memory (never persisted), so `dashboard-visual.spec.ts`
  captures the *stopped* state. Add a test seam (like igloo-home's
  `currentVisualScenario`) so the running dashboard can be seeded + captured
  against Paper `1-signer-dashboard`. The running layout is already unit-tested in
  `repos/igloo-ui/test/OperatorPanels.test.tsx` — test/igloo-pwa.
- [x] (effort: M) **DONE (2026-06-17) — pwa `@fast` red gate fixed.** The two
  `app-shell.spec.ts` persistence specs seeded the legacy `igloo-pwa.state.v2`
  partition directly, which the 2026-06-16 two-store move stopped hydrating to a
  dashboard (hard-failed at `expectDashboard()`). Reseeded both via the supported
  `applyPwaSeed(pwaSeedPayload(buildPwaPersistedState(...)))` path and read the
  settings poll from the global store; added an opt-in `PwaSeedPayload.ifAbsent`
  so the reloading spec doesn't re-seed on reload. pwa `@fast` lane green (20
  passed). `eafdb4a`.
- [ ] (effort: M) **`chrome-pwa-pairing.spec.ts` — last blocker: pwa **dist**
  decryption "Incorrect password".** 2026-06-17: modernized 3 of 4 stale layers and
  the test now drives correctly up to the pwa unlock: (1) dropped the obsolete
  `readPwaRuntimeState(localStorage)` runtime inspection — the pwa keeps no
  `runtimeSnapshot` in storage since the two-store split — for DOM-based hydration
  (`getByLabel('SIGN capable')`); (2) replaced the stale chrome-helper profile load
  (`selectChromeStoredProfile`, expecting a removed "Stored Profiles" card) with the
  current pwa welcome unlock via `loadStoredPwaProfile(page, label, { url })` (added a
  `url` option to that helper); (3) `sign-ready` → `SIGN capable` chips. **Remaining:**
  the unlock modal submits the correct `DEFAULT_BROWSER_PASSWORD` but the pwa **dist**
  returns "Incorrect password", while the identical seed+unlock recipe passes in
  `profile-inventory`/`pwa-home-pairing` against the **vite dev server**. So the
  share decrypts under dev-server WASM but not the prebuilt **dist** WASM → a
  dist-vs-test WASM skew ([[wasm-build-macos]]), not a test-selector issue. This test
  is the only `loadStoredPwaProfile` user that serves the dist. Run it via
  `FROSTR_TEST_PREPARED=1 npx --prefix test playwright test -c
  test/igloo-chrome/playwright.config.ts -g "hydrates nonce pools"` after
  `bash scripts/test-prebuild.sh sync pwa chrome`. `@cross-client`, no default lane.
- [x] (effort: M) **DONE (2026-06-17) — RED GATE chrome `@fast` lane fixed.** Took
  fork **(a)** modernize selectors. The render tool (below) showed the cold seeded
  dashboard renders the stopped **Readiness / Next-Step** cards, not a `Pending
  Operations` section at all — so fork (b) (restore heading roles) wouldn't have
  fixed it. `dashboard.spec.ts`: replaced the `Pending Operations` heading assertion
  with the cold-state `Start Signer` button + `Start signer to restore connectivity.`
  Readiness copy. `profile-import.spec.ts`: `Chrome Import` is the header chip
  `Chrome Import (<id>)`, so dropped `{ exact: true }` for a substring match. Also
  surfaced + fixed a real running-dashboard bug: chrome's `Signer.tsx` never set
  `view.running`, so a *running* signer rendered the stopped cards (no live peers /
  pending sections) — added `running: isSignerRunning` (mirrors igloo-pwa). That
  un-broke the `@live` `signer tab surfaces live nonce pool diagnostics` test, whose
  `sign-ready` peer label is gone post-restructure → retargeted to the `~N ready`
  nonce-pool pill + `SIGN capable` chip. `make verify` green; `@live` diagnostics
  green. chrome `Signer.tsx` (submodule) + test/.
- [ ] (effort: M) **Cross-tab single-active-signer lock.** The 2026-06-16 move to
  a global profile list (shared `igloo-pwa.profiles.v1`, per-tab session in
  `igloo-pwa.session.v1::<id>`) removed the storage partition that *implicitly*
  prevented the same device running in two tabs. Nothing now hard-stops two tabs
  unlocking the same FROST share at once (nonce-reuse / double-sign risk). Add an
  explicit `navigator.locks` per-`profileId` lock acquired **before**
  `adapter.startSession`, with a BroadcastChannel "active in another tab — take
  over?" handshake that stops the other tab's signer before this one starts.
  Start sites: `loadStoredProfile`, `startSigner`, distribution/onboard
  auto-starts; release on stop/logout/delete/unmount — igloo-pwa.
- [x] (effort: L) **DONE (2026-06-15).** Dashboard error/empty states (loading,
  load-failed, all-relays-offline, signing-blocked, signing-failed) — reusable
  igloo-ui screens (`DashboardLoadingScreen` / `DashboardLoadFailedScreen` /
  `DashboardConditionBanner`) + a `deriveDashboardState` selector consumed by all
  three clients (pwa / chrome / home). First-class signals: `last_sign_failure`
  (bifrost-signer, true core field) + bridge-enriched `connected_relays` /
  `configured_relays` (Tokio + browser bridges). Mixed presentation: loading &
  load-failed full-panel; the other three are banners over a usable dashboard.
  Follow-ups below.
- [x] (effort: M) **Dashboard load-failed now reachable in pwa + home — DONE
  (2026-06-15).** A signer-start failure is captured into a `dashboardLoadError`
  state (pwa store / home App) and routes to the dashboard so the full-panel
  load-failed screen shows (Retry / Clear); cleared on success/stop. chrome's
  `runtime_unavailable` stays a soft in-panel state by design. (Native daemon-start
  failures are home-frontend; the `status.last_load_error` wire field is still
  bridge-unfilled — see next item.)
- [x] (effort: M) **Native `last_load_error` enrichment — WON'T BUILD (2026-06-15).**
  Architecturally moot: a native restore failure aborts daemon startup
  (`store.load()?` in bifrost-app bootstrap → daemon never starts), so there is no
  running runtime to query — `runtime_status().last_load_error` is unreachable.
  Home correctly drives load-failed from its own start-error state. The wire field
  is kept as a documented reserved slot (a future host that surfaces a load error
  from a *running* runtime could fill it). Comment on the field corrected.
- [x] (effort: M) **Live relay-health re-probe (browser bridge) — DONE (2026-06-15).**
  `refreshRelayHealth()` re-probes on a ~30s interval (started in connect, cleared in
  shutdown), recomputing `connected_relays` so all-relays-offline fires on post-boot
  relay drops/recoveries; pumps a runtime-status event only on change.
- [x] (effort: M) **`@live` e2e for the dashboard banners — DONE (2026-06-15).**
  `test/igloo-pwa/specs/dashboard-states.spec.ts` drives **signing-blocked** (deny the
  peer's request.sign → sign_ready drops) then **all-relays-offline** (close the relay →
  re-probe empties connected_relays; the banner flips, exploiting their precedence).
- [x] (effort: M) **`@live` e2e for the signing-failed banner — WON'T BUILD
  (2026-06-15).** Only the sign *initiator* holds a pending `Sign` op that can fail
  (responders answer immediately, no pending op), so the responder-only PWA dashboard
  can never populate its own `last_sign_failure` without becoming an initiator or a
  test mock. The banner's derivation + render are already covered by the igloo-ui unit
  test (`DashboardStates.test.tsx`). Revisit only if/when a client gains a
  self-initiated sign surface.
- [ ] (effort: S, unsure) Make the Settings dirty-check structural rather than
  `JSON.stringify` of relays/signerSettings, if those shapes grow.
- [ ] (effort: S) Decide the fate of the redundant `RelayInput`
  (`igloo-ui/src/components/ui/relay-input.tsx`) vs the newer `RelayList`.
- [ ] (effort: S) **Onboard-save relay field — vestigial `onRelaysChange` cleanup.**
  The "lock vs honor" decision landed on **lock**: `renderOnboardSave` passes
  `lockIdentity={true}`, so the relay list renders read-only and
  `finalizeOnboardedDevice` (correctly) ignores relay edits — the profile's relays
  come from the onboarding package. Remaining cleanup: a now-pointless
  `onRelaysChange` callback is still wired at `igloo-pwa` `App.tsx:1193`; drop it
  (surfaced 2026-06-13; rescoped 2026-06-15).

- [ ] (effort: S) Rich device labeling/renaming in the instance registry UI
  (initial impl shows the id prefix + null label).

## igloo-chrome

- [ ] (effort: M) Convert the remaining igloo-chrome e2e specs to the page-object
  model — `check-e2e-selector-contracts.sh` already covers chrome, and a few specs
  (e.g. `dashboard`, `rotation-update`) use `support/ui.ts`, but most still inline
  locators.

## igloo-home

- [ ] (effort: L, spike first) **Evaluate decoupling the signer into a sidecar Rust
  daemon (instead of in-process in `src-tauri`).** Today igloo-home embeds the native
  Tokio signer in-process via `bifrost-bridge-tokio` (`src-tauri/Cargo.toml:39-45`),
  reached from the frontend through ~36 Tauri `invoke`/`listen`/`dialog` call sites
  (`src/lib/api.ts`, `App.tsx`). Evaluate moving it to the **sidecar daemon model the
  codebase already supports** — `bifrost-app`'s daemon over a token-auth Unix socket,
  as `igloo-shell` uses (ADRs [005](./adrs/ADR-005-shell-daemon-over-bifrost-app.md) /
  [006](./adrs/ADR-006-bridge-transport-boundaries.md)) — with the desktop app as a
  thin client over `DaemonClient`. **Why:** it decouples the signer from the GUI
  framework, which is the high-leverage fix for the home test/orchestration friction —
  the signer becomes testable directly over its socket (no GUI, no `xvfb`, no custom
  `--features test-server` TCP harness), the GUI becomes a thin client testable in
  plain Playwright (the frontend already renders headless via the visual seam), and
  the three duplicated home harnesses (`fixtures/app.ts` TCP, `test/desktop/run.mjs`
  X11, `test/visual/run.mjs` system-chromium) can collapse. It keeps the native
  always-on / durable / background-relay signer (NOT a WASM downgrade) and is
  framework-agnostic. **Context (investigated 2026-06-18):** this came out of a
  Tauri→Electron question. Electron was rejected as the wrong lever — it can't host
  the native Rust signer in-process (Node main), igloo-ui/igloo-shared reuse is already
  maximal (the frontend is plain web), moving to the WASM signer would lose the
  always-on/durable co-signer behavior, and Electron's larger Chromium+Node attack
  surface is a downside for a key-share custodian. The sidecar daemon delivers the
  testing win without the framework switch. **Spike scope:** what a (C) refactor
  concretely touches (daemon spawn/lifecycle from the app, socket/token plumbing,
  passphrase-over-stdin, process cleanup, packaging the daemon binary), and whether to
  reuse the `igloo-shell` daemon or a lean dedicated one. Intersects the home
  test-harness consolidation (P0 #3b + the unified visual-harness item) —
  `igloo-home` + `bifrost-app` + test/.
- [ ] (effort: S) **Recover-key meter could show member count** — `get_profile_threshold`
  returns just the threshold; optionally widen it to `{ threshold, member_count }` so the
  `RecoverCollectSharesPanel` meter reads "X of threshold (group of N)" (`src-tauri`
  `app/commands.rs` + `src/App.tsx`; surfaced 2026-06-13).
- [ ] (effort: S) **Optional: a "save recovered nsec to file" affordance in home**
  for full parity with the shell's `0o600` file write. The in-transit exposure is
  now documented (the key already crosses into the webview when displayed), so this
  is a convenience, not a hardening — a scoped `0o600` write via the existing
  `tauri-plugin-dialog` + `path_scope` export infra (`src/App.tsx` +
  `src-tauri`; surfaced 2026-06-13).

## Dependencies & packaging

- [ ] (effort: S) **High-severity `esbuild` advisory** surfaced in
  `igloo-chrome` (and igloo-pwa) `npm audit` — "Missing binary integrity
  verification in Deno module enables RCE via `NPM_CONFIG_REGISTRY`". Dev-only
  tooling (esbuild bundler / vitest); not a runtime exposure. Bump esbuild past
  the patched version across the affected repos once a non-breaking release is
  available — surfaced 2026-06-13 during the nostr-tools dedupe pass.

## Test harness / CI

- [ ] (effort: S) **Showcase spec tag/gate mismatch** —
  `test/igloo-ui-showcase/specs/reference-screens.spec.ts` is tagged `@fast` but only
  runs in its own `test:igloo-ui-showcase` lane, not the `make verify` `@fast` gate, so
  its breakage during the ADR-014 P0 cut went uncaught by `verify` (found only by a
  manual sweep). Either fold the showcase into the gate or correct the misleading tag
  — relates to ADR-013 tag taxonomy · test/ · added 2026-06-19.
- [ ] (effort: S) **Harden the `make dev` daemon socket path (unsure if it ever
  overflows).** `scripts/dev.sh` puts the igloo-shell control socket under an
  ad-hoc `mktemp -d "${TMPDIR}/frostr-dev.XXXXXX"` rather than the codebase's
  secure path-shortener ([[daemon-socket-sunlen]]). On a deep macOS `TMPDIR`
  (`/var/folders/...`) the resulting `.../igloo-shell-<hash>.sock` lands ~96/104 of
  the unix-socket `sun_path` limit — it fits today but the margin is thin and it
  bypasses the established helper.
- [ ] (effort: M) **`make dev`: verify in-browser + zero-import auto-seed.** The
  native loop is verified up to vite serving (HTTP 200); the in-browser
  import-of-`dev-device.bfprofile` + signing against the native relay is unverified
  (manual for now). Fold into Thread 5b: build the `PwaProfile` from
  `dev/fixtures/dev-device.bfshare` and seed `igloo-pwa.profiles.v1` directly so the
  device is provisioned with zero manual import, and verify the running dashboard
  headlessly via `make screenshot`.
- [ ] (effort: S) **Decide nightly `test:guards:full` fate (premise corrected
  2026-06-17).** Re-checked after the lean-CI cut: the doc/command-surface guards
  actually **pass** — `check-doc-command-surfaces.sh`, `check-doc-surfaces.sh`, and
  `check-markdown-links.mjs` are all green (even with the new `make install` /
  `make bump-pointers` targets). The *only* thing making nightly `test:guards:full`
  red is `check-e2e-selector-contracts.sh` flagging `agent-screenshot.spec.ts`
  (already tracked in the igloo-pwa section). So this is no longer a docs-drift fix:
  either exempt `@agent` tool specs from the selector contract (greens the nightly)
  or formally demote `test:guards:full` to advisory. (The broader "delete the
  de-gated guards" item below still stands.)
- [ ] (effort: M) **Finish throwing out the de-gated visual + low-value guards.**
  2026-06-17 removed them from the PR gate but kept the files. Once the screenshot
  capability is recast as `make screenshot` (Thread 5b), delete
  `test/igloo-pwa/visual-manifest.json`, `check-pwa-visual-manifest*.{mjs,sh}`,
  `report-pwa-visual-comparison.mjs`, and the low-value guard scripts (markdown-
  links, doc-command-surfaces, workflow-node24, client-scoped-submodules,
  shared-setup, cross-client-imports, e2e-selector-contracts) + their `package.json`
  entries.
- [ ] (effort: S) **Make `make verify` affected-aware.** It currently runs the full
  pwa+chrome `@fast` lanes; route through `scripts/test-affected.sh` so it scales to
  the touched client.
- [ ] (effort: S) **Verify `make bump-pointers PUSH=1` against a real remote.** Added
  2026-06-17. The stage / commit / dry-run / dirty-guard paths are tested, but the
  `--push-submodules` path (detached-HEAD guard + `git push origin <branch>` per
  submodule) has never run against a remote. Exercise it once before relying on it
  for a release — frostr-infra.
- [ ] (effort: S) **Enrich `make verify` machine output with per-test results.**
  Added 2026-06-17. `.tmp/agent/verify.json` is only `{ok, exitCode}`, so an agent
  can't see *which* test failed without scraping logs. Have `scripts/verify.sh` emit
  a Playwright `--reporter=json` (and vitest / `cargo --message-format=json`)
  artifact under `.tmp/agent/` so failures are parseable — test/ + scripts/.
- [x] (effort: M) **DONE (2026-06-17) — render-and-verify extended to chrome.**
  `make screenshot CLIENT=chrome STATE=…` renders the extension options page
  headlessly to `.tmp/agent/chrome-<state>.{png,txt}` + `screenshot.json`. Mirrored
  the pwa/home seam: `repos/igloo-chrome/src/lib/dev-scenario.ts` `resolveDevScenario`
  reads `?__frostr_dev=<scenario>` and returns an in-memory `ExtensionStateSnapshot`
  (dashboard-running / dashboard-stopped / onboarding); `store.tsx` short-circuits the
  background fetch + guards `loadRuntimeDiagnostics` in scenario mode. New chrome
  `@agent` capture spec (`test/igloo-chrome/specs/agent-screenshot.spec.ts`, excluded
  from the chrome `@fast` lane). It paid off immediately — capturing the dashboard DOM
  fixed the chrome `@fast` red gate and surfaced the `view.running` bug (above).
  **Home still pending** (igloo-home has the `currentVisualScenario` seam but no
  `make screenshot CLIENT=home`) — test/ + igloo-chrome.
- [ ] (effort: S) **chrome signer keys use the legacy KeyField, not the split-copy
  KeyRow.** Found 2026-06-17 while fixing the red gate: `repos/igloo-chrome/src/pages/
  Signer.tsx` sets `publicKeyLabel`/`shareLabel` (legacy KeyField fallback) but not
  `groupKey`/`shareKey`, so the chrome dashboard lacks the npub/hex split-copy control
  igloo-pwa has (`App.tsx` `toDashboardKey(...)`). Add structured `groupKey`/`shareKey`
  to chrome's view model for parity — igloo-chrome. (Keep the "Group Public Key" /
  "Share Public Key" label text — both KeyRow and KeyField render it, so the smoke
  specs stay green.)
- [x] (effort: S) **DONE (2026-06-17) — `make screenshot CLIENT=home`.** Renders the
  home desktop frontend headlessly to `.tmp/agent/home-<state>.{png,txt}` via a
  Playwright `@agent` spec (`test/igloo-home/screenshot/agent-screenshot.spec.ts`) +
  an isolated `playwright-screenshot.config.ts` (separate testDir so it never sweeps
  the tauri-driver live suite; `npm run dev` webServer). Guarded `installTestBridge`
  under a visual scenario in `igloo-home` `App.tsx` so the Tauri `invoke()` at mount
  doesn't throw in a plain browser. Uses the existing `?__igloo_visual=` seam; the
  shared default `dashboard-running` maps to home's `dashboard-signer`. Cross-platform
  (bundled chromium) unlike the Linux-only `test/visual/run.mjs` — test/ + igloo-home.
- [ ] (effort: S) **Home `dashboard-signer` visual scenario renders a *loading*
  dashboard.** Found 2026-06-17 via `make screenshot CLIENT=home`: the panel shows
  "Starting signer… / Restoring your session…" rather than a running dashboard, so the
  injected `sampleRuntimeSnapshot` (repos/igloo-home/src/test/visualMode.ts) needs the
  same fidelity tuning the chrome scenario got — a status/readiness shape that
  `deriveDashboardState` reads as ready, not loading — igloo-home.
- [ ] (effort: S) **Playwright leaks `bifrost-devtools relay` processes.** Found
  2026-06-17: ~16 orphaned `bifrost-devtools relay --host 127.0.0.1 --port <ephemeral>`
  processes (PPID 1, dated back to May 31 / Jun 8) accumulating across e2e/`@live`
  runs — a relay spawned by a spec/webServer isn't torn down when its parent dies.
  Harmless but unbounded (port/FD pressure over time); killed this batch with
  `pkill -f "bifrost-devtools relay"`. Find the spawn site (likely a `@live`/demo
  fixture or webServer) and ensure relay teardown on suite end / process exit.
- [ ] (effort: M) **WASM watch + drop committed-WASM double-maintenance.** Browser
  WASM is committed to git AND regenerated on every prepare. Add `make wasm-watch`
  (cargo-watch/watchexec) and build-on-demand for dev; the cheap stamp guard can
  stay in the lean gate or move to nightly. (Deferred from the 2026-06-17 hot-reload
  pass, which did igloo-ui CSS watch only.)

- [x] (effort: S) **DONE (2026-06-16).** Export-package `@live` flake under load.
  `exportProfileWithPassword` (`test/igloo-pwa/support/pages.ts`) now re-fills both
  password fields and polls the confirm value via `expect.poll` at
  `LIVE_EXPECT_TIMEOUT_MS` (20s) before waiting for the Export button to enable —
  robust against the controlled-input onChange lagging past the default 10s under
  back-to-back-run CPU contention. Test-harness-only.
- [x] (effort: S) **DONE (2026-06-15).** The cross-repo `demo-pair-check` guard
  missed igloo-shell test drift: it ran `cargo check --bin` (bin-only), so it never
  compiled igloo-shell-core/cli **test fixtures**. bifrost-rs struct-field additions
  silently rotted the shell's struct-literal fixtures twice (2026-06-13 `PeerStatus`,
  2026-06-15 the four `RuntimeStatusSummary` host/bridge fields). Strengthened the
  `Makefile` `demo-pair-check` target to `cargo check --locked --all-targets` for the
  whole igloo-shell workspace (and bifrost-devtools), so test/bench targets compile at
  pointer-bump time. Verified it catches a dropped fixture field and passes clean.
- [x] (effort: M) **DONE (2026-06-16).** igloo-shell full approval round-trip
  integration test — `crates/igloo-shell-cli/tests/approval_roundtrip.rs`. Two daemons
  over a relay (alice invites bob via bfonboard so the handshake seeds mutual
  sign-readiness); bob gates alice with `respond.sign = ask`; the deny path makes
  alice's blocking `runtime sign` fail, the approve path completes with a verified
  Schnorr signature. Concurrent blocking-sign + resolve driven via
  `std::thread::scope`; `request_id` read from `pending_approvals` (no new CLI — the
  optional `runtime approvals` list was skipped to keep the cut tight). Surfaced
  2026-06-14.
- [x] (effort: S) **DONE (2026-06-16).** Pre-existing selectors-guard violation in
  `dashboard-states.spec.ts` (it called `page.getByTestId(...)` directly at three
  banner-assertion sites). Added `DashboardPage.conditionBanner` /
  `expectConditionBanner` / `expectNoConditionBanner` (over the dynamic
  `dashboard-banner-<kind>` id) and routed the spec through them. Full
  `npm --prefix test run test:guards` is green again; the `@live` spec still passes.
  hardcodes `/usr/bin`/`/snap` chromium paths and the desktop lane needs `xvfb-run` +
  ImageMagick `identify` + X11 `xwininfo`, so neither runs on macOS (homebrew chromium at
  `/opt/homebrew/bin`, no ImageMagick). Probe the homebrew path and degrade gracefully when
  `identify` is absent so local macOS dev can at least capture screenshots (surfaced
  2026-06-13; the `recover-key` visual scenario is registered and CI/Linux will screenshot it).
- [ ] (effort: S) **Desktop smoke for recover-key** — once the desktop lane runs (CI/Linux),
  add a `repos/igloo-home/test/desktop` step that dispatches `recover_group_key` and
  screenshots the recover-key view; today it's covered by Rust unit + a vitest
  behavioral test only (`igloo-home`; surfaced 2026-06-13).
- [ ] (effort: M) **Behavioral test for the resilient-restore fallback.** Phase-1.2
  added a re-bootstrap-from-packages fallback when a persisted snapshot fails WASM
  restore; only the package-carrying half (`createBrowserRuntimeNodeInit`) is
  unit-tested. A true behavioral test needs a real WASM runtime + relay, which the
  igloo-shared unit harness deliberately avoids — so this belongs in the
  integration/demo lane (feed a structurally-valid but incompatible snapshot, assert
  it emits `restore_fallback_to_profile` and comes up sign-ready), not a unit test
  (re-scoped M, 2026-06-13) — Test harness.
- [ ] (effort: S) Verify the chrome `@demo` lane (`make test-demo`) end-to-end on
  colima — only `make test-smoke` was completed previously.
- [ ] (effort: S) Silence the jsdom `--localstorage-file` Node warning in igloo-pwa
  unit runs.
- [ ] (effort: S) Investigate the PWA visual web-server `NO_COLOR`/`FORCE_COLOR`
  warning (`test/igloo-pwa/playwright.config.ts`) — config deletes both keys yet it
  still prints.
- [ ] (effort: S) Add a small regression test for
  `repos/igloo-paper/scripts/update_usage_coverage.py`.
- [ ] (effort: S) **Harden `.tsx`-only vitest include globs (igloo-ui).** igloo-pwa
  was fixed 2026-06-13 (`vitest.config.ts` now `*.test.{ts,tsx}`). **igloo-ui** still
  has the `test/**/*.test.tsx`-only glob (`repos/igloo-ui/vitest.config.ts`) — no
  `.ts` test today, but a future one would be silently dropped. Broaden it to
  `{ts,tsx}` and consider a workspace guard (e.g. extend `check-shared-test-setup.sh`)
  that flags a committed `*.test.ts` no project glob matches (surfaced 2026-06-13;
  pwa half resolved, rescoped to igloo-ui 2026-06-15).
- [ ] (effort: M) **`pwa-home-pairing` is effectively dead** — it's `@cross-client`
  (runs in NO CI lane), DISPLAY-gated, and until 2026-06-11 read the runtime
  snapshot from localStorage where it is never persisted. It now uses the corrected
  DOM-based `expectPwaSignerSignReady`, but is still unverified + ungated, and it's
  the only PWA↔native nonce-hydration coverage. Run it (xvfb), confirm it passes,
  then gate `@cross-client` in `release-validation` — or retire it — Test harness/CI.
- [ ] (effort: M) Promote the manual multi-PWA-tab signature to an automated spec
  (two browser contexts + igloo-shell initiator) once the manual flow is stable —
  Test harness · see the `pwa-multisig-demo` scaffolding.
- [ ] (effort: S) **Optional race-safety: enrich the sign-miss response.** Today a stale-nonce
  sign converges once the resetting peer's next ping conveys its new generation. For the
  narrow window where an initiator signs *before* receiving that ping, have the responder
  return its current generation + fresh nonces on a `NonceUnavailable` miss so the initiator
  prunes-and-retries immediately instead of waiting for the ping — bifrost-rs.

## Code-health audit (2026-06-13)

Curated from the 2026-06-13 workspace code-health audit (full 81 findings —
18H/38M/25L — in the `audit/` run dated 2026-06-13; entry point
`audit/.../workspace-audit-synthesis-2026-06-13.md`). All High findings were
adversarially re-verified before landing here: severity-inflated items were
reframed and one false-rationale item (the NIP-44 "wrong KDF" claim) was
corrected. The remaining Medium/Low findings stay in the per-target reports.

### Correctness / CI (highest confidence)

- [x] (effort: S) **`release-validation.yml` never fires on merge — DONE (2026-06-15).**
  The `push` trigger now includes `master` (the default branch), so the release
  matrix runs post-merge, not only on PRs.
- [x] (effort: S) **bifrost-rs CI rewritten to the current layout — DONE (2026-06-15).**
  The whole `checks` matrix tested a vanished node-era architecture (bifrost-node /
  bifrost-transport-ws / bifrost-dev, devnet/test-node-e2e/tui scripts,
  node_ws_multi_peer_example) — bigger than wrong crate names. Replaced the dead
  `test-*` shards with one `cargo test --workspace` (covers every real crate incl.
  the NIP-44 KATs; rot-proof), dropped the gone runtime-e2e/check-example steps +
  the bifrost-dev regressions job, kept fmt/clippy/check/coverage/security-audit.
  **NB:** the (unchanged) clippy `-D warnings` job now surfaces pre-existing
  bifrost-profile lints — see the new item below.
- [x] (effort: S) **DONE (2026-06-15).** bifrost-profile `clippy::too_many_arguments`
  cleared with `#[allow(...)]` + rationale on the three builder/import functions
  (and a `bifrost-app` `items_after_test_module` lint that the same `-D warnings` job
  surfaced), so CI's clippy job is green. Rode the NIP-44 raw-X WASM rebuild —
  bifrost-rs `acab2b0`.

### Crypto / secret seam

- [x] (effort: M) **DONE (2026-06-15).** Hand-rolled-crypto port audit + ECDH KATs.
  Prompted by the threshold-ECDH Lagrange regression (a silent TS→Rust porting
  divergence), audited every EC/scalar operation in the core crates for the same risk.
  **Conclusion:** `bifrost-core/src/ecdh.rs` was the ONLY hand-rolled elliptic-curve
  math (now fixed + consolidated onto `frost::Identifier`); everything else delegates
  to vetted primitives — signing → `frost::round2::sign`/`aggregate`, nonces →
  `frost::round1::commit`, cosigner-message ECDH → `k256::ecdh::diffie_hellman`, NIP-44
  cipher → ChaCha20/HMAC/HKDF (pinned by `nip44_kat.rs`/`nip44_protocol_kat.rs` against
  the official vectors), event signing → k256 Schnorr, package encryption →
  XChaCha20Poly1305/Argon2 (pinned by `package_kats.rs`). No refactor needed. Locked
  the ECDH surface with spec-anchored + frost-anchored KATs (bifrost-rs `50e729a`):
  a pinned fixed-input→raw-X vector cross-checked by independent k256, asserted across
  quorums; and a reconstruct-anchored check over (2,3)/(3,5)/(3,4). Tests only — no
  blob change (stamp re-written, blobs untouched). — bifrost-rs.
- [x] (effort: M) **DONE (2026-06-15).** Unified app-facing NIP-44 on the standard
  raw-X derivation (it was a real interop bug). bifrost-core `combine_ecdh_packages`
  now returns the raw X-coordinate of the combined threshold point instead of
  `SHA256(point)` (bifrost-rs `89ee694`); since the combined point equals the point a
  normal ECDH with the group key produces, the app-facing
  `window.nostr.nip44.{encrypt,decrypt}` conversation key now matches what any
  standard nostr client derives. `deriveConversationKeyFromSharedSecret` already does
  HKDF-Extract, so it needed no code change — only its warning comment was flipped to a
  match-confirmation. **Blast radius:** the threshold secret flows only outbound to the
  app-facing NIP-44 / native `EcdhResult`; cosigner protocol messages use the *share*
  secret via `event_shared_x` (already raw-X) and were unaffected, so no flag-day and
  the NIP-44 KATs were untouched. Hard cut (alpha — no flags/migration). Coverage: a
  Rust source test pinning threshold-combine == standard ECDH raw-X
  (`combine_returns_standard_raw_x_ecdh_secret`) and a TS interop regression test
  (`igloo-shared/src/nip44-interop.test.ts`) proving FROSTR↔nostr-tools round-trips
  both directions. WASM rebuilt + re-stamped + re-vendored (shared/pwa/chrome). A real
  `@live` provider-vs-nostr-tools behavioral check remains a (non-blocking) follow-up.
  — bifrost-rs + igloo-shared.
- [x] (effort: M) **DONE (2026-06-15).** `@live` NIP-44 interop behavioral test
  (gold-standard for the raw-X fix) — added to
  `test/igloo-chrome/specs/provider-live-nip44.spec.ts`: a live 2-of-3 group encrypts
  via `window.nostr.nip44.encrypt` and a standard `nostr-tools` client decrypts it
  (and vice versa), against an external non-member counterparty. **It caught two more
  real interop bugs that the unit/source tests could not, both now fixed:**
  (1) app-facing `nip44Encrypt` emitted *unpadded* base64 (strict standard decoders
  reject it) — fixed in igloo-shared `8fccc0b`; (2) the threshold ECDH was missing
  Lagrange interpolation, so for any t-of-n with t>1 the combined secret was
  `(Σ shares)·C` not `group_secret·C` — undecryptable by a standard peer. FROSTR V1
  (`@vbyte/frost`) applies `calc_lagrange_coeff`; the Rust port had dropped it (the
  `members` quorum was threaded in but unused). Restored in bifrost-rs `d8264a4`
  (+ cross-quorum test `38bbba3`); WASM rebuilt + re-stamped + re-vendored.
  **Net:** app-facing NIP-44 now interoperates with standard nostr clients for real
  threshold groups, not just threshold-1. NIP-44 is chrome-extension-only (the PWA has
  no app-facing nip44 surface), so the test is chrome-only. — test/igloo-chrome +
  bifrost-rs + igloo-shared.

### Secret hygiene ("decide once, propagate")

- [x] (effort: S) **DONE (2026-06-16).** Zeroize `GeneratedKeyset` (igloo-home).
  `GeneratedKeyset` + `GeneratedKeysetShare` now derive `Zeroize`/`ZeroizeOnDrop`
  with a redacted `Debug` (mirroring `RecoveredGroupKey`), scrubbing the group `nsec`
  and each share's `share_package_json`; the `generatedKeyset` React state + its
  secret-bearing form drafts are nulled on create-view exit (mirroring the
  recover-key cleanup). + a Debug-redaction unit test. — igloo-home `7498e15`.
- [x] (effort: M) **PARTIAL/DONE (2026-06-16) — top flows; broader sweep remains.**
  Applied `Secret<T>` in production for the two highest-value flows end-to-end:
  profile-package decrypt/encrypt password (`Passphrase`) and onboarding shareSecret
  (`ShareSecretHex`), wrapped at the call sites and `.expose()`d only at the WASM
  boundary (igloo-shared `e247473`; pwa `3a2f6b0`; chrome `561cb49`). Bounded
  deliberately to those flows.
  - [ ] (effort: M) **Remaining `Secret<T>` sweep.** Thread the wrappers through the
    rest of the bare-`string` secret sites — chrome extension message types
    (`ProfilesUnlock/Import/ExportPackage`, `Onboarding*`), pwa session controllers,
    and the other package/onboarding call chains — for full leak-greppability ·
    surfaced 2026-06-16.

### Trust boundaries

- [x] (effort: M) **Origin-pinned the `window.postMessage` page bridge — DONE
  (2026-06-15).** The content script + injected provider now post with
  `window.location.origin` (not `'*'`) and validate `event.origin ===
  window.location.origin` on both inbound handlers, closing the cross-origin
  sniff + forge vectors. Chose origin-pin over a MessageChannel handshake (the
  audit's documented minimum; smaller diff). Unit test asserts a foreign-origin
  response is dropped — igloo-chrome.
- [x] (effort: S) **Redacted the runtime-log suffix on thrown errors — DONE
  (2026-06-15).** The breadcrumb appended to the surfaced error is now an
  allow-list of structured fields (`domain.event` + `request_id`) built from the
  observability events — never the verbatim `error_message` — igloo-pwa.

### UI correctness

- [x] (effort: S) **`activeView` dead branches removed — DONE (2026-06-15).**
  Dropped `'create-choice'` and `'settings'` from the `PwaView` union (neither had
  a render branch); the mid-create reload fallback that set `'create-choice'` (the
  blank pane) now bounces to `'landing'`, and the unused `startCreateChoice` action
  is gone — igloo-pwa.

### Demo / test hardening (low prod risk, factual)

- [x] (effort: S) **Demo passphrase off argv — DONE (2026-06-15).** `import` and
  `daemon start` now read the passphrase from a `0600` `mktemp /tmp` file via
  `--passphrase-file` (removed from `/proc/<pid>/cmdline`), cleaned up on exit.
  **Deliberately NOT done:** the `chmod 0777`/`a+rwX` on the artifact dir + socket
  are load-bearing for the demo's Docker cross-UID/mount access, and tightening
  them risks breaking the (ephemeral, hardcoded-passphrase) harness for ~nil real
  gain — frostr-infra.

### Code health (large / cross-cutting)

- [ ] (effort: L) **Break up the per-host god files.** Each control plane is a
  named coordination bottleneck: bifrost-signer `lib.rs` (4948 LOC), igloo-home
  `App.tsx` (2006), igloo-pwa `store.tsx` (2073) + `App.tsx` (1741), igloo-shared
  `BrowserBridgeNode` (1572), igloo-ui `CreateFlow.tsx` (1723). Split along
  responsibility seams, one target at a time — all targets · audit 2026-06-13.
- [ ] (effort: M) **Adopt a workspace TS formatter + lint gate.** No TypeScript
  target configures Prettier/ESLint; formatting is per-author. Add Prettier +
  ESLint (`react-hooks`) with a CI gate — this also retires the stale
  `eslint-disable` in `CreateFlow.tsx` that suppresses a rule with no ESLint
  present. Rust analog: a `rustfmt.toml` + `cargo fmt --check` gate for
  igloo-shell — workspace · audit 2026-06-13 (AES-06).

### Deprecation

- [x] (effort: S) **Removed the dead NIP-04 provider surface — DONE (2026-06-15).**
  Deleted the `nip04.{encrypt,decrypt}` provider methods, routing, permission
  labels, and the throwing execution branch (they prompted then hard-threw "not
  planned for v2") — igloo-chrome.

## Open questions

- [ ] (effort: S) Event Log Filter chips key off `badgeLabel` = domain for structured
  events but = level for the string fallback — decide whether the fallback should be
  filterable or the chips hidden when unstructured.
