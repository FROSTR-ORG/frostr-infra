# Hand-off: ADR-014 P2 — shared-UI cleanup

> **Read this first.** This is the entry point for continuing the ADR-014 P2 work in a fresh session. Everything you need to resume is here; you should not need the prior conversation.

_Last updated: 2026-06-20._

## TL;DR

ADR-014 ("unified shared-UI consumption") makes the three FROSTR clients (`igloo-pwa`, `igloo-chrome`, `igloo-home`) genuinely share one UI surface. **P0 (consumption contract) and all of P1 (visual seam + home fix, nav, Checkbox, Alert) are DONE and landed on `dev`.** What remains is **P2** — low-stakes internal cleanup: (1) lift the *accidentally* duplicated view-model helpers into the shared layer; (2) delete the dead `DesktopAppShell`. Plus a handful of small backlogged follow-ups. `make verify` is green; nothing is pushed.

## The user

cmdruid (Scott), the FROSTR maintainer — senior engineer, works across the Rust core and the TS clients. Strong, explicit standards to honor:
- **Hard cut / zero tech debt.** Delete the old path in the same change — no deprecation aliases, compat shims, dual code paths, or dead stubs. He will call out left-behind debt.
- **Stays on `dev`.** He integrates himself; do not push or open PRs unless he asks. He runs his own refresh/merge.
- **Control-oriented.** Surface findings and genuine forks rather than burying them; recommend, then proceed.

## The project

