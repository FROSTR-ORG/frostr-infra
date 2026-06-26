# igloo-ui Remaining Paper Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Paper -> `igloo-ui` sync for all remaining FROSTR application flows by expanding visual coverage, aligning shared UI components, and validating the rendered `igloo-pwa` experience against `igloo-paper`.

**Architecture:** Treat `repos/igloo-paper` as the visual reference, `repos/igloo-ui` as the shared component implementation, and `repos/igloo-pwa` as the rendered verification target. Add missing visual states to the parent test harness first, then align flow families in small hard-cut batches and mark manifest entries `aligned` only after screenshot review.

**Tech Stack:** Paper Desktop export artifacts, React/TypeScript in `igloo-ui`, Vite/Vitest in `igloo-ui` and `igloo-pwa`, Playwright visual capture in `test/igloo-pwa`, parent workspace `make` targets.

> **UPDATE (2026-05-27): Generate / Import / Onboard flows were redesigned in Paper.** This doc
> predates that redesign; assertions below were corrected to match. Net design changes:
> - Welcome CTA `Generate` → `Generate Keyset` (all welcome screens).
> - Import collapsed to 2 screens — `Import Device Profile` (paste backup + passphrase together) →
>   `Save Profile` (reuses the shared Save Profile form, button `Launch Signer`). The old `Decrypt
>   Backup` and `Review & Save Profile` screens are deleted; the Import/Recover **choice screen is
>   dropped** (Welcome "Import Existing Device" goes straight to Import Device Profile); Recover-from-
>   share becomes its own deferred entry.
> - Onboard recipient is now a redesigned **3-step** flow (`Input Package` → `Onboard Device` →
>   `Save Profile`, button `Launch Signer`) — it is **no longer "aligned"** and needs code
>   realignment.
> - Device cards on the returning screens use an `[Unlock] [⋮]` row; the kebab opens Rotate +
>   destructive Delete (documented on the new `Welcome — 1b-1. Returning (Menu Open)` artboard).
>
> Paper-side consistency (error/failed screens, Flow-Section boards) and the `artboard-map.json` /
> `export-metadata.json` / `design-contract.json` refresh + re-export are DONE (Phase A of the
> orchestration plan).

---

## Current Baseline

Current manifest status in `test/igloo-pwa/visual-manifest.json`:

- `aligned`: 9 entries
- `needs-work`: 6 entries
- Missing from manifest: most import, recover, dashboard, signer state, settings, sponsor onboarding, replace-share, rotate-keyset, and error/progress screens exported under `repos/igloo-paper/screens/`

Known `needs-work` entries:

- `welcome-first-launch`
- `welcome-returning-single`
- `welcome-returning-multi`
- `welcome-returning-many`
- `welcome-unlock-modal`
- `welcome-unlock-modal-error`

Known aligned entries:

- create profile/distribution flow

(The onboard recipient flow was previously aligned but was redesigned 2026-05-27 — it now needs
realignment to the new 3-step design; see the UPDATE note above.)

Paper sync prerequisite:

- Paper Desktop must be open to the `igloo-ui-shared` file on the `core` page before running `make igloo-paper-sync`.

## File Responsibilities

- `test/igloo-pwa/visual-manifest.json`: canonical list of Paper/PWA screenshot pairs and alignment status.
- `test/igloo-pwa/specs/*visual.spec.ts`: deterministic Playwright capture specs for app states.
- `test/igloo-pwa/support/state.ts`: persisted-state builders for seeded visual states.
- `test/igloo-pwa/support/ui.ts`: shared UI actions used by visual and e2e specs.
- `test/scripts/report-pwa-visual-comparison.mjs`: Markdown report generator for screenshot review.
- `repos/igloo-ui/src/components/flows/*.tsx`: shared flow components to align to Paper.
- `repos/igloo-ui/src/components/flows/HostShell.tsx`: dashboard, settings, profile, and runtime shell components.
- `repos/igloo-ui/src/styles.css`: shared visual system styles consumed by `igloo-pwa`.
- `repos/igloo-ui/test/*.test.tsx`: focused component tests for new or changed UI states.
- `repos/igloo-pwa/src/App.tsx`: app wiring, state transitions, and seeded-state compatibility.
- `repos/igloo-pwa/test/frontend/App.test.tsx`: unit coverage for app-level state transitions and labels.
- `dev/reports/*`: archived visual review reports when a batch needs a durable artifact.

