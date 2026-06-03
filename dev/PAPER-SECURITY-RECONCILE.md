# Paper ↔ security-hardening reconciliation — resume notes (2026-06-03)

R1+R2+R3 are complete and pushed to `origin/security-hardening` (all repos).
While we worked, a parallel **Paper UI** track advanced on `origin/master` +
`origin/paper-create-flow-update`. This note tracks reconciling the two before
the L2 cutover. **`master` and the Paper branch remain untouched** (no cutover
yet). The per-repo `reconcile/paper+security` branches ARE now pushed to their
`origin` as **backup only** (2026-06-03) — a safety net for the local merge work,
not a cutover. Resume from `origin/reconcile/paper+security` if local state is lost.

## Topology (forked ~2026-04-13 from a common base)

- `origin/master` = old base + **Paper foundation** (parent +33).
- `origin/paper-create-flow-update` = master **+41** (more Paper: Settings/
  Permissions/dashboard alignment, password modals, chrome MV3 wasm fix, docker
  follow-ups). `ahead=41, behind=0` of master — a clean superset.
- `origin/security-hardening` = old base + our R1/R2/R3 (a66c2a1 parent).
- Both tracks restructure the **UI** (Paper design system vs our Bucket H) AND
  the **backend** (Paper landed "onboard-served completion + signer/runtime WIP"
  in bifrost-rs/shell/shared, overlapping our crypto/secret hardening).

## Decisions (locked with the operator)

