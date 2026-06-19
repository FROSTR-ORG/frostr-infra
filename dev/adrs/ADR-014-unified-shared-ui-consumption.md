# ADR-014: Unified Shared-UI Consumption

## Status

Accepted

## Context

A side-by-side screenshot showed `igloo-home` looking "stale" next to `igloo-pwa`,
raising the worry that a UI redesign had been applied directly to a client instead
of to the shared libraries. The 2026-06-19 shared-UI audit
([`dev/docs/UI-AUDIT.md`](../docs/UI-AUDIT.md)) found the opposite: the Paper
signer-dashboard redesign lives correctly in `igloo-ui` (`fcc0592`), `igloo-home`
renders the **same** `OperatorSignerPanel`, and all clients source-alias the same
`repos/igloo-ui/src` checkout — so no client can carry a newer shared UI than
another. `igloo-pwa/src` holds no local component files at all.

What the screenshot actually exposed is **inconsistent consumption and drifting
per-app tooling** around an otherwise-shared UI (adoption is already ~70–95% per
client). Five seams diverge:

1. **Consumption asymmetry** — every client resolves `igloo-ui` JS from `src`
   (live) but CSS from a prebuilt `dist/styles.css`. Edit a component → live; edit
   its styles → stale until `dist` rebuilds. This is the root footgun, and the
   reason a `make igloo-ui-styles` band-aid was bolted onto the home dev targets.
2. **Three CSS pipelines** — pwa/home consume prebuilt `dist`; chrome self-builds
   Tailwind scanning `igloo-ui/src`. Utilities available in one client can be
   missing in another.
3. **Per-app dev/visual seam** — pwa's seeded-running-dashboard seam
   (`?__frostr_dev=`) exists only in pwa; home/chrome screenshots can't reach the
   running dashboard. This is the drift that made Home *look* stale.
4. **Competing app-level UI** — pwa's one-off `igloo-dashboard-nav` (home/chrome
   already use shared `OperatorDashboardTabs`); 6 hand-rolled toggles (no shared
   primitive); ~24 inline alert boxes bypassing the shared `Alert`; an unused
   exported `DesktopAppShell`.
5. **View-model duplication** — some accidental (`toDashboardKey`, pending-ops row
   builder), some essential (runtime-shape-specific glue per host).

The three clients are genuinely different **hosts** — a browser PWA, a Chrome MV3
extension, a Tauri desktop app with a native Rust signer over IPC — and that
boundary is load-bearing. The shared layer is the `igloo-ui` component surface and
the `igloo-shared` runtime contracts. This ADR records the **target consumption
architecture** so the shared UI is consumed *identically* by every client, rather
than re-wired and re-tooled per app.

It **builds on** [ADR-013 (Test Infrastructure Architecture)](./ADR-013-test-infrastructure-architecture.md)
— the seeded-state and unified-visual-harness decisions extend to the app
consumption side here — and [ADR-004 (Cross-Repo E2E Ownership)](./ADR-004-cross-repo-e2e-ownership.md):
submodules keep ownership; this ADR governs how the parent's clients *consume*
`igloo-ui`/`igloo-shared`. It supersedes neither.

## Decision

The target is "one UI, consumed identically by every client." Remediation toward it
is sequenced in the BACKLOG roadmap and gated on this ADR.

