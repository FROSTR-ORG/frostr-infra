# Shared Visual/Dev Seam (P1c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all three clients render the **same canonical seeded "running dashboard"** for screenshots/dev from one shared fixture, and fix `igloo-home` so its seeded snapshot actually renders the running dashboard instead of "Loading…".

**Architecture:** Add a dev/test-only `igloo-shared/testing/dev-fixtures` module holding the canonical seeded profile identity + `RuntimeStatusSummary` (the data that drives the signer dashboard). Each client's existing dev-scenario seam keeps its own param/registry/wrapper but builds its `dashboard-running` fixture from the shared module. Home's wrapper currently seeds a malformed `runtime_status` (no `peers[]`) that the runtime parser rejects → permanent loading; consuming the shared `RuntimeStatusSummary` both fixes that and unifies the data.

**Tech Stack:** TypeScript, igloo-shared (source-only package), Vite (pwa/home) + esbuild (chrome), Playwright `@agent` screenshot specs.

## Global Constraints

- **ADR-014 (c), option A.** Share the fixture DATA + fix home. Do NOT unify the params/scenario-name registries (pwa/chrome `?__frostr_dev=`, home `?__igloo_visual=`) — that's a separate tracked follow-up (param unification is out of scope here).
- **Dev-only / tree-shakes from prod.** `igloo-shared/testing/dev-fixtures` is a subpath export, NOT on the main `index.ts` barrel. Each client imports it only inside its `import.meta.env.DEV` / `VITE_IGLOO_VISUAL`-gated seam, so production bundles exclude it. A task verifies prod bundles don't contain the fixture marker.
- **Hard cut (per the repo standard):** when a client adopts the shared fixture, DELETE its now-duplicated local fixture constants — no client keeps a parallel hardcoded copy.
- **Behaviour-preserving for pwa/chrome:** their rendered `dashboard-running` screenshot must look the same after the refactor (the values are identical today). The visible behaviour CHANGE is home only (Loading → running dashboard).
- **Submodule workflow:** commit inside each submodule first; bump pointers in the parent last (`make bump-pointers`).
- **igloo-shared is source-only** (ADR-014 P0): no dist build; `package.json` `exports` map points at `src`.

---

## Current state (verified 2026-06-19)

- **Loading gate:** `repos/igloo-ui/src/adapters/runtime-view-models.ts:199` — `if (active && !status) return { kind: 'loading' }`. `status = parseRuntimeStatus(runtimeSnapshot?.runtime_status)`.
- **Home parser:** `repos/igloo-home/src/lib/runtime-status.ts:27-35` — `parseRuntimeStatus` returns `null` unless `runtime_status.peers` is an array. Home `App.tsx:~607` seeds `runtimeSnapshot` from `resolveVisualScenario()`; `App.tsx:~637-648` derives dashboard state.
- **Home fixture (broken):** `repos/igloo-home/src/test/visualMode.ts:150-180` `sampleRuntimeSnapshot.runtime_status = { state:'online', pending_ops:1, known_peers:2 }` — **no `peers[]`** → rejected.
- **pwa fixture:** `repos/igloo-pwa/src/lib/dev-scenario.ts` — `fixtureProfile` (PwaProfile) + `runningSnapshot` (PwaRuntimeSnapshot) whose `runtime_status` is a full `RuntimeStatusSummary` with two peers (idx 0 online, idx 2 offline), profile id `dev-scenario-device`, label `Dev Signing Key`, group_pk `'02'.repeat(32)`, share_pk `'11'.repeat(32)`, relay `ws://127.0.0.1:8194`.
- **chrome fixture:** `repos/igloo-chrome/src/lib/dev-scenario.ts` — `ExtensionStateSnapshot.runtime.summary` holds the **identical** `RuntimeStatusSummary` (same peers/identity).
- **igloo-shared exports** (`repos/igloo-shared/package.json`): `"."` → `./src/index.ts`, `"./testing/setup-dom"` → `./src/testing/setup-dom.ts`, `"./testing/vitest-base"` → `./src/testing/vitest-base.ts`. Wire types in `repos/igloo-shared/src/wire/runtime.ts`: `RuntimeStatusSummary`, `RuntimeReadiness`, `RuntimePeerStatus`.
- Screenshot specs: `test/igloo-pwa/specs/agent-screenshot.spec.ts` (`?__frostr_dev=`), `test/igloo-chrome/specs/agent-screenshot.spec.ts` (`?__frostr_dev=`), `test/igloo-home/screenshot/agent-screenshot.spec.ts` (`?__igloo_visual=`, maps `dashboard-running`→`dashboard-signer`).

