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
  bounds. (igloo-ui specifics + the locked **Dialog-vs-Modal decision** are in the
  "igloo-ui pre-scout" section below.)
- **Backend conflicts: both-keep.** Preserve our hardening AND Paper's feature,
  reconciled per hunk.

## Per-submodule Paper tips (merge target = `git ls-tree origin/paper-create-flow-update repos/<x>`)

| repo | paper tip | sec tip | paper Δ vs sec | notes |
|---|---|---|---|---|
| bifrost-rs | 7a41c3b | d0bf343 | +1 / -48 | **DONE** |
| igloo-shell | a6eece3 | 7bf3ff4 | +2 / -6 | **DONE** |
| igloo-shared | e617db1 | 303514d | +4 | **DONE** |
| igloo-chrome | ee45a64 | 5410f1d | +7 | **DONE** (e43a115 → **6aa9936** after test-release Permissions-titles fix); fast e2e 17/17 |
| igloo-pwa | 007754e | 1044edc | +30 | **DONE** (a78a2ea) — tsc + vite build clean; vitest 32/33 (1 env-only) |
| igloo-ui | 66f144a | 24e3b81 | +33 | **DONE** (b68acdd) |
| igloo-home | eed7b7a | d99c987 | 0 | **DONE** (270024e → **12d9c2d** after test-release src-tauri signing_key32 fix); view-model migration vs reconciled igloo-ui; tsc + build clean, vitest 23/23 |
| igloo-paper | 38d734f | (none) | — | **DONE** (38d734f) reference submodule; took Paper tip |

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

- **igloo-ui** — reconciled on local branch `reconcile/paper+security`
  (`b68acdd`, parents `[66f144a 24e3b81]`). 11 git conflicts + ripples, all
  resolved. Highlights:
  (1) **Fonts (re-layer security):** styles.css Paper-wins layout, but dropped
  the Google Fonts CDN `@import` and vendored BOTH fonts locally — Share Tech
  Mono (already vendored) + **NEW Inter latin variable woff2** (`src/fonts/
  Inter-latin.woff2`, weight axis 400–700, `@font-face font-weight: 400 700`).
  Inter OFL license + README added; build.mjs already ships `src/fonts`→`dist/
  fonts`. Emitted `dist/styles.css` = 2 `@font-face`, **0 CDN refs**.
  (2) **vitest:** Paper-wins `vitest ^4`; bumped `vitest-axe`→`^1.0.0-pre.5`
  (same `./matchers`+`./extend-expect` subpaths; PR38 a11y suite runs under v4).
  setup.ts merged both (ensureLocalStorage + axe matchers + canvas stub).
  (3) **Dialog-vs-Modal (per LOCKED decision):** security's `Dialog`/`ConfirmDialog`
  kept as the single hardened engine, panel chrome restyled to igloo-* tokens;
  Paper's `Modal` is now a thin `Dialog`-backed shim (`modal.tsx`) preserving the
  `open/onClose/title/className` API; `confirm-modal.tsx` deleted (→ConfirmDialog);
  `QrPayloadModal` auto-merged onto Dialog + SensitiveTextarea.
  (4) **StepProgress:** enhanced the shared `StepIndicator` primitive to render
  Paper's connectors + completed-step checkmarks on a semantic `<ol>`+`aria-current`
  (Paper look + security a11y); used in HostShell. Both sides' new HostShell
  exports kept (Paper Welcome*/Public* + security StepIndicator).
  (5) **CreateFlow (Paper-wins NOW):** took Paper's onboarding rewrite verbatim
  (status-lifecycle model). **DEFERRED:** security's host-side live distribution
  tracking (`kind`+`tracking`, `distributionTrackingPresentation`/`formatTrackingUpdatedAt`,
  StatusBadge on cards) was DROPPED from igloo-ui; re-layer it at **igloo-pwa**
  where the runtime status signal flows (backend already keeps `note_onboarding_status`).
  (6) **index.ts barrel:** re-layered security's explicit named-export surface
  (PR34), re-derived from each module's actual exports; added Paper-new modules +
  security primitives; dropped confirm-modal and the **Operator\* permission/runtime
  types** (Paper moved them into `models/view-models` — pwa consumers must migrate
  to the view-model names).
  (7) build.mjs: fixed auto-merge duplicate `cp` import. AppHeader unit test
  updated to Paper's `mode`-based API (a11y intent preserved).
  **Validation:** `npm run build` clean; `tsc --noEmit` clean; `vitest run`
  **120/120 across 19 files**.

