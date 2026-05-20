# Igloo Paper Design System Hard-Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the hard-cut migration from Paper design references into `igloo-ui` while preserving `igloo-shared` as the runtime/domain contract package and keeping Paper artifacts out of runtime builds.

**Architecture:** `igloo-paper` remains reference-only. `igloo-ui` owns React components, semantic design tokens, view models, and UI adapters. `igloo-shared` owns runtime/profile/package semantics and may expose pure projection helpers, but never imports React or CSS.

**Tech Stack:** React 18, TypeScript, Tailwind CSS, Vitest, Testing Library, Playwright, FROSTR submodules under `repos/`.

---

## Current Baseline

The first milestone is already in progress:

- `dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md` exists as the API/mismatch gate.
- `repos/igloo-ui` has Paper token CSS/TS exports, semantic Tailwind colors, additive Paper `AppHeader` modes, `PageBackLink`, view-model types, and primitive token refactors.
- `test/igloo-ui-showcase` renders welcome/create/dashboard/policies reference screens and writes screenshots under `.tmp/igloo-ui-showcase/`.
- `repos/bifrost-rs` and `repos/igloo-chrome` are not initialized, so root guards currently fail on release-doc link checks.

## Task 1: Review Gate And Commit Current Milestone

**Files:**
- Review: `dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md`
- Review: `dev/reports/igloo-ui-paper-design-system-investigation-2026-05-20.md`
- Commit in submodule: `repos/igloo-ui`
- Commit in root: `dev/reports/*`, `test/igloo-ui-showcase/*`, `test/package.json`, `test/shared/repo-paths.ts`

- [ ] **Step 1: Confirm the API ledger is the approved break set**

Read:

```bash
sed -n '1,260p' dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md
```

Approved hard-cut breaks are:

- Replace generic `AppHeader` usage with Paper modes.
- Move task back navigation to `PageBackLink`.
- Replace loose stored-profile props with `StoredProfileCardModel`.
- Split create and rotate presentation surfaces.
- Replace large dashboard prop lists with cohesive view models.
- Replace duplicated policy/settings/log types with UI models mapped from `igloo-shared` data.

If the ledger content differs from this list, stop and revise this plan before code changes.

- [ ] **Step 2: Verify current milestone before committing**

Run:

```bash
npm test
npm run build
```

from `repos/igloo-ui`.

Expected:

- Vitest passes.
- Package build passes and writes `dist/styles.css`.

Run:

```bash
npm --prefix test run test:igloo-ui-showcase
```

from the root. If Chromium fails under sandbox on macOS, rerun outside sandbox with the same command.

Expected:

- Four showcase tests pass.
- Screenshots exist in `.tmp/igloo-ui-showcase/`.

- [ ] **Step 3: Commit `igloo-ui` milestone**

Run:

```bash
cd repos/igloo-ui
git add scripts/build.mjs src/components/ui src/index.ts src/models src/styles.css src/tokens tailwind.config.js test/PaperNavigation.test.tsx test/PaperPrimitives.test.tsx test/PaperTokens.test.tsx
git commit -m "Add Paper token bridge and semantic UI primitives"
```

Expected:

- `repos/igloo-ui` has a focused commit containing token bridge, primitive refactor, navigation additions, and tests.

- [ ] **Step 4: Commit root milestone**

Run:

```bash
git add dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md dev/reports/igloo-ui-paper-design-system-investigation-2026-05-20.md test/package.json test/shared/repo-paths.ts test/igloo-ui-showcase repos/igloo-ui
git commit -m "Add Igloo UI Paper design-system cutover baseline"
```

Expected:

- Root commit records the report artifacts, showcase harness, and updated `igloo-ui` submodule pointer.

## Task 2: Restore Root Guard Preconditions

**Files:**
- Populate submodules: `repos/bifrost-rs`, `repos/igloo-chrome`
- No code edits expected.

- [ ] **Step 1: Initialize missing guard submodules**

Run:

```bash
git submodule update --init repos/bifrost-rs repos/igloo-chrome
```

Expected:

- `repos/bifrost-rs` checks out `4a9d4f86b92a7f832137cab63ba361c70ed2e0fa`.
- `repos/igloo-chrome` checks out `1d92ce0bbbe842754b08528e21d12fc969ec9ccd`.

- [ ] **Step 2: Verify root guard link preconditions**

Run:

```bash
test -f repos/bifrost-rs/RELEASE.md
test -f repos/igloo-chrome/RELEASE.md
npm --prefix test run test:guards
```

Expected:

- The two `test -f` commands exit 0.
- `test:guards` reaches completion. If it fails after link checks, treat the new failure as a separate existing guard issue and record the exact failing command/output in the final summary.

## Task 3: Implement The UI Adapter Boundary

**Files:**
- Create: `repos/igloo-ui/src/adapters/runtime-view-models.ts`
- Test: `repos/igloo-ui/test/PaperAdapters.test.ts`
- Modify: `repos/igloo-ui/src/index.ts`
- Optional shared helper edits only if needed: `repos/igloo-shared/src/browser-runtime-core.ts`, `repos/igloo-shared/src/observability.ts`

- [ ] **Step 1: Write failing adapter tests**

Create `repos/igloo-ui/test/PaperAdapters.test.ts` with tests for these exported functions:

```ts
import { describe, expect, it } from 'vitest';

import {
  runtimeStatusToSignerDashboardView,
  runtimePeerPermissionStatesToPolicyDashboardView,
  observabilityEventsToEventRows,
} from '../src';

describe('Paper runtime adapters', () => {
  it('maps runtime status into the signer dashboard view model', () => {
    const view = runtimeStatusToSignerDashboardView({
      status: { device_id: 'device-1', pending_ops: 1, last_active: 1700000000, known_peers: 2, request_seq: 7 },
      metadata: {
        device_id: 'device-1',
        member_idx: 1,
        share_public_key: 'share-pub-1',
        group_public_key: 'group-pub-1',
        peers: ['peer-1', 'peer-2'],
      },
      readiness: {
        runtime_ready: true,
        restore_complete: true,
        sign_ready: true,
        ecdh_ready: true,
        threshold: 2,
        signing_peer_count: 2,
        ecdh_peer_count: 2,
        last_refresh_at: 1700000000,
        degraded_reasons: [],
      },
      peers: [
        {
          idx: 2,
          pubkey: 'peer-1',
          known: true,
          last_seen: 1700000000,
          online: true,
          incoming_available: 9,
          outgoing_available: 7,
          outgoing_spent: 1,
          can_sign: true,
          should_send_nonces: false,
        },
      ],
      peer_permission_states: [],
      pending_operations: [
        {
          op_type: 'sign',
          request_id: 'req-1',
          started_at: 1700000000,
          timeout_at: 1700000300,
          target_peers: ['peer-1', 'peer-2'],
          threshold: 2,
          collected_responses: [{}],
          context: {},
        },
      ],
    });

    expect(view.profileName).toBe('device-1');
    expect(view.thresholdLabel).toBe('2/2');
    expect(view.readinessLabel).toBe('Signer online');
    expect(view.peerRows[0]).toMatchObject({
      alias: 'Peer #2',
      pubkey: 'peer-1',
      state: 'online',
      statusLabel: 'sign-ready',
      incomingAvailable: 9,
      outgoingAvailable: 7,
      outgoingSpent: 1,
    });
    expect(view.pendingOperationRows[0]).toMatchObject({
      id: 'req-1',
      operationLabel: 'sign',
      thresholdLabel: 'threshold 2',
      responseLabel: '1 response',
    });
  });

  it('maps runtime peer permission states into the policy dashboard view model', () => {
    const view = runtimePeerPermissionStatesToPolicyDashboardView([
      {
        pubkey: 'peer-1',
        manual_override: {
          request: { ping: 'allow', onboard: 'unset', sign: 'deny', ecdh: 'unset' },
          respond: { ping: 'unset', onboard: 'allow', sign: 'allow', ecdh: 'deny' },
        },
        remote_observation: null,
        effective_policy: {
          request: { ping: true, onboard: false, sign: false, ecdh: false },
          respond: { ping: true, onboard: true, sign: true, ecdh: false },
        },
      },
    ]);

    expect(view.peerRows[0].pubkey).toBe('peer-1');
    expect(view.peerRows[0].request.sign).toBe(false);
    expect(view.peerRows[0].respond.onboard).toBe(true);
    expect(view.peerRows[0].manualOverride?.request.ping).toBe('allow');
  });

  it('maps observability events into Paper event log rows', () => {
    const rows = observabilityEventsToEventRows([
      { ts: 1700000000000, level: 'warn', component: 'runtime', domain: 'runtime', event: 'restore_skipped', reason: 'missing_snapshot' },
      { ts: 1700000001000, level: 'error', component: 'runtime', domain: 'runtime', event: 'failure', message: 'sign failed' },
    ]);

    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ badgeLabel: 'runtime', badgeTone: 'warning' });
    expect(rows[1]).toMatchObject({ badgeLabel: 'runtime', badgeTone: 'danger', message: 'sign failed' });
  });
});
```

