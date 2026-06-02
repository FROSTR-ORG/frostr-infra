# Design Plan: Dashboard / Settings / Export — Paper redesign → igloo-ui alignment

Living design plan. Shaped collaboratively first, implemented in a later pass.
Sections are tagged:

- **[LOCKED]** — decided.
- **[TO SHAPE]** — open for discussion before implementation.
- **[CONFLICT]** — Paper-vs-runtime/functionality clashes needing an explicit
  product decision (per the standing rule: surface conflicts, decide together).

## Context

The dashboard/settings/export surface is the last major area not yet aligned to
Paper. Before aligning the UI we are **first revising the Paper design itself**,
because the current Paper dashboard wastes space, uses confusing terminology
("Policies"), and encodes a per-request signing-approval flow the PWA runtime does
not implement. Aligning to the *current* Paper would bake in those problems, so the
work is two-phase:

- **Phase A — shape the Paper design** (edit Paper source via MCP, re-sync the
  `igloo-paper` export). This plan is the spec for those edits.
- **Phase B — align igloo-ui + igloo-pwa** to the revised design (components,
  test-ids, visual capture specs, manifest entries, token sync), following the
  established Paper→UI workflow used for Welcome/Create/Onboard/Import/Recover.

Current implementation (for reference): a single dashboard `ContentCard` with a
3-tab shell (`OperatorDashboardTabs`: Signer / Permissions / Settings) rendering
`OperatorSignerPanel`, `OperatorPermissionsPanel`, `OperatorSettingsPanel`
(`repos/igloo-ui/src/components/flows/`), wired in
`repos/igloo-pwa/src/App.tsx` `renderDashboard()`. Settings currently exposes
inline `copy profile`/`copy share` buttons; there is no Pending-Approvals list and
no signing-approval prompt anywhere in the PWA.

Paper source on disk: 16 dashboard screens + 2 recover screens under
`repos/igloo-paper/screens/{dashboard,recover}/` (artboard map in
`repos/igloo-paper/artboard-map.json`). The PWA visual manifest
(`test/igloo-pwa/visual-manifest.json`) currently has **0** dashboard entries
(recover is already covered).

## Signer dashboard — design changes [LOCKED]

These four are decided and apply to the Paper `1-signer-dashboard` artboard (and
ripple into related screens / the implementation):

1. **Rename "Policies" → "Permissions"** in user-facing places. The policies
   *declare permissions*; "Permissions" is clearer. Affects: top-nav link, the
   page title, and section headers. (Implementation note: the current PWA tab is
   already labelled "Permissions" — this aligns Paper *to* the PWA, and we keep
   "Permissions" as the canonical term everywhere.)

2. **Reorder dashboard cards** to: **Peers → Pending Approvals → Event Log**.
   Pending Approvals moves up directly under Peers and above the Event Log.

3. **Top navigation = Dashboard · Permissions · Settings** (three links), living
   **in the AppHeader** (keep the design light/simple — no secondary nav bar). The
   active page is indicated with a **pill + color** treatment. Remove **History**
   and **Recover**:
   - **History** — dropped for now.
   - **Recover** — **removed entirely from the dashboard.** It was a designer
     mistake: there is **no signer-runtime recover process**. The existing Recover
     flow (collect shares → recover private key) is a **pre-login / Welcome-side
     flow**, not a dashboard runtime feature, and stays reachable from its Welcome
     entry point. (Resolves the former "[TO SHAPE]: Recover entry" question.)

4. **Merge the "My Signing Key" card into the "Signer Running" card** — one
   streamlined identity + runtime card. Eliminates the wasted full-width "My
   Signing Key · 2/3 · npub…" banner. Card spec:
   - **Two keys**: "Group Public Key" and "Share Public Key", each truncated
     (`npub1qe3...7k4m`) with a **split copy button** — copies **`npub` by
     default**, with a small caret/dropdown to pick **`hex`** (per-key, so the two
     keys can be copied in different formats).
   - **Threshold context inline**: surface the threshold (e.g. `2/3`) and member
     index (e.g. `#1`) on the card, since the merge frees space.
   - **Runtime status/controls**: Signer Running / Stop Signer (or Start Signer
     when stopped), relay summary — in the same card.
   - **Stopped state** (Paper `2-stopped`): same card stays present — shows
     "Signer Stopped" + a **Start Signer** button, with **keys still visible and
     copyable**; Peers / Pending Approvals / Event Log render calm empty states.