- **igloo-pwa** — **DONE** on local branch `reconcile/paper+security`
  (`a78a2ea`, parents `[007754e 1044edc]`, pushed to `origin/reconcile/paper+security`).
  All 5 markered files resolved (`App.tsx` 15, `store.tsx` 20, `types.ts` 4,
  `profile-packages.ts` 2, `App.test.tsx` 3) plus a second wave of cross-repo
  type adaptations. **`tsc --noEmit` clean; `vite build` clean (1751 modules).**
  Unit/e2e deferred to the workspace harness — bare `vitest` hits the pre-existing
  `igloo-shared/testing/vitest-base` `.ts` config-loader issue (no local `tsx`;
  bun runtime is vitest-worker-incompatible), exactly the igloo-chrome precedent.
  - **How it was resolved (against the locked decisions below):**
    - **types.ts:** PwaDraftState made fully secret-free (security secret-segregation
      is the documented invariant — `toPersistable` serializes `drafts` wholesale).
      Moved EVERY inline form secret to PwaDraftSecrets, incl. two that auto-merged
      silently: `createForm.privateKey` (nsec → `createFormPrivateKey`) and
      `recoverKeyForm.sources[].password` (→ `recoverKeySources`); also added
      `importSaveFormPassword/Confirm`, dropped `recoverProfileFormPassword`.
      Kept Paper's `distributionPermissions` + `importSaveForm` + `recoverKeyForm`;
      `onboardSaveForm`/`importSaveForm` keep non-secret `relayUrls` (Paper UI).
      `pendingLoadError` both-keep.
    - **store.tsx:** security runtime body is the base; UI methods reconciled to
      Paper vocabulary — `generatedKeyset`→`pendingKeyset`, `unlockPhrase`→
      `unlockPassphrase`, Paper view names (`create-select-share`/`create-save-profile`),
      dropped `runtime_snapshot_json`/`stored_password` (persisted-session leak),
      `finalizeRotationUpdate()` derives target passphrase from `unlockPassphrase`.
      Secret setters route to draftSecrets; `recoverProfileFromShare` dropped.
    - **App.tsx:** Paper JSX (`--ours`), secret inputs re-pointed to draftSecrets
      setters; `generatedKeyset`→`pendingKeyset`; dropped local PwaRuntime* types
      re-added.
    - **profile-packages.ts:** dropped bfshare `recoverProfileFromBfShare`;
      `localPassword ?? input.passphrase`.
    - **App.test.tsx:** both typed state literals updated to the reconciled
      draft/secret shape (now also asserts the new secret fields are non-persisted).
  - **Second-wave cross-repo adaptations (f012004 runtime layer had never been
    typechecked against the reconciled siblings):**
    - `NodeWithEvents` → `BrowserBridgeNode` (igloo-shared restructured
      browser-runtime-core → runtime-api; the interface was replaced by the class).
    - `ConfirmModal` → `ConfirmDialog` (igloo-ui deleted confirm-modal).
    - `share_package_json` removed from PwaProfile → member label derived from the
      public `member_idx` (`dashboard-view.ts` ExportSummaryProfile, welcome card).
    - Re-layered `clearSessionLogs` onto the security SessionController adapter
      (Paper's module-global version was dropped); rewrote `clear-session-logs.test.tsx`
      to the controller model (return-null contract, no runtimeSnapshotJson).
  - **Faithful-typecheck dep setup (restore after):** temporarily set
    igloo-shared→reconcile (b966139) and igloo-ui→reconcile (b68acdd, `npm run build`
    for dist), ran tsc + vite build, then restored both siblings to security-hardening.
  - **Locked decisions (operator, 2026-06-03):**
    1. **Runtime: security-wins.** security's `SessionController`+`SessionEpoch`
       (per-instance, epoch drift no-op, passphrase on-stack) + `buildStatusSnapshot`
       (never calls `snapshot_state()` — that export leaks `bootstrap.share.seckey`)
       + `persist-allowlist`/`toPersistable` + `PwaDraftSecrets` secret-segregation
       are canonical. **Paper's persisted-session DROPPED** (`startPersistedBrowserRuntimeSession`/
       `runtimeSnapshotJson`/`runtime_snapshot_json`) — it serialized the seckey via
       `snapshot_state`, a secret-at-rest regression. Paper's **onboard-complete
       forwarder RE-LAYERED** onto the controller.
    2. **UI: App.tsx Paper-wins**, adapted to security's runtime + types.
    3. **types: security-wins** on runtime/load types (`PwaProfile`,
       `PwaRuntimeSnapshot`, `PwaLoadConfirmation` = `passphrase`/`BrowserProfilePreview`)
       and secret-segregation; **Paper-wins** on distribution (status-lifecycle) +
       non-secret UI fields (`distributionPermissions`).
    4. **Distribution: Paper status-lifecycle now**; fine-grained live tracking
       (`kind`+`tracking`, the item deferred from igloo-ui) deferred again — the
       re-layered onboard-forwarder drives `onboarded` coarsely.
    5. **Recovery:** DROP security's `recoverProfileFromBfShare` (Paper removed that
       path; reconciled igloo-shared dropped `recoverBrowserProfilePackage`); keep
       Paper's shares-based `RecoverPrivateKeyView`.
  - **Resolved (no markers, in f012004):** `page-runtime-host.ts` (observability
    events + onboard forwarder kept; **session-snapshot seckey leak removed**;
    onboarding one-shot snapshot kept — security-allowed); `profile-runtime.ts`
    (security `SessionController` base + re-layered onboard-forwarder: attach in
    `startSession`, detach in `stopSession`/`disposeRuntimeSessionForProfile`);
    `vite.config.ts` (Paper `allow:[../..]` + security COOP/COEP headers + test
    config); `types.ts` 3/7 (imports merged + dropped broken igloo-ui
    `SharedDistributionTrackingStatus` import; `PwaLoadConfirmation` security-wins;
    `PwaDistributionActionResult` Paper status-lifecycle). wasm binaries → Paper's.
  - **RESUME:** `git -C repos/igloo-pwa checkout reconcile/paper+security` (WIP tip
    f012004). Resolve the 5 markered files per the locked decisions: finish
    `types.ts` drafts (distributionForms `{label}` + keep `distributionPermissions`;
    move inline form secrets → `PwaDraftSecrets`; `importSaveForm` vs
    `recoverProfileForm`; `pendingLoadError` both-keep); `profile-packages.ts` drop
    the bfshare recovery + reconcile the `password`/`passphrase` field; `App.tsx`
    prefer Paper (`--ours`) then adapt to security types via tsc; `store.tsx`
    hunk-by-hunk (Paper UI state + security controller wiring + `adapter.setOnboardCompleteListener`
    at ~512/539); `App.test.tsx` align to Paper App. Then build + `tsc` + vitest and
    `git commit --amend` to land a clean single merge commit. Cross-repo deps for a
    faithful typecheck: igloo-shared→reconcile, igloo-ui→reconcile (build `dist`).