- [ ] **Step 2: Run failing adapter tests**

Run:

```bash
npm test -- PaperAdapters
```

from `repos/igloo-ui`.

Expected:

- Fails because adapter exports are missing.

- [ ] **Step 3: Implement adapter module**

Create `repos/igloo-ui/src/adapters/runtime-view-models.ts` exporting:

```ts
import type {
  EventLogRowModel,
  PeerPolicyRowModel,
  PeerReadinessRowModel,
  PendingOperationRowModel,
  PolicyDashboardViewModel,
  SignerDashboardViewModel,
} from '../models/view-models';

type RuntimePeerStatusInput = {
  idx: number;
  pubkey: string;
  known: boolean;
  last_seen: number | null;
  online: boolean;
  incoming_available: number;
  outgoing_available: number;
  outgoing_spent: number;
  can_sign: boolean;
  should_send_nonces: boolean;
};

type RuntimePendingOperationInput = {
  op_type: string;
  request_id: string;
  started_at: number;
  timeout_at: number;
  target_peers: string[];
  threshold: number;
  collected_responses: unknown[];
  context: unknown;
};

type RuntimeMethodPolicy = {
  ping: boolean;
  onboard: boolean;
  sign: boolean;
  ecdh: boolean;
};

type RuntimeMethodPolicyOverride = {
  ping: 'unset' | 'allow' | 'deny';
  onboard: 'unset' | 'allow' | 'deny';
  sign: 'unset' | 'allow' | 'deny';
  ecdh: 'unset' | 'allow' | 'deny';
};

type RuntimePeerPermissionStateInput = {
  pubkey: string;
  manual_override: {
    request: RuntimeMethodPolicyOverride;
    respond: RuntimeMethodPolicyOverride;
  };
  remote_observation: {
    request: RuntimeMethodPolicy;
    respond: RuntimeMethodPolicy;
    updated: number;
    revision: number;
  } | null;
  effective_policy: {
    request: RuntimeMethodPolicy;
    respond: RuntimeMethodPolicy;
  };
};

type RuntimeStatusSummaryInput = {
  status: {
    device_id: string;
    pending_ops: number;
    last_active: number;
    known_peers: number;
    request_seq: number;
  };
  metadata: {
    device_id: string;
    member_idx: number;
    share_public_key: string;
    group_public_key: string;
    peers: string[];
  };
  readiness: {
    runtime_ready: boolean;
    restore_complete: boolean;
    sign_ready: boolean;
    ecdh_ready: boolean;
    threshold: number;
    signing_peer_count: number;
    ecdh_peer_count: number;
    last_refresh_at: number | null;
    degraded_reasons: string[];
  };
  peers: RuntimePeerStatusInput[];
  peer_permission_states: RuntimePeerPermissionStateInput[];
  pending_operations: RuntimePendingOperationInput[];
};

type ObservabilityEventInput = {
  ts: number;
  level: 'debug' | 'info' | 'warn' | 'error';
  component: string;
  domain: string;
  event: string;
  message?: string;
  [key: string]: unknown;
};

export function runtimeStatusToSignerDashboardView(
  status: RuntimeStatusSummaryInput
): SignerDashboardViewModel {
  return {
    profileName: status.metadata.device_id,
    thresholdLabel: `${status.readiness.threshold}/${status.metadata.peers.length}`,
    publicKeyLabel: status.metadata.group_public_key,
    shareLabel: `Share #${status.metadata.member_idx}`,
    readinessLabel: status.readiness.sign_ready ? 'Signer online' : 'Signer degraded',
    relaySummary: status.readiness.degraded_reasons.length
      ? status.readiness.degraded_reasons.join(', ')
      : 'Runtime ready',
    peerRows: status.peers.map(runtimePeerToReadinessRow),
    pendingOperationRows: status.pending_operations.map(pendingOperationToRow),
    eventRows: [],
  };
}

