# Hand-off: chrome `@fast` red gate fixed + render-and-verify extended to chrome

_Last updated: 2026-06-17_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The two tasks the previous hand-off queued are **done**: the chrome
> `@fast` red gate is fixed and `make screenshot` now renders the chrome options
> page. `make verify` is **green** (pwa + chrome). All work is on `dev`
> (parent + the `igloo-chrome` submodule) and is **not yet committed or pushed**.

## TL;DR

The chrome `@fast` lane was red from 2026-06-16 Paper-restructure drift. Built a
chrome render-and-verify seam first (`make screenshot CLIENT=chrome`), used it to
*see* the restructured dashboard DOM, then modernized the stale smoke selectors.
Along the way the render tool surfaced a real bug — chrome's running dashboard
never showed live peers — which is also fixed. `make verify` green;
`.tmp/agent/verify.json` → `{"ok":true,"exitCode":0}`. The `@live` chrome
diagnostics test (touched by the bug fix) also passes.

## The user

`cmdruid` (git), the FROSTR maintainer — senior, terse, signal over ceremony,
decisive on scope. Broad authority for this alpha ("make our development cycle
fast and lean"). Prefers the **submodule-first → bump-pointer** commit flow
([[workflow-no-new-prs]]) and a follow-up harvest (`dev/BACKLOG.md`). Surface
genuine design forks with a recommendation. Commits/pushes happen **only when he
asks** — this session left the tree uncommitted pending his go-ahead.

## What shipped this session (uncommitted, on `dev`)

**igloo-chrome submodule** (`repos/igloo-chrome/`):
- `src/lib/dev-scenario.ts` (new) — `resolveDevScenario()` reads
  `?__frostr_dev=<scenario>` and returns an in-memory `ExtensionStateSnapshot`
  (`dashboard-running` / `dashboard-stopped` / `onboarding`). Mirrors the pwa /
  igloo-home seams; inert without the param, never writes storage.
- `src/lib/store.tsx` — bootstrap effect short-circuits the background fetch when
  a scenario is active; `loadRuntimeDiagnostics` returns an empty snapshot in
  scenario mode (no background round-trip).
- `src/pages/Signer.tsx` — **bug fix:** set `view.running: isSignerRunning`. It
  was never set, so a *running* chrome signer rendered the stopped Readiness /
  Next-Step cards instead of live peers / pending sections (mirrors igloo-pwa's
  `running` field). Surfaced by the new render tool.

**Parent repo:**
- `test/igloo-chrome/specs/agent-screenshot.spec.ts` (new, `@agent`) — opens
  `options.html?__frostr_dev=<state>` via the extension fixture, writes
  `.tmp/agent/chrome-<state>.{png,txt}` + `screenshot.json`.
- `test/igloo-chrome/specs/dashboard.spec.ts` — `@fast` smoke: replaced the stale
  `Pending Operations` heading assertion with cold-state `Start Signer` +
  Readiness copy; `@live` diagnostics: `sign-ready` → `~N ready` nonce pill +
  `SIGN capable` chip.
- `test/igloo-chrome/specs/profile-import.spec.ts` — `Chrome Import` is the header
  chip `Chrome Import (<id>)`; dropped `{ exact: true }`.
- `test/package.json` — `test:screenshot:{pwa,chrome}` scripts; **`@agent` added
  to the chrome `@fast` grep-invert** (it was missing, unlike pwa).
- `Makefile` — `make screenshot CLIENT=pwa|chrome`.
- `AGENTS.md`, `dev/BACKLOG.md` — docs + follow-ups.

## Validation run

- `make verify` → green (`.tmp/agent/verify.json` `ok:true`).
- `make screenshot CLIENT=chrome STATE=dashboard-running` / `dashboard-stopped` →
  rendered, artifacts in `.tmp/agent/`.
- `@live` `signer tab surfaces live nonce pool diagnostics` → 1 passed (57s).

## What's pending (priority order)

1. **Commit + push (needs the user's go-ahead).** Flow: commit the three
   `igloo-chrome` src files **inside the submodule first**, then
   `make bump-pointers MSG="…"` to record the moved pointer, then a parent commit
   for `test/` + `Makefile` + `package.json` + docs. Push `dev` when he wants.
2. **`chrome-pwa-pairing.spec.ts:248-249` stale `sign-ready` selectors**
   (`@cross-client`, no default lane). Same fix pattern as the `@live` diagnostics
   test; the `view.running` fix is the prerequisite. Needs a full two-client run to
   verify. Backlog has the detail (also: it still seeds legacy `PWA_STORAGE_KEY`).
3. **`make screenshot CLIENT=home`** — extend the render loop to igloo-home (it
   already has the `currentVisualScenario` seam). Backlog item.
4. Other tracked follow-ups: gate the dev-scenario seams behind a build flag
   (chrome has no `import.meta.env.DEV` — needs a define); enrich the running
   fixtures (empty pending/approvals/events); exempt pwa `@agent` spec's
   `getByTestId` from the selector contract; leaked `bifrost-devtools relay`
   processes.

## Critical considerations (the WHY)

- **The fork resolved itself to (a).** The render tool showed the *cold* dashboard
  renders Readiness / Next-Step cards, not a `Pending Operations` section — so fork
  (b) (restore heading roles in igloo-ui) wouldn't have fixed the cold smoke test.
  Modernizing selectors test-side was the only correct fix.
- **`view.running` is a real product fix, not just a test prop.** Without it a live
  chrome signer shows "Offline / Signing unavailable" — wrong. Confirmed against a
  live signer.
- **Chrome tests load the built `dist/`** (`IGLOO_CHROME_DIST_DIR`), and the chrome
  build sets `NODE_ENV=production` with no `import.meta.env.DEV`. The seam is gated
  purely on the URL param (like pwa/home), so it ships inert in prod — see the
  build-flag-gating backlog item.
- **Commit flow:** submodule first, then `make bump-pointers`, non-recursive only
  ([[workflow-no-new-prs]]). The chrome src changes are a submodule commit + pointer
  bump; the test/doc changes are parent-only.

## Suggested first action

Confirm with the user whether to commit + push. If yes: commit the three
`igloo-chrome` src files in the submodule, `make bump-pointers MSG="chrome:
dev-scenario seam + running-dashboard fix"`, then the parent test/doc commit, then
push `dev`. Otherwise pick up follow-up #2 (cross-client pairing selectors).
