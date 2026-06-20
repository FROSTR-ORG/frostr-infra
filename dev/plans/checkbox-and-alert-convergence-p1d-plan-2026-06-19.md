# Checkbox + Alert Convergence (P1d) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish ADR-014 P1 (d) component convergence: (1) add a shared `Checkbox` to igloo-ui and retire the 6 hand-rolled `<input type="checkbox">` toggles; (2) route the 8 genuine inline alert `<div>`s through the existing shared `Alert` (which also fixes home's broken, undefined `igloo-shell-alert` class).

**Architecture:** `Checkbox` is a new igloo-ui primitive that emits the existing `.igloo-toggle-row` markup (so the CSS contract is unchanged), replacing hand-rolled toggle markup in pwa + home. The `Alert` migration needs NO igloo-ui change — the current `tone` set (`danger`/`warning`/`default`) + optional `title` cover every site; it's a pure client-side swap of inline `<div>`s for `<Alert>`.

**Tech Stack:** TypeScript, React, igloo-ui primitives (`forwardRef` + `cn()` + explicit exports), Playwright `@agent`/`@fast` specs.

## Global Constraints

- **Hard cut:** delete the hand-rolled toggle markup and the inline alert `<div>`s outright — no parallel copies.
- **`Checkbox` reproduces the existing `.igloo-toggle-row` markup** (`<label class="igloo-toggle-row"><input type="checkbox"><span><strong>label</strong><small>description</small></span></label>`); do NOT change the CSS — the component just encapsulates the existing classes, so the rendered toggles look identical.
- **NO `Alert` API change.** The existing `Alert` (`tone: 'default'|'danger'|'warning'|'success'`, optional `title`, children) covers all 8 sites. Do not add `info`/`dismissible`/etc. — the investigation confirmed they're unneeded.
- **Migration is appearance-preserving** for the toggles and (for chrome) near-identical for alerts; home's `igloo-shell-alert` sites currently render UNSTYLED (the class is undefined) so those will visibly *improve* to real Alert styling.
- **Preserve test-ids:** pwa's auto-open toggle has `data-testid={CRITICAL_E2E_TEST_IDS.settingsAutoOpenToggle}` — `Checkbox` must forward `data-testid` to the `<input>`.
- **Out of scope:** status badges, code/data boxes, pwa's `igloo-task-banner` (educational), form-field validation errors, empty-state dashed boxes — these are NOT alerts; leave them.
- Submodule workflow: commit inside each submodule first; bump parent pointers last.

---

## Current state (verified 2026-06-19)

**Checkbox — 6 hand-rolled toggles, all the `<label …><input type="checkbox"><span><strong>…</strong><small>…</small></span></label>` shape:**
- pwa `App.tsx`: `~424` recovery "Encrypt Key" (wrapper class `igloo-recover-encrypt-toggle`, not `igloo-toggle-row`); `~1543` remember_browser_state; `~1554` auto_open_signer (`data-testid={CRITICAL_E2E_TEST_IDS.settingsAutoOpenToggle}`); `~1566` prefer_install_prompt. The 3 settings toggles are inside `<div className="igloo-settings-grid">`.
- home `App.tsx`: `~474` close_to_tray; `~485` launch_on_login (inside `igloo-settings-grid`).
- CSS `.igloo-toggle-row` (igloo-ui `src/styles.css:3127-3133, 3764-3791`): grid `auto 1fr`, border, 16px checkbox, `strong` 0.84rem, `small` 0.74rem. **Do not change.**
- Primitive pattern (`igloo-ui/src/components/ui/label.tsx`): `forwardRef`, `cn()` from `../../lib/utils`, named export + type export from `src/index.ts`, no `'use client'`.

**Alert — 8 genuine inline sites (no igloo-ui change):**
- `Alert` (`igloo-ui/src/components/ui/alert.tsx`): `tone?: 'default'|'danger'|'warning'|'success'` (default `danger`), `title?`, children; title-less already supported. Exported from `index.ts`.
- home `App.tsx:1416` `<div className="igloo-shell-alert">{error}</div>` → `<Alert tone="danger">` (the class is UNDEFINED → currently unstyled).
- home `App.tsx:1577` `<div className="igloo-shell-alert">Live onboarding tracking is paused…</div>` → `<Alert tone="default">`.
- chrome `popup.tsx:38` red error → `<Alert tone="danger">`; `popup.tsx:62` amber → `<Alert tone="warning">`.
- chrome `pages/Onboarding.tsx:270` red error → `danger`; `:455` red error → `danger`; `:461` amber "Last onboarding failure" + message → `<Alert title="Last onboarding failure" tone="warning">`.
- chrome `components/options/runtime-state-sections.tsx:112` amber "Snapshot error: …" → `<Alert title="Snapshot error" tone="warning">`.

