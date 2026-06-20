# Unified Landing (Shared Welcome Heroes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `igloo-home` and `igloo-chrome` render the same shared Welcome landing that `igloo-pwa` already uses, by generalizing the `igloo-ui` heroes to be host-adapted, then hard-cutting the old `StoredProfilesLandingCard` / `HostEntryTile`.

**Architecture:** Generalize `WelcomeEntryHero` / `WelcomeReturningHero` in `repos/igloo-ui/src/components/flows/HostShell.tsx` so title, tagline, footer, and the action set are passed by each host (no host-specific defaults remain in the shared layer). Migrate pwa to the new prop shape (behavior unchanged), then home and chrome onto the heroes, then delete the now-dead components.

**Tech Stack:** React 18 + TypeScript, Tailwind (igloo-ui preset, all-source consumption), Vite, Playwright (screenshots + `@fast` e2e), Vitest.

## Global Constraints

- **Hard cut, zero tech debt:** delete the old path in the same change — no deprecation aliases, compat shims, dual code paths, or dead exports.
- **No host-specific defaults in the shared component:** every app passes explicit `productLabel` / `tagline` / `footer` / actions.
- **Preserve critical e2e test ids:** `welcomeEntryGenerate`, `welcomeEntryImport`, `welcomeEntryOnboard`, `welcomeProfileRow`, `welcomeProfileUnlock`, `welcomeProfileMenuTrigger`, `welcomeProfileMenuRotate`, `welcomeProfileMenuRecover`, `welcomeProfileMenuDelete` must still land on the same elements (carried via action descriptors). These live in `igloo-ui`'s `CRITICAL_E2E_TEST_IDS`.
- **Submodule workflow:** commit **inside each submodule first**, then bump the parent pointer with **explicit staging** (`git add repos/<name>`), never `git add -A` and never blanket `make bump-pointers` — the parent tree carries an unrelated, not-ours `dev/audit/` stream that must stay out of these commits.
- **Stay on `dev`; do not push or open PRs.**
- **`igloo-ui` tests** live in `repos/igloo-ui/test/**/*.test.tsx`; its test script is `test`. **`igloo-ui` is consumed all-source** (symlink + vite alias to `../igloo-ui/src/index.ts`) so edits are live in every client with no rebuild.

---

### Task 1: Generalize the shared Welcome heroes + keep pwa green

Generalize the heroes and migrate the existing consumer (pwa) in the same task so `make verify` stays green — the shared API change and its reference consumer land together.

**Files:**
- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx` (`WelcomeEntryHero` ~13-65, `WelcomeReturningHero` ~105-242, `WelcomeReturningProfileModel` ~67-73)
- Modify: `repos/igloo-ui/src/index.ts` (export the new action/primary types)
- Test: `repos/igloo-ui/test/host-shell-welcome.test.tsx` (create, or extend the existing welcome test if present — check `repos/igloo-ui/test/` first)
- Modify: `repos/igloo-pwa/src/App.tsx` (`renderLanding` ~677-712, the `WelcomeEntryHero` instances ~679 and ~1580)

**Interfaces:**
- Produces (new exported types, consumed by Tasks 2 & 3):

```ts
export type WelcomeHeroAction = {
  id: string;
  label: string;
  onAction: () => void;
  testId?: string;
};