## Paper Screen Families To Cover

Use the exported screenshots under `repos/igloo-paper/screens/` as the hard scope:

- Welcome: `welcome/1-welcome`, `welcome/1b-returning`, `welcome/1c-returning-multi`, `welcome/1d-returning-many`, `welcome/1c-1-unlock-profile-modal`, `welcome/1c-2-unlock-error-modal`
- Create gaps: `create/1b-validation-error`, `create/1c-generation-progress`
- Import: `import/1-load-backup`, `import/2-decrypt-backup`, `import/3-review-save-profile`, `import/error`
- Recover: `recover/1-collect-shares`, `recover/1b-recover-success`
- Dashboard/runtime: `dashboard/1-signer-dashboard`, `dashboard/1b-loading-profile`, `dashboard/1b-profile-load-failed`, `dashboard/1c-policies`, `dashboard/1d-recover`, `dashboard/1e-recover-success`, `dashboard/2-stopped`, `dashboard/2b-all-relays-offline`, `dashboard/2c-signing-blocked`
- Settings/export/prompt states: `dashboard/3-settings-lock-profile`, `dashboard/3b-clear-credentials-modal`, `dashboard/3c-unsaved-changes-modal`, `dashboard/4-export-profile`, `dashboard/4b-export-complete`, `dashboard/4c-export-share`, `dashboard/4d-share-export-complete`, `dashboard/5-signer-policy-prompt`, `dashboard/6-signing-failed`
- Settings sponsor onboarding: `dashboard/3d-onboard-device-modal`,
  `dashboard/3e-onboard-package-handoff-modal`; older `onboard-sponsor/*`
  paths were not present in the current Paper file and should not be used as
  canonical references without being restored intentionally.
- Replace share: `replace-share/1-enter-onboarding-package`, `replace-share/2-applying-replacement`, `replace-share/2b-replacement-failed`, `replace-share/3-share-replaced`
- Rotate keyset: `rotate-keyset/1-rotate-keyset`, `rotate-keyset/1d-review-generate`, `rotate-keyset/1e-generation-progress`, `rotate-keyset/error-generation-failed`, `rotate-keyset/error-group-mismatch`, `rotate-keyset/error-wrong-password`

## Task 1: Refresh Paper Export And Lock Baseline

**Files:**

- Inspect: `repos/igloo-paper/screens/**/screenshot.png`
- Inspect: `repos/igloo-paper/design-contract.json`
- Modify only if Paper has real source changes: `repos/igloo-paper/**`
- Report if blocked: `dev/reports/igloo-paper-sync-churn-investigation-YYYY-MM-DD.md`

- [ ] **Step 1: Confirm clean workspace**

Run:

```bash
git status --short
git -C repos/igloo-paper status --short
git -C repos/igloo-ui status --short
git -C repos/igloo-pwa status --short
```

Expected: no output from each `--short` command.

- [ ] **Step 2: Run Paper sync when Paper Desktop is ready**

Run:

```bash
make igloo-paper-sync
make igloo-paper-verify STRICT=1
```

Expected: both commands pass. If Paper MCP reports `Open a Paper file to use this tool.`, stop this task, open Paper Desktop to `igloo-ui-shared` on the `core` page, and rerun.

- [ ] **Step 3: Check for generated churn**

Run:

```bash
git -C repos/igloo-paper status --short
make igloo-paper-sync
git -C repos/igloo-paper status --short
```

Expected: second sync does not create additional unexplained generated changes.

- [ ] **Step 4: Commit real Paper export changes**

If `repos/igloo-paper` changed because Paper source changed, commit it:

```bash
git -C repos/igloo-paper add .
git -C repos/igloo-paper commit -m "Refresh Paper application flow exports"
```

