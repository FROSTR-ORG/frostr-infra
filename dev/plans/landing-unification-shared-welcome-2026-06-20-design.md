# Design: Unified landing across chrome / pwa / home (shared Welcome heroes)

_Status: Design approved 2026-06-20 — pending implementation plan._
_Relates to: ADR-014 (unified shared-UI consumption). Extends the shared-UI
consolidation to the landing/welcome surface._

## Problem

The three FROSTR clients render **divergent landing screens**, only one of which
is the current design:

| App | Landing today |
|-----|---------------|
| `igloo-pwa` | NEW shared `WelcomeEntryHero` / `WelcomeReturningHero` + `WelcomeUnlockModal` / `WelcomeDeleteModal` |
| `igloo-home` | OLD `StoredProfilesLandingCard` + bespoke 4× `HostEntryTile` grid (`App.tsx`, `activeView==='landing'`) |
| `igloo-chrome` | OLD `StoredProfilesLandingCard` (onboarding-centric, `pages/Onboarding.tsx`) |

`igloo-home` and `igloo-chrome` were never migrated to the shared welcome heroes
that `igloo-pwa` already uses. The divergence persisted across prior remediation
sessions because those converged the **dashboard** (nav, Checkbox, Alert) and
verified via the `dashboard-running` screenshot, which never renders the landing
(`landing` is a different `activeView`). Root cause: not a build/caching/
resolution problem — the source genuinely composes an older landing in two of
the three apps.

### Why the shared heroes don't yet serve all three

`WelcomeEntryHero` / `WelcomeReturningHero` (in
`repos/igloo-ui/src/components/flows/HostShell.tsx`) are ~80% host-agnostic
(callback-driven, `logoSrc` configurable) but bake in pwa specifics:

- Title hardcoded `"Igloo Web"` (lines 31, 136).
- Taglines hardcoded (`"Split your Nostr key. Sign from anywhere."`,
  `"Welcome back."`).
- `PublicFocusFooter` (Globe / Docs / GitHub / Feather) auto-rendered — web-app
  chrome that doesn't fit a desktop app or an extension.
- Entry/secondary actions hardcoded to pwa's set (Generate Keyset / Import /
  Onboard), with the `CRITICAL_E2E_TEST_IDS` fixed on those buttons.

The apps also have genuinely different capabilities:

| Action | pwa | home | chrome |
|--------|-----|------|--------|
| Generate / Rotate keyset | ✅ | ✅ (Create/Rotate) | ❌ (thin host) |
| Import / Load profile | ✅ | ✅ | ✅ |
| Recover group key | ✅ (per-profile) | ✅ | ❌ |
| Onboard device | ✅ | ✅ | ✅ |
| Stored-profile unlock/delete | ✅ | ✅ | ✅ |

## Goal

One shared `WelcomeEntryHero` / `WelcomeReturningHero` family in `igloo-ui` with
**identical layout / styling / behavior** across all three apps, where title,
tagline, footer, and the available action set are **parameterized** so each app
shows host-appropriate content. (Chosen over pixel-identical — which would force
chrome/home into capabilities they don't have — and over loose
"shared-primitives-only" composition.)

## Approach (chosen): generalize the existing heroes in place

