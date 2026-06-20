# PWA Dashboard Nav Convergence (P1d-nav) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire igloo-pwa's bespoke dashboard nav (`renderDashboardNav()` + `.igloo-dashboard-nav` CSS) in favour of the shared `OperatorDashboardTabs` that home and chrome already use — so all three clients render the same dashboard nav.

**Architecture:** pwa-only change. `OperatorDashboardTabs` (igloo-ui) needs NO modification — it already emits the `dashboard-tab-{signer,permissions,settings}` test-ids pwa's E2E specs depend on. pwa moves the nav out of `AppHeader`'s `actions` slot to a tabs-below-header layout (matching home/chrome), wires its existing dirty-settings guard (`requestDashboardTab`) to `onChangeTab`, and deletes the local nav + CSS.

**Tech Stack:** TypeScript, React, igloo-ui (`OperatorDashboardTabs`), Playwright (`test/igloo-pwa` specs).

## Global Constraints

- **No igloo-ui change.** `OperatorDashboardTabs` already produces the right test-ids and is used by home/chrome; do not modify it. (If a genuine gap appears, STOP and report — don't fork the component.)
- **Hard cut:** delete `renderDashboardNav()` and the `.igloo-dashboard-nav*` CSS outright — no dead local nav left behind.
- **Preserve the dirty-settings guard:** leaving the Settings tab with unsaved changes must still park the pending tab + show the `ConfirmDialog` (the existing `requestDashboardTab` behaviour). Wire it as `onChangeTab`.
- **E2E test-ids must not break:** the rendered tabs must keep `data-testid="dashboard-tab-signer|permissions|settings"` (which `OperatorDashboardTabs` emits by default). The pwa specs in `test/igloo-pwa/support/{pages,ui}.ts` (`openTab`, `expectNavLinks`, `expectPwaDashboard`, `openPwaRotateShare`) depend on these.
- **Parity:** match home's tab config — first tab label `Signer` (home/chrome use `Signer`, not pwa's old `Dashboard`), descriptions `runtime console` / `peer policies` / `operator controls`, no icons (home omits them).
- pwa is a sibling submodule consumed all-source; commit inside `repos/igloo-pwa` then bump the parent pointer.

---

## Current state (verified 2026-06-19)

- `repos/igloo-ui/src/components/flows/OperatorDashboardTabs.tsx`: props `{ tabs: { key:'signer'|'permissions'|'settings', label, icon?, description }[], activeTab, onChangeTab }`; renders `data-testid={`dashboard-tab-${tab.key}`}`. Used by home (`App.tsx:1855`) + chrome (`Dashboard.tsx:71`).
- `repos/igloo-pwa/src/App.tsx`:
  - `renderDashboardNav()` at **1313-1340** (the local `<nav className="igloo-dashboard-nav">`; tab labels `Dashboard`/`Permissions`/`Settings`; test-ids from `CRITICAL_E2E_TEST_IDS.dashboardTab*`; `onClick={() => requestDashboardTab(item.key)}`).
  - Rendered via `actions={renderDashboardNav()}` on `AppHeader` at **~1616**.
  - The guard `requestDashboardTab` at **572-581** (if leaving `settings` with `settingsDirty`, park in `pendingSettingsNav` + show `ConfirmDialog` at ~1665-1678; else `store.setDashboardTab(tab)`).
  - `store.activeDashboardTab` is `'signer'|'permissions'|'settings'`.
  - The dashboard body is rendered by `renderDashboard()` (the per-tab panels switch on `store.activeDashboardTab`).
- `repos/igloo-pwa/src/index.css:6-36`: the `.igloo-dashboard-nav` / `.igloo-dashboard-nav-link` rules (delete).
- `CRITICAL_E2E_TEST_IDS.dashboardTab{Signer,Permissions,Settings}` = `dashboard-tab-{signer,permissions,settings}` (igloo-ui `src/lib/e2e-test-ids.ts:79-81`).
- pwa fast specs use these via `test/igloo-pwa/support/pages.ts` (`expectDashboard:281`, `openTab:283-291`, `expectNavLinks:318-321`) and `support/ui.ts` (`openPwaRotateShare:135`, `expectPwaDashboard:159-163`).

---

## File structure

- `repos/igloo-pwa/src/App.tsx` — **modify** (delete `renderDashboardNav`; remove it from `AppHeader.actions`; render `OperatorDashboardTabs` at the top of the dashboard body wired to `requestDashboardTab`).
- `repos/igloo-pwa/src/index.css` — **modify** (delete the `.igloo-dashboard-nav*` rules).
- Parent — pointer bump.

---

### Task 1: pwa adopts OperatorDashboardTabs

**Files:**
- Modify: `repos/igloo-pwa/src/App.tsx`
- Modify: `repos/igloo-pwa/src/index.css`

**Interfaces:**
- Consumes: `OperatorDashboardTabs` from `igloo-ui` (already imported in pwa `App.tsx`; if not, add it to the existing `igloo-ui` import).