Expected: a focused `igloo-paper` commit, or no commit if there were no export changes.

## Task 2: Expand Visual Harness Inventory

**Files:**

- Modify: `test/igloo-pwa/visual-manifest.json`
- Create: `test/igloo-pwa/specs/import-recover-visual.spec.ts`
- Create: `test/igloo-pwa/specs/dashboard-visual.spec.ts`
- Create: `test/igloo-pwa/specs/lifecycle-visual.spec.ts`
- Modify: `test/igloo-pwa/support/state.ts`
- Modify: `test/igloo-pwa/support/ui.ts`

- [ ] **Step 1: Add manifest entries for every Paper screen family**

Add one entry per exported screen listed in “Paper Screen Families To Cover”. Use stable names and output folders:

```json
{
  "name": "import-load-backup",
  "viewport": "1440x1080",
  "output": ".tmp/visual/igloo-pwa/import/01-load-backup.png",
  "paperReference": "repos/igloo-paper/screens/import/1-load-backup/screenshot.png",
  "status": "needs-work"
}
```

Expected: `test/igloo-pwa/visual-manifest.json` covers every exported screen in scope. Existing aligned entries stay aligned until a screenshot review proves otherwise.

- [ ] **Step 2: Run manifest guard**

Run:

```bash
npm --prefix test run test:guards:visual
```

Expected: PASS with all Paper references resolving.

- [ ] **Step 3: Add capture helpers for deterministic seeded states**

In `test/igloo-pwa/support/state.ts`, add builders for:

```ts
export function buildPaperVisualProfileState(overrides = {}) {
  return buildPwaPersistedState({
    profiles: [
      {
        id: 'paper-visual-primary',
        label: 'My Signing Key',
        share_public_key: 'ab'.repeat(32),
        group_public_key: 'cd'.repeat(32),
        relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
        group_package_json: JSON.stringify({
          group_name: 'My Signing Key',
          group_pk: 'cd'.repeat(32),
          threshold: 2,
          members: [
            { idx: 0, pubkey: '01'.repeat(32) },
            { idx: 1, pubkey: '02'.repeat(32) },
            { idx: 2, pubkey: '03'.repeat(32) }
          ]
        }),
        share_package_json: JSON.stringify({ idx: 0, seckey: '11'.repeat(32) }),
        source: 'generated',
        relay_profile: 'local',
        group_ref: 'paper-visual-group',
        encrypted_profile_ref: 'paper-visual-encrypted',
        state_path: '/tmp/igloo-pwa/paper-visual-primary',
        created_at: Date.UTC(2026, 4, 25),
        stored_password: 'paper-pass',
        profile_string: 'bfprofile1paperdemo',
        share_string: 'bfshare1paperdemo',
        signer_settings: {
          sign_timeout_secs: 30,
          ping_timeout_secs: 15,
          request_ttl_secs: 300,
          state_save_interval_secs: 30,
          peer_selection_strategy: 'deterministic_sorted'
        },
        manual_peer_policy_overrides: [],
        peer_pubkey: null,
        runtime_snapshot_json: null,
        onboarding_package: null
      }
    ],
    selectedProfileId: 'paper-visual-primary',
    activeView: 'dashboard',
    activeDashboardTab: 'signer',
    ...overrides
  });
}
```

Expected: visual specs can seed dashboard/import/recover states without duplicating full profile payloads in every file.

- [ ] **Step 4: Create visual specs that capture missing flow families**

Create one spec file per batch:

```ts
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { expect, test, type Page } from '@playwright/test';
import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { PWA_STORAGE_KEY, buildPaperVisualProfileState } from '../support/state';

const CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'dashboard');

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(([storageKey, payload]) => {
    window.localStorage.setItem(storageKey, JSON.stringify(payload));
  }, [PWA_STORAGE_KEY, state] as const);
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await mkdir(CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Dashboard visual harness', () => {
  test('captures signer dashboard', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await seedState(page, buildPaperVisualProfileState());
    await expect(page.getByText('Device Dashboard')).toBeVisible();
    await capture(page, '01-signer-dashboard.png');
  });
});
```