- **igloo-paper** — **DONE** on local branch `reconcile/paper+security` (`38d734f`,
  pushed). Reference submodule, no security changes; current base `b333321` is an
  ancestor of the Paper tip `38d734f` (0 behind / 17 ahead) → took the Paper tip
  outright. Do NOT import into runtime. Parked back on `b333321`.

- **igloo-home** — **DONE** (`reconcile/paper+security` @ `270024e`, pushed;
  single parent `d99c987`, which already contains Paper's `eed7b7a` so a parent
  ff from `master` is clean). Migrated the consumer to the reconciled igloo-ui API
  (resolution summary below the error list). **Validation (siblings on reconcile,
  igloo-ui dist built): `tsc --noEmit` clean; `vite build` + CSS check clean;
  vitest 23/23** (`NODE_OPTIONS=--experimental-strip-types`). How it was resolved:
  - New `src/lib/dashboard-view.ts` maps igloo-home's runtime data onto
    `SignerDashboardViewModel`/`PolicyDashboardViewModel`; the two `OperatorSignerPanel`
    sites + `OperatorPermissionsPanel` now take `view`. Keyset identity sourced from
    `runtime_status.metadata` (ProfileManifest lacks group/share keys + member idx).
  - Dropped igloo-ui exports replaced: `Operator{PeerPermissionState,PendingOperation}`
    → local `Home*` types; `SharedDistributionTrackingStatus` removed.
  - `deriveDistributionResults` → `SharedDistributionResult` (Paper status-lifecycle;
    fine-grained tracking dropped — deferred). `AppHeader` → `mode`; card gains
    `shortId`/`state`/action labels (+`destructiveActionLabel: 'Delete Profile'`).
  - `CreatePage` split into `CreateFlowGenerateCard` (new) + `RotateKeysetPanel`
    (rotate) with a mode toggle; privateKey input ignored. Updated 2 own unit tests
    (mode-button label "New Keyset"; delete button restored via destructiveActionLabel).
  - **Distribution lifecycle now fully wired** (commit `270024e`): `handleDistributeGeneratedShare`
    takes `SharedDistributionAction` and runs the full Paper lifecycle (ported from
    igloo-pwa) — `prepare` builds the package once (→ 'packaged'); copy/qr/save operate
    on it (save → 'saved'); mark → 'delivered'; revert → 'packaged'; cancel discards.
    `DistributionResult` is status-based; `deriveDistributionResults` promotes to
    'onboarded' on the live peer signal. tsc + build clean, vitest 23/23.

  --- original scoping (for reference) ---
  The pointer Δ is 0 (Paper tip `eed7b7a` is an
  ANCESTOR of sec tip `d99c987` — sec is +24/-0, a superset), so `git merge
  security-hardening` from the Paper tip just **fast-forwards to `d99c987`** — no
  Paper commits to reconcile. BUT the doc's "Δ0 / already current" was a
  pointer-only read: igloo-home **consumes igloo-shared + igloo-ui** (`file:`
  deps, imports in `App.tsx`/`CreatePage.tsx`/`lib/runtime-status.ts`), and its
  security-era code (`d99c987`) was written against the OLD igloo-ui API. Against
  the **reconciled** igloo-ui (`b68acdd`, Paper redesign) it does NOT typecheck —
  **12 `tsc` errors in `App.tsx` (8) + `CreatePage.tsx` (4)**:
  - Renamed/moved exports: `OperatorPeerPermissionState`/`OperatorPendingOperation`
    → `models/view-models` (`PeerPolicyRowModel`/`PolicyDashboardViewModel`/
    `PendingOperationRowModel`); `SharedDistributionTrackingStatus` →
    `SharedDistributionStatus`.
  - **Dashboard panels redesigned to view-models:** `OperatorSignerPanel` now takes
    `view: SignerDashboardViewModel` (+ callbacks), NOT `profile`; `OperatorPermissionsPanel`
    takes `view: PolicyDashboardViewModel`, NOT `peerPermissions`/`peerPermissionStates`.
    Must build them via the `runtimeStatusToSignerDashboardView` /
    `runtimePeerPermissionStatesToPolicyDashboardView` adapters — the SAME pattern
    igloo-pwa's `App.tsx` uses (ports cleanly, but needs igloo-home's Tauri runtime
    state mapped to the adapter inputs).
  - `AppHeader` is now `mode`-based (no `title`/`centered`/`subtitle`);
    `StoredProfileCardModel` now requires `shortId`.
  - `CreatePage`: create-form field union (`mode`/`sourceProfileId` vs `privateKey`)
    + distribution `SharedDistributionResult` needs `status` + `SharedDistributionAction`
    includes `revert` (Paper status-lifecycle).
  This is a real (bounded) dashboard view-model migration — same class as igloo-pwa's
  App work, scaled down. Reusable: igloo-pwa `App.tsx` is the reference for the
  view-model panel wiring. **Resume:** siblings→reconcile (igloo-ui build `dist`),
  igloo-home→`reconcile/paper+security`, migrate the 2 files, `npm run typecheck:raw`
  with `NODE_OPTIONS='--experimental-strip-types'` for vitest, commit + push backup.

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
  `src/lib/use-focus-trap.ts` — **ABSENT at Paper tip ⇒ clean re-add.** See the
  locked **Dialog-vs-Modal decision** below; this + `styles.css` is the crux.
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