- **Strategy A:** per repo, branch at the **Paper tip**, `git merge
  security-hardening`, resolve, then ff `master` to the result. Submodules first
  (so the parent's pointer conflicts resolve against reconciled submodules), then
  the parent. Local only until reviewed; re-validate (`make test-release`) before
  cutover/push.
- **UI conflicts (igloo-ui, igloo-pwa): Paper wins, re-layer security.** Paper's
  design system / `styles.css` / primitives are canonical; re-apply only the
  security *behavior* on top where Paper doesn't cover it: `SensitiveField`
  mask-by-default, `Dialog` focus-trap/scroll-lock/Escape-stack, `LogEntry`
  bounds.
- **Backend conflicts: both-keep.** Preserve our hardening AND Paper's feature,
  reconciled per hunk.

## Per-submodule Paper tips (merge target = `git ls-tree origin/paper-create-flow-update repos/<x>`)

| repo | paper tip | sec tip | paper Δ vs sec | notes |
|---|---|---|---|---|
| bifrost-rs | 7a41c3b | d0bf343 | +1 / -48 | **DONE** |
| igloo-shell | a6eece3 | 7bf3ff4 | +2 / -6 | **DONE** |
| igloo-shared | e617db1 | 303514d | +4 | **DONE** |
| igloo-chrome | ee45a64 | 5410f1d | +7 | **DONE** (typecheck only; full unit+e2e after igloo-ui) |
| igloo-pwa | 007754e | 1044edc | +30 | HARD: Paper flows vs App/store/types; Paper-wins |
| igloo-ui | 66f144a | 24e3b81 | +33 | HARDEST: Paper design hard-cut; Paper-wins re-layer |
| igloo-home | eed7b7a | d99c987 | 0 | already current |
| igloo-paper | 38d734f | (none) | — | reference submodule; take Paper tip |

## Progress

- **bifrost-rs** — reconciled on local branch `reconcile/paper+security`
  (`dab2b94`). 3 git conflicts (both-keep): bridge-wasm imports (security
  superset), signer onboard handler (kept BOTH `OnboardServed` completion AND
  `note_onboarding_status`), verify/keyset tests. Plus semantic ripples: Paper's
  WIP used pre-hardening raw bytes where our newtypes now exist —
  `recovered.signing_key32.expose_bytes()`, and `CreateKeysetConfig::new()` +
  the new `signing_key32` field (converted our struct-literal test sites).
  **`cargo test --workspace` all pass** (R3 FROST/nonce/codec/router + Paper's
  onboard-served + bridge round-trips).
- **igloo-shell** — reconciled on local branch `reconcile/paper+security`
  (`479bfbd`). **0 git conflicts**; clean `cargo check --workspace`; lib tests
  pass. (Full managed_integration deferred to final validation.)
- **igloo-shared** — reconciled on local branch `reconcile/paper+security`
  (`b966139`). 7 conflicts. The big one: Paper's WIP modified the pre-PR29/PR30
  layout (`browser-runtime-core.ts`, flat `browser-profile-*`) while security
  restructured into `browser-profile/<sub>/` + extracted `runtime-api.ts`/
  `runtime-pump.ts`/`runtime-internal.ts`/`onboarding-transport.ts`. Resolutions:
  (1) **index.ts barrel** — kept security's explicit named barrel; dropped the
  recovery path Paper deliberately removed (`recover{,AndSave}BrowserProfilePackage`,
  `saveRecoveredBrowserProfileAndMaybeActivate`, `BrowserRecoveredProfilePackage`);
  re-layered Paper's NEW public surface onto it (`relay-ping`'s `pingRelay`/
  `RelayPingResult`; rotation's `recoverSecretKeyFromShares`/`BrowserRecoveredKey`).
  (2) **recovery.ts** — accepted Paper's deletion (security only *moved* it in
  PR33, no hardening to keep); fixed `recovery.test.ts` + `save/imports.ts` to drop
  removed symbols on security's new paths. (3) **wasm-bridge-node.ts** — kept
  security's PR30 class/extraction; re-layered Paper's **OnboardServed→
  onboard-complete** seam by adding `parseOnboardServedCompletion` to
  `runtime-pump.ts` (the dispatch loop git-merged it in but the parser lived only
  in Paper's deleted inline block). (4) **wasm binaries** — took Paper's refreshed
  artifacts (match merged loader .js/.d.ts); authoritative regen deferred to the
  igloo-chrome / `browser-wasm-sync` step. **`test:typecheck` clean; vitest
  141/141; `browser-wasm-exports` guard ok.** NOTE: amended once — a late edit
  (drop `saveRecoveredBrowserProfileAndMaybeActivate`) post-dated the `git add`,
  so re-stage before commit when a typecheck fix lands after staging.
- **igloo-chrome** — reconciled on local branch `reconcile/paper+security`
  (`e43a115`). **Text merge fully automatic** (Paper's igloo-ui API migration,
  MV3 static-glue WASM loader, recover-from-share removal, audit fixes did not
  line-collide with security's runtime-type dedup / test renames). Only the 2
  vendored wasm binaries conflicted → took Paper's (HEAD/ours), matching the
  merged loader .mjs + the igloo-shared decision. **Validation:** chrome resolves
  `igloo-shared` → `../igloo-shared/src/index.ts` (tsconfig path) and `igloo-ui`
  → sibling `dist/index.d.ts` (node_modules symlink). To get a faithful signal I
  temporarily set igloo-shared→reconcile (b966139) and igloo-ui→Paper tip
  (66f144a, `npm run build` to emit dist), then `bunx tsc --noEmit` → **clean**;
  restored both siblings after. Unit tests (`vitest run`) cannot load their
  config standalone (config imports igloo-shared's raw `.ts` testing subpath by
  package name → ERR_UNKNOWN_FILE_EXTENSION); this **reproduces identically on
  the pristine Paper tip**, so it's a pre-existing harness-invocation matter, not
  a reconcile regression. Full unit + e2e deferred to the workspace harness after
  igloo-ui is reconciled. CAUTION LEARNED: do **not** `git checkout` other commits
  while a merge is mid-resolve — it silently drops `MERGE_HEAD` and the next
  commit loses the second parent. I hit this, `git reset --hard <paper-tip>` +
  re-merged cleanly; final commit has parents `[ee45a64 5410f1d]`. Side effect:
  igloo-ui's gitignored `dist/` is currently a Paper-tip build over
  security-hardening source — harmless (rebuilt at igloo-ui reconcile).

## igloo-ui pre-scout (read-only, 2026-06-03 — for the fresh session)

Paper tip `66f144a`, sec tip `24e3b81`, merge-base `32b6188d`. **Paper = +33
commits** (hard-cut design system: token bridge, `design-tokens.{ts,css}`,
`view-models.ts`, semantic UI primitives, full create/onboard/welcome flow
redesign, `styles.css` +2163). **Security = only +5 commits**, and they map
almost 1:1 to the three behaviors to re-layer:
- `c5387fd` PR34 — neutral entry tokens, vendored font, named exports, NonceBar capacity
- `0626ed1` PR35 — **SensitiveField/SensitiveTextarea** + mask in-library secret renders
- `ad61597` PR36 — **Dialog/a11y primitives (replace Modal)** + **LogEntry hardening**
- `24e3b81` PR38 — vitest-axe + primitive unit/keyboard tests
- `87f2ac5` — live onboarding status in distribution cards

**Re-layer targets (where the security behavior lives in `24e3b81`):**
- `SensitiveField` → `src/components/ui/sensitive-field.tsx`, `sensitive-textarea.tsx`
  — **ABSENT at Paper tip ⇒ clean re-add.** No git conflict; the work is *wiring*
  them into Paper's redesigned components wherever a secret renders (create/import/
  export flows), plus the `src/index.ts` export.
- `Dialog` focus-trap/scroll-lock/Escape → `src/components/ui/dialog.tsx`,
  `src/lib/use-focus-trap.ts` — **ABSENT at Paper tip ⇒ clean re-add.** BUT Paper
  kept & redesigned `modal.tsx` and built `ExportPackageModal` on it. Security
  *replaced* Modal with Dialog. Decision needed: graft Dialog's a11y behavior onto
  Paper's `modal.tsx`, or migrate Paper's modal usages to security's `dialog.tsx`.
  This + `styles.css` is the crux of the hard part.
- `LogEntry` bounds → `src/components/ui/log-entry.tsx`, `event-log.tsx` —
  **PRESENT at Paper tip ⇒ real conflict.** Paper redesigned event-log (domain
  filter, indexed row ids, readiness counts in `3782c2c`/`424b707`); re-layer
  security's entry-bounds onto Paper's event-log.

**Git-level conflict surface (12 files, from `git merge-tree 66f144a 24e3b81`):**
`package.json`, `package-lock.json`, `scripts/build.mjs`, `src/index.ts`
(barrel — both add exports, merge both), `src/styles.css` (**Paper-wins**, huge),
`src/components/ui/modal.tsx` (the Dialog-vs-Modal crux), `src/test/setup.ts`,
and four flow files Paper redesigned + security touched:
`components/flows/{CreateFlow,CreateImportPanel,HostShell,OperatorSignerPanel}.tsx`
+ `test/CreateFlow.test.tsx`. The Sensitive*/dialog/use-focus-trap files are NOT
in this list (clean adds). Suggested order: merge → take Paper for `styles.css`/
tokens/flow layout → re-add the 4 clean security primitives → wire SensitiveField
into secret renders → reconcile Dialog-vs-Modal a11y → re-layer LogEntry bounds
onto Paper's event-log → reconcile `index.ts` barrel (both export sets) → build
igloo-ui dist → `tsc`/vitest.

## The pattern that works

1. `git checkout -b reconcile/paper+security <paper-tip>` in the submodule.
2. `git merge --no-edit security-hardening`.
3. Resolve git conflicts (UI: Paper-wins; backend: both-keep).
4. `cargo check`/`tsc --noEmit` — fix the **semantic** ripples git didn't flag
   (Paper code using raw bytes vs our secret newtypes → `expose_bytes()`; old
   `CreateKeysetConfig` struct literals → `::new`).
5. Build + test; `cargo fmt`/lint; commit the merge.

## Remaining order

~~igloo-shared~~ → ~~igloo-chrome~~ (both done) → **igloo-ui**
(Paper-wins re-layer — the real work) → **igloo-pwa** → parent (reconcile
submodule pointers to the reconciled tips + `test/igloo-pwa/specs/app-shell.spec.ts`
our v2-seed fix vs Paper's PWA test wiring + CI/scripts/`AGENTS.md`). Then ff each
`master` to its reconciled tip, re-run `make test-release` on infra, then push.

## State to restore on resume

**Done (4):** each holds its work on local branch `reconcile/paper+security`,
also pushed to `origin/reconcile/paper+security` (backup):

| repo | reconcile tip | validation |
|---|---|---|
| bifrost-rs  | `dab2b94` | `cargo test --workspace` pass |
| igloo-shell | `479bfbd` | `cargo check` clean, lib tests pass |
| igloo-shared| `b966139` | typecheck clean, vitest 141/141, wasm-exports ok |
| igloo-chrome| `e43a115` | typecheck clean (vs reconciled deps); unit+e2e deferred |

**All submodules are parked on `security-hardening`** so the parent tree is clean
(parent stays on `security-hardening`, no pointer changes committed). The reconcile
work is only on the `reconcile/paper+security` branches. To resume a repo:
`git -C repos/<x> checkout reconcile/paper+security`.

**Next:** igloo-ui (see pre-scout above) → igloo-pwa → igloo-home (Δ0, just adopt
Paper tip `eed7b7a`) / igloo-paper (take Paper tip `38d734f`) → parent.

### Gotchas / env (consolidated)

- **Never `git checkout` another commit while a merge is mid-resolve** — it
  silently drops `MERGE_HEAD`, and the next commit becomes single-parent (loses
  the merge). Recovery: `git reset --hard <paper-tip>` then re-merge. (Hit on
  igloo-chrome; final commit verified 2-parent.)
- **Re-stage after a late fix** — if a typecheck/lint fix edits a file *after*
  you `git add`ed it, `git commit` uses the stale staged blob. Re-`git add` then
  commit (or `commit -a`). (Hit on igloo-shared `index.ts`; amended.)
- **Cross-repo TS deps resolve from the sibling checkout.** igloo-chrome (and
  igloo-pwa) typecheck against `../igloo-shared/src` and `../igloo-ui/dist`. For a
  faithful typecheck, temporarily point igloo-shared→`reconcile` and
  igloo-ui→Paper-tip (`npm run build` to emit `dist`), check, then restore. `dist/`
  is gitignored so it won't dirty git. igloo-ui's `dist/` is currently a Paper-tip
  build over security-hardening source — harmless, rebuilt at igloo-ui reconcile.
- **vitest config `.ts` loader**: chrome/pwa `vitest.config.ts` import
  igloo-shared's raw `.ts` testing subpath (`igloo-shared/testing/vitest-base`) by
  package name; running `vitest run` standalone fails with
  `ERR_UNKNOWN_FILE_EXTENSION`. This is pre-existing (reproduces on pristine Paper
  tips), not a reconcile bug. Run unit/e2e via the **workspace harness** (`make`),
  not bare `vitest`.
- **wasm binaries**: at every browser repo, took Paper's refreshed `*_bg.wasm`
  (HEAD/ours) to match the merged loader glue. Authoritative regen from reconciled
  bifrost-rs happens later via `make browser-wasm-sync` / `test-prep`.
- **env**: `rg` is a shell-function shim (real binary at
  `/usr/share/codium/.../@vscode/ripgrep/bin/rg`); `bun`/`bunx` at `~/.bun/bin`
  (needed for `tsc`/`vitest` — no local `node_modules/.bin/tsc`); background
  subagents are read-only here (do mutations in the main thread).