---

## File structure

- `repos/igloo-shared/src/testing/dev-fixtures.ts` — **create** (canonical fixture: identity constants + `createFixtureRuntimeStatusSummary()` + `createFixturePeer()`).
- `repos/igloo-shared/package.json` — **modify** (add the `./testing/dev-fixtures` subpath export).
- `repos/igloo-pwa/src/lib/dev-scenario.ts` — **modify** (build the running fixture from the shared module; delete duplicated constants).
- `repos/igloo-chrome/src/lib/dev-scenario.ts` — **modify** (same).
- `repos/igloo-home/src/test/visualMode.ts` — **modify** (THE FIX: `runtime_status` ← shared `RuntimeStatusSummary`; delete the malformed inline shape).
- Parent — pointer bump.

---

### Task 1: Canonical fixture in igloo-shared

**Files:**
- Create: `repos/igloo-shared/src/testing/dev-fixtures.ts`
- Modify: `repos/igloo-shared/package.json` (exports map)
- Test: `repos/igloo-shared/src/testing/dev-fixtures.test.ts`

**Interfaces:**
- Produces (imported as `igloo-shared/testing/dev-fixtures`):
  - `FIXTURE_PROFILE_ID`, `FIXTURE_PROFILE_LABEL`, `FIXTURE_GROUP_PK`, `FIXTURE_SHARE_PK`, `FIXTURE_RELAY`, `FIXTURE_MEMBER_IDX`, `FIXTURE_SIGNER_SETTINGS`, `FIXTURE_PEER_A`, `FIXTURE_PEER_B` — string/number/object constants.
  - `createFixturePeer(idx: number, pubkey: string, online: boolean): RuntimePeerStatus`
  - `createFixtureRuntimeStatusSummary(): RuntimeStatusSummary`

- [ ] **Step 1: Write the failing test** at `repos/igloo-shared/src/testing/dev-fixtures.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { createFixtureRuntimeStatusSummary, FIXTURE_GROUP_PK } from './dev-fixtures';

describe('dev-fixtures', () => {
  it('builds a valid RuntimeStatusSummary with a peers array (the shape home parseRuntimeStatus requires)', () => {
    const s = createFixtureRuntimeStatusSummary();
    expect(Array.isArray(s.peers)).toBe(true);
    expect(s.peers.length).toBe(2);
    expect(s.peers[0].online).toBe(true);
    expect(s.peers[1].online).toBe(false);
    expect(s.metadata.group_public_key).toBe(FIXTURE_GROUP_PK);
    expect(s.readiness.sign_ready).toBe(true);
  });
});
```

- [ ] **Step 2: Run it, expect failure** (module missing):

Run: `npm --prefix repos/igloo-shared run test -- dev-fixtures`
Expected: FAIL (`Cannot find module './dev-fixtures'`).

- [ ] **Step 3: Create `repos/igloo-shared/src/testing/dev-fixtures.ts`:**