Expected: the first version may capture visually incorrect UI, but every capture path exists and is reproducible.

- [ ] **Step 5: Run expanded visual capture and report**

Run:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Expected: visual capture command passes and `.tmp/visual/igloo-pwa/comparison-report.md` includes every manifest entry.

- [ ] **Step 6: Commit harness inventory**

```bash
git add test/igloo-pwa test/scripts/report-pwa-visual-comparison.mjs test/package.json
git commit -m "Expand PWA Paper visual coverage"
```

Expected: parent workspace commit with manifest/spec/helper changes only.

## Task 3: Align Welcome Flow

**Files:**

- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx`
- Modify: `repos/igloo-ui/src/styles.css`
- Modify: `repos/igloo-ui/test/HostShell.test.tsx` or closest existing host-shell test
- Modify: `repos/igloo-pwa/src/App.tsx` only if state wiring differs from Paper behavior
- Modify: `test/igloo-pwa/visual-manifest.json`
- Inspect: `repos/igloo-paper/screens/welcome/*/screenshot.png`

- [ ] **Step 1: Write focused tests for Welcome states**

Add tests that assert:

```ts
expect(screen.getByRole('heading', { name: 'Igloo Web' })).toBeInTheDocument();
expect(screen.getByRole('button', { name: 'Generate Keyset' })).toBeInTheDocument();
expect(screen.getByRole('button', { name: 'Import Existing Device' })).toBeInTheDocument();
expect(screen.getByRole('button', { name: 'Onboard New Device' })).toBeInTheDocument();
expect(screen.getByText('Welcome back.')).toBeInTheDocument();
expect(screen.getByRole('dialog', { name: 'Unlock Profile' })).toBeInTheDocument();
```

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/HostShell.test.tsx
```

Expected before implementation: FAIL only on missing or mismatched Welcome structure/labels.

- [ ] **Step 2: Align Welcome component and styles**

Update the shared shell to match Paper:

- first-launch Welcome composition
- returning single profile state
- returning multi profile state
- returning many profile state
- unlock modal normal state
- unlock modal error state

Implementation stays in `igloo-ui`; use `igloo-pwa` changes only for app-state mismatches.

- [ ] **Step 3: Verify Welcome unit tests**

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/HostShell.test.tsx
npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx
```

Expected: PASS.

- [ ] **Step 4: Capture and review Welcome visuals**

Run:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Open `.tmp/visual/igloo-pwa/comparison-report.md` and compare each Welcome entry to its Paper reference.

Expected: six Welcome entries visually match Paper.

- [ ] **Step 5: Mark Welcome manifest entries aligned**

Change these entries to `"status": "aligned"`:

- `welcome-first-launch`
- `welcome-returning-single`
- `welcome-returning-multi`
- `welcome-returning-many`
- `welcome-unlock-modal`
- `welcome-unlock-modal-error`

- [ ] **Step 6: Commit Welcome alignment**

```bash
git -C repos/igloo-ui add src/components/flows/HostShell.tsx src/styles.css test
git -C repos/igloo-ui commit -m "Align Welcome flow with Paper"
git add repos/igloo-ui repos/igloo-pwa test/igloo-pwa/visual-manifest.json
git commit -m "Mark Welcome Paper visuals aligned"
```

Expected: `igloo-ui` contains implementation; parent contains pointer and manifest status.

## Task 4: Align Import And Recover Flows

**Files:**

- Modify: `repos/igloo-ui/src/components/flows/CreateFlow.tsx` or import/recover flow component files if split exists
- Modify: `repos/igloo-ui/src/styles.css`
- Modify: `repos/igloo-ui/test/CreateFlow.test.tsx`
- Modify: `repos/igloo-pwa/src/App.tsx`
- Modify: `repos/igloo-pwa/test/frontend/App.test.tsx`
- Modify: `test/igloo-pwa/specs/import-recover-visual.spec.ts`
- Modify: `test/igloo-pwa/visual-manifest.json`

- [ ] **Step 1: Add tests for import flow labels and states**

Add focused assertions for:

```ts
// Import is now 2 screens reached directly from Welcome "Import Existing Device" (no choice screen):
expect(screen.getByRole('heading', { name: 'Import Device Profile' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Save Profile' })).toBeInTheDocument();
expect(screen.getByRole('button', { name: 'Launch Signer' })).toBeInTheDocument();
// Recover-from-share is a separate (deferred) entry, no longer bundled under a load-choice screen.
```

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx
```

Expected before implementation: FAIL on missing Paper labels or missing states.

- [ ] **Step 2: Add tests for recover flow labels and states**

Add focused assertions for:

```ts
expect(screen.getByRole('heading', { name: 'Collect Recovery Shares' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Recovery Complete' })).toBeInTheDocument();
```

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx
```

Expected before implementation: FAIL on missing Paper labels or missing states.

- [ ] **Step 3: Implement import/recover Paper structures**

Align the React components to these Paper references:

- `repos/igloo-paper/screens/import/1-load-backup/screenshot.png`
- `repos/igloo-paper/screens/import/2-decrypt-backup/screenshot.png`
- `repos/igloo-paper/screens/import/3-review-save-profile/screenshot.png`
- `repos/igloo-paper/screens/import/error/screenshot.png`
- `repos/igloo-paper/screens/recover/1-collect-shares/screenshot.png`
- `repos/igloo-paper/screens/recover/1b-recover-success/screenshot.png`

- [ ] **Step 4: Verify import/recover unit and visual lanes**

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx
npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Expected: PASS and import/recover screenshots match Paper.

- [ ] **Step 5: Mark import/recover entries aligned and commit**

```bash
git -C repos/igloo-ui add src test
git -C repos/igloo-ui commit -m "Align import and recover flows with Paper"
git -C repos/igloo-pwa add src test
git -C repos/igloo-pwa commit -m "Wire Paper import and recover states"
git add repos/igloo-ui repos/igloo-pwa test/igloo-pwa/visual-manifest.json test/igloo-pwa/specs/import-recover-visual.spec.ts
git commit -m "Mark import and recover Paper visuals aligned"
```

Expected: no `needs-work` import/recover entries remain.

## Task 5: Align Dashboard, Runtime, Policies, Settings, And Export States

**Files:**

- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx`
- Modify: `repos/igloo-ui/src/styles.css`
- Modify: `repos/igloo-ui/test/HostShell.test.tsx`
- Modify: `repos/igloo-pwa/src/App.tsx`
- Modify: `repos/igloo-pwa/test/frontend/App.test.tsx`
- Modify: `test/igloo-pwa/specs/dashboard-visual.spec.ts`
- Modify: `test/igloo-pwa/visual-manifest.json`

- [ ] **Step 1: Add host-shell tests for dashboard tab states**

Assert the Paper dashboard states:

```ts
expect(screen.getByRole('heading', { name: 'Device Dashboard' })).toBeInTheDocument();
expect(screen.getByRole('tab', { name: /Signer/ })).toBeInTheDocument();
expect(screen.getByRole('tab', { name: /Permissions/ })).toBeInTheDocument();
expect(screen.getByRole('tab', { name: /Settings/ })).toBeInTheDocument();
expect(screen.getByText('All relays offline')).toBeInTheDocument();
expect(screen.getByText('Signing blocked')).toBeInTheDocument();
```

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/HostShell.test.tsx
```

Expected before implementation: FAIL on states not yet exposed.

- [ ] **Step 2: Add app tests for settings/export modals**

Assert:

```ts
expect(screen.getByRole('dialog', { name: 'Clear Credentials' })).toBeInTheDocument();
expect(screen.getByRole('dialog', { name: 'Unsaved Changes' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Export Profile' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Export Complete' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Export Share' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Share Export Complete' })).toBeInTheDocument();
```

Run:

```bash
npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx
```

Expected before implementation: FAIL only on missing states/labels.

- [ ] **Step 3: Implement dashboard/runtime/settings alignment**

Align to:

- `dashboard/1-signer-dashboard`
- `dashboard/1b-loading-profile`
- `dashboard/1b-profile-load-failed`
- `dashboard/1c-policies`
- `dashboard/1d-recover`
- `dashboard/1e-recover-success`
- `dashboard/2-stopped`
- `dashboard/2b-all-relays-offline`
- `dashboard/2c-signing-blocked`
- `dashboard/3-settings-lock-profile`
- `dashboard/3b-clear-credentials-modal`
- `dashboard/3c-unsaved-changes-modal`
- `dashboard/4-export-profile`
- `dashboard/4b-export-complete`
- `dashboard/4c-export-share`
- `dashboard/4d-share-export-complete`
- `dashboard/5-signer-policy-prompt`
- `dashboard/6-signing-failed`

- [ ] **Step 4: Verify dashboard visual batch**

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/HostShell.test.tsx
npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Expected: PASS and dashboard screenshots match Paper.

- [ ] **Step 5: Commit dashboard alignment**

```bash
git -C repos/igloo-ui add src test
git -C repos/igloo-ui commit -m "Align dashboard states with Paper"
git -C repos/igloo-pwa add src test
git -C repos/igloo-pwa commit -m "Wire Paper dashboard states"
git add repos/igloo-ui repos/igloo-pwa test/igloo-pwa/visual-manifest.json test/igloo-pwa/specs/dashboard-visual.spec.ts
git commit -m "Mark dashboard Paper visuals aligned"
```

Expected: no `needs-work` dashboard entries remain.

## Task 6: Align Settings Sponsor Onboarding, Replace Share, And Rotate Keyset

**Files:**

- Modify: `repos/igloo-ui/src/components/flows/CreateFlow.tsx`
- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx`
- Modify: `repos/igloo-ui/src/styles.css`
- Modify: `repos/igloo-ui/test/CreateFlow.test.tsx`
- Modify: `repos/igloo-ui/test/HostShell.test.tsx`
- Modify: `repos/igloo-pwa/src/App.tsx`
- Modify: `repos/igloo-pwa/test/frontend/App.test.tsx`
- Modify: `test/igloo-pwa/specs/lifecycle-visual.spec.ts`
- Modify: `test/igloo-pwa/visual-manifest.json`

- [ ] **Step 1: Add component tests for lifecycle flow labels**

Assert:

```ts
expect(screen.getByRole('heading', { name: 'Configure Device' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Package Handoff' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Enter Onboarding Package' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Share Replaced' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Rotate Keyset' })).toBeInTheDocument();
expect(screen.getByRole('heading', { name: 'Review & Generate' })).toBeInTheDocument();
```

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx test/HostShell.test.tsx
```

Expected before implementation: FAIL on missing lifecycle states.

- [ ] **Step 2: Implement Settings sponsor onboarding alignment**

Align to:

- `dashboard/3d-onboard-device-modal`
- `dashboard/3e-onboard-package-handoff-modal`

The older `onboard-sponsor/*` references were superseded by the dashboard
modal screens. Add separate Device Onboarded / Onboarding Failed / Cancel
Confirm Paper references only if product design intentionally restores them.

- [ ] **Step 3: Implement replace-share alignment**

Align to:

- `replace-share/1-enter-onboarding-package`
- `replace-share/2-applying-replacement`
- `replace-share/2b-replacement-failed`
- `replace-share/3-share-replaced`

- [ ] **Step 4: Implement rotate-keyset alignment**

Align to:

- `rotate-keyset/1-rotate-keyset`
- `rotate-keyset/1d-review-generate`
- `rotate-keyset/1e-generation-progress`
- `rotate-keyset/error-generation-failed`
- `rotate-keyset/error-group-mismatch`
- `rotate-keyset/error-wrong-password`

- [ ] **Step 5: Verify lifecycle visual batch**

Run:

```bash
npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx test/HostShell.test.tsx
npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Expected: PASS and lifecycle screenshots match Paper.

- [ ] **Step 6: Commit lifecycle alignment**

```bash
git -C repos/igloo-ui add src test
git -C repos/igloo-ui commit -m "Align lifecycle flows with Paper"
git -C repos/igloo-pwa add src test
git -C repos/igloo-pwa commit -m "Wire Paper lifecycle states"
git add repos/igloo-ui repos/igloo-pwa test/igloo-pwa/visual-manifest.json test/igloo-pwa/specs/lifecycle-visual.spec.ts
git commit -m "Mark lifecycle Paper visuals aligned"
```

Expected: no `needs-work` lifecycle entries remain.

## Task 7: Final Closure And Release-Quality Verification

**Files:**

- Modify: `test/igloo-pwa/visual-manifest.json`
- Create: `dev/reports/igloo-ui-paper-sync-completion-YYYY-MM-DD.md`
- Modify: submodule pointers in parent repo

- [ ] **Step 1: Verify no unresolved manifest entries**

Run:

```bash
node -e "const m=require('./test/igloo-pwa/visual-manifest.json'); const bad=m.screens.filter(s=>s.status!=='aligned'); console.log(JSON.stringify(bad.map(s=>s.name), null, 2)); process.exit(bad.length ? 1 : 0);"
```

Expected: PASS with `[]`.

- [ ] **Step 2: Run full package and harness validation**

Run:

```bash
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa test
npm --prefix test run test:typecheck:strict-support
npm --prefix test run test:guards:visual
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Expected: all commands pass.

- [ ] **Step 3: Archive completion report**

Create `dev/reports/igloo-ui-paper-sync-completion-YYYY-MM-DD.md` with:

```markdown
# igloo-ui Paper Sync Completion

Date: YYYY-MM-DD

## Scope

All exported Paper application screens under `repos/igloo-paper/screens/` are represented in `test/igloo-pwa/visual-manifest.json`.

## Result

- Manifest entries: N
- Aligned entries: N
- Deferred entries: 0

## Verification

- `npm --prefix repos/igloo-ui test`: PASS
- `npm --prefix repos/igloo-ui run build`: PASS
- `npm --prefix repos/igloo-pwa test`: PASS
- `npm --prefix test run test:typecheck:strict-support`: PASS
- `npm --prefix test run test:guards:visual`: PASS
- `npm --prefix test run test:e2e:igloo-pwa:visual`: PASS
- `npm --prefix test run test:visual:report`: PASS
```

Expected: durable completion artifact under `dev/reports`.

- [ ] **Step 4: Commit parent closure**

```bash
git add dev/reports test/igloo-pwa/visual-manifest.json repos/igloo-ui repos/igloo-pwa repos/igloo-paper
git commit -m "Complete igloo-ui Paper visual sync"
```

Expected: parent commit records final manifest status and submodule pointers.

- [ ] **Step 5: Push in dependency order**

```bash
git -C repos/igloo-paper push
git -C repos/igloo-ui push
git -C repos/igloo-pwa push
git push
```

Expected: all repos are on `master...origin/master` with clean worktrees.

## Execution Notes

- Use `igloo-ui` for reusable structure and visual treatment.
- Use `igloo-pwa` only for state transitions, app wiring, seeded visual state support, and PWA-specific tests.
- Do not import `igloo-paper` from runtime code.
- Do not hand-edit generated Paper screenshots or HTML.
- Keep visual screenshots in `.tmp/visual/igloo-pwa`; commit only harness, manifest, code, docs, and reports.
- If a Paper design is internally inconsistent with functional UI behavior, document the discrepancy in `dev/reports/` before choosing whether to adjust Paper source through MCP or adapt implementation.

## Self-Review

- Spec coverage: the plan covers Paper refresh, visual harness expansion, all current `needs-work` Welcome states, missing import/recover/dashboard/settings/lifecycle flows, final manifest closure, verification, commits, and push order.
- Placeholder scan: no `TBD`, `TODO`, or unbounded “handle edge cases” steps remain.
- Type consistency: helper names and file paths match the current workspace conventions; execution agents should inspect current component exports before adding tests because some flow components may already be split or renamed by the time a later task begins.