- [ ] **Step 1: Confirm no pwa spec asserts the old `Dashboard` tab label text** (we're changing it to `Signer`):

Run: `grep -rn "getByText('Dashboard')\|getByRole('tab', { name: 'Dashboard'\|>Dashboard<" test/igloo-pwa`
Expected: no matches that refer to the nav tab (the specs key off test-ids, not the label). If a real label assertion exists, update it to `Signer` as part of this task.

- [ ] **Step 2: Add `OperatorDashboardTabs` to pwa's dashboard body.** In `repos/igloo-pwa/src/App.tsx`, inside `renderDashboard()` (the function that renders the dashboard tab panels), render the tabs as the first child, above the per-tab panels:

```tsx
<OperatorDashboardTabs
  tabs={[
    { key: 'signer', label: 'Signer', description: 'runtime console' },
    { key: 'permissions', label: 'Permissions', description: 'peer policies' },
    { key: 'settings', label: 'Settings', description: 'operator controls' },
  ]}
  activeTab={store.activeDashboardTab}
  onChangeTab={requestDashboardTab}
/>
```

  `requestDashboardTab` already has the signature `(tab: 'signer'|'permissions'|'settings') => void`, matching `onChangeTab`. Ensure `OperatorDashboardTabs` is in the `igloo-ui` import block at the top of `App.tsx`.

- [ ] **Step 3: Remove the local nav from the header.** Delete `actions={renderDashboardNav()}` from the `AppHeader` props (~line 1616). If `AppHeader` then has no `actions`, drop the prop entirely.

- [ ] **Step 4: Delete `renderDashboardNav()`** (the whole function, ~lines 1313-1340) from `App.tsx`. If `CRITICAL_E2E_TEST_IDS` is now unused in `App.tsx`, remove it from the imports (check with a grep first).

- [ ] **Step 5: Delete the local nav CSS.** Remove the `.igloo-dashboard-nav`, `.igloo-dashboard-nav-link`, `.igloo-dashboard-nav-link:hover`, and `.igloo-dashboard-nav-link.is-active` rules (and their comment) from `repos/igloo-pwa/src/index.css`.

- [ ] **Step 6: Typecheck + build.**

Run: `npm --prefix repos/igloo-pwa run build`
Expected: succeeds (tsc clean). Then `grep -n "igloo-dashboard-nav\|renderDashboardNav" repos/igloo-pwa/src/App.tsx repos/igloo-pwa/src/index.css` → no matches.

- [ ] **Step 7: Render check — the tabs render the same test-ids.**

Run: `make screenshot CLIENT=pwa STATE=dashboard-running`
Expected: `1 passed`; `.tmp/agent/dashboard-running.png` shows the dashboard with the boxed `OperatorDashboardTabs` (Signer / Permissions / Settings) BELOW the header (matching home/chrome), not the old inline pill nav in the header.

- [ ] **Step 8: E2E — the nav/tab specs still pass (test-id contract + guard).**

Run: `npm --prefix test run test:e2e:igloo-pwa:fast -- -g "dashboard|settings|permissions|nav"`
Expected: pass. These exercise `openTab` / `expectNavLinks` (the `dashboard-tab-*` test-ids) and the Settings tab. If any fail on a missing test-id, the tabs aren't emitting `dashboard-tab-${key}` — investigate before committing.

- [ ] **Step 9: Commit (inside submodule).**

```bash
git -C repos/igloo-pwa add src/App.tsx src/index.css
git -C repos/igloo-pwa commit -m "Adopt shared OperatorDashboardTabs; retire pwa-local dashboard nav + CSS (ADR-014 P1d)"
```

---

### Task 2: Verify + land

**Files:** parent pointer commit.

- [ ] **Step 1: Guard the dirty-settings behaviour still works.** With the dev server (or via an existing `@live`/`@fast` spec that edits Settings then switches tabs), confirm: editing a Settings field then clicking another tab parks the switch and shows the confirm dialog. If no spec covers it, do a manual `make igloo-pwa-dev` check: go to Settings, change the signer name, click Permissions → expect the confirm dialog, not an immediate switch.

- [ ] **Step 2: Gate.**

Run: `make verify`
Expected: exit 0.

- [ ] **Step 3: Bump the pointer.**

Run: `git -C repos/igloo-pwa status --short` → clean. Then:
```bash
git add repos/igloo-pwa
git commit -m "Bump pointer: pwa adopts shared OperatorDashboardTabs (ADR-014 P1d nav)"
```
(Stage only `repos/igloo-pwa` — keep the concurrent `dev/audit` work out.)

- [ ] **Step 4: Mark the BACKLOG item done** — the `P1 — OperatorDashboardTabs ... retire pwa's local nav` item — and commit `dev/BACKLOG.md`.

---

## Self-Review

**Spec coverage (ADR-014 d, nav):** pwa retires local nav for `OperatorDashboardTabs` → Task 1. Test-ids preserved (component default matches) → Global Constraints + Task 1 Step 8. Guard preserved → Task 1 Step 2 + Task 2 Step 1. Layout moved below header → Task 1 Steps 2-3. ✓

**Placeholder scan:** none — the `OperatorDashboardTabs` invocation is given in full; every step has exact file:line + commands.

**Type consistency:** `requestDashboardTab: (tab:'signer'|'permissions'|'settings')=>void` matches `OperatorDashboardTabs`' `onChangeTab: (tab: OperatorDashboardTab)=>void`; `store.activeDashboardTab` matches `activeTab: OperatorDashboardTab`.

**Note:** chrome uses tab icons; home and (now) pwa don't. Aligning chrome to drop icons (or all three to add them) is a separate small parity follow-up, out of scope here.