`frostr-infra` is the coordinating workspace: a Rust signing core (`bifrost-rs`) wrapped by TS `igloo-*` clients, with git submodules under `repos/`. The shared UI lives in `repos/igloo-ui`; shared runtime contracts in `repos/igloo-shared`. The clients are **independent npm packages, not a workspace** (no hoisting). As of P0, **`igloo-ui` is consumed all-source** (JS + CSS) via a shared Tailwind preset — there is no `igloo-ui/dist` and no igloo-ui build. The decision record is **`dev/adrs/ADR-014-unified-shared-ui-consumption.md`** (Accepted); the supporting audit (with the view-model duplication matrix you'll need for P2) is **`dev/docs/UI-AUDIT.md`**.

## What's been done (this is all on `dev`)

Shipped via the submodule-commit-then-pointer-bump flow. Parent commits `88c3f4a..cca8f33`:
- **P0 — consumption contract.** All clients resolve igloo-ui JS+CSS from source via a shared `igloo-ui/tailwind.preset.js`; deleted igloo-ui's `dist` build + `esbuild` dep + CSS→dist aliases + the `make igloo-ui-styles`/`igloo-ui-watch` band-aids + orphaned build refs in the test harness.
- **P1c — shared visual seam + home fix.** Added `igloo-shared/testing/dev-fixtures` (canonical seeded `RuntimeStatusSummary`); pwa/chrome/home build their `dashboard-running` fixture from it. **Fixed home** — its dashboard was stuck on "Starting signer…/Loading…" because its fixture seeded a malformed `runtime_status` with no `peers[]`; now renders the running dashboard.
- **chrome local-typecheck P0 regression** — fixed by aligning chrome's `@types/react`/`csstype` to igloo-ui's versions (all-source consumption surfaced a version skew).
- **P1d nav** — pwa retired its bespoke `igloo-dashboard-nav` for the shared `OperatorDashboardTabs` (home/chrome already used it). pwa now renders the same boxed tabs below the header.
- **P1d Checkbox + Alert** — added a shared `Checkbox` primitive (igloo-ui), migrated 5 toggles (pwa ×3, home ×2); routed 8 inline alert `<div>`s through the shared `Alert` (home ×2 fixing the undefined `igloo-shell-alert` class; chrome ×6). `Alert` needed **no API change**.

## Repo state (baseline you're resuming from)

- Branch: **`dev`** (parent + every submodule). Nothing pushed.
- `make verify` → **green** (`{"ok":true,"exitCode":0}`, `.tmp/agent/verify.json`). It's the canonical gate (guards + typecheck + `@fast` e2e).
- Working tree: **clean except `dev/audit/`** — a *concurrent* "anti-slop front-end audit" run that is **NOT ours** (modified `TASKS.md`/`NOTES.md` + untracked `dev/audit/findings/*`). **Leave it untouched, and never `git add -A`** — stage pointer bumps explicitly (`git add repos/igloo-ui repos/...`) so that work stays out of our commits.
- Submodule HEADs: igloo-ui `576b35c` · igloo-shared `a765fee` · igloo-pwa `9f79aa7` · igloo-home `daf4498` · igloo-chrome `3d0f36a`.

## What's pending (P2 — priority order)

1. **Lift the accidental view-model duplicates** (ADR-014 (e); `dev/BACKLOG.md` P2 item; matrix in `dev/docs/UI-AUDIT.md` §"Seam 5"):
   - `toDashboardKey` (hex→npub/hex display) is an **identical** copy in `repos/igloo-pwa/src/lib/dashboard-view.ts` and `repos/igloo-chrome/src/lib/dashboard-view.ts` → lift to shared, delete both local copies.
   - A single `buildPendingOperationRows` (pwa `App.tsx`, chrome `Signer.tsx`, home `lib/dashboard-view.ts` each have a variant drifting only on timestamp formatting) → one shared builder.
   - Adopt the **already-exported-but-unused** `runtimePeerPermissionStatesToPolicyDashboardView` (in igloo-ui's runtime-view-model adapters).
   - **Keep host-specific glue local** — `parseRuntimeStatus` (home Tauri IPC), `deriveRuntimePresentation` (chrome MV3 activation), `normalizeStoredPeerPolicy` (chrome storage), and the log-line→event-row fallback (pwa/home). These differ because the runtime state shapes genuinely differ; do NOT force them into one union.
2. **Delete dead `DesktopAppShell`** (ADR-014 (d)) — `repos/igloo-ui/src/components/flows/DesktopAppShell.tsx`, exported but **0 consumers** (verified during the audit). Also re-evaluate `ManagedProfilesPanel` (also unused — confirm zero consumers with a grep before deleting).
3. **Backlogged follow-ups** (lower priority, all in `dev/BACKLOG.md` under "Shared-UI consolidation"): migrate pwa's recovery "Encrypt Key" toggle (distinct `igloo-recover-encrypt-toggle` class — needs a `Checkbox` variant whose row class *replaces* the base, since current `rowClassName` is additive); unify the dev-scenario param/scenario-names (`?__frostr_dev=` vs home's `?__igloo_visual=`); extend the shared fixture to `dashboard-stopped`/`onboarding`; the "Guard the consumption contract" `test:guards` check; the dev-scenario-seams-ship-in-prod tree-shaking item; reconcile the two parallel UI audits; dev-fixtures polish nits; showcase `@fast` tag/gate mismatch.

## Critical considerations (the WHY)

- **Execute with the same rigor as P0/P1.** This session used `superpowers:writing-plans` → `superpowers:subagent-driven-development`: one implementer subagent per task, a spec+quality review subagent after each, `make verify` + pointer bump at the end. The ledger lives at `.superpowers/sdd/progress.md` (git-ignored scratch). For P2 (small, mechanical), a lighter touch is fine, but keep the per-task review gate — it caught real issues (e.g. the dist-deletion test-harness blast radius, the @types skew).
- **Submodule workflow:** commit *inside* each submodule first, then bump the parent pointer (`git add repos/<name>` explicitly, then commit; or `make bump-pointers` — but that may sweep the `dev/audit` work, so prefer explicit staging here).
- **Test-location gotchas:** `igloo-ui` tests live in `repos/igloo-ui/test/**/*.test.tsx` (NOT co-located) and its test script is `test`. `igloo-shared` tests live in `src/**` and its script is `test:unit`. Getting this wrong = the test silently doesn't run.
- **`make verify` is authoritative;** per-client local `npm run typecheck` can differ from the gate's tsconfig (that's how the chrome @types skew hid). If you touch deps, check both.
- **P2 (e) is judgment work, not pure mechanics:** the audit already separated *accidental* duplication (lift) from *essential* host-specific glue (keep). Re-confirm against `dev/docs/UI-AUDIT.md` before lifting — don't over-share.

## Pointers

- `dev/adrs/ADR-014-unified-shared-ui-consumption.md` — the decision (P2 = decisions (d) DesktopAppShell + (e) adapters).
- `dev/docs/UI-AUDIT.md` — the audit; §Seam 5 has the view-model duplication matrix (lift-vs-keep).
- `dev/BACKLOG.md` — "Shared-UI consolidation (audit 2026-06-19)" section: P2 items + all follow-ups, with completed P0/P1 items checked off.
- `dev/plans/` — the P0/P1c/P1d plans (templates for how P2 plans should look).
- `AGENTS.md` (root) — workspace routing, command surface, submodule workflow, gotchas.

## Suggested first action

Write a P2 implementation plan (`dev/plans/p2-view-model-lift-and-desktopappshell-2026-06-20.md`) covering both P2 items, grounding the view-model lift in `dev/docs/UI-AUDIT.md` §Seam 5 (lift `toDashboardKey` + `buildPendingOperationRows`, adopt `runtimePeerPermissionStatesToPolicyDashboardView`, keep host glue local) and a grep-confirmed deletion of `DesktopAppShell`/`ManagedProfilesPanel`; then execute it subagent-driven with a review gate per task and `make verify` before the pointer bump.