export type WelcomeEntryPrimaryAction = {
  heading: string;      // panel <h3>, e.g. "Generate New Keyset"
  description: string;  // panel body copy
  buttonLabel: string;  // primary button text, e.g. "Generate Keyset"
  onAction: () => void;
  testId?: string;
  showInfo?: boolean;   // Info icon beside heading; default true
};
```

- Produces (`WelcomeReturningProfileModel` gains optional capability flags):

```ts
export type WelcomeReturningProfileModel = {
  id: string;
  label: string;
  thresholdLabel: string;
  memberLabel: string;
  publicKeyLabel: string;
  canRotate?: boolean;   // default true
  canRecover?: boolean;  // default = Boolean(onRecover)
  canDelete?: boolean;   // default true
};
```

- Produces (`WelcomeEntryHero` new prop shape):

```ts
{
  logoSrc?: string;
  logoAlt?: string;             // default 'Igloo'
  productLabel: string;         // replaces hardcoded "Igloo Web"
  tagline: string;              // replaces hardcoded entry tagline
  primaryAction: WelcomeEntryPrimaryAction;
  secondaryActions: WelcomeHeroAction[];
  footer?: React.ReactNode;     // pwa passes <PublicFocusFooter/>; others omit
}
```

- Produces (`WelcomeReturningHero` new prop shape):

```ts
{
  logoSrc?: string;
  logoAlt?: string;             // default 'Igloo'
  productLabel: string;
  tagline?: string;             // default "Welcome back."
  layout: 'single' | 'multi' | 'many';
  profiles: WelcomeReturningProfileModel[];
  onUnlock: (profileId: string) => void;
  onRotate: (profileId: string) => void;
  onRecover?: (profileId: string) => void;
  onDelete: (profileId: string) => void;
  secondaryActions: WelcomeHeroAction[];
  footer?: React.ReactNode;
}
```

- [ ] **Step 1: Inspect existing welcome tests** so the new test extends rather than duplicates.

Run: `ls repos/igloo-ui/test/ && grep -rln "WelcomeEntryHero\|WelcomeReturningHero" repos/igloo-ui/test/`
Note which file (if any) already renders the heroes; add the new assertions there if so, otherwise create `repos/igloo-ui/test/host-shell-welcome.test.tsx`.

- [ ] **Step 2: Write the failing test** for host-adapted props + capability flags.

```tsx
import { render, screen } from '@testing-library/react';
import { WelcomeEntryHero, WelcomeReturningHero } from '../src/components/flows/HostShell';

const noop = () => {};

test('WelcomeEntryHero renders host productLabel, tagline, primary + secondary actions', () => {
  render(
    <WelcomeEntryHero
      productLabel="Igloo Home"
      tagline="Desktop co-signer."
      primaryAction={{ heading: 'Create / Rotate Keyset', description: 'Generate or rotate.', buttonLabel: 'Start', onAction: noop, testId: 'entry-primary' }}
      secondaryActions={[{ id: 'load', label: 'Load Profile', onAction: noop }]}
    />,
  );
  expect(screen.getByRole('heading', { name: 'Igloo Home' })).toBeInTheDocument();
  expect(screen.getByText('Desktop co-signer.')).toBeInTheDocument();
  expect(screen.getByTestId('entry-primary')).toHaveTextContent('Start');
  expect(screen.getByRole('button', { name: 'Load Profile' })).toBeInTheDocument();
});

test('WelcomeReturningHero hides ⋮ menu items the host does not support', () => {
  render(
    <WelcomeReturningHero
      productLabel="Igloo"
      layout="single"
      profiles={[{ id: 'p1', label: 'Dev', thresholdLabel: '2/3', memberLabel: '#1', publicKeyLabel: 'npub…', canRotate: false, canRecover: false, canDelete: true }]}
      onUnlock={noop}
      onRotate={noop}
      onDelete={noop}
      secondaryActions={[{ id: 'onboard', label: 'Onboard New Device', onAction: noop }]}
    />,
  );
  expect(screen.getByRole('button', { name: 'Onboard New Device' })).toBeInTheDocument();
  expect(screen.queryByRole('menuitem', { name: 'Rotate' })).not.toBeInTheDocument();
  expect(screen.queryByRole('menuitem', { name: 'Recover' })).not.toBeInTheDocument();
});
```

Note: the second test must open the ⋮ menu first (click `welcomeProfileMenuTrigger`) — add a `fireEvent.click(screen.getByTestId('...welcomeProfileMenuTrigger value...'))` before the `queryByRole('menuitem')` assertions. Read the exact `CRITICAL_E2E_TEST_IDS` value while writing.

- [ ] **Step 3: Run the test to verify it fails**

Run: `npm --prefix repos/igloo-ui run test -- host-shell-welcome`
Expected: FAIL — current heroes don't accept `productLabel`/`primaryAction`/`secondaryActions`/capability flags.

- [ ] **Step 4: Implement the generalized heroes** in `HostShell.tsx`.

In `WelcomeEntryHero`: replace the hardcoded `<h2>Igloo Web</h2>` / tagline `<p>` with `{productLabel}` / `{tagline}`; replace the fixed "Generate New Keyset" panel with `primaryAction.heading` (+ `Info` icon gated on `showInfo !== false`), `primaryAction.description`, and a primary `Button` rendering `primaryAction.buttonLabel` with `data-testid={primaryAction.testId}` / `onClick={primaryAction.onAction}`; replace the fixed Import/Onboard buttons with `secondaryActions.map(a => <Button key={a.id} size="sm" variant="secondary" data-testid={a.testId} onClick={a.onAction}>{a.label}</Button>)`; replace `<PublicFocusFooter />` with `{footer}`.

In `WelcomeReturningHero`: same `productLabel`/`tagline` (default `"Welcome back."`)/`{footer}` changes; render each profile's ⋮ menu items conditionally — Rotate when `profile.canRotate !== false`, Recover when `profile.canRecover ?? Boolean(onRecover)`, Delete when `profile.canDelete !== false`; replace the fixed Generate/Import/Onboard secondary row with `secondaryActions.map(...)` identical to entry.

Export `WelcomeHeroAction` and `WelcomeEntryPrimaryAction` from `HostShell.tsx` and add them to `repos/igloo-ui/src/index.ts` (next to `WelcomeReturningProfileModel`).

- [ ] **Step 5: Run the igloo-ui test to verify it passes**

Run: `npm --prefix repos/igloo-ui run test -- host-shell-welcome`
Expected: PASS.

- [ ] **Step 6: Migrate pwa to the new prop shape** in `repos/igloo-pwa/src/App.tsx` (`renderLanding` and the second `WelcomeEntryHero` at ~1580). Preserve current pwa behavior + test ids:

```tsx
// Entry hero (no profiles)
<WelcomeEntryHero
  logoSrc="/igloo-paper-mark.png"
  productLabel="Igloo Web"
  tagline="Split your Nostr key. Sign from anywhere."
  primaryAction={{
    heading: 'Generate New Keyset',
    description: 'Generate a new threshold keyset and set up its first device profile.',
    buttonLabel: 'Generate Keyset',
    onAction: () => store.setActiveView('create-generate'),
    testId: CRITICAL_E2E_TEST_IDS.welcomeEntryGenerate,
  }}
  secondaryActions={[
    { id: 'import', label: 'Import Existing Device', onAction: () => store.startLoadImport(), testId: CRITICAL_E2E_TEST_IDS.welcomeEntryImport },
    { id: 'onboard', label: 'Onboard New Device', onAction: () => store.setActiveView('onboard-connect'), testId: CRITICAL_E2E_TEST_IDS.welcomeEntryOnboard },
  ]}
  footer={<PublicFocusFooter />}