---

## File structure

- `repos/igloo-ui/src/components/ui/checkbox.tsx` — **create**; export from `src/index.ts`; test `checkbox.test.tsx`.
- `repos/igloo-pwa/src/App.tsx` — **modify** (4 toggles → `Checkbox`).
- `repos/igloo-home/src/App.tsx` — **modify** (2 toggles → `Checkbox`; 2 `igloo-shell-alert` → `Alert`).
- `repos/igloo-chrome/src/{popup.tsx,pages/Onboarding.tsx,components/options/runtime-state-sections.tsx}` — **modify** (6 inline alerts → `Alert`).
- Parent — pointer bumps + BACKLOG.

---

### Task 1: igloo-ui `Checkbox` primitive

**Files:**
- Create: `repos/igloo-ui/src/components/ui/checkbox.tsx`
- Modify: `repos/igloo-ui/src/index.ts` (export)
- Test: `repos/igloo-ui/src/components/ui/checkbox.test.tsx`

**Interfaces:**
- Produces: `Checkbox` (+ `CheckboxProps`) — props `{ checked: boolean; onCheckedChange: (checked: boolean) => void; label: string; description?: string; disabled?: boolean; id?: string }` + passthrough `data-testid` etc. Renders `<label class="igloo-toggle-row"><input type="checkbox" …><span><strong>{label}</strong>{description && <small>{description}</small>}</span></label>`.

- [ ] **Step 1: Write the failing test** `repos/igloo-ui/src/components/ui/checkbox.test.tsx`:

```tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { Checkbox } from './checkbox';

describe('Checkbox', () => {
  it('renders igloo-toggle-row markup with label + description and fires onCheckedChange', () => {
    const onCheckedChange = vi.fn();
    render(
      <Checkbox checked={false} onCheckedChange={onCheckedChange} label="Remember state" description="Persist things." data-testid="cb" />,
    );
    const input = screen.getByTestId('cb') as HTMLInputElement;
    expect(input.type).toBe('checkbox');
    expect(input.checked).toBe(false);
    expect(screen.getByText('Remember state')).toBeInTheDocument();
    expect(screen.getByText('Persist things.')).toBeInTheDocument();
    expect(input.closest('label')?.className).toContain('igloo-toggle-row');
    fireEvent.click(input);
    expect(onCheckedChange).toHaveBeenCalledWith(true);
  });
});
```

- [ ] **Step 2: Run it, expect fail** (module missing):

Run: `npm --prefix repos/igloo-ui run test -- checkbox`
Expected: FAIL (cannot find `./checkbox`).

- [ ] **Step 3: Create `repos/igloo-ui/src/components/ui/checkbox.tsx`:**

```tsx
import * as React from 'react';
import { cn } from '../../lib/utils';

export interface CheckboxProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type' | 'checked' | 'onChange'> {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  label: string;
  description?: string;
  /** override the row class (defaults to igloo-toggle-row) */
  rowClassName?: string;
}

export const Checkbox = React.forwardRef<HTMLInputElement, CheckboxProps>(
  ({ checked, onCheckedChange, label, description, rowClassName, ...inputProps }, ref) => (
    <label className={cn('igloo-toggle-row', rowClassName)}>
      <input
        ref={ref}
        type="checkbox"
        checked={checked}
        onChange={(event) => onCheckedChange(event.target.checked)}
        {...inputProps}
      />
      <span>
        <strong>{label}</strong>
        {description ? <small>{description}</small> : null}
      </span>
    </label>
  ),
);

Checkbox.displayName = 'Checkbox';
```

> `data-testid`, `id`, `disabled` flow through `...inputProps` onto the `<input>`. `rowClassName` lets the pwa recovery toggle keep `igloo-recover-encrypt-toggle` if its styling differs.

- [ ] **Step 4: Export from `repos/igloo-ui/src/index.ts`** (next to the other ui primitives, e.g. after `Card`):

```ts
export { Checkbox } from './components/ui/checkbox';
export type { CheckboxProps } from './components/ui/checkbox';
```

- [ ] **Step 5: Run test + igloo-ui suite, expect pass:**

Run: `npm --prefix repos/igloo-ui run test -- checkbox` (then full `npm --prefix repos/igloo-ui run test`).
Expected: PASS; full suite green.

- [ ] **Step 6: Commit:**