```ts
// Dev/test-only canonical fixture for the seeded "running dashboard" scenario.
// Consumed ONLY by the clients' import.meta.env.DEV-gated dev-scenario seams via
// the `igloo-shared/testing/dev-fixtures` subpath export — never on the main
// barrel, so production app bundles tree-shake it out.
import type { RuntimePeerStatus, RuntimeReadiness, RuntimeStatusSummary } from '../wire/runtime';

export const FIXTURE_PROFILE_ID = 'dev-scenario-device';
export const FIXTURE_PROFILE_LABEL = 'Dev Signing Key';
export const FIXTURE_GROUP_PK = '02'.repeat(32);
export const FIXTURE_SHARE_PK = '11'.repeat(32);
export const FIXTURE_RELAY = 'ws://127.0.0.1:8194';
export const FIXTURE_MEMBER_IDX = 1;
export const FIXTURE_PEER_A = '03a3f8c2d1'.padEnd(64, '0');
export const FIXTURE_PEER_B = '02d7e1b93b'.padEnd(64, '0');

export const FIXTURE_SIGNER_SETTINGS = {
  sign_timeout_secs: 30,
  ping_timeout_secs: 15,
  request_ttl_secs: 300,
  state_save_interval_secs: 30,
  peer_selection_strategy: 'deterministic_sorted',
} as const;

const FIXTURE_READINESS: RuntimeReadiness = {
  runtime_ready: true,
  restore_complete: true,
  sign_ready: true,
  ecdh_ready: true,
  threshold: 2,
  signing_peer_count: 2,
  ecdh_peer_count: 2,
  last_refresh_at: null,
  degraded_reasons: [],
};

export function createFixturePeer(idx: number, pubkey: string, online: boolean): RuntimePeerStatus {
  return {
    idx,
    pubkey,
    known: true,
    last_seen: online ? 1_700_000_000 : null,
    online,
    incoming_available: online ? 92 : 0,
    outgoing_available: online ? 78 : 0,
    outgoing_spent: online ? 14 : 0,
    can_sign: online,
    can_ecdh: online,
    can_ping: online,
    should_send_nonces: online,
    last_response_latency_ms: online ? 24 : null,
    avg_latency_ms: online ? 31 : null,
    nonce_history: [],
  };
}

export function createFixtureRuntimeStatusSummary(): RuntimeStatusSummary {
  return {
    status: { device_id: FIXTURE_PROFILE_ID, pending_ops: 0, last_active: 1_700_000_000, known_peers: 2, request_seq: 7 },
    metadata: {
      device_id: FIXTURE_PROFILE_ID,
      member_idx: FIXTURE_MEMBER_IDX,
      share_public_key: FIXTURE_SHARE_PK,
      group_public_key: FIXTURE_GROUP_PK,
      peers: [FIXTURE_PEER_A, FIXTURE_PEER_B],
    },
    readiness: FIXTURE_READINESS,
    peers: [createFixturePeer(0, FIXTURE_PEER_A, true), createFixturePeer(2, FIXTURE_PEER_B, false)],
    peer_permission_states: [],
    pending_operations: [],
    pending_approvals: [],
    connected_relays: [FIXTURE_RELAY],
    configured_relays: [FIXTURE_RELAY],
  };
}
```

> If `tsc` reports a missing/extra field vs the real `RuntimeStatusSummary` /
> `RuntimeReadiness` / `RuntimePeerStatus` in `src/wire/runtime.ts`, conform to the
> real type (it is the source of truth) — adjust the fixture, do not cast.

- [ ] **Step 4: Add the subpath export** to `repos/igloo-shared/package.json` `exports` (after `./testing/vitest-base`):

```json
    "./testing/dev-fixtures": "./src/testing/dev-fixtures.ts"
```

  Do NOT add it to `src/index.ts` (keep it off the main barrel).

- [ ] **Step 5: Run the test + typecheck, expect pass:**

Run: `npm --prefix repos/igloo-shared run test -- dev-fixtures`
Expected: PASS. Then `npm --prefix repos/igloo-shared run test` → whole suite green.

- [ ] **Step 6: Commit:**

```bash
git -C repos/igloo-shared add src/testing/dev-fixtures.ts src/testing/dev-fixtures.test.ts package.json
git -C repos/igloo-shared commit -m "Add dev-only canonical running-dashboard fixture (igloo-shared/testing/dev-fixtures)"
```

---

### Task 2: pwa consumes the shared fixture

**Files:**
- Modify: `repos/igloo-pwa/src/lib/dev-scenario.ts`

**Interfaces:**
- Consumes: `igloo-shared/testing/dev-fixtures` (Task 1).

- [ ] **Step 1: Import the shared fixture** at the top of `repos/igloo-pwa/src/lib/dev-scenario.ts`:

```ts
import {
  FIXTURE_PROFILE_ID, FIXTURE_PROFILE_LABEL, FIXTURE_GROUP_PK, FIXTURE_SHARE_PK,
  FIXTURE_RELAY, FIXTURE_MEMBER_IDX, FIXTURE_SIGNER_SETTINGS,
  createFixtureRuntimeStatusSummary,
} from 'igloo-shared/testing/dev-fixtures';
```

- [ ] **Step 2: Replace the hardcoded identity + runtime_status.** In `fixtureProfile`, source the shared fields from the constants (`id: FIXTURE_PROFILE_ID`, `label: FIXTURE_PROFILE_LABEL`, `share_public_key: FIXTURE_SHARE_PK`, `group_public_key: FIXTURE_GROUP_PK`, `relays: [FIXTURE_RELAY]`, `member_idx: FIXTURE_MEMBER_IDX`, `signer_settings: FIXTURE_SIGNER_SETTINGS`), keeping pwa-only fields (`source`, `relay_profile`, `group_ref`, `encrypted_profile_ref`, `state_path`, `created_at`, `encrypted_bfshare_artifact`, `manual_peer_policy_overrides`, `peer_pubkey`, `onboarding_package`, etc.). In `runningSnapshot`, set `runtime_status: createFixtureRuntimeStatusSummary()` and derive `readiness` from it (`createFixtureRuntimeStatusSummary().readiness`) instead of the inline literals. **Delete** the now-duplicated inline peer/status/readiness literals.