**This is a hard cut** (in the spirit of [ADR-002](./ADR-002-encrypted-onboarding-hard-cut.md)).
The workspace is pre-release alpha, so each decision below is implemented by
**deleting the old path and replacing it** — no deprecation aliases, no
compatibility shims, no dual code paths, no "legacy" fallbacks, and no client left
on the old model behind a flag. Where a decision removes something (the prebuilt
`dist`, pwa's local nav, a duplicated adapter, `DesktopAppShell`), the old code is
**deleted in the same change**, not retained. The explicit goal is zero migration
debt left behind. (This is the one place ADR-014 departs from ADR-013, which kept
deprecation aliases for its lane renames — that allowance does not apply here.)

### (a) One consumption contract — all-source resolution

Every client resolves both `igloo-ui` **and** `igloo-shared` from **source**
(`../igloo-*/src`) for **both JS and CSS**, through a **single shared resolution
config** rather than per-client alias blocks that can drift. The CSS→`dist` alias
is removed: there is no longer a "JS from src, CSS from dist" asymmetry. In dev,
editing any shared component **or** its styles is live via HMR in all three
clients with no intermediate build step.

_Rejected:_ **all-built package** (clients consume `igloo-ui` `dist` for JS+CSS,
rebuild/watch in dev) — cleaner standalone-publish story, but a heavier, indirect
dev loop, the opposite of the goal. **All-prebuilt CSS** (igloo-ui scans every
client's source and ships one `dist/styles.css`) — couples `igloo-ui` to its
consumers and preserves the rebuild-or-stale footgun. **Status quo** (per-client
alias blocks, CSS from `dist`) — the drift this ADR exists to remove.

### (b) One CSS pipeline — a shared Tailwind preset

`igloo-ui` ships a **Tailwind preset** (`tailwind.preset.js`: theme tokens,
fonts, colors, radii, plugins) and its **source** `styles.css` (the hand-written
`@layer components` `igloo-*` classes) as a consumable input. Each client carries a
small `tailwind.config` with `presets: [igloo-ui preset]` and
`content: ['./src/**', '../igloo-ui/src/**']`, and imports `igloo-ui`'s source
`styles.css`. The preset is the single source of design tokens, so per-client
configs cannot drift the theme. Per the hard cut, `igloo-ui`'s prebuilt `dist` is
**removed outright** — the `dist` build script is deleted and `package.json`
`main`/`module`/`types`/`exports` repoint at `src` (it is consumed only as
co-resolved source). The CSS→`dist` path, the `make igloo-ui-styles` prerequisite,
and the `igloo-ui-watch` target are **deleted**, not deprecated (the asymmetry they
patched no longer exists).

_Rejected:_ **each client an independent Tailwind config** (no shared preset) —
theme drifts. **Keep prebuilt `dist`** — see (a). Chrome's current self-build
becomes the standard; pwa/home adopt the same shape.

### (c) One visual/dev seam — shared, not per-app

The seeded-runtime-snapshot dev seam (today pwa-only `lib/dev-scenario.ts` +
`?__frostr_dev=`) moves to a **shared dev-only surface** consumed identically by
every client's store/bootstrap, so `?__frostr_dev=<scenario>` and
`make screenshot CLIENT=<any> STATE=dashboard-running` render a seeded running
dashboard for pwa, chrome, **and** home. The seam stays gated behind
`import.meta.env.DEV` and bootstraps transient runtime state **in memory**, never
via storage seeds — consistent with ADR-013 (c)/(d).

_Rejected:_ **per-app seams** (the exact drift that hid parity here); **storage-
seeding the snapshot** (ADR-013 already rejected it — the snapshot is transient).

### (d) One shell + component set

The canonical dashboard shell is `PageLayout` + `AppHeader` +
`OperatorDashboardTabs`. Concretely:

- `igloo-pwa` retires its local `igloo-dashboard-nav` (+ CSS) for
  `OperatorDashboardTabs`; the tabs component gains an optional per-tab `testId`
  to preserve pwa's E2E ids. `AppHeader`'s `actions` slot is for status/profile
  only — **not** navigation — across all clients.
- Add a shared **`Checkbox`/`Toggle` primitive** to `igloo-ui`; retire the 6
  hand-rolled `<input type="checkbox">` toggles (pwa, home).
- Route inline alert/banner sites through the shared **`Alert`**, after filling its
  API gaps (first-class `info` tone, optional `dismissible`, title-less mode).
  Status **badges** and code/data boxes are explicitly **out of scope** for
  `Alert` — they are not alerts.
- **Delete `DesktopAppShell`** (and re-evaluate `ManagedProfilesPanel`): dead,
  unused, and superseded by the canonical composition above.

_Rejected:_ keeping pwa's bespoke nav (the divergence); a new unifying shell
component (the three already converge on the existing composition); keeping
`DesktopAppShell` "for a future client" (dead exported code rots).

### (e) View-model adapters — lift the accidental, keep the essential

Lift to the shared layer only the duplications that are **accidental** (identical
logic retyped): `toDashboardKey` (hex → npub/hex display) and a single
`buildPendingOperationRows` (with shared timestamp formatting), **deleting every
local copy** in the same change (no client keeps its own). Adopt the existing but
unused `runtimePeerPermissionStatesToPolicyDashboardView`. Keep **essential**
runtime-shape glue local — `parseRuntimeStatus` (Tauri IPC), `deriveRuntime
Presentation` (MV3 activation), `normalizeStoredPeerPolicy` (extension storage),
pwa profile-package JSON parsing, and the log-line→event-row fallback — because the
host state shapes genuinely differ.

_Rejected:_ **lift everything** (forces a union type over three runtime shapes,
obscuring intent); **lift nothing** (the triplicated logic already drifts on
timestamp formatting).

## Consequences

- The dev loop gets **simpler and uniform**: no prebuilt-`dist` step, no stale
  CSS, identical resolution across clients. The `make igloo-ui-styles` band-aid and
  `igloo-ui-watch` are removed, not maintained.
- `igloo-ui` ceases to be a standalone **publishable** npm package — it is consumed
  only as a co-resolved sibling-submodule **source** library. Accepted: nothing in
  this workspace publishes or consumes it standalone.
- Screenshots become **honest across all clients** — home/chrome gain the seeded
  running-dashboard seam, so parity can actually be verified (and regressions
  caught) per client.
- **Migration churn is real and bounded**: three client Tailwind configs + the
  shared preset and resolution config (a/b); the shared dev seam (c); pwa's nav +
  CSS removal, 6 toggles, ~24 alert sites, the `Checkbox` primitive, and
  `Alert` API additions (d); two adapter lifts (e). The roadmap front-loads the
  low-churn, footgun-removing consumption contract.
- Builds on ADR-013 (extends its seeding/visual decisions to the app side) and
  ADR-004 (no change to submodule ownership; the parent governs only how its
  clients consume the shared surface).
- **Hard cut, no back-compat surface.** Each decision deletes the old path in the
  same change — no deprecation aliases, compat shims, dual code paths, or feature
  flags, and no client left on the old model. This is affordable because the
  workspace is pre-release alpha; the payoff is **zero migration debt** carried
  forward. The cost is that each consumption-contract change is **atomic across
  `igloo-ui` + all three clients** (a client cannot lag), landing as one coordinated
  set of submodule commits + parent pointer bump rather than a gradual rollout.

## Implementation Rule

Remediation follows the **"Shared-UI consolidation (audit 2026-06-19)"** roadmap in
[`dev/BACKLOG.md`](../BACKLOG.md), each item gated on this ADR being **Accepted**.
Fixed sequencing constraints:

- **Each step is a hard cut.** The old path is deleted in the same change as its
  replacement; reviewers reject any deprecation alias, compat shim, dual path, or
  "legacy" fallback introduced "to be safe." Done means the old code is gone.
- **P0 lands first — the consumption contract (a)+(b), atomically.** Shared
  resolution config + `igloo-ui` Tailwind preset + each client's `tailwind.config`;
  **delete** the CSS→`dist` alias, `igloo-ui`'s `dist` build + prebuilt artifact,
  and the `make igloo-ui-styles` / `igloo-ui-watch` targets. Because no client may
  lag onto the old prebuilt path, this lands as one coordinated change across
  `igloo-ui` + pwa + chrome + home (+ parent pointer bump). It removes the root
  footgun and must precede any visual convergence (everything else is judged by a
  now-consistent CSS pipeline).
- **The shared visual seam (c) precedes the shell/component convergence (d)** — it
  is the instrument that verifies per-client parity during the (d) migration; each
  (d) change is validated via the unified visual harness (ADR-013 (d)), rendering
  the seeded dashboard per client.
- The `OperatorDashboardTabs` `testId` addition precedes the pwa nav retirement; the
  `Alert` API additions precede the inline-alert migration; the `Checkbox` primitive
  precedes the toggle retirement.
- The adapter lifts (e) and the `DesktopAppShell` deletion are P2 cleanup, after the
  consumption contract and visual seam are in place.
- Parity is verified by rendering the **seeded** dashboard per client (the (c)
  seam), never inferred from one client's screenshot.

Roadmap scope at a glance (full detail in the BACKLOG): **P0** = the consumption
contract (resolution + preset, footgun removal); **P1** = the shared visual seam +
the shell/nav/`Checkbox`/`Alert` convergence; **P2** = adapter lifts + dead-code
removal + docs. This ADR is satisfied when the P0 items merge and P1/P2 are
unblocked.
