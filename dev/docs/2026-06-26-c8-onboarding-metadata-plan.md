# C8 — Real Onboarding Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Completed at the current submodule pointers (`igloo-shared` `4b95c4a`, `igloo-ui` `e8aa760`, `igloo-pwa` `afab144`). Re-grounded on 2026-06-27; no additional implementation work remains for C8.

**Verification (2026-06-27):**

- `npm --prefix repos/igloo-shared run test:unit -- src/browser-profile/core/preview.test.ts`
- `npm --prefix repos/igloo-ui test -- test/onboard-handshake.test.tsx`
- `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/onboard-metadata.test.tsx`

**Goal:** Replace the hardcoded `"My Signing Key"` / `"2/3"` / `"Share #0"` shown during the live igloo-pwa onboarding handshake with the real keyset name, threshold, and share index parsed from the connected package.

**Architecture:** Add one pure helper in `igloo-shared` that derives display metadata from the `BrowserProfilePreview` the store already holds (reusing the existing `groupPackageFromWireJson` / `groupNameFromPackage` / `totalCountFromGroupPackage` parsers). Add a `shareLabel` prop to the shared `OnboardHandshakePanel`. Wire both into the igloo-pwa `OnboardHandshakeView` / `OnboardFailedView`. The share index is derived secret-free by matching the share public key against the parsed group members — the seckey-bearing `share_package_json` is never touched.

**Tech Stack:** TypeScript, React 18, Vitest + React Testing Library, three independent submodules (`igloo-shared`, `igloo-ui`, `igloo-pwa`).

## Global Constraints

- **License:** MIT, "2025 FROSTR Protocol". No new third-party deps.
- **Submodule workflow:** commit INSIDE each submodule first, then bump the pointer in `frostr-infra` (`make bump-pointers MSG="…"`). Never a recursive parent commit.
- **No formatter churn:** do not add Prettier/ESLint or reformat untouched lines (maintainer declined a formatter gate).
- **Secret hygiene:** derive the share index from public-key matching only; never parse or pass `share_package_json` / `seckey` into the view layer.
- **TDD:** failing test first, minimal implementation, green, commit.
- **Test commands:**
  - igloo-shared: `npm --prefix repos/igloo-shared run test:unit -- <path>`
  - igloo-ui: `npm --prefix repos/igloo-ui test -- <path>`
  - igloo-pwa (full): `make igloo-pwa-test-unit` · (single file, faster) `npm --prefix repos/igloo-pwa run test:unit:raw -- <path>`
- **Source consumption:** `igloo-ui` is consumed all-source by clients (edits are live, no rebuild). Confirm in Task 3 how `igloo-pwa` resolves `igloo-shared` (path/link vs published) before relying on the new export being visible.

---

## File Structure

- `repos/igloo-shared/src/browser-profile/core/preview.ts` — **add** `onboardPreviewDisplayMeta()` next to the existing `createBrowserProfilePreview()` (same module owns preview shaping).
- `repos/igloo-shared/src/browser-profile/core/preview.test.ts` — **add/extend** unit tests for the helper.
- `repos/igloo-shared/src/index.ts` — **export** the new helper + type.
- `repos/igloo-ui/src/components/flows/create/onboard-handshake.tsx` — **modify** `OnboardHandshakePanel` to accept a `shareLabel` prop (`:62-92`).
- `repos/igloo-ui/test/...onboard-handshake.test.tsx` — **add/extend** a render test for the prop.
- `repos/igloo-pwa/src/views/onboard.tsx` — **modify** `OnboardHandshakeView` (`:54-73`) and `OnboardFailedView` (`:75-102`) to derive and pass real metadata.
- `repos/igloo-pwa/test/frontend/onboard-metadata.test.tsx` — **add** a view test asserting real values render (not the hardcoded literals).

---

### Task 1: `igloo-shared` — `onboardPreviewDisplayMeta()` helper

**Files:**
- Modify: `repos/igloo-shared/src/browser-profile/core/preview.ts`
- Test: `repos/igloo-shared/src/browser-profile/core/preview.test.ts`
- Modify: `repos/igloo-shared/src/index.ts`

**Interfaces:**
- Consumes: `groupPackageFromWireJson`, `groupNameFromPackage`, `totalCountFromGroupPackage`, `xOnlyFromCompressedPubkey` (all from `../../profile-package`); `BrowserProfilePreview` (from `./types`, fields `group_package_json: string`, `share_public_key: string`).
- Produces: `onboardPreviewDisplayMeta(preview: BrowserProfilePreview): OnboardPreviewDisplayMeta` where `OnboardPreviewDisplayMeta = { keysetName: string; thresholdLabel: string; shareLabel: string }`.

- [ ] **Step 1: Write the failing test**