### Dialog-vs-Modal decision (LOCKED 2026-06-03)

The two are **visually near-identical** (centered `max-w-2xl` panel + dismiss
backdrop). The difference is almost entirely **behavior/a11y** — Paper's `Modal`
is a thin shell; security's `Dialog` adds focus-trap, initial-focus + restore,
ref-counted body scroll-lock, a module-level LIFO **Escape stack** (only the
topmost closes; Modal's per-instance `window` listener closes ALL open modals at
once), full ARIA (`role=dialog`/`aria-modal`/labelledby/describedby), and
`preventDismissOnBackdrop|Escape` opt-outs. Security also ships `ConfirmDialog`.
Visually, Dialog's only distinct content is hard-coded `slate-*` colors that
Paper-wins overwrites anyway.

**Decision: keep security's hardened `Dialog`/`ConfirmDialog` as the single
engine; restyle it to Paper's `igloo-*` tokens (Paper-wins on look); and back
Paper's `Modal` API with it** (a thin `Modal` shim over `Dialog`, or migrate the
call sites). Rationale: behavior is the thing we must not lose, and it's the part
Paper lacks entirely.

**Scope is small** (checked at the tips):
- Paper `Modal` consumers = **4 usages / 3 files**: `flows/ExportPackageModal.tsx`
  (1), `flows/HostShell.tsx` (2), `flows/QrPayloadModal.tsx` (1).