```bash
git -C repos/igloo-ui add src/components/ui/checkbox.tsx src/components/ui/checkbox.test.tsx src/index.ts
git -C repos/igloo-ui commit -m "Add shared Checkbox primitive (igloo-toggle-row markup)"
```

---

### Task 2: pwa migrates its toggles to `Checkbox`

**Files:** Modify `repos/igloo-pwa/src/App.tsx`

**Interfaces:** Consumes `Checkbox` from `igloo-ui` (Task 1).

- [ ] **Step 1: Import `Checkbox`** into the existing `igloo-ui` import block in `repos/igloo-pwa/src/App.tsx`.

- [ ] **Step 2: Replace the 3 settings toggles** (`~1543` remember_browser_state, `~1554` auto_open_signer, `~1566` prefer_install_prompt) with `<Checkbox>`. Example (auto_open_signer — keep the test-id):

```tsx
<Checkbox
  checked={store.settings.auto_open_signer}
  onCheckedChange={(checked) => store.updateSettings('auto_open_signer', checked)}
  label="Open signer after import"
  description="Jump straight into the signer workspace after a successful setup action."
  data-testid={CRITICAL_E2E_TEST_IDS.settingsAutoOpenToggle}
/>
```

  Do the same for the other two (no test-id). Keep them inside the `<div className="igloo-settings-grid">`.

- [ ] **Step 3: Replace the recovery "Encrypt Key" toggle** (`~424`). It uses `igloo-recover-encrypt-toggle`. First check whether that class is defined: `grep -rn "igloo-recover-encrypt-toggle" repos/igloo-ui/src/styles.css`. If defined with distinct styling, migrate with `rowClassName="igloo-recover-encrypt-toggle"` (so it keeps its look); if NOT defined (renders like a plain toggle), migrate to a plain `<Checkbox>`. Either way:

```tsx
<Checkbox
  checked={encrypt}
  onCheckedChange={setEncrypt}
  label="Encrypt Key"
  description="Protect the exported key with a password before saving or sharing."
  // rowClassName="igloo-recover-encrypt-toggle"  // only if that class is defined
/>
```

- [ ] **Step 4: Delete** any now-orphaned local markup. Confirm: `grep -n 'type="checkbox"' repos/igloo-pwa/src/App.tsx` → no matches.

- [ ] **Step 5: Build + render + e2e.**

Run: `npm --prefix repos/igloo-pwa run build` → clean.
Run: `make screenshot CLIENT=pwa STATE=dashboard-stopped` (settings live on the stopped/settings view) — confirm the toggles render identically. Also `make screenshot CLIENT=pwa STATE=dashboard-running`.
Run: `npm --prefix test run test:e2e:igloo-pwa:fast -- -g "settings"` → passes (exercises `settingsAutoOpenToggle`).

- [ ] **Step 6: Commit:**

```bash
git -C repos/igloo-pwa add src/App.tsx
git -C repos/igloo-pwa commit -m "Adopt shared Checkbox for settings + recovery toggles (ADR-014 P1d)"
```

---

### Task 3: home migrates toggles → `Checkbox` and `igloo-shell-alert` → `Alert`

**Files:** Modify `repos/igloo-home/src/App.tsx`

**Interfaces:** Consumes `Checkbox` (Task 1) + existing `Alert` from `igloo-ui`.

- [ ] **Step 1: Import `Checkbox` (and `Alert` if not already)** into home's `igloo-ui` import block.

- [ ] **Step 2: Replace the 2 toggles** (`~474` close_to_tray, `~485` launch_on_login):

```tsx
<Checkbox
  checked={settings.close_to_tray}
  onCheckedChange={(checked) => onToggle('close_to_tray', checked)}
  label="Close to tray"
  description="Hide the window instead of prompting to stop the active signer session."
/>
```
  (and `launch_on_login` likewise). Keep them in the `igloo-settings-grid`.

- [ ] **Step 3: Replace the 2 `igloo-shell-alert` divs** (the class is undefined → currently unstyled):
  - `~1416`: `<div className="igloo-shell-alert">{error}</div>` → `<Alert tone="danger">{error}</Alert>`
  - `~1577`: the "Live onboarding tracking is paused…" div → `<Alert tone="default">Live onboarding tracking is paused until the host signer is running.</Alert>`

- [ ] **Step 4: Confirm cleanup.** `grep -n 'type="checkbox"\|igloo-shell-alert' repos/igloo-home/src/App.tsx` → no matches.

- [ ] **Step 5: Build + render.**