Generalize the proven pwa components rather than introduce a new wrapper
abstraction (YAGNI on a `<HostWelcome>` that would absorb each app's view-state).
**No host-specific defaults remain in the shared component** — every app passes
explicit config, so the shared layer is genuinely neutral.

### Shared component API (`igloo-ui/src/components/flows/HostShell.tsx`)

`WelcomeEntryHero` — new/changed props:

- `productLabel: string` — replaces hardcoded `"Igloo Web"` heading.
- `tagline?: string` — replaces hardcoded entry tagline.
- `primaryAction: { label; description; onAction; testId?; infoTooltip? }` —
  the single highlighted action (pwa/home: Generate/Create Keyset; chrome:
  Onboard or Import, since it can't generate).
- `secondaryActions: Array<{ id; label; onAction; testId? }>` — the "or …" row
  (variable length per host).
- `footer?: ReactNode` — defaults to none; pwa passes `<PublicFocusFooter/>`.

`WelcomeReturningHero` — new/changed props:

- Same `productLabel` / `tagline` / `footer` as entry.
- `secondaryActions: Array<{ id; label; onAction; testId? }>` — replaces the
  hardcoded Generate/Import/Onboard row.
- Per-profile capability flags on `WelcomeReturningProfileModel` (or alongside
  it): `canRotate`, `canRecover`, `canDelete` — the ⋮ menu renders only the
  items the host supports (chrome omits Rotate/Recover).

`PublicFocusFooter` stays exported but is no longer auto-rendered — it becomes an
explicit opt-in passed via `footer`.

**E2E test-id preservation:** the `CRITICAL_E2E_TEST_IDS` currently hardcoded on
the action buttons are carried by the action descriptors (`testId`) so
`igloo-pwa`'s welcome e2e (which targets `welcomeEntryGenerate`,
`welcomeEntryImport`, `welcomeEntryOnboard`, `welcomeProfile*`) stays green.

### Per-app consumption

- **pwa** — light refactor to the new prop shape; visual/behavior unchanged.
  `productLabel="Igloo Web"`, `footer={<PublicFocusFooter/>}`. Action descriptors
  carry the existing critical test ids.
- **home** — replace the whole `activeView==='landing'` block (`ContentCard` +
  `StoredProfilesLandingCard` + 4× `HostEntryTile`) with `WelcomeEntryHero`
  (no stored profiles) / `WelcomeReturningHero` (has profiles) +
  `WelcomeUnlockModal` + `WelcomeDeleteModal`, wired to home's native Tauri flows
  (load / create-rotate / recover / onboard / delete). `productLabel="Igloo
  Home"`, footer off, add the missing `logoSrc` on `AppHeader`. Entry primary =
  "Create / Rotate Keyset"; secondary = Load, Recover, Onboard. Unlock moves from
  the inline-passphrase pattern to the shared `WelcomeUnlockModal`.
- **chrome** — replace `StoredProfilesLandingCard` in `pages/Onboarding.tsx` with
  `WelcomeReturningHero` (stored profiles) / `WelcomeEntryHero` (import/onboard
  path) + unlock modal, wired to chrome flows. No generate / no recover; primary
  = Onboard New Device, secondary = Import Existing Device. `productLabel="Igloo"`.
  Verify fit in the narrow
  extension options-page width; add a `compact` layout variant **only if** the
  screenshot shows the default hero doesn't fit.

### Hard-cut cleanup (zero tech debt)

After home and chrome are migrated, `StoredProfilesLandingCard` and
`HostEntryTile` have **zero consumers** (confirmed: only home `App.tsx` +
chrome `Onboarding.tsx` today). Delete both from `HostShell.tsx` and the
`igloo-ui` barrel in the same change — no deprecation aliases or dead exports.
Re-grep to confirm zero consumers immediately before deleting.

## Verification

- Extend the agent screenshot harness to capture the landing/welcome state for
  all three clients; confirm visual convergence (centered hero, profile-unlock
  card, host-appropriate actions, no old grid).
- `make verify` — guards + typecheck + `@fast` e2e. The pwa welcome e2e
  (critical test ids) must stay green; this is the regression guard for the
  shared-component refactor.
- `npm --prefix test run test:guards` — shared-UI change touches the consumption
  contract surface.
- Per-client typecheck for home + chrome (`make igloo-home-typecheck`,
  `make igloo-chrome-typecheck`) — the `make verify` tsconfig can differ from
  per-client tsconfig (how an earlier `@types` skew once hid).

## Submodule / workflow notes

- Commit **inside each submodule first** (igloo-ui, then home/chrome/pwa
  consumers), then bump the parent pointer with explicit staging
  (`git add repos/<name>`) — **not** `git add -A` and **not** blanket
  `make bump-pointers`, because the parent working tree carries an unrelated,
  not-ours `dev/audit/` work stream that must stay out of these commits.
- Stay on `dev`; do not push or open PRs — the maintainer integrates himself.

## Out of scope

- Dashboard, settings, and in-flow (create/recover/onboard step) screens — only
  the landing/welcome entry surface.
- `igloo-ui`'s own `HostShell.tsx` internal `StoredProfilesLandingCard` reference
  beyond removing the now-dead export.
- The minor dashboard header/banner/wording deltas between home and pwa (logo
  excepted — added here since we touch home's `AppHeader`).