## Shell / navigation model [LOCKED]

- **Separate routed pages**, not a tab strip. The header nav (Dashboard ·
  Permissions · Settings) routes to **distinct full-height pages**, matching
  Paper. Settings becomes its own scrolling page; Permissions its own page; the
  Dashboard page holds the signer card + Peers + Pending Approvals + Event Log.
  Phase B replaces the current single-card `OperatorDashboardTabs` shell with a
  routed shell. (Resolves the Settings page-vs-tab open question.)

## Functional conflicts — resolved [CONFLICT → DECIDED]

- **Pending Approvals + Signer Policy Prompt** (interactive per-request signing
  approval): **Defer the behavior, keep the visual shell.** Build the Pending
  Approvals card + prompt UI to match Paper, wired to an **empty/stub state** (no
  real signing gating — the runtime still auto-signs per stored policy). Real
  interactive approval is tracked as a **separate future runtime feature**
  (`igloo-shared` / `bifrost-rs`: queue requests, await Deny / Allow once / Always
  allow). The stub must read as "no pending approvals," not as a broken control.

## Other screens — to shape before implementation [TO SHAPE]

All shaped over the 2026-06-01 grilling rounds. Decisions:

- **Settings page** (`3-settings-lock-profile`): **separate full page** (Device
  Profile / Group Profile / Replace Share / Export & Backup / Logout). Numeric
  signer settings (Sign Timeout, Ping Timeout, Request TTL, State Save Interval,
  Peer Selection Strategy) live under an **"Advanced"** section.
  **[REFINED 2026-06-02 for step 3 build]:**
  - Sections to build now: **Device Profile** (name + password-change + relays),
    **Replace Share** (= rotate flow), **Export & Backup**, **Profile Security
    (Logout)**, plus **Advanced** (numeric settings). **Dropped from PWA scope:**
    Group Profile read-only card and the "Onboard a Device" Settings entry (onboard
    stays welcome-side); **Clear Credentials deferred**.
  - **Advanced is expanded by default** (not collapsed — revised from the earlier
    collapsed-by-default note).
  - **Surface = routed page** (`activeDashboardTab='settings'`), matching steps 1-2;
    Paper's slide-over treatment is a prototype affordance, not adopted.
  - **Export & Backup in step 3 = relabel only** ("Export Profile"/"Export Share"
    under the section heading) keeping the current copy-to-clipboard behavior; the
    password modal lands in step 4.
  - **Paper edit in step 3:** rename `502-0` "Lock Profile" → "Logout" + re-sync.
- **Replace Share === the existing rotate-key flow** (investigated 2026-06-01,
  confirmed). Paper's "Replace Share" ("import a bfonboard package to replace only
  this device's local share while keeping the same group public key and profile")
  is *behaviorally identical* to the PWA rotate flow (`store.connectRotationPackage`
  → "Replacement Preview" → `finalizeRotationUpdate`, "Same keyset, fresh device
  share"). Not a missing feature — **terminology drift**. **[DECIDED] standardize
  the user-facing term to "Replace Share"** everywhere (Paper + igloo-ui): the
  Settings section, the flow title (currently "Rotate Key"), and the button
  (currently "Replace Active Device") all become "Replace Share". Keep "rotate" only
  in internal store/protocol names (`startRotateKey`, `connectRotationPackage`,
  `finalizeRotationUpdate`, the `rotate-*` activeViews) to avoid a churny rename.
  The Settings "Replace Share" section launches that existing flow.
- **Logout (not Lock)** [DECIDED]. Paper's "Lock Profile" and the PWA's "logout"
  are the same return-to-Welcome action (`store.logout()`). Standardize on
  **"Logout"** (more familiar) across igloo-ui **and** the Paper design — a small
  Paper edit changes the Settings artboard "Lock Profile" → "Logout".
- **Export Profile / Export Share** (`4-export-profile`, `4c-export-share` +
  `-complete`): **adopt Paper's password modal** (export → password + confirm →
  encrypted package → "complete" state with copy / save-to-file / QR). Replaces the
  current one-click `copyProfilePackage` clipboard buttons. Reuse the existing
  password-encrypt path in
  `repos/igloo-pwa/src/lib/local-adapter/profile-packages.ts`.