Run: `npm --prefix repos/igloo-home run build` → clean.
Run: `make screenshot CLIENT=home STATE=dashboard-settings` (the settings tab — confirm the toggles render) and `make screenshot CLIENT=home STATE=dashboard-running`.
Expected: toggles render as before; no unstyled `igloo-shell-alert` text.

- [ ] **Step 6: Commit:**

```bash
git -C repos/igloo-home add src/App.tsx
git -C repos/igloo-home commit -m "Adopt shared Checkbox + Alert; drop hand-rolled toggles + undefined igloo-shell-alert (ADR-014 P1d)"
```

---

### Task 4: chrome migrates its inline alerts → `Alert`

**Files:** Modify `repos/igloo-chrome/src/popup.tsx`, `src/pages/Onboarding.tsx`, `src/components/options/runtime-state-sections.tsx`

**Interfaces:** Consumes existing `Alert` from `igloo-ui` (import where missing).

- [ ] **Step 1: `popup.tsx`** — `:38` red error `<div>` → `<Alert tone="danger">{error}</Alert>`; `:62` amber `<div>` → `<Alert tone="warning">{status.lifecycle.activation.lastError.message}</Alert>`. Add the `Alert` import.

- [ ] **Step 2: `pages/Onboarding.tsx`** — `:270` red error → `<Alert tone="danger">{error}</Alert>`; `:455` red error → `<Alert tone="danger">{error}</Alert>`; `:461` amber "Last onboarding failure" → `<Alert title="Last onboarding failure" tone="warning">{lastOnboardingFailure.message}</Alert>`. Add the `Alert` import.

- [ ] **Step 3: `runtime-state-sections.tsx`** — `:112` amber snapshot error → `<Alert title="Snapshot error" tone="warning">{snapshotError}</Alert>`. Add the `Alert` import.

- [ ] **Step 4: Confirm.** `grep -rn 'border-red-500/30\|border-amber-500/30' repos/igloo-chrome/src/popup.tsx repos/igloo-chrome/src/pages/Onboarding.tsx repos/igloo-chrome/src/components/options/runtime-state-sections.tsx` → only matches that are NOT the migrated alert divs (e.g. unrelated). The 6 migrated divs are gone.

- [ ] **Step 5: Build + render.**

Run: `make igloo-chrome-build` → clean.
Run: `make screenshot CLIENT=chrome STATE=dashboard-running` (sanity) and `CLIENT=chrome STATE=onboarding` (exercises Onboarding alerts).
Expected: alerts render via shared `Alert` styling.

- [ ] **Step 6: Commit:**

```bash
git -C repos/igloo-chrome add src/popup.tsx src/pages/Onboarding.tsx src/components/options/runtime-state-sections.tsx
git -C repos/igloo-chrome commit -m "Route inline alert banners through shared Alert (ADR-014 P1d)"
```

---

### Task 5: Verify + land

**Files:** parent pointer commit + BACKLOG.

- [ ] **Step 1: Gate.** Run `make verify` → exit 0.
- [ ] **Step 2: Submodules clean.** `for r in igloo-ui igloo-pwa igloo-home igloo-chrome; do git -C repos/$r status --short; done` → all clean.
- [ ] **Step 3: Bump pointers** (stage only the 4 submodules — keep `dev/audit` out):
```bash
git add repos/igloo-ui repos/igloo-pwa repos/igloo-home repos/igloo-chrome
git commit -m "Bump pointers: shared Checkbox + Alert convergence (ADR-014 P1d)"
```
- [ ] **Step 4: Mark the two BACKLOG items done** (the `P1 — Shared Checkbox/Toggle` and `P1 — Alert API gaps … migrate the inline alert/banner sites` items; note the Alert one needed no API change, only migration) and commit `dev/BACKLOG.md`.

---

## Self-Review

**Spec coverage (ADR-014 d, Checkbox + Alert):** Checkbox added + 6 toggles retired → Tasks 1-3. Inline alerts (8) routed through `Alert`, home's undefined class fixed → Tasks 3-4. No `Alert` API change (confirmed sufficient) → Global Constraints. ✓

**Placeholder scan:** none — `Checkbox` source + test given in full; each migration site has an exact before→after with tone/title; verification commands have expected output.

**Type consistency:** `Checkbox`'s `onCheckedChange: (checked:boolean)=>void` consumed identically in Tasks 2-3; `Alert`'s existing `tone`/`title` props used as defined. The pwa `data-testid` flows through `...inputProps` (Task 1) and is exercised by the settings e2e (Task 2 Step 5).

**Note:** chrome has `Alert`-eligible sites only in the 3 files listed; the excluded non-alerts (badges, empty-states, field errors, code boxes) are intentionally left.