- [ ] **Step 3: Typecheck + render parity.**

Run: `npm --prefix repos/igloo-pwa run build`
Expected: succeeds.

Run: `make screenshot CLIENT=pwa STATE=dashboard-running`
Expected: `1 passed`; `.tmp/agent/dashboard-running.png` shows the running dashboard with the two peers — visually identical to before (same data).

- [ ] **Step 4: Commit:**

```bash
git -C repos/igloo-pwa add src/lib/dev-scenario.ts
git -C repos/igloo-pwa commit -m "Build dashboard-running dev fixture from shared igloo-shared/testing/dev-fixtures"
```

---

### Task 3: chrome consumes the shared fixture

**Files:**
- Modify: `repos/igloo-chrome/src/lib/dev-scenario.ts`

**Interfaces:**
- Consumes: `igloo-shared/testing/dev-fixtures` (Task 1).

- [ ] **Step 1: Import the shared fixture** (same import block as Task 2 Step 1) in `repos/igloo-chrome/src/lib/dev-scenario.ts`.

- [ ] **Step 2: Replace chrome's hardcoded identity + `runtime.summary`.** Build `fixtureProfile` (`StoredExtensionProfile`) identity fields from the shared constants (`id`, `groupName: FIXTURE_PROFILE_LABEL`, `relays: [FIXTURE_RELAY]`, `groupPublicKey: FIXTURE_GROUP_PK`, `sharePublicKey`/`publicKey: FIXTURE_SHARE_PK`, `signerSettings: FIXTURE_SIGNER_SETTINGS`, keeping `peerPubkey`). Set the running snapshot's `summary = createFixtureRuntimeStatusSummary()` and derive `metadata`/`readiness`/`peerStatus`/`pendingOperations` from that summary (`summary.metadata`, `summary.readiness`, `summary.peers`, `summary.pending_operations`). **Delete** the duplicated inline peer/summary literals. Keep chrome-only wrapper fields (`desiredActive`, `phase: 'ready'`, `snapshot`, `lifecycle`, `lastError`, the outer `ExtensionStateSnapshot` config/lifecycle/permission fields).

- [ ] **Step 3: Typecheck + render parity.**

Run: `make igloo-chrome-build`
Expected: succeeds.

Run: `make screenshot CLIENT=chrome STATE=dashboard-running`
Expected: `1 passed`; `.tmp/agent/chrome-dashboard-running.png` shows the running dashboard with the two peers — visually identical to before.

- [ ] **Step 4: Commit:**

```bash
git -C repos/igloo-chrome add src/lib/dev-scenario.ts
git -C repos/igloo-chrome commit -m "Build dashboard-running dev fixture from shared igloo-shared/testing/dev-fixtures"
```

---

### Task 4: home — THE FIX (seed a valid RuntimeStatusSummary)

**Files:**
- Modify: `repos/igloo-home/src/test/visualMode.ts`

**Interfaces:**
- Consumes: `igloo-shared/testing/dev-fixtures` (Task 1).

- [ ] **Step 1: Import the shared fixture** in `repos/igloo-home/src/test/visualMode.ts`:

```ts
import {
  FIXTURE_PROFILE_ID, FIXTURE_PROFILE_LABEL, FIXTURE_GROUP_PK, FIXTURE_SHARE_PK,
  FIXTURE_RELAY, createFixtureRuntimeStatusSummary,
} from 'igloo-shared/testing/dev-fixtures';
```

- [ ] **Step 2: Replace the malformed `runtime_status`.** In `sampleRuntimeSnapshot` (lines ~150-180), set:

```ts
runtime_status: createFixtureRuntimeStatusSummary(),
```

  **deleting** the inline `{ state: 'online', pending_ops: 1, known_peers: 2 }` shape (the bug — it has no `peers[]`, so `parseRuntimeStatus` rejects it). Keep home's wrapper fields (`active: true`, `profile`, `readiness`, `runtime_diagnostics`, `daemon_log_path`, `daemon_log_lines`, `daemon_metadata`). For identity parity, set the sample profile's `id`/`label`/group+share keys/relays from the shared constants where the `ProfileManifest` shape allows (keep home-only fields like `group_ref`, `daemon_socket_path`, `state_path`).