- Security `Dialog`/`ConfirmDialog` consumers = only `flows/QrPayloadModal.tsx`.
  Paper tip has **no** Dialog/ConfirmDialog at all.
- `flows/QrPayloadModal.tsx` exists on BOTH (security→Dialog, Paper→Modal) ⇒ it
  will conflict; resolve Paper-wins layout but land it on the hardened engine.
- Net: re-add `dialog.tsx` + `use-focus-trap.ts` (clean), restyle to igloo tokens,
  delete/shrink `modal.tsx` to a `Dialog`-backed shim (preserve its
  `open/onClose/title/className` API so `ExportPackageModal`/`HostShell` are
  untouched), then settle `QrPayloadModal.tsx`.

## The pattern that works

1. `git checkout -b reconcile/paper+security <paper-tip>` in the submodule.
2. `git merge --no-edit security-hardening`.
3. Resolve git conflicts (UI: Paper-wins; backend: both-keep).
4. `cargo check`/`tsc --noEmit` — fix the **semantic** ripples git didn't flag
   (Paper code using raw bytes vs our secret newtypes → `expose_bytes()`; old
   `CreateKeysetConfig` struct literals → `::new`).
5. Build + test; `cargo fmt`/lint; commit the merge.

## Remaining order

~~igloo-shared~~ → ~~igloo-chrome~~ → ~~igloo-ui~~ → ~~igloo-pwa~~ →
~~igloo-paper~~ → ~~igloo-home~~ → ~~parent~~ — **ALL RECONCILED.**
**CUTOVER DONE** (2026-06-04) — see "Cutover (DONE)" below.