- **Settings modals** [DECIDED]: build the **Unsaved Changes** dirty-state guard
  modal (`3c`) — adds dirty tracking on the Settings form + a confirm-on-leave
  guard. **Defer Clear Credentials** (`3b`) — it introduces a new destructive
  "clear credentials" concept the store doesn't have; track as a follow-up.
- **Permissions page** (`1c-permissions`): **[DONE 2026-06-02]** Section titles
  parameterized in `OperatorPermissionsPanel` (defaults now "Signer Permissions" /
  "Peer Permissions", matching Paper). **CONFLICT RESOLVED:** Paper's "Signer
  Permissions" section (per-origin `sign_event:1`/`get_public_key` rows + "Default
  policy: Ask every time" selector) is a **NIP-07 website-bridge concept that only
  igloo-chrome has** — the igloo-pwa signer is standalone with no site/origin
  permissions. Decision: **PWA Permissions is peer-only** (the site section simply
  doesn't render on the PWA because `siteRows` is undefined; it still renders on
  chrome, which populates `siteRows`). The **default-policy selector is deferred**
  (ties to the same site-permission + interactive-approval model the PWA lacks).
  Net PWA change: just the title rename via the component default.
- **Recover entry**: **[RESOLVED]** Recover is *not* a dashboard feature. Launched
  from the **Welcome returning-profile card action menu** (`WelcomeReturningHero`
  `onRecover` → `store.startRecoverKey`, test-id `welcomeProfileMenuRecover`,
  `App.tsx:680`), reachable while logged out. Nothing dashboard-side to add.
- **Error / empty / modal states** (`1b-loading-profile`, `1b-profile-load-failed`,
  `2b-all-relays-offline`, `2c-signing-blocked`, `6-signing-failed`): **deferred** —
  align after the core Dashboard/Permissions/Settings pages; several depend on
  runtime states the PWA may not surface yet. (`2-stopped` is already aligned in
  Paper as part of Phase A.)

## Implementation decisions [DECIDED]

- **Routing: extend `activeView` now; router is a future refactor.** Add new
  `activeView` values (e.g. `dashboard`, `dashboard-permissions`,
  `dashboard-settings`) the store drives; the header nav sets `activeView`. No new
  router dependency — consistent with the existing hand-rolled state machine.
  **Follow-up (separate project):** evaluate adopting a real router for URL
  deep-linking / back-button semantics once the routed pages exist; weigh against
  the risk of deep-linking into sensitive unlocked states (needs route guards).