> Note: `parseRuntimeStatus` (runtime-status.ts) only requires `runtime_status.peers`
> to be an array; the canonical summary provides it. Home's top-level `readiness`/
> `runtime_diagnostics` are separate home-specific fields and stay as-is.

- [ ] **Step 3: Verify the FIX — home now renders the running dashboard.**

Run: `npm --prefix repos/igloo-home run build`
Expected: succeeds.

Run: `make screenshot CLIENT=home STATE=dashboard-running`
Expected: `1 passed`; **`.tmp/agent/home-dashboard-signer.png` now shows the running signer dashboard (OperatorSignerPanel with the two peers) — NOT "Starting signer… / Loading…".** This is the visible behaviour change; confirm by eye that the peer rows render.

- [ ] **Step 4: Commit:**

```bash
git -C repos/igloo-home add src/test/visualMode.ts
git -C repos/igloo-home commit -m "Fix home visual seam: seed a valid RuntimeStatusSummary so the running dashboard renders (not Loading)"
```

---

### Task 5: Tree-shaking check, parity, pointer bump

**Files:** parent pointer commit.

- [ ] **Step 1: Confirm the dev fixture tree-shakes from production bundles.**

Run: `npm --prefix repos/igloo-pwa run build && grep -rl "dev-scenario-device\|FIXTURE_GROUP_PK" repos/igloo-pwa/dist/assets 2>/dev/null || echo "ABSENT-OK"`
Expected: `ABSENT-OK` (the fixture marker is not in the prod bundle — it's behind `import.meta.env.DEV`). If present, the gating is wrong; fix before continuing. Repeat the grep for `repos/igloo-chrome/dist` and `repos/igloo-home/dist`.

> If home's `visualMode` is not `import.meta.env.DEV`-gated and the marker appears in
> home's prod bundle, gate the dev-fixtures import behind the visual/DEV flag (home's
> seam already keys on `?__igloo_visual=`; ensure the fixture import is reachable only
> under that flag) so it tree-shakes. Re-run the grep.

- [ ] **Step 2: All three render the same canonical state.** Re-run all three screenshots and confirm the same two peers (one online idx 0, one offline idx 2), same group key tail, same relay appear in each:

Run: `make screenshot CLIENT=pwa STATE=dashboard-running && make screenshot CLIENT=chrome STATE=dashboard-running && make screenshot CLIENT=home STATE=dashboard-running`
Expected: all `1 passed`; the three PNGs in `.tmp/agent/` show the same canonical dashboard data (home no longer on Loading).

- [ ] **Step 3: Gate `make verify`.**

Run: `make verify`
Expected: exit 0.

- [ ] **Step 4: Confirm submodules clean + bump pointers.**

Run: `for r in igloo-shared igloo-pwa igloo-home igloo-chrome; do git -C repos/$r status --short; done`
Expected: all clean.

Run: `make bump-pointers MSG="Shared dev-scenario fixture + fix home running-dashboard render (ADR-014 P1c)"`
Expected: one parent commit recording the igloo-shared/pwa/home/chrome pointer moves.

- [ ] **Step 5: Mark the BACKLOG P1 visual-seam item done** in `dev/BACKLOG.md` (the "P1 — Shared visual/dev seam" item), then commit it in the parent.

---

## Self-Review

**Spec coverage (ADR-014 c, option A):**
- One canonical seeded fixture in a shared dev-only module → Task 1. ✓
- All three clients build `dashboard-running` from it → Tasks 2/3/4. ✓
- Home renders the running dashboard (bug fixed) → Task 4 (valid `runtime_status.peers`). ✓
- Tree-shakes from prod; param/registry unification deferred → Task 5 Step 1 + Global Constraints. ✓
- Param/scenario-name unification explicitly OUT of scope (option A, not C). ✓

**Placeholder scan:** none — the fixture module is given in full; each client task names the exact import + the exact field to set (`createFixtureRuntimeStatusSummary()`); verification commands have expected output.

**Type/name consistency:** `createFixtureRuntimeStatusSummary` / `createFixturePeer` / the `FIXTURE_*` constants are defined in Task 1 and consumed by the identical names in Tasks 2-4. The fixture conforms to `RuntimeStatusSummary` from `igloo-shared/src/wire/runtime.ts` (Task 1 Step 3 note enforces this).

**Ordering safety:** Task 1 lands the shared module before any client imports it. pwa/chrome refactors are behaviour-preserving (identical values); home's is the one intended behaviour change. The tree-shaking gate (Task 5) runs before the pointer bump.