## State to restore on resume

**Done (8 — ALL submodules):** each holds its work on local branch
`reconcile/paper+security`, all pushed to `origin/reconcile/paper+security` (backup):

| repo | reconcile tip | validation |
|---|---|---|
| bifrost-rs  | `dab2b94` | `cargo test --workspace` pass |
| igloo-shell | `479bfbd` | `cargo check` clean, lib tests pass |
| igloo-shared| `b966139` | typecheck clean, vitest 141/141, wasm-exports ok |
| igloo-chrome| `6aa9936` | typecheck clean; fast e2e **17/17**; +`6aa9936` Permissions titles fix |
| igloo-ui    | `b68acdd` | build + `tsc --noEmit` clean, vitest 120/120 |
| igloo-pwa   | `a78a2ea` | `tsc --noEmit` + `vite build` clean; **vitest 32/33** (1 env-only); fast e2e 20/20 |
| igloo-home  | `12d9c2d` | `tsc --noEmit` + `vite build` clean; vitest 23/23; +`12d9c2d` src-tauri signing_key32 fix |
| igloo-paper | `38d734f` | reference submodule (Paper tip); no validation needed |

**PARENT reconcile — DONE** (parent branch `reconcile/paper+security` @ `eb2ebfb`,
parents `[9d157e0 paper, 20c728d security]`, pushed to
`origin/reconcile/paper+security` as **backup only** — NOT a cutover). 8 submodule
pointers set to the reconciled tips + 15 parent-infra content conflicts resolved:
- **Paper infra restructure = canonical base; re-layer security:** in-Docker demo
  build (services/demo/Dockerfile) wins → dropped per-service dockerfiles +
  security host-build paths (demo.sh/entrypoint.sh/compose.test.yml volumes);
  Paper's test-harness superset (test/package.json + global-setup + check-setup,
  renamed check-makefile-surface→test-run-sh); AGENTS.md Paper.
- **Operator decisions:** CI workflows **SHA-pin @v5** (checkout 93cb6efe,
  setup-node a0853c24 — node24 + immutable); `reset.sh` **security** (mandatory
  --force + demo.sh stop); `.env.example` **kept from security** (Paper deleted it
  but README still `cp`s it).
- **app-shell.spec.ts:** Paper page-object wiring + security v2 storage key +
  debounce poll; re-layered v2-seed (support/state.ts + pwa-home-pairing.spec.ts →
  `igloo-pwa.state.v2`).
- **Validation:** 12 lightweight parent guards PASS (docs, command/doc surfaces,
  test-targets, shared-setup, cross-client, e2e-selectors, wasm-harness,
  node24-actions, client-scoped-submodules, markdown-links, pwa-visual-manifest).
  Heavier guards (`make repo-check`, test-affected, e2e) + `make test-release`
  deferred to the operator's pre-cutover run.
- **Current workspace state:** parent on `reconcile/paper+security` @ `eb2ebfb`,
  submodules checked out at their reconcile tips (tree clean). `security-hardening`
  = `20c728d`, `origin/master` = `ace4930` (both untouched).

**Cutover (DONE — 2026-06-04):** all 9 `master` branches advanced to the reconcile
tips and pushed. Final masters on `origin`:

| repo | master after cutover | how |
|---|---|---|
| bifrost-rs  | `fe379c9` | **merge** of `origin/master` (435e7f6) into reconcile dab2b94 — origin carried a net-zero add+revert pair, so a pure ff would have rewritten published history; merge tree == dab2b94 |
| igloo-shell | `479bfbd` | ff |
| igloo-shared| `b966139` | ff |
| igloo-chrome| `6aa9936` | ff |
| igloo-ui    | `b68acdd` | ff |
| igloo-pwa   | `a78a2ea` | ff |
| igloo-home  | `12d9c2d` | ff |
| igloo-paper | `38d734f` | ff |
| **parent**  | **`3e18a9d`** | ff to 12e5f89, then +1 to repin bifrost gitlink dab2b94→fe379c9 |