Add to `repos/igloo-shared/src/browser-profile/core/preview.test.ts` (create if absent; if present, append the `describe` block and reuse existing payload fixtures via `createBrowserProfilePreview`):

```ts
import { describe, expect, it } from 'vitest';
import { createBrowserProfilePreview, onboardPreviewDisplayMeta } from './preview';
import type { BrowserProfilePackagePayload } from '../../profile-package';

// Minimal 2-of-3 payload; member pubkeys must match the share secrets' derived
// public keys for index resolution. Reuse the repo's existing keyset test
// fixture if one is exported; otherwise build via the keyset WASM test helper.
function fixturePayload(): BrowserProfilePackagePayload {
  // NOTE: replace with the existing shared test fixture for a real 2-of-3 keyset.
  // The fixture MUST produce a group package with groupName "Acme Keyset",
  // threshold 2, 3 members, and a device shareSecret belonging to member idx 1.
  return TEST_2_OF_3_PAYLOAD_ACME; // defined in the shared test fixtures module
}

describe('onboardPreviewDisplayMeta', () => {
  it('derives keyset name, threshold label, and share index from the preview', () => {
    const preview = createBrowserProfilePreview(fixturePayload(), 'onboard');
    const meta = onboardPreviewDisplayMeta(preview);
    expect(meta.keysetName).toBe('Acme Keyset');
    expect(meta.thresholdLabel).toBe('2/3');
    expect(meta.shareLabel).toBe('Share #1');
  });

  it('falls back to a generic share label when the share is not a group member', () => {
    const preview = createBrowserProfilePreview(fixturePayload(), 'onboard');
    const orphaned = { ...preview, share_public_key: 'f'.repeat(64) };
    expect(onboardPreviewDisplayMeta(orphaned).shareLabel).toBe('Share');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix repos/igloo-shared run test:unit -- src/browser-profile/core/preview.test.ts`
Expected: FAIL — `onboardPreviewDisplayMeta` is not exported.

- [ ] **Step 3: Implement the helper**