/>

// Returning hero (has profiles) — same onUnlock/onRotate/onRecover/onDelete as today, plus:
secondaryActions={[
  { id: 'generate', label: 'Generate Keyset', onAction: () => store.setActiveView('create-generate'), testId: CRITICAL_E2E_TEST_IDS.welcomeEntryGenerate },
  { id: 'import', label: 'Import Existing Device', onAction: () => store.startLoadImport(), testId: CRITICAL_E2E_TEST_IDS.welcomeEntryImport },
  { id: 'onboard', label: 'Onboard New Device', onAction: () => store.setActiveView('onboard-connect'), testId: CRITICAL_E2E_TEST_IDS.welcomeEntryOnboard },
]}
productLabel="Igloo Web"
footer={<PublicFocusFooter />}
```

Import `PublicFocusFooter` and `CRITICAL_E2E_TEST_IDS` from `igloo-ui` if not already imported (grep first — `CRITICAL_E2E_TEST_IDS` may be exported under a different path; reuse the test ids the way pwa's existing e2e expects).

- [ ] **Step 7: Verify pwa still renders + passes its welcome e2e**

Run: `make igloo-pwa-typecheck && make screenshot CLIENT=pwa STATE=welcome-returning`
Then: `npm --prefix test run test:e2e:igloo-pwa:fast -- -g "welcome"`
Expected: typecheck clean; screenshot `.tmp/agent/welcome-returning.png` looks identical to before; welcome e2e PASS.

- [ ] **Step 8: Commit igloo-ui, commit pwa, bump pointers**

```bash
git -C repos/igloo-ui add src/components/flows/HostShell.tsx src/index.ts test/
git -C repos/igloo-ui commit -m "Generalize Welcome heroes: host-adapted productLabel/tagline/footer + declarative actions"
git -C repos/igloo-pwa add src/App.tsx
git -C repos/igloo-pwa commit -m "Adopt generalized Welcome hero prop shape (behavior unchanged)"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-ui repos/igloo-pwa
git commit -m "Bump pointers: generalized shared Welcome heroes + pwa adoption"
```

---

### Task 2: Migrate igloo-home landing to the shared heroes

**Files:**
- Modify: `repos/igloo-home/src/App.tsx` — landing block `activeView==='landing'` (~1411-1500), the `AppHeader` (~1399), imports (~14-46), and remove the now-dead `landingPassphrases` inline-unlock state (~521) + `StoredProfilesLandingCard`/`HostEntryTile` imports.
- Reference: `repos/igloo-pwa/src/App.tsx` `renderLanding` + modal wiring (the proven template).

**Interfaces:**
- Consumes: `WelcomeEntryHero`, `WelcomeReturningHero`, `WelcomeUnlockModal`, `WelcomeDeleteModal`, `WelcomeHeroAction`, `WelcomeEntryPrimaryAction`, `WelcomeReturningProfileModel` from Task 1.
- home flow handlers already present: `handleLoadLandingProfile(profileId)` (~1244, adapt to take the modal password), `handleRemoveProfile(profileId)` (~1314), `setActiveView('create' | 'load' | 'recover-key' | 'onboard-connect')`.

- [ ] **Step 1: Build the home returning-profile model.** Add a `deriveHomeReturningProfile(profile)` helper mapping home's `ProfileManifest` → `WelcomeReturningProfileModel` (`thresholdLabel` / `memberLabel` / `publicKeyLabel` from the profile's threshold/member/`share_public_key`; `canRotate: true`, `canRecover: true`, `canDelete: true`). Model it on pwa's `deriveWelcomeReturningProfile` (~257) and `formatWelcomeKey` (~292).

- [ ] **Step 2: Add unlock/delete modal state.** Add `welcomeUnlockProfileId` / `welcomeUnlockPassword` / `welcomeUnlockError` / `welcomeUnlockSubmitting` and `welcomeDeleteProfileId` `useState`, plus `openWelcomeUnlock` / `closeWelcomeUnlock` / `submitWelcomeUnlock` / `openWelcomeDelete` / `closeWelcomeDelete` / `confirmWelcomeDelete` handlers, mirroring pwa (~466-546, ~640). `submitWelcomeUnlock` calls the existing load-with-password path (`handleLoadLandingProfile` adapted to accept the typed password instead of reading `landingPassphrases`).

- [ ] **Step 3: Replace the landing render block.** Swap the `ContentCard` + `StoredProfilesLandingCard` + 4× `HostEntryTile` for:

```tsx
{activeView === 'landing' ? (
  profiles.length === 0 ? (
    <WelcomeEntryHero
      logoSrc={iglooLogoSrc}
      productLabel="Igloo Home"
      tagline="Threshold signing for your desktop."
      primaryAction={{
        heading: 'Create / Rotate Keyset',
        description: 'Generate new share material or rotate an existing keyset, save one local desktop device, and distribute the remaining shares.',
        buttonLabel: 'Start',
        onAction: () => setActiveView('create'),
      }}
      secondaryActions={[
        { id: 'load', label: 'Load Profile', onAction: () => setActiveView('load') },
        { id: 'recover', label: 'Recover Group Key', onAction: () => { setRecoveredKey(null); setActiveView('recover-key'); } },
        { id: 'onboard', label: 'Onboard Device', onAction: () => setActiveView('onboard-connect') },
      ]}
    />
  ) : (
    <WelcomeReturningHero
      logoSrc={iglooLogoSrc}
      productLabel="Igloo Home"
      layout={profiles.length === 1 ? 'single' : profiles.length <= 3 ? 'multi' : 'many'}
      profiles={profiles.map(deriveHomeReturningProfile)}
      onUnlock={openWelcomeUnlock}
      onRotate={(profileId) => { setSelectedProfileId(profileId); setActiveView('create'); }}
      onRecover={(profileId) => { setRecoveredKey(null); setRecoverProfileId(profileId); setActiveView('recover-key'); }}
      onDelete={openWelcomeDelete}
      secondaryActions={[
        { id: 'load', label: 'Load Profile', onAction: () => setActiveView('load') },
        { id: 'recover', label: 'Recover Group Key', onAction: () => { setRecoveredKey(null); setActiveView('recover-key'); } },
        { id: 'onboard', label: 'Onboard Device', onAction: () => setActiveView('onboard-connect') },
      ]}
    />
  )
) : null}
```

Verify the `onRotate`/`onRecover` setters (`setSelectedProfileId`, `setRecoverProfileId`, `setRecoveredKey`) against home's actual state hooks while editing — use the real names.

- [ ] **Step 4: Render the unlock + delete modals** once, alongside the existing top-level content (mirror pwa ~1588-1606):

```tsx
<WelcomeUnlockModal open={Boolean(welcomeUnlockProfileId)} profile={welcomeUnlockProfile} password={welcomeUnlockPassword} error={welcomeUnlockError} submitting={welcomeUnlockSubmitting} onPasswordChange={(v) => { setWelcomeUnlockPassword(v); setWelcomeUnlockError(null); }} onSubmit={(e) => void submitWelcomeUnlock(e)} onClose={closeWelcomeUnlock} />
<WelcomeDeleteModal open={Boolean(welcomeDeleteProfileId)} profile={welcomeDeleteProfile} onConfirm={confirmWelcomeDelete} onClose={closeWelcomeDelete} />
```

- [ ] **Step 5: Add the logo + clean up.** Pass `logoSrc` to home's `AppHeader` (~1399) — define `iglooLogoSrc` from home's public asset (check `repos/igloo-home/public/` / how pwa references `/igloo-paper-mark.png`; copy the mark into home's public dir if absent). Remove the `StoredProfilesLandingCard` + `HostEntryTile` imports and the now-unused `landingPassphrases` state.

- [ ] **Step 6: Typecheck + render the landing**

Run: `make igloo-home-typecheck`
Then: `make screenshot CLIENT=home STATE=landing` and `make screenshot CLIENT=home STATE=landing-seeded`
Expected: typecheck clean; `.tmp/agent/home-landing.png` now shows the centered Welcome hero (no old 4-card grid), `home-landing-seeded.png` shows the returning profile-unlock card.

- [ ] **Step 7: Run home unit tests**

Run: `make igloo-home-test-unit`
Expected: PASS (update any test asserting the old landing markup to the new hero).

- [ ] **Step 8: Commit home + bump pointer**

```bash
git -C repos/igloo-home add src/App.tsx public/
git -C repos/igloo-home commit -m "Adopt shared Welcome heroes on landing; drop StoredProfilesLandingCard + HostEntryTile grid"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-home
git commit -m "Bump pointer: igloo-home shared landing convergence"
```

---

### Task 3: Migrate igloo-chrome landing to the shared heroes

**Files:**
- Modify: `repos/igloo-chrome/src/pages/Onboarding.tsx` — the `StoredProfilesLandingCard` block (~289-340), imports (~14).
- Reference: pwa `renderLanding` + Task 2's home migration.

**Interfaces:**
- Consumes: same Task 1 exports.
- chrome handlers present: `onLoadStoredProfile(profileId)`, `onDeleteStoredProfile(profileId)`, unlock state (`unlockProfileId` / `unlockPassword` / `setUnlockPassword`), onboarding handlers (`onConnectOnboarding`, connect step). Chrome has **no** generate/recover.

- [ ] **Step 1: Build the chrome returning-profile model.** Map chrome's stored `profile` → `WelcomeReturningProfileModel` with `canRotate: false`, `canRecover: false`, `canDelete: true` (chrome cannot generate/recover from the landing). Derive `thresholdLabel`/`memberLabel`/`publicKeyLabel` from chrome's profile fields (reuse `shortProfileId`).

- [ ] **Step 2: Replace the StoredProfilesLandingCard block** with the returning hero (stored profiles) and entry hero (no profiles / import path):

```tsx
profiles.length === 0 ? (
  <WelcomeEntryHero
    productLabel="Igloo"
    tagline="Threshold signing for your browser."
    primaryAction={{
      heading: 'Onboard New Device',
      description: 'Use a password-protected bfonboard package to set up this browser as a signing device.',
      buttonLabel: 'Onboard Device',
      onAction: () => setMode('onboard'),
      showInfo: false,
    }}
    secondaryActions={[
      { id: 'import', label: 'Import Existing Device', onAction: () => setMode('import') },
    ]}
  />
) : (
  <WelcomeReturningHero
    productLabel="Igloo"
    layout={profiles.length === 1 ? 'single' : profiles.length <= 3 ? 'multi' : 'many'}
    profiles={profiles.map(deriveChromeReturningProfile)}
    onUnlock={(profileId) => { setSelectedProfileId(profileId); setUnlockProfileId(profileId); }}
    onRotate={() => {}}
    onDelete={(profileId) => void onDeleteStoredProfile(profileId)}
    secondaryActions={[
      { id: 'onboard', label: 'Onboard New Device', onAction: () => setMode('onboard') },
      { id: 'import', label: 'Import Existing Device', onAction: () => setMode('import') },
    ]}
  />
)
```

Wire the unlock-password entry: chrome currently renders the unlock field inside `renderProfileDetail`. With the hero, route unlock through `WelcomeUnlockModal` (Task 1/2 pattern) OR keep chrome's inline unlock if the hero's `onUnlock` opens chrome's existing `unlockProfileId` flow — verify which fits chrome's narrow page while editing and pick the modal for consistency with pwa/home. Replace `setMode`/`onLoadStoredProfile` references with chrome's actual control names (grep `Onboarding.tsx` for the real state setters; `setMode` is illustrative).

- [ ] **Step 3: Remove the `StoredProfilesLandingCard` import** from `Onboarding.tsx`.

- [ ] **Step 4: Typecheck + render the onboarding landing**

Run: `make igloo-chrome-typecheck`
Then: `make screenshot CLIENT=chrome STATE=onboarding`
Expected: typecheck clean; `.tmp/agent/chrome-onboarding.png` shows the shared Welcome hero, fits the options-page width. **If it overflows/looks cramped**, add a `compact` layout variant to the heroes (extra Task 1-style change) — only if the screenshot proves it's needed.

- [ ] **Step 5: Run chrome fast e2e**

Run: `npm --prefix test run test:e2e:igloo-chrome:fast`
Expected: PASS (update any onboarding e2e that asserted the old card markup).

- [ ] **Step 6: Commit chrome + bump pointer**

```bash
git -C repos/igloo-chrome add src/
git -C repos/igloo-chrome commit -m "Adopt shared Welcome heroes on onboarding landing; drop StoredProfilesLandingCard"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-chrome
git commit -m "Bump pointer: igloo-chrome shared landing convergence"
```

---

### Task 4: Hard-cut the dead components + final gate

**Files:**
- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx` (delete `StoredProfilesLandingCard` ~434-end, `HostEntryTile` ~351-391, and `LandingIcon` if only used by them)
- Modify: `repos/igloo-ui/src/index.ts` (remove the two exports)

