# Shared-UI Consumption Audit (2026-06-19)

How much of each client's UI actually comes from the shared `igloo-ui` /
`igloo-shared` libraries, versus app-local "competing implementations" — and
where the **consumption and tooling** of that shared UI diverge per client.

Design direction is fixed by
[ADR-014](../adrs/ADR-014-unified-shared-ui-consumption.md). Remediation is
sequenced in [`BACKLOG.md`](../BACKLOG.md). This doc is the findings record; the
ADR is the target.

## How this started

`igloo-home` *looked* stale next to `igloo-pwa` in a side-by-side screenshot. The
forensic finding: **not** a misapplied redesign. The Paper signer-dashboard
redesign lives correctly in `igloo-ui` (`fcc0592`, +700 lines
`OperatorSignerPanel.tsx` / +794 lines `styles.css`); `igloo-home` renders the
**same** `OperatorSignerPanel` (`App.tsx:1581,1894`) that `igloo-pwa` does
(`App.tsx:1386`); all clients source-alias the **same** `repos/igloo-ui/src`
checkout, so no client can carry a newer shared UI than another. All five
submodule trees were clean; `igloo-pwa/src` carries **no** local component files
(only `App.tsx` / `main.tsx` / `store.tsx` / `lib/`). Recent `igloo-pwa` commits
*remove* local UI into shared ("Use the shared `buildPeerReadinessRows`; drop the
duplicated merge"; "Drop pwa-local wire mirrors").

What actually made Home look stale: the screenshot harness could only reach Home's
**"Starting signer… / Loading…"** state, because the seeded-running-dashboard dev
seam (`?__frostr_dev=`, `pwa/src/lib/dev-scenario.ts`, pwa commit `2a869f4`) exists
**only in pwa**. We compared pwa's *running* dashboard against home's *loading*
screen.

Conclusion: the shared-UI architecture is sound and ~70–95% adopted. The trouble is
**inconsistent consumption and drifting per-app tooling**, not the architecture.

## Adoption per client

| Client | Shared UI | igloo-ui symbols | Own Tailwind build? | Local CSS |
|---|---|---|---|---|
| `igloo-home` | ~95% | ~40 | no (consumes prebuilt `dist`) | `index.css` empty |
| `igloo-pwa` | ~85% | ~47 | no (consumes prebuilt `dist`) | 34 lines (nav classes) |
| `igloo-chrome` | ~70–75% | ~34 | **yes** (own `tailwind.config.ts`) | imports only |

All three import the same core panels (`OperatorSignerPanel`,
`OperatorPermissionsPanel`, `OperatorSettingsPanel`, dashboard state screens) and
the same shared builders (`buildPeerReadinessRows`, `buildPendingApprovalRows`,
`deriveDashboardState`).

## Seam 1 — Consumption asymmetry (root footgun)

Every client's Vite config resolves `igloo-ui` **JS from `../igloo-ui/src`**
(live) but **CSS from `../igloo-ui/dist/styles.css`** (a prebuilt Tailwind
artifact). Consequence: edit a component → live via HMR; edit its styles → stale
until `igloo-ui`'s `dist` is rebuilt. This is the single mechanism behind the
original "stale UI" confusion, and the reason a `make igloo-ui-styles` prerequisite
band-aid was added to the home dev targets.

## Seam 2 — Three CSS pipelines

- `igloo-pwa`, `igloo-home`: consume prebuilt `igloo-ui/dist/styles.css` (Vite
  alias → `dist`). No local Tailwind.
- `igloo-chrome`: **self-builds** Tailwind (`tailwind.config.ts` scanning
  `./src` + `../igloo-ui/src`; `scripts/build.mjs` inlines `igloo-ui` CSS then runs
  PostCSS/Tailwind).
- `igloo-ui` itself: `tailwindcss -c tailwind.config.js -i src/styles.css -o
  dist/styles.css`, content scan = `igloo-ui/src` **only**.

Drift risk (concrete): an arbitrary utility used by pwa/home but not by any
`igloo-ui` component (e.g. `min-h-[112px]`, `space-y-6`) is **not** in the prebuilt
`dist` and silently fails to render; chrome, which re-scans `igloo-ui/src`, can get
classes the others can't.

## Seam 3 — Per-app dev/visual seam

`igloo-pwa` has `lib/dev-scenario.ts` + `?__frostr_dev=<scenario>` (gated behind
`import.meta.env.DEV`) to seed a running dashboard for the screenshot harness.
`igloo-home` and `igloo-chrome` have no equivalent — only real runtime-snapshot
consumption. Result: `make screenshot CLIENT=home` cannot reach the running
dashboard. (Aligns with ADR-013's in-memory-snapshot + unified-visual-harness
decisions, which this gap violates on the app side.)

## Seam 4 — Competing app-level UI

### Dashboard navigation — pwa is the outlier
- `igloo-chrome` → shared `OperatorDashboardTabs` (`Dashboard.tsx:71`).
- `igloo-home` → shared `OperatorDashboardTabs` (`App.tsx:1855`).
- `igloo-pwa` → local `<nav className="igloo-dashboard-nav">` (`App.tsx:1313–1340`)
  + 30 lines of bespoke CSS (`index.css:4–34`). `OperatorDashboardTabs` covers it
  except per-tab `testId` override (pwa uses `CRITICAL_E2E_TEST_IDS.*`) and the
  in-header placement — both small.

### Unused shared shell
`igloo-ui` exports `DesktopAppShell` (and `ManagedProfilesPanel`) with **zero
consumers**. The canonical shell all three already converge on is
`PageLayout` + `AppHeader` + `OperatorDashboardTabs`.

### `AppHeader` config divergence
All three use the shared `AppHeader`; the visible header difference is **prop
config**: pwa passes a logo + the nav in its `actions` slot; home passes
`taskLabel="Igloo Home"` + profile; chrome passes badge actions. The `actions`
slot is being used for navigation (pwa) vs status (chrome/home).

### No shared Checkbox/Toggle → 6 hand-rolled
`igloo-ui` exports no checkbox/toggle/switch. Hand-rolled `<input type="checkbox">`
wrapped in `igloo-toggle-row` / `igloo-settings-grid`: pwa `App.tsx:424,1564,1575,
1587`; home `App.tsx:476,487`. The wrapper classes are defined once (in
`igloo-ui/src/styles.css:3745+`), so only the control is duplicated.

### Inline alerts instead of shared `Alert`
`igloo-ui` exports `Alert` (`tone: default|danger|warning|success`). ~24 inline
colored-box sites reimplement it: pwa `igloo-task-banner` (educational, OK) + 2
`Alert` (OK); chrome scattered red/amber/cyan boxes (`Onboarding.tsx:271,456,462`,
`popup.tsx:39,63`, `runtime-state-sections.tsx:113`); home `igloo-shell-alert`
(`App.tsx:1416,1577` — references an **undefined** CSS class) + `igloo-task-banner`.
Alert API gaps to fill first: first-class `info` tone, optional `dismissible`,
title-less mode. Note: status **badges** and code/data boxes are *not* alerts and
should not fold into `Alert`.

## Seam 5 — View-model duplication (partly essential)

Shared builders exist and are used by all clients: `buildPeerReadinessRows`,
`buildPendingApprovalRows`, `deriveDashboardState`,
`observabilityEventsToEventRows`. One adapter exists but is **unused**:
`runtimePeerPermissionStatesToPolicyDashboardView`.

**Accidental duplication (lift to shared):**
- `toDashboardKey()` (hex → npub/hex display model) — **identical** copies in
  `pwa/src/lib/dashboard-view.ts` and `chrome/src/lib/dashboard-view.ts`.
- pending-operations → row model — three local variants (pwa `App.tsx:145`, chrome
  `Signer.tsx:166`, home `lib/dashboard-view.ts:52`), drifting only on timestamp
  formatting.

**Essential, keep local** (genuinely different runtime shapes — browser bridge vs
MV3 messaging vs Tauri IPC): `parseRuntimeStatus` (home IPC boundary),
`deriveRuntimePresentation` (chrome MV3 activation lifecycle),
`normalizeStoredPeerPolicy` (chrome storage), pwa profile-package JSON parsing,
log-line→event-row fallback (pwa/home receive unstructured log lines; chrome
receives structured `ObservabilityEvent`).

## The throughline

Every seam above is **"make it the same,"** not "remove a capability." The three
hosts (PWA, MV3 extension, Tauri desktop) are genuinely different and that
boundary is load-bearing; the shared layer is the `igloo-ui` component surface and
the `igloo-shared` contracts. The fix is uniform consumption + retiring the
app-local UI that predates the shared components — see ADR-014.