export function runtimePeerPermissionStatesToPolicyDashboardView(
  states: RuntimePeerPermissionStateInput[]
): PolicyDashboardViewModel {
  return {
    peerRows: states.map((state): PeerPolicyRowModel => ({
      pubkey: state.pubkey,
      request: state.effective_policy.request,
      respond: state.effective_policy.respond,
      manualOverride: {
        request: state.manual_override.request,
        respond: state.manual_override.respond,
      },
    })),
  };
}

export function observabilityEventsToEventRows(
  events: ObservabilityEventInput[]
): EventLogRowModel[] {
  return events.map((event) => ({
    id: `${event.ts}-${event.component}-${event.domain}-${event.event}`,
    badgeLabel: event.domain,
    badgeTone: event.level === 'error' ? 'danger' : event.level === 'warn' ? 'warning' : 'info',
    message: event.message ?? event.event,
    timestampLabel: new Date(event.ts).toLocaleTimeString(),
  }));
}

function runtimePeerToReadinessRow(peer: RuntimePeerStatusInput): PeerReadinessRowModel {
  return {
    id: peer.pubkey,
    alias: `Peer #${peer.idx}`,
    pubkey: peer.pubkey,
    state: peer.online ? (peer.can_sign ? 'online' : 'idle') : peer.known ? 'warning' : 'offline',
    statusLabel: peer.can_sign ? 'sign-ready' : peer.online ? 'online' : peer.known ? 'known' : 'offline',
    incomingAvailable: peer.incoming_available,
    outgoingAvailable: peer.outgoing_available,
    outgoingSpent: peer.outgoing_spent,
  };
}

function pendingOperationToRow(operation: RuntimePendingOperationInput): PendingOperationRowModel {
  const responseCount = operation.collected_responses.length;
  return {
    id: operation.request_id,
    operationLabel: operation.op_type,
    thresholdLabel: `threshold ${operation.threshold}`,
    startedLabel: formatTimestamp(operation.started_at),
    timeoutLabel: formatTimestamp(operation.timeout_at),
    responseLabel: `${responseCount} ${responseCount === 1 ? 'response' : 'responses'}`,
  };
}