Pre-cutover safety: fetched fresh, verified `origin/master` was an ancestor of every
reconcile tip (7 clean ff). Only bifrost-rs was non-ff — investigated and found the 2
extra origin commits were `fc6bf1a` ("Add responder sign activity events") + its own
revert `435e7f6` (identical tree to the merge-base), resolved by merge (no force-push,
no code lost). Post-cutover: all 9 repos checked out on `master`, `HEAD == origin/master`
everywhere, parent worktree clean, `git submodule status` all space-prefixed. The
`reconcile/paper+security` branches remain on `origin` as backups (safe to delete later).

(Historical: during the submodule phase, all submodules were parked on
`security-hardening` to keep the parent tree clean. Now the parent is reconciled,
they sit at their reconcile tips so the parent tree matches `eb2ebfb`.) To resume a repo:
`git -C repos/<x> checkout reconcile/paper+security`.

**igloo-pwa unit harness — RAN (2026-06-03): vitest 32/33.** Bare `vitest` hits the
pre-existing `igloo-shared/testing/vitest-base` `.ts` config-loader issue; the fix
is the **CI node-env piece** `NODE_OPTIONS='--experimental-strip-types'` (node 22.13).
Invoke: `NODE_OPTIONS='--experimental-strip-types' ./node_modules/.bin/vitest run`
with siblings on reconcile (igloo-shared b966139, igloo-ui b68acdd+dist). bun's
runtime is vitest-worker-incompatible; `tsx` isn't installed locally.
- Fixed under security behavior: the legacy `onboard-confirm` normalization test
  now expects package entry (the passphrase-bearing `pendingOnboardConnection` is
  reset on reload, so the save screen can't resume) — was the only behavior-level
  test mismatch.
- **1 env-only failure** (not a reconcile regression): "opens the hard-cut create
  flow and finishes setup…" (Paper-only test). Security's save path **mandates a
  successful `publishEncryptedProfileBackup`** (real `SimplePool.publish` to a
  relay, throws fatally on failure — `igloo-shared/profile-backup-host.ts`). Offline
  it times out at ~1.1s. Passes with network / the workspace dev-relay. Can't be
  cheaply mocked from the pwa test — igloo-shared (sibling source) imports
  `nostr-tools` from its own module graph, so a pwa-side `vi.mock('nostr-tools')`
  doesn't intercept its `SimplePool`. To green it: run with a reachable relay, or
  add an igloo-shared-level publish stub.
- **e2e NOT run** (Playwright + dev-relay + Rust WASM build) — defer to CI / the
  parent `make` harness.
- Adopt the renamed Operator\* types from igloo-ui's `models/view-models` if any
  pwa consumer still references the old names (tsc was clean against reconciled
  igloo-ui, so none currently do).
- `onboardSaveForm.relayUrls` is a non-secret Paper UI field that the security
  `finalizeOnboardedDevice` does not consume (relays come from the connection).

**Next:** ALL repos + the parent are reconciled (parent @ **`69ea6cc`**, local; the
doc-bookkeeping commit recording this update rides one above it as HEAD). Only the
**operator-gated cutover** remains: review the merges → re-run `make test-release`
(the full Docker/browser matrix on real CI infra) → ff each submodule `master` to its
reconcile tip and the parent `master` to the current `reconcile/paper+security` HEAD →
push. The parent `reconcile/paper+security` branch is pushed to `origin` as a backup.

## test-release validation (RAN 2026-06-03/04) — lanes run individually

Strategy chosen by operator: drop the 2 pwa save-profile visual captures, run each
lane individually, push through everything locally. Parent advanced `eb2ebfb` →
`f72fa1e` → `c1d1a89` → **`69ea6cc`** (this results doc) as reconcile regressions
surfaced and were fixed.

**GREEN — every functional / Rust / typecheck / non-live lane passed:**

| lane | result |
|---|---|
| prebuild (Rust bins, browser artifacts, demo images) | ok |
| bifrost-rs `cargo test --workspace` | pass (bifrost-devtools ETXTBSY = transient flake, 3/3 isolated) |
| igloo-shell CLI / devnet / node-E2E | pass |
| igloo-shared typecheck | clean |
| igloo-pwa fast (non-live browser) | **20/20** |
| igloo-chrome fast (non-live browser) | **17/17** |

**4 real reconcile regressions found & fixed during the run:**
1. **igloo-home src-tauri** — Paper `CreateKeysetConfig` struct literals vs security's
   `signing_key32` newtype → `CreateKeysetConfig::new(group_name, threshold, count)`.
2. **services/igloo-demo/entrypoint.sh** — corrupted merge dropped `lib-wait.sh`; took
   Paper's complete self-contained 438-line entrypoint, `git rm`'d `lib-wait.sh`.
3. **igloo-chrome PermissionsPanel** — Paper view-model migration dropped the section
   titles → re-added `siteTitle="Site Policies"` / `peerTitle="Peer Policies"`; test
   updated to Paper's `Device Profile` settings heading.
4. **igloo-chrome live fixture** (`ensureResponder`) — security-hardened `daemon start`
   requires a passphrase; first wrongly used `--passphrase-env` (import/profile-only),
   re-fixed to pipe via **stdin** (commit `c1d1a89`). Confirmed: 0 `--passphrase-env`
   errors, live fixtures bootstrap cleanly (`prepare-stable-live-signer:ok`).

**Env/infra walls — NOT reconcile regressions (need CI infra to green):**
- **Live relay round-trip timing** (pwa live, chrome live `dashboard.spec.ts:67`): the
  signer dashboard assertions (`Share/Group Public Key`, formatted peer pubkey, `sign-ready`)
  need a completed live signing round-trip; times out in this slow sandbox.
- **Multi-process demo-harness orchestration** (chrome demo, home live): `Timed out
  waiting for harness artifact onboard-bob.txt` (300s) — the alice/bob/relay multi-proc
  fan-out doesn't settle here.
- **Rootless-Docker `/w` symlink** (home live, chrome demo): `ln: failed to create
  symbolic link '/w': Permission denied` (uid 1000) — pure env, not reconcile.

**Verdict:** the reconcile is functionally sound. Every deterministic lane is green;
all 4 regressions the run exposed are fixed and committed; the only red lanes are
live/Docker round-trips blocked by sandbox env, to be re-run on CI before cutover.

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
  tips), not a reconcile bug. **Workaround (the CI node-env piece): run with
  `NODE_OPTIONS='--experimental-strip-types'`** on node ≥22.6 — node then loads the
  `.ts` config directly. Confirmed on igloo-pwa (node 22.13): `NODE_OPTIONS=
  '--experimental-strip-types' ./node_modules/.bin/vitest run` → 32/33. Do NOT use
  `bun`'s runtime for vitest (tinypool worker incompatibility); `tsx` is not
  installed locally.
- **wasm binaries**: at every browser repo, took Paper's refreshed `*_bg.wasm`
  (HEAD/ours) to match the merged loader glue. Authoritative regen from reconciled
  bifrost-rs happens later via `make browser-wasm-sync` / `test-prep`.
- **env**: `rg` is a shell-function shim (real binary at
  `/usr/share/codium/.../@vscode/ripgrep/bin/rg`); `bun`/`bunx` at `~/.bun/bin`
  (needed for `tsc`/`vitest` — no local `node_modules/.bin/tsc`); background
  subagents are read-only here (do mutations in the main thread).