Append to `repos/igloo-shared/src/browser-profile/core/preview.ts` (the file already imports `groupPublicKeyFromPackage`, `xOnlyFromCompressedPubkey`, etc.; add the three named imports it doesn't yet have):

```ts
import {
  groupPackageFromWireJson,
  groupNameFromPackage,
  totalCountFromGroupPackage,
} from '../../profile-package';
import type { BrowserProfilePreview } from './types';

export type OnboardPreviewDisplayMeta = {
  keysetName: string;
  thresholdLabel: string;
  shareLabel: string;
};

/**
 * Derive human-facing onboarding metadata (keyset name, `threshold/count`
 * label, and `Share #idx`) from a profile preview. The share index is resolved
 * secret-free by matching the preview's share public key against the parsed
 * group members — the seckey-bearing `share_package_json` is never read.
 */
export function onboardPreviewDisplayMeta(
  preview: BrowserProfilePreview,
): OnboardPreviewDisplayMeta {
  const group = groupPackageFromWireJson(preview.group_package_json);
  const member = group.members.find(
    (candidate) => xOnlyFromCompressedPubkey(candidate.pubkey) === preview.share_public_key,
  );
  return {
    keysetName: groupNameFromPackage(group),
    thresholdLabel: `${group.threshold}/${totalCountFromGroupPackage(group)}`,
    shareLabel: member ? `Share #${member.idx}` : 'Share',
  };
}
```

- [ ] **Step 4: Export from the barrel**

In `repos/igloo-shared/src/index.ts`, add to the existing `igloo-shared` export block (near the other `browser-profile/core` re-exports):

```ts
export { onboardPreviewDisplayMeta } from './browser-profile/core/preview';
export type { OnboardPreviewDisplayMeta } from './browser-profile/core/preview';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npm --prefix repos/igloo-shared run test:unit -- src/browser-profile/core/preview.test.ts`
Expected: PASS (both cases).

- [ ] **Step 6: Typecheck + full unit run**

Run: `npm --prefix repos/igloo-shared run test:unit`
Expected: PASS, no type errors.

- [ ] **Step 7: Commit (inside the submodule)**

```bash
git -C repos/igloo-shared add src/browser-profile/core/preview.ts src/browser-profile/core/preview.test.ts src/index.ts
git -C repos/igloo-shared commit -m "Add onboardPreviewDisplayMeta for real onboarding metadata"
```

---

### Task 2: `igloo-ui` — `shareLabel` prop on `OnboardHandshakePanel`

**Files:**
- Modify: `repos/igloo-ui/src/components/flows/create/onboard-handshake.tsx:62-92`
- Test: `repos/igloo-ui/test/onboard-handshake.test.tsx` (create or extend the existing create-flow test)

**Interfaces:**
- Produces: `OnboardHandshakePanel` gains an optional `shareLabel?: string` prop (default preserves current `"Share #0"` text for other callers); renders `{shareLabel}` in place of the hardcoded literal at `:86`.

- [ ] **Step 1: Write the failing test**

Create `repos/igloo-ui/test/onboard-handshake.test.tsx`:

```tsx
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { OnboardHandshakePanel } from '../src/components/flows/create/onboard-handshake';

describe('OnboardHandshakePanel', () => {
  it('renders the provided keyset, threshold, and share label', () => {
    render(
      <OnboardHandshakePanel
        keysetName="Acme Keyset"
        thresholdLabel="2/3"
        shareLabel="Share #1"
      />,
    );
    expect(screen.getByText(/Acme Keyset \(2\/3\)/)).toBeInTheDocument();
    expect(screen.getByText(/Share #1/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix repos/igloo-ui test -- test/onboard-handshake.test.tsx`
Expected: FAIL — `shareLabel` is ignored; the panel still renders `"Share #0"`.

- [ ] **Step 3: Add the prop**

In `repos/igloo-ui/src/components/flows/create/onboard-handshake.tsx`, edit `OnboardHandshakePanel`'s props (`:62-76`) to add `shareLabel = 'Share #0'`, and change `:86` from `· Share #0` to `· {shareLabel}`:

```tsx
export function OnboardHandshakePanel({
  packageText = '',
  keysetName = 'My Signing Key',
  thresholdLabel = '2/3',
  shareLabel = 'Share #0',
  activeStep = 'negotiate',
  onCancel,
  title = 'Onboard Device',
}: {
  packageText?: string;
  keysetName?: string;
  thresholdLabel?: string;
  shareLabel?: string;
  activeStep?: OnboardTimelineStepKey;
  onCancel?: () => void;
  title?: string;
}) {
  const compactPackage = packageText ? packageText.slice(0, 24) : 'bfonboard1...';
  return (
    <div className="igloo-onboard-handshake-flow">
      <header>
        <h3>{title}</h3>
        <p>Validating the onboarding package and saving this device's share.</p>
      </header>
      <OnboardTimeline steps={buildOnboardSteps(keysetName, thresholdLabel)} activeStep={activeStep} />
      <div className="igloo-onboard-package-summary">
        Onboarding package: {compactPackage} · {shareLabel}
      </div>
      <Button type="button" variant="secondary" onClick={onCancel}>
        Cancel Onboarding
      </Button>
    </div>
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npm --prefix repos/igloo-ui test -- test/onboard-handshake.test.tsx`
Expected: PASS.

- [ ] **Step 5: Full unit run**

Run: `npm --prefix repos/igloo-ui test`
Expected: PASS (no regression in existing create-flow tests).

- [ ] **Step 6: Commit (inside the submodule)**

```bash
git -C repos/igloo-ui add src/components/flows/create/onboard-handshake.tsx test/onboard-handshake.test.tsx
git -C repos/igloo-ui commit -m "Add shareLabel prop to OnboardHandshakePanel"
```

---

### Task 3: `igloo-pwa` — wire real metadata into the onboarding views

**Files:**
- Modify: `repos/igloo-pwa/src/views/onboard.tsx:54-102`
- Test: `repos/igloo-pwa/test/frontend/onboard-metadata.test.tsx`

**Interfaces:**
- Consumes: `onboardPreviewDisplayMeta` (Task 1, from `igloo-shared`); `OnboardHandshakePanel` `shareLabel` prop (Task 2); `store.pendingOnboardConnection.preview` (a `BrowserProfilePreview`).

- [ ] **Step 0: Verify the preview type (no-placeholder guard)**

Confirm `store.pendingOnboardConnection.preview` is a `BrowserProfilePreview` carrying `group_package_json` + `share_public_key` (grep the store's `pendingOnboardConnection` type and `connectOnboardingPackage` return). Also confirm `igloo-pwa` resolves `igloo-shared` such that the new export is visible (path/link vs published version — if published, the pointer bump from Task 1 must land in `igloo-pwa`'s lockfile first). If the preview is the slim `SharedOnboardProfilePreview` without the JSON, STOP — the helper input must instead come from the full connection object; adjust the source accordingly before proceeding.

- [ ] **Step 1: Write the failing test**

Create `repos/igloo-pwa/test/frontend/onboard-metadata.test.tsx`:

```tsx
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { OnboardHandshakeView } from '../../src/views/onboard';

// Build a store stub whose pendingOnboardConnection.preview yields the Acme 2-of-3
// metadata via onboardPreviewDisplayMeta. Reuse the existing store test harness /
// fixture used by store-onboard tests for the preview shape.
function storeStub() {
  return {
    pendingOnboardConnection: { preview: ACME_2_OF_3_PREVIEW },
    drafts: { onboardConnectForm: { packageText: 'bfonboard1abc' } },
    setActiveView: () => {},
  } as unknown as Parameters<typeof OnboardHandshakeView>[0]['store'];
}

describe('OnboardHandshakeView metadata', () => {
  it('shows the real keyset, threshold, and share index — not the placeholders', () => {
    render(<OnboardHandshakeView store={storeStub()} />);
    expect(screen.getByText(/Acme Keyset \(2\/3\)/)).toBeInTheDocument();
    expect(screen.getByText(/Share #1/)).toBeInTheDocument();
    expect(screen.queryByText(/My Signing Key/)).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/onboard-metadata.test.tsx`
Expected: FAIL — the view still renders `"My Signing Key"` / `"2/3"` and no real share index.

- [ ] **Step 3: Wire the helper into both views**

In `repos/igloo-pwa/src/views/onboard.tsx`, add `onboardPreviewDisplayMeta` to the existing `from 'igloo-shared'` import, and update `OnboardHandshakeView` (`:54-73`) and `OnboardFailedView` (`:75-102`):

```tsx
import { onboardPreviewDisplayMeta, pingRelay } from 'igloo-shared';

// ...

export function OnboardHandshakeView({ store }: { store: PwaStore }) {
  const preview = store.pendingOnboardConnection?.preview;
  const meta = preview ? onboardPreviewDisplayMeta(preview) : null;
  return (
    <>
      <PublicTaskShell>
        <StepProgress steps={ONBOARD_FLOW_STEPS} active={1} />
        <section className="igloo-flow-root">
          <OnboardHandshakePanel
            title="Onboard Device"
            packageText={store.drafts.onboardConnectForm.packageText}
            keysetName={meta?.keysetName ?? 'Signing Keyset'}
            thresholdLabel={meta?.thresholdLabel ?? ''}
            shareLabel={meta?.shareLabel}
            activeStep="negotiate"
            onCancel={() => store.setActiveView('onboard-connect')}
          />
        </section>
      </PublicTaskShell>
      <PublicFocusFooter />
    </>
  );
}
```

Apply the same `preview`/`meta` derivation in `OnboardFailedView`, passing `keysetName={meta?.keysetName ?? 'Signing Keyset'}` and `thresholdLabel={meta?.thresholdLabel ?? ''}` to `OnboardFailedPanel` (it has no share label).

- [ ] **Step 4: Run the test to verify it passes**

Run: `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/onboard-metadata.test.tsx`
Expected: PASS.

- [ ] **Step 5: Full pwa unit run + typecheck**

Run: `make igloo-pwa-test-unit`
Expected: PASS, no type errors.

- [ ] **Step 6: Commit (inside the submodule)**

```bash
git -C repos/igloo-pwa add src/views/onboard.tsx test/frontend/onboard-metadata.test.tsx
git -C repos/igloo-pwa commit -m "Show real onboarding metadata in handshake/failed views (C8)"
```

---

### Task 4: Bump submodule pointers

- [ ] **Step 1: Record all three moved pointers in one parent commit**

```bash
make bump-pointers MSG="Bump igloo-shared/ui/pwa: real onboarding metadata (C8)"
```

- [ ] **Step 2: Verify the gate**

Run: `make verify`
Expected: guards + typecheck + @fast e2e green (exit 0); result mirrored in `.tmp/agent/verify.json`.

---

## Self-Review

**Spec coverage:** C8's three hardcoded sites are all covered — `keysetName`/`thresholdLabel` in `OnboardHandshakeView` (Task 3) and `OnboardFailedView` (Task 3), and `"Share #0"` in `OnboardHandshakePanel` (Task 2), fed by the parser helper (Task 1). The failure-path view is included.

**Placeholder scan:** The test fixtures (`TEST_2_OF_3_PAYLOAD_ACME`, `ACME_2_OF_3_PREVIEW`) are named but must be bound to the repo's real shared keyset test fixture during Task 1/Task 3 — flagged inline as the one thing to wire to existing fixtures, not invent. Step 0 in Task 3 is an explicit guard against the preview-type assumption.

**Type consistency:** `onboardPreviewDisplayMeta(preview: BrowserProfilePreview): OnboardPreviewDisplayMeta` is defined in Task 1 and consumed with that exact name/shape in Task 3; the `shareLabel?: string` prop defined in Task 2 is passed in Task 3. `thresholdLabel` format (`"2/3"`) is consistent across all three tasks.

**Open risk:** the share-index test expects `Share #1` — confirm the chosen fixture's device share belongs to member idx 1 (adjust the expectation to the fixture's actual idx if different).