- **Pending Approvals stub = always-present empty-state card** ("No pending
  approvals"), matching Paper's layout/position, honest that nothing is queued.
  Not hidden, no "coming soon" copy.
- **Deterministic key fixture for visuals + tests.** Live keygen
  (`createGeneratedBrowserArtifacts`) is random and unfit for byte-stable
  screenshots. Add a small shared fixture of **pinned test-vector keys** under
  `test/igloo-pwa/support/` — valid secp256k1 x-only pubkeys whose `npub`
  encodings are known/stable (verified to bech32-encode without throwing; not
  arbitrary `'22'×32`-style bytes). Seeded dashboard/export visual states use
  these so screenshots are deterministic AND functional specs can assert exact
  `npub`/`hex` copy output. Mirrors the fixed-key seeding already used in
  `onboard-visual.spec.ts`.
- **Export visual capture = seed state + screenshot.** Drive the export modal open
  via seeded store state (as `onboard-visual` seeds `pendingOnboardConnection`),
  using the deterministic key fixture; capture password-entry + complete states.

## Sequencing [DECIDED]

**Dashboard end-to-end first (vertical slice).** Fully shape → Paper-edit →
implement → visually verify the **signer Dashboard page alone** before touching
Settings / Permissions / Export. This proves the routed-shell + merged
identity/runtime card + `npub`/`hex` copy + Pending-Approvals-stub patterns on one
screen, then the rest follow the established shape.

Within the Dashboard slice, **Peers and Event Log are reorder + restyle only** —
keep them functionally as-is, reposition to **Peers → Pending Approvals → Event
Log**, and restyle to Paper. Full Paper parity for Peers rows (online/ready
counts, avg latency, per-method badges) and Event Log (filter, event-type tags) is
a **later enhancement**, not part of the first slice.

## Ownership & fixtures [DECIDED]

- **Paper edits: I drive them via the Paper MCP** (rename Policies→Permissions,
  reorder cards, nav links, merged card), review with `get_screenshot`, then
  re-sync. Requires Paper Desktop open on the Igloo file at Phase A start.
- **Deterministic key fixture: derive from fixed secrets.** Pin a few fixed
  32-byte secret keys and derive their real x-only pubkeys + `npub` at
  fixture-build time using the same `nostr-tools` the app uses — guarantees valid
  secp256k1 points + correct `npub`, and lets share-secret-dependent flows work.
  Lives under `test/igloo-pwa/support/`.

## Paper artboard map (confirmed via MCP — file `igloo-ui-shared`, page `core`)

Dashboard-slice edit targets and references (artboard IDs are stable handles for
the MCP edits):

- **`4HK-0`** — "Web — Dashboard — 1. Signer Dashboard" (1440×1192) — **primary
  edit target** for the four LOCKED changes.
- **`4WB-0`** — "Web — Dashboard — 1c. Policies" → rename to **Permissions**.
- **`7LC-0`** — "Web — Dashboard — 2. Stopped" (545 tall) — stopped-card variant.
- Later-batch dashboard variants: `7O9-0` loading, `7Q9-0` load-failed, `7SF-0`
  relays-offline, `7V9-0` signing-blocked, `7CU-0` signing-failed, `5BY-0`
  clear-credentials modal, `5O7-0` unsaved-changes modal, `7XW-0` signer-policy
  prompt (the deferred-approval modal).
- Settings/export batch: `502-0` settings+lock, `6CH-0` export-profile, `60E-0`
  export-complete, `70P-0` export-share, `6OM-0` share-export-complete.
- Reusable component artboards to source patterns from: `1HI-0` Navigation &
  Layout, `S7-0` Profile Cards, `4BT-0` Pool & Signing Readiness, `HI-0` Tables/
  Lists/Logs, `Z7-0` Overlays & Feedback.

**MCP availability confirmed:** Paper Desktop is connected to the Igloo file, so I
can drive the Phase A edits directly.

## Phase A — Paper design edits (process)

Follow the canonical Paper-source workflow (`dev/docs/WORKFLOWS.md` "Paper Source →
igloo-paper", `repos/igloo-paper/docs/mcp-edit-workflow.md`):

1. Open Paper Desktop on the Igloo file; load the Paper MCP guide
   (`get_guide paper-mcp-instructions`) and `get_basic_info` before any edit.
2. Edit the dashboard artboard(s) for the four LOCKED changes; add/rename variant
   artboards only where a state is materially different (per the variant-state
   policy). Review each with `get_screenshot`; `finish_working_on_nodes` when done.
3. Sync + verify: `make igloo-paper-sync`, then `make igloo-paper-verify STRICT=1`
   (use `make igloo-paper-usage-coverage-sync` if strict drift fails). Update
   `artboard-map.json` / `export-metadata.json` names + outputPaths and remove any
   renamed/stale entries; update `test/igloo-pwa/visual-manifest.json` references.
4. Token changes (if any) flow one-way via `make igloo-ui-paper-token-sync` /
   `make igloo-ui-paper-token-check`. `igloo-paper` stays reference-only — never
   imported into runtime.

## Phase B — igloo-ui / igloo-pwa alignment (process, after design is shaped)

- Update `repos/igloo-ui/src/components/flows/Operator*Panel.tsx` (+ a merged
  identity/runtime card; key-copy with `npub`/`hex` via a shared helper) and
  `repos/igloo-ui/src/styles.css`; rename "Policies"→"Permissions" copy.
- Wire `repos/igloo-pwa/src/App.tsx` `renderDashboard()` to the new structure;
  add the `npub`/`hex` encode for group/share keys (reuse existing key utils).
- Add/extend test-ids in `repos/igloo-ui/src/lib/e2e-test-ids.ts` for new
  copy-format controls + any new sections.
- New `test/igloo-pwa/specs/dashboard-visual.spec.ts` capturing each aligned
  screen; add matching `visual-manifest.json` entries (`status: needs-work` →
  `aligned` once matched). Keep igloo-ui unit tests + `App.test.tsx` green.
- Commit order: `igloo-paper` → `igloo-ui` (+ unit tests) → `igloo-pwa` → parent
  pointer + workflow docs.

## Critical files

- Paper source: `repos/igloo-paper/screens/dashboard/`, `artboard-map.json`,
  `export-metadata.json`, `design/tokens/`.
- UI: `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx`,
  `OperatorPermissionsPanel.tsx`, `OperatorSettingsPanel.tsx`,
  `OperatorDashboardTabs.tsx`, `src/lib/e2e-test-ids.ts`, `src/styles.css`,
  `test/HostShell.test.tsx`.
- PWA: `repos/igloo-pwa/src/App.tsx` (`renderDashboard`, key utils),
  `test/frontend/App.test.tsx`.
- Harness: `test/igloo-pwa/specs/dashboard-visual.spec.ts` (new),
  `test/igloo-pwa/visual-manifest.json`.

## Verification (Phase B)

- `npm --prefix test run test:e2e:igloo-pwa:visual` + `npm --prefix test run
  test:visual:report` → review `.tmp/visual/igloo-pwa/comparison-report.md`
  against Paper screenshots.
- `npm --prefix test run test:guards:visual` (manifest guard),
  `npm --prefix test run test:guards:selectors`, full `npm --prefix test run
  test:typecheck`.
- igloo-ui `npm test`; igloo-pwa `npm test`; `make test-fast` stays green.

## Status

- **Phase A — dashboard slice: DONE & committed.** Edited artboards `4HK-0`,
  `4WB-0` (→ `1c. Permissions`), `7LC-0`; synced + strict-verified (0 token drift).
  igloo-paper `4fedc72`, parent `207b494`.
- **All six original open questions: resolved** (approvals defer-with-stub;
  Settings = separate page; export = password modals; error states deferred;
  Recover = Welcome-side; numeric settings → Advanced section).

## Remaining Paper edits (before / alongside Phase B)

Small Paper-source edits still needed on the Settings/export artboards when we
align them, then a re-sync:

- **`502-0` Settings**: "Lock Profile" → **"Logout"**; "Replace Share" copy
  stays (it's now the canonical term — the *code* renames toward it, not Paper).
- Confirm the export modal artboards (`6CH-0`/`70P-0` + `-complete`) match the
  adopted password-modal flow; no rename expected.

## Nav realization [DECIDED 2026-06-01]

Render Dashboard · Permissions · Settings as **header nav links in the AppHeader**
(pill+color active), still driven by `store.activeDashboardTab` — not new
`activeView` values. Preserves all existing `App.test` setups (9 rely on
`activeDashboardTab`), matches Paper visually, low risk. The in-card
`OperatorDashboardTabs` tab strip is removed from the dashboard. (The true-router
refactor remains the deferred future project.)

## Phase B — execution order (DECIDED: Dashboard page first)

1. **Routed shell + Dashboard page only** (extend `activeView`; header nav with
   pill+color active state; merged identity/runtime card with `npub`/`hex` split
   copy; reordered Peers → Pending-Approvals-stub → Event Log) + its
   `dashboard-visual.spec.ts` + deterministic key fixture. Verify green before
   moving on.
2. Permissions page (rename + `OperatorPermissionsPanel` align).
3. Settings page (sections + Advanced collapsible + Replace Share section + Logout
   + Unsaved-Changes guard modal).
4. Export Profile / Share password modals (+ complete states).
5. Deferred follow-ups: error/empty states batch, Clear Credentials modal,
   interactive signing-approval runtime feature, router refactor.