- [ ] **Step 1: Confirm zero consumers**

Run: `grep -rn "StoredProfilesLandingCard\|HostEntryTile" repos/*/src repos/igloo-ui/src | grep -v "HostShell.tsx" | grep -v "src/index.ts"`
Expected: **no output**. If anything prints, that consumer was missed in Tasks 2/3 — stop and migrate it first.

- [ ] **Step 2: Delete the components + exports.** Remove `StoredProfilesLandingCard`, `HostEntryTile` (and `LandingIcon` if now unused — grep it) from `HostShell.tsx`; remove both names from `src/index.ts`.

- [ ] **Step 3: igloo-ui tests + typecheck**

Run: `npm --prefix repos/igloo-ui run test`
Expected: PASS (delete/adapt any test that referenced the removed components).

- [ ] **Step 4: Full gate**

Run: `make verify`
Then: `npm --prefix test run test:guards`
Expected: `make verify` → `{"ok":true,"exitCode":0}` in `.tmp/agent/verify.json`; guards PASS.

- [ ] **Step 5: Visual confirmation across all three** — render and eyeball convergence:

Run: `make screenshot CLIENT=pwa STATE=welcome-returning && make screenshot CLIENT=home STATE=landing-seeded && make screenshot CLIENT=chrome STATE=onboarding`
Expected: all three show the same shared Welcome hero family (centered, profile-unlock card, host-appropriate actions, no old grid/card).

- [ ] **Step 6: Commit igloo-ui + bump pointer**

```bash
git -C repos/igloo-ui add src/components/flows/HostShell.tsx src/index.ts test/
git -C repos/igloo-ui commit -m "Hard-cut dead StoredProfilesLandingCard + HostEntryTile (zero consumers after landing convergence)"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-ui
git commit -m "Bump pointer: remove dead landing components"
```

---

## Self-Review notes

- **Spec coverage:** Task 1 = shared API generalization + e2e-id preservation + pwa; Task 2 = home (incl. logoSrc, modal unlock, grid removal); Task 3 = chrome (no generate/recover, width check); Task 4 = hard-cut + verification (`make verify`, guards, per-client typechecks via the per-task screenshot/typecheck steps). All spec sections covered.
- **Illustrative names flagged:** `setMode` (chrome), `iglooLogoSrc`, `deriveHomeReturningProfile`/`deriveChromeReturningProfile`, and the `onRotate`/`onRecover` setters are marked "verify against the real file" — the implementer must grep the actual control/handler names; these are not guaranteed-existing identifiers.
- **Type consistency:** `WelcomeHeroAction` / `WelcomeEntryPrimaryAction` / capability flags defined in Task 1 are the exact types consumed in Tasks 2-3.