function formatTimestamp(value: number) {
  const normalized = value > 10_000_000_000 ? value : value * 1000;
  return new Date(normalized).toLocaleString();
}
```

- [ ] **Step 4: Export adapters**

Modify `repos/igloo-ui/src/index.ts`:

```ts
export * from './adapters/runtime-view-models';
```

- [ ] **Step 5: Run adapter verification**

Run:

```bash
npm test -- PaperAdapters
npm test
npm run build
```

from `repos/igloo-ui`.

Expected:

- Adapter tests pass.
- Full tests pass.
- Build passes.

- [ ] **Step 6: Commit adapter boundary**

Run:

```bash
cd repos/igloo-ui
git add src/adapters src/index.ts test/PaperAdapters.test.ts
git commit -m "Add Paper runtime view adapters"
```

## Task 4: Hard-Cut Header And Stored Profile Components

**Files:**
- Modify: `repos/igloo-ui/src/components/ui/app-header.tsx`
- Modify: `repos/igloo-ui/src/components/flows/HostShell.tsx`
- Modify: `repos/igloo-ui/src/components/flows/CreateFlow.tsx`
- Modify: `repos/igloo-ui/src/index.ts`
- Test: `repos/igloo-ui/test/PaperNavigation.test.tsx`
- Test: `repos/igloo-ui/test/CreateFlow.test.tsx`

- [ ] **Step 1: Update tests to require hard-cut APIs**

Update `PaperNavigation.test.tsx` so `AppHeader` usage always includes `mode`, and remove assertions that depend on legacy generic `right`.

Add this stored-profile test to `CreateFlow.test.tsx`:

```ts
it('renders Paper stored profile card models', () => {
  const onLoad = vi.fn();
  const onDelete = vi.fn();

  render(
    <StoredProfilesLandingCard
      profiles={[
        {
          id: 'profile-1',
          label: 'Primary Browser Device',
          shortId: 'npub1qe3...7k4m',
          thresholdLabel: '2/3',
          state: 'available',
          primaryActionLabel: 'Load Profile',
          destructiveActionLabel: 'Delete',
        },
      ]}
      onLoad={onLoad}
      onDelete={onDelete}
    />,
  );

  expect(screen.getByText('Primary Browser Device')).toBeInTheDocument();
  expect(screen.getByText('npub1qe3...7k4m')).toBeInTheDocument();
  expect(screen.getByText('2/3')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Load Profile' }));
  expect(onLoad).toHaveBeenCalledWith('profile-1');
  fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
  expect(onDelete).toHaveBeenCalledWith('profile-1');
});
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
npm test -- PaperNavigation CreateFlow
```

Expected:

- Fails because `StoredProfilesLandingCard` still expects legacy `HostStoredProfileSummary` fields or because legacy header props are still accepted.

- [ ] **Step 3: Hard-cut `AppHeader` prop type**

In `repos/igloo-ui/src/components/ui/app-header.tsx`, remove generic legacy props from the public type:

- Remove `title`, `subtitle`, `right`, and `centered`.
- Keep `logoSrc`, `logoAlt`, `className`.
- Require `mode`.
- Use `links`, `taskLabel`, `profileName`, and `actions` only in their relevant modes.

The component must render Paper header modes exactly:

- `welcome`: brand, subtitle, Website/Docs/GitHub links.
- `task`: brand, subtitle, passive flow tag.
- `profile`: brand, profile name.
- `dashboard`: brand, dashboard actions.

- [ ] **Step 4: Hard-cut stored profile model**

In `repos/igloo-ui/src/components/flows/HostShell.tsx`:

- Replace `HostStoredProfileSummary` with exported `StoredProfileCardModel`.
- Render `shortId`, `thresholdLabel`, `publicKeyLabel`, `updatedLabel`, and `state` when present.
- Use `primaryActionLabel ?? 'Load Profile'`.
- Use `destructiveActionLabel ?? 'Delete'`.
- Keep `onSelect`, `onLoad`, `onDelete`, `loadDisabled`, and `deleteDisabled`.

- [ ] **Step 5: Update imports and exports**

Ensure `StoredProfileCardModel` is imported from `../../models/view-models` in `HostShell.tsx` and exported through `src/index.ts`.

- [ ] **Step 6: Verify hard-cut header/profile changes**

Run:

```bash
npm test -- PaperNavigation CreateFlow
npm test
npm run build
```

Expected:

- Targeted tests pass.
- Full tests pass.
- Build passes.

- [ ] **Step 7: Commit header/profile hard cut**

Run:

```bash
cd repos/igloo-ui
git add src/components/ui/app-header.tsx src/components/flows/HostShell.tsx src/index.ts test/PaperNavigation.test.tsx test/CreateFlow.test.tsx
git commit -m "Hard cut Paper header and stored profile APIs"
```

## Task 5: Split Create, Rotate, And Policy Presentation

**Files:**
- Modify: `repos/igloo-ui/src/components/flows/CreateFlow.tsx`
- Modify: `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx`
- Modify: `repos/igloo-ui/src/components/flows/OperatorPermissionsPanel.tsx`
- Test: `repos/igloo-ui/test/CreateFlow.test.tsx`
- Test: `repos/igloo-ui/test/OperatorPanels.test.tsx`

- [ ] **Step 1: Write failing tests for split create/rotate presentation**

Update `CreateFlow.test.tsx`:

- `CreateFlowGenerateCard` only accepts create-keyset props.
- New `RotateKeysetPanel` accepts selected source profile and recovery share entries.
- Create test asserts `CreateFlowGenerateCard` no longer renders "Rotate Existing Keyset".
- Rotate test asserts `RotateKeysetPanel` renders "Rotate Keyset" and calls `onAddRotationSource`.

- [ ] **Step 2: Write failing tests for dashboard view models**

Update `OperatorPanels.test.tsx`:

- `OperatorSignerPanel` accepts `view: SignerDashboardViewModel` instead of large profile/runtime prop lists.
- `OperatorPermissionsPanel` accepts `view: PolicyDashboardViewModel`.
- Keep action callbacks separate: `onPrimaryAction`, `onRefreshPeers`, `onPeerPolicyOverrideChange`, `onClearAllPeerPermissions`.

- [ ] **Step 3: Run failing tests**

Run:

```bash
npm test -- CreateFlow OperatorPanels
```

Expected:

- Fails because old props are still required.

- [ ] **Step 4: Implement split create/rotate presentation**

In `CreateFlow.tsx`:

- Keep `CreateFlowGenerateCard` focused on `groupName`, `threshold`, `count`, and `onGenerate`.
- Add `RotateKeysetPanel` for source profile and recovery share inputs.
- Keep existing lower-level distribution/local-save/review components unchanged.

- [ ] **Step 5: Implement dashboard view-model panels**

In `OperatorSignerPanel.tsx`:

- Replace `profile`, `runtimeState`, `runtimeSummaryLabel`, `peers`, `pendingOperations`, and `logs` props with `view: SignerDashboardViewModel`.
- Keep action callbacks as callbacks.
- Render peer rows and pending operation rows from `view`.

In `OperatorPermissionsPanel.tsx`:

- Replace `peerPermissions` and `peerPermissionStates` props with `view: PolicyDashboardViewModel`.
- Render request/respond policy tags from `view.peerRows`.
- Keep edit callbacks keyed by `pubkey`, direction, method, value.

- [ ] **Step 6: Verify split flow/dashboard changes**

Run:

```bash
npm test -- CreateFlow OperatorPanels
npm test
npm run build
```

Expected:

- Targeted tests pass.
- Full tests pass.
- Build passes.

- [ ] **Step 7: Commit flow/dashboard hard cut**

Run:

```bash
cd repos/igloo-ui
git add src/components/flows/CreateFlow.tsx src/components/flows/OperatorSignerPanel.tsx src/components/flows/OperatorPermissionsPanel.tsx test/CreateFlow.test.tsx test/OperatorPanels.test.tsx
git commit -m "Hard cut Paper flow and dashboard view models"
```

## Task 6: Update Real Consumers Or Add Explicit Compatibility Adapters

**Files:**
- Inspect and modify initialized consumer repos that import `igloo-ui`: `repos/igloo-chrome`, `repos/igloo-pwa`, `repos/igloo-home`, `repos/igloo-shell` if populated.
- Root tests under `test/igloo-pwa`, `test/igloo-chrome`, and `test/igloo-home`.

- [ ] **Step 1: Find consumer usage**

Run:

```bash
rg -n "AppHeader|StoredProfilesLandingCard|CreateFlowGenerateCard|OperatorSignerPanel|OperatorPermissionsPanel|OperatorSettingsPanel|PeerList|CreateFlow" repos -g '*.tsx' -g '*.ts'
```

Expected:

- All consumer call sites are listed.

- [ ] **Step 2: Update each consumer to use adapters**

For each call site:

- Convert shared runtime/profile data into `StoredProfileCardModel`, `SignerDashboardViewModel`, or `PolicyDashboardViewModel`.
- Use `runtimeStatusToSignerDashboardView()`, `runtimePeerPermissionStatesToPolicyDashboardView()`, and `observabilityEventsToEventRows()` where runtime data is available.
- Use `AppHeader mode="welcome"`, `mode="task"`, `mode="profile"`, or `mode="dashboard"` explicitly.
- Replace in-header back controls with `PageBackLink`.

- [ ] **Step 3: Run consumer checks**

Run available checks for populated consumers:

```bash
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix test run test:e2e:igloo-pwa:fast
npm --prefix test run test:e2e:igloo-chrome:fast
npm --prefix test run test:e2e:igloo-home
```

Expected:

- `igloo-ui` tests/build pass.
- Populated consumer tests pass.
- If a consumer submodule is not populated or lacks dependencies, initialize/install it and rerun.

- [ ] **Step 4: Commit consumer migration**

Commit per consumer repo first, then root submodule pointer updates:

```bash
cd repos/igloo-pwa
git add .
git commit -m "Migrate to Paper igloo-ui view models"

cd ../igloo-chrome
git add .
git commit -m "Migrate to Paper igloo-ui view models"

cd ../..
git add repos/igloo-pwa repos/igloo-chrome repos/igloo-ui
git commit -m "Update clients for Paper igloo-ui hard cut"
```

Only run commands for repos that actually changed.

## Task 7: Final Visual And Guard Verification

**Files:**
- Test outputs only: `.tmp/igloo-ui-showcase/*`
- No tracked files expected unless failures require fixes.

- [ ] **Step 1: Run visual showcase**

Run:

```bash
npm --prefix test run test:igloo-ui-showcase
```

Expected:

- Four tests pass.
- Screenshots exist:
  - `.tmp/igloo-ui-showcase/welcome-returning-profiles.png`
  - `.tmp/igloo-ui-showcase/create-keyset.png`
  - `.tmp/igloo-ui-showcase/signer-dashboard.png`
  - `.tmp/igloo-ui-showcase/policies.png`

- [ ] **Step 2: Run package and root verification**

Run:

```bash
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix test run test:guards
make test-affected
```

Expected:

- `igloo-ui` passes tests/build.
- Root guards pass after missing submodules are populated.
- `make test-affected` passes or reports only documented external-service/live-test skips.

- [ ] **Step 3: Record final evidence**

Update `dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md` with an "Implementation Outcome" section:

```md
## Implementation Outcome

- Approved API breaks implemented:
  - AppHeader Paper modes
  - PageBackLink screen-level navigation
  - StoredProfileCardModel
  - SignerDashboardViewModel
  - PolicyDashboardViewModel
- Verification:
  - `npm --prefix repos/igloo-ui test`
  - `npm --prefix repos/igloo-ui run build`
  - `npm --prefix test run test:igloo-ui-showcase`
  - `npm --prefix test run test:guards`
  - `make test-affected`
```

- [ ] **Step 4: Commit final report update**

Run:

```bash
git add dev/reports/igloo-ui-paper-api-mismatch-ledger-2026-05-20.md
git commit -m "Document Paper design-system hard-cut outcome"
```

## Completion Criteria

The hard cut is complete when:

- `igloo-ui` no longer relies on legacy generic `AppHeader` APIs.
- Stored profile, create, dashboard, policies, and event-log surfaces use Paper-aligned view models.
- `igloo-ui` has deterministic adapter helpers for shared runtime/profile data.
- The showcase screenshots render from built `igloo-ui` CSS.
- `igloo-ui` tests/build pass.
- Root guards pass with required submodules populated.
- Root commits include updated submodule pointers for every changed implementation repo.

## Execution Notes

- Do not import from `repos/igloo-paper` in package or app code.
- Do not copy Paper JSX into production components.
- Keep generated or review-only screenshots under `.tmp/`.
- Prefer one commit per submodule milestone, then one root pointer/report commit.
- Stop immediately if a listed public API break is rejected during review; revise this plan before implementation.
