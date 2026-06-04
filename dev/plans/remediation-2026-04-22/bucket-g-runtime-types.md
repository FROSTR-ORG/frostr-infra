# Bucket G — Typed Runtime-Shape Exports (Structural Refactor)

Status: draft, pending user approval
Related: consumes the work in Buckets A+B+D (the runtime types the exports describe). Ships in a **second coordinated release** after A+B+C+D+E+F. No operator-facing migration.

## Context

The 2026-04-22 audit synthesis identified the "monolith per host" pattern
as a cross-cutting root cause. Six different files across the TS
ecosystem re-implement the same FROSTR runtime projection:

- `igloo-shared/src/browser-runtime-core.ts` — 2,189 lines. Owns the
  `BrowserBridgeNode` class (relay pool, WASM ingest, NIP-44, session
  orchestration, pending-op bookkeeping, ~20 free functions that
  type-narrow `NodeWithEvents` back to `BrowserBridgeNode` just to call
  a method).
- `igloo-home/src/App.tsx` — 1,875 lines. Inlines `HomeRuntimeStatus`,
  `RuntimeOnboardingStatus`, `extractPeerPermissionStates`,
  `extractRuntimePeers` with repeated `as Record<string, unknown>` casts.
- `igloo-pwa/src/App.tsx` — 1,345 lines. Declares
  `PwaRuntimePeerStatus`, `PwaRuntimePendingOperation`,
  `PwaRuntimeReadiness`, `PwaRuntimeStatus`, casts
  `runtime_status: unknown` at every consumer via
  `(runtimeStatus ?? null) as PwaRuntimeStatus | null`.
- `igloo-pwa/src/lib/store.tsx` — 1,147 lines. Typed as `unknown`
  because the host can't import the shape it actually wants.
- `igloo-chrome/src/background.ts` — per the 2026-04-02 audit, the same
  pattern in extension-runtime-host logic.
- Plus six overlapping `browser-profile-*` modules in `igloo-shared`
  that each wrap a slightly different finalize/save/persist flow with
  subtle error-taxonomy drift (audit finding 6).

The shared cause: **typed, versioned runtime-shape exports don't exist
in a form hosts can actually depend on.** Most of the types are
`export type` in `browser-runtime-core.ts` *today* — they're reachable
via `import { RuntimeStatusSummary } from 'igloo-shared'` — but hosts
don't use them because (a) the public API returns `NodeWithEvents` and
requires runtime guards to narrow, (b) the 2,189-line single-file layout
makes the type's provenance hard to find, (c) some relevant projections
(`RuntimeConfig`, `OnboardingDecoded`, `OnboardingRequestBundleWire`)
are internal, not exported, (d) the `export *` barrel in `index.ts`
surfaces everything indiscriminately, so adding a new type feels like
enlarging the public surface by default.

Bucket G fixes the structural problem: extract the wire shapes into a
dedicated `wire/` module, split the 2,189-line monolith into focused
files, export `BrowserBridgeNode` directly, publish typed projection
helpers so hosts can drop their local re-declarations, and consolidate
the six `browser-profile-*` modules into one coherent namespace.

Bucket G has **no operator-facing impact**. It is a pure internal
refactor that unblocks the host-side monolith cleanups (tentatively
Bucket H). Ships in a second coordinated release, decoupled from the
crypto-hardening release window.

Alpha; hard-cut throughout. Every rename / move lands atomically with
its consumer migration in the same PR — no transitional shim files,
no `export * from` re-export layers for one release. Old files are
deleted when their contents move.

## Scope

**In:**
- G.1 — Wire-type extraction: create `igloo-shared/src/wire/` with one
  file per concern (`runtime.ts`, `onboarding.ts`, `bridge.ts`,
  `policy.ts`). Move the 13+ runtime types out of
  `browser-runtime-core.ts`. Promote currently-internal types
  (`OnboardingRequestBundleWire`, `RuntimeConfig`, `OnboardingDecoded`,
  `BridgeEnvelope`) to `export`. Add a contract test that round-trips
  fixture JSON from bifrost-rs through every wire type.
- G.2 — Split `browser-runtime-core.ts` into `wasm-bridge-node.ts`,
  `relay-transport.ts`, `onboarding-transport.ts`, `runtime-pump.ts`,
  `runtime-api.ts`. The original file becomes a thin re-export façade
  for one release cycle, then deleted.
- G.3 — Export `BrowserBridgeNode` class directly from
  `igloo-shared/src/runtime-api.ts`. Kill the 20+
  `isBrowserBridgeNode(node) && typeof node.X === 'function'` runtime
  guards. Consumers hold a typed `BrowserBridgeNode` reference, not a
  `NodeWithEvents` bag.
- G.4 — Typed projection helpers in
  `igloo-shared/src/runtime-projections.ts`:
  `selectActivePeers`, `selectPendingOperations`,
  `selectPeerPermissionStates`, `selectOnboardingStatuses`,
  `selectReadinessExplanation` (already exists as
  `deriveReadinessExplanation`; consolidate). Migrate `igloo-home` and
  `igloo-pwa` to import these; drop local re-declarations and
  `as any`/`as unknown` casts.
- G.5 — Collapse `browser-profile-*` top-level modules into
  `igloo-shared/src/browser-profile/` hierarchy with one flow per
  source. Deprecate the five peer-level modules (empty shim re-exports
  for one release, then delete).
- G.6 — Replace `index.ts` `export *` barrel with explicit named
  exports. Makes the public surface reviewable in PRs.

**Out of scope for Bucket G:**
- Host-side App.tsx / store.tsx splits — these benefit from Bucket G but
  are larger refactors in their own right. Tracked as a future "browser
  host modularization" bucket.
- bifrost-rs WASM ABI changes (e.g. generating TS types from Rust
  structs). The wire types stay hand-authored in TS; a bifrost-rs-side
  `.d.ts` generation step is a future optimization.
- `igloo-chrome` `background.ts` cleanup — the 2026-04-02 audit covers
  this; Bucket J owns the re-audit + targeted fix.
- `observability.ts` + `nip44-normalize.ts` restructuring — already
  reasonable-size single-purpose modules.

## Execution Order

Five PRs. Numbering continues from Bucket F (PR25–PR28). Bucket G's 5
PRs are **PR29–PR33** — they ship in a second coordinated release after
Buckets A–F.

| PR | Items | Depends on |
|---|---|---|
| PR29 | G.1 (wire type extraction) + G.6 (named exports) | none |
| PR30 | G.2 (split browser-runtime-core) | PR29 |
| PR31 | G.3 (export BrowserBridgeNode; kill NodeWithEvents) | PR30 |
| PR32 | G.4 (typed projections + consumer migration in igloo-home, igloo-pwa) | PR29 |
| PR33 | G.5 (consolidate browser-profile-*) + consumer migration | PR29 |

PR29 is the foundation — every other PR imports from the new `wire/`
module. PR30 depends on PR29. PR31 depends on PR30 (the split exposes
`BrowserBridgeNode` as a clean class to export). PR32 and PR33 each
depend only on PR29, can run in parallel.

Total touch: ~3,000 lines in `igloo-shared`, ~800 lines of consumer
migration across `igloo-home`, `igloo-pwa`, `igloo-chrome`.

Ships in the second coordinated release. No version bumps on disk
formats, no migration event, no user-visible behavior change.

---

## G.1 — Wire-type extraction + named exports

### Target module layout

New directory `igloo-shared/src/wire/`:

```
wire/
  index.ts           — barrel; explicit named exports only
  runtime.ts         — RuntimePeerStatus, RuntimeMetadata, RuntimeReadiness,
                       RuntimeOperationReadiness, RuntimeReadinessExplanation,
                       RuntimeStatusDetails, RuntimePendingOperation,
                       RuntimeOnboardingStatus, RuntimeStatusSummary,
                       DecodedOnboardingProfile
  onboarding.ts      — OnboardingDecoded, OnboardingRequestBundleWire,
                       OnboardingRequestResult, OnboardResponseWire
  bridge.ts          — BridgeEnvelope, BridgePayload + payload variants
                       (Sign, Ecdh, Ping, OnboardRequest, OnboardResponse, Error)
  policy.ts          — PolicyOverrideValue, RuntimeMethodPolicy,
                       RuntimeMethodPolicyOverride, RuntimePeerPermissionState
  config.ts          — RuntimeConfig (promoted to exported)
```

### What moves

From `browser-runtime-core.ts` (lines 54-247 per the Read):
- `RuntimeConfig` (currently internal, line 54) → `wire/config.ts` as `export type`.
- `OnboardingDecoded` (internal, line 70) → `wire/onboarding.ts` as `export type`.
- `OnboardingRequestBundleWire` (internal, line 77) → `wire/onboarding.ts` as `export type`.
- `OnboardingRequestResult` (internal, line 85) → `wire/onboarding.ts`.
- `DecodedOnboardingProfile` (line 112, exported) → `wire/runtime.ts`.
- `RuntimePeerStatus` through `RuntimeStatusSummary` (lines 118-247, all exported) → `wire/runtime.ts`.
- `PolicyOverrideValue`, `RuntimeMethodPolicy`, `RuntimeMethodPolicyOverride`, `RuntimePeerPermissionState` (lines 139-171) → `wire/policy.ts`.

From elsewhere in `browser-runtime-core.ts` (hunting required):
- `OnboardResponseWire` — wire/onboarding.ts.
- `BridgeEnvelope`, `BridgePayload` — wire/bridge.ts.
- `RuntimeSnapshotWire`, `RuntimeBootstrapWire` — wire/runtime.ts (these
  carry bootstrap material; flagged so reviewers know the Bucket D
  redactor must allow-list none of their fields).

### Consumer-visible surface unchanged

External consumers import from the `igloo-shared` package root (e.g.
`import { RuntimeStatusSummary } from 'igloo-shared'`). The new
`index.ts` (G.6) re-exports the types from `wire/` instead of
`browser-runtime-core.ts`, so external imports keep resolving the same
symbol. No consumer change is needed in PR29 for the type moves.

Internal imports within `igloo-shared` are updated atomically in the
same PR: every file that previously imported a type from
`browser-runtime-core.ts` now imports from the appropriate `wire/*`
file. `browser-runtime-core.ts` loses the type declarations but
retains the class + free-function logic until PR30 splits it.

### G.6 — Named exports in `index.ts`

Replace:
```ts
// Before
export * from './browser-runtime-core';
export * from './browser-profile-persistence';
// ... 14 more export * lines
```

With an explicit list:

```ts
// After — wire types
export type {
  RuntimePeerStatus,
  RuntimeMetadata,
  RuntimeReadiness,
  RuntimeOperationReadiness,
  RuntimeReadinessExplanation,
  RuntimeStatusDetails,
  RuntimePendingOperation,
  RuntimeOnboardingStatus,
  RuntimeStatusSummary,
  RuntimeConfig,
  DecodedOnboardingProfile,
  OnboardingDecoded,
  OnboardingRequestBundleWire,
  OnboardResponseWire,
  BridgeEnvelope,
  BridgePayload,
  PolicyOverrideValue,
  RuntimeMethodPolicy,
  RuntimeMethodPolicyOverride,
  RuntimePeerPermissionState,
} from './wire';

// Runtime API
export {
  createSignerNode,
  connectSignerNode,
  stopSignerNode,
  // ... the rest of the public runtime API
  BrowserBridgeNode,
} from './runtime-api';

// Profile flows (post-G.5 shape)
export {
  importBfProfile,
  importBfShare,
  importBfOnboard,
  applyRotation,
  saveBrowserProfile,
  // ... explicit list
} from './browser-profile';

// Observability, secrets, etc.
export { createLogger, sanitizeDetails } from './observability';
export { Secret, SecretBytes } from './secret';     // from Bucket D PR13
export { normalizeNip44PayloadForJs } from './nip44-normalize';
```

Adding a new export is a visible diff. Removing an accidentally-exported
symbol is possible because the barrel now enumerates the contract.

### Contract test

`igloo-shared/tests/wire-contract.spec.ts` (NEW) imports a fixture set
captured from bifrost-rs WASM output:

```ts
import fixture from './fixtures/runtime-status.example.json';
import type { RuntimeStatusSummary } from '../src/wire';

// Compile-time check — any shape drift breaks the build.
const _check: RuntimeStatusSummary = fixture as RuntimeStatusSummary;
```

Plus a runtime shape-check using a lightweight schema (`zod` or
hand-rolled guards) for every wire type. Fixtures live in
`igloo-shared/tests/fixtures/` and are regenerated with a
`make regen-wasm-fixtures` target that runs bifrost-rs WASM against a
scripted scenario and captures the JSON. PR29 seeds the fixtures from
the current shape; subsequent bifrost-rs changes that shift the wire
format will fail the contract test loudly.

### Testing

- `tsc --noEmit` across `igloo-shared` and all consumers — should still
  compile because `browser-runtime-core.ts` re-exports the moved types.
- `npm test` in `igloo-shared` — existing tests pass.
- Wire contract test: pass on captured fixture, fail loud on a
  synthetic shape drift (add a CI regression test that mutates the
  fixture and asserts `tsc` errors).
- Grep regression: `rg '^export \*' src/` in `igloo-shared` returns at
  most the `wire/index.ts` internal barrel, not the top-level `index.ts`.

---

## G.2 — Split `browser-runtime-core.ts` monolith

### Target module layout

New files in `igloo-shared/src/`:

```
wasm-bridge-node.ts      — BrowserBridgeNode class (the one big thing)
relay-transport.ts       — SimplePool, relay-probe, subscribe helpers
onboarding-transport.ts  — requestOnboardResponse, bfonboard decode,
                           subscribeMany onevent dispatch
runtime-pump.ts          — tick loop, drain, completion dispatch
                           (from Bucket D PR14: request_id-keyed map)
runtime-api.ts           — public free functions: createSignerNode,
                           connectSignerNode, stopSignerNode, etc.
                           Also re-exports BrowserBridgeNode class
                           and the wire types (delegates to wire/).
```

Original `browser-runtime-core.ts` is **deleted** in the same PR.
`index.ts` is updated to re-export from the five new files instead.
External consumers of the `igloo-shared` barrel (`createSignerNode`,
`connectSignerNode`, `BrowserBridgeNode`, etc.) are unaffected because
the names come out of the barrel unchanged. Any internal import of
`./browser-runtime-core` is rewritten to the appropriate new module in
the same PR — `rg "from '.*browser-runtime-core" repos/igloo-shared/src/`
must return zero matches post-PR30.

### `BrowserBridgeNode` → `wasm-bridge-node.ts`

The class owns: relay pool (now delegated to `RelayTransport`),
WASM bridge runtime (already in `bridge-wasm-runtime.ts` imports),
pending-op map (Bucket D PR14), snapshot accessor, public operation
methods (`sign`, `ecdh`, `ping`, `onboard`, `snapshot_state`, etc.).

The class keeps its existing public surface; the change is purely
*where* it lives. Move lines 607-1886 of `browser-runtime-core.ts` to
`wasm-bridge-node.ts` verbatim, adjust imports.

Dependencies injected through the constructor:
- `RelayTransport` (was inlined relay pool logic)
- `WasmBridgeRuntimeApi` (from `bridge-wasm-runtime`, already external)
- `Logger` (from `observability`, already external)

### `relay-transport.ts`

Owns: SimplePool lifecycle, relay URL normalization
(`normalizePubkey32Hex`, `normalizeHex32`, etc. — currently duplicated
across files per audit finding 14), subscribe/publish/probe helpers.

Public API:
```ts
export class RelayTransport {
  constructor(relays: string[], opts?: RelayTransportOptions);
  publish(event: Event): Promise<void>;
  subscribeMany(relays: string[], filters: Filter[], handler: (ev: Event) => void): Subscription;
  probe(relay: string): Promise<boolean>;
  close(): Promise<void>;
}
```

Moves lines related to relay I/O from `browser-runtime-core.ts` — exact
line ranges confirmed during PR30 implementation.

### `onboarding-transport.ts`

Owns: `requestOnboardResponse`, `subscribeMany` onevent handling for
onboarding (lines 1585-1636 per Bucket D exploration), `bfonboard`
decode + deep validation (lines 1600-1619 post-Bucket D), decrypt
rate-limit (Bucket D PR15).

Depends on `RelayTransport` for the subscription primitive.

### `runtime-pump.ts`

Owns: tick loop, `drain_runtime_events`, completion dispatch. This is
where Bucket D PR14 introduced the `request_id`-keyed
`Map<string, PendingBridgeCommand>`. G.2 splits it out so the dispatch
logic has a single home.

Public API:
```ts
export class RuntimePump {
  constructor(node: BrowserBridgeNode, opts: RuntimePumpOptions);
  start(): void;
  stop(): void;
  registerPending(requestId: string, command: PendingBridgeCommand): void;
  // ...
}
```

### `runtime-api.ts`

The public façade — what hosts actually import. Re-exports wire types
and exports the public free functions `createSignerNode`,
`connectSignerNode`, `stopSignerNode`, `getRuntimeStatus`,
`getRuntimeSnapshot` (deprecated, per Bucket D), etc.

Also re-exports `BrowserBridgeNode` class directly (G.3).

### Test layout

Each new module gets its own `*.test.ts` where the coverage makes
sense:
- `wasm-bridge-node.test.ts` — the class smoke test (largest).
- `relay-transport.test.ts` — pool lifecycle, probe timeout.
- `onboarding-transport.test.ts` — Bucket D PR15's adversarial coverage lives here.
- `runtime-pump.test.ts` — Bucket D PR14's request_id correlation tests live here.

Existing tests under `browser-onboarding.test.ts`,
`browser-profile.test.ts`, etc. keep working via the back-compat shim.

### Testing

- `tsc --noEmit` across `igloo-shared` and all consumers.
- Full `npm test` in `igloo-shared`.
- Manual: run `make demo-start && make demo-smoke` to confirm no
  runtime regressions.
- Line-count check: `wc -l src/browser-runtime-core.ts` → ~50 lines
  (the shim) post-PR30; zero post-deletion.
- File count check: `ls src/` shows the five new top-level files.

---

## G.3 — Export `BrowserBridgeNode` directly

### The problem

Per Bucket D exploration: `browser-runtime-core.ts` has ~20 call sites
of the pattern:

```ts
if (isBrowserBridgeNode(node) && typeof node.someMethod === 'function') {
  node.someMethod(...);
}
```

This is because the public API currently returns `NodeWithEvents` (an
intersection type that's compatible with the class instance but doesn't
advertise its methods). Consumers narrow via `isBrowserBridgeNode`.

### The fix

In `runtime-api.ts`:

```ts
export { BrowserBridgeNode } from './wasm-bridge-node';

export async function createSignerNode(
  config: RuntimeConfig,
  adapters: SignerNodeAdapters,
): Promise<BrowserBridgeNode> {  // was Promise<NodeWithEvents>
  // ... existing implementation
}

export async function connectSignerNode(
  config: RuntimeConfig,
  adapters: SignerNodeAdapters,
): Promise<BrowserBridgeNode> {  // was Promise<NodeWithEvents>
  // ... existing implementation
}
```

### Remove the runtime guards

In every file inside `igloo-shared/src/` that currently uses:
```ts
if (isBrowserBridgeNode(node) && typeof node.X === 'function') { node.X(...); }
```

Replace with:
```ts
node.X(...);  // node is now typed BrowserBridgeNode
```

`isBrowserBridgeNode` the helper can stay as a `type predicate` but
none of the production code calls it.

### Consumer migration

`igloo-pwa`, `igloo-home`, `igloo-chrome` currently hold `unknown` or
`NodeWithEvents` typed references. Change their type declarations:

- `igloo-pwa/src/lib/local-adapter/profile-runtime.ts:15` —
  `activeRuntimeSession: BrowserRuntimeSession | null` — verify the
  `BrowserRuntimeSession` wrapping is correct post-G.3; if it wraps
  `BrowserBridgeNode` directly, update the type.
- `igloo-home/src-tauri/src/session.rs` — Rust backend calls through
  bifrost-rs directly; no TS-side change needed for Home's backend,
  but its frontend (`igloo-home/src/App.tsx`) gets the G.4 treatment.
- `igloo-chrome` — call through `BrowserBridgeNode` directly in the
  extension-runtime-host path. (Minimal change; deeper Chrome cleanup
  is Bucket J.)

### Testing

- Type-check across all consumers — must pass without `as any` at the
  new call sites.
- Grep regression: `rg 'isBrowserBridgeNode\(' repos/` — should return
  only the type-predicate definition itself, not any production call
  site.
- Demo harness smoke: full onboard → sign → ecdh flow.

---

## G.4 — Typed projection helpers + consumer migration

### New module `igloo-shared/src/runtime-projections.ts`

Helper selectors over `RuntimeStatusSummary`:

```ts
import type {
  RuntimeStatusSummary,
  RuntimePeerStatus,
  RuntimePendingOperation,
  RuntimePeerPermissionState,
  RuntimeOnboardingStatus,
  RuntimeReadinessExplanation,
} from './wire';

export function selectActivePeers(
  status: RuntimeStatusSummary,
): RuntimePeerStatus[] {
  return status.peers.filter(peer => peer.online && peer.known);
}

export function selectPendingOperations(
  status: RuntimeStatusSummary,
): RuntimePendingOperation[] {
  return status.pending_operations;
}

export function selectPeerPermissionStates(
  status: RuntimeStatusSummary,
): RuntimePeerPermissionState[] {
  return status.peer_permission_states;
}

export function selectOnboardingStatuses(
  status: RuntimeStatusSummary,
): RuntimeOnboardingStatus[] {
  return status.onboarding_statuses ?? [];
}

export function selectReadinessExplanation(
  status: RuntimeStatusSummary,
): RuntimeReadinessExplanation {
  return deriveReadinessExplanation(status);  // existing function
}
```

Plus UI-oriented aggregates:

```ts
export function countOnlinePeers(status: RuntimeStatusSummary): number {
  return status.peers.filter(p => p.online).length;
}

export function countKnownPeers(status: RuntimeStatusSummary): number {
  return status.peers.filter(p => p.known).length;
}

export function hasPendingSigns(status: RuntimeStatusSummary): boolean {
  return status.pending_operations.some(op => op.op_type === 'sign');
}
```

### Consumer migration: `igloo-pwa`

`igloo-pwa/src/App.tsx` lines 139-205 per audit:
- Delete local type declarations `PwaRuntimePeerStatus`,
  `PwaRuntimePendingOperation`, `PwaRuntimeReadiness`, `PwaRuntimeStatus`.
- Import canonical types from `igloo-shared`.
- Replace `derivePwaPeers`, `derivePendingOperations`, ... with
  `selectActivePeers`, `selectPendingOperations`, ... from
  `igloo-shared/runtime-projections`.
- `igloo-pwa/src/lib/types.ts:118` — change
  `runtime_status: unknown` to
  `runtime_status: RuntimeStatusSummary | null`.
- Remove the `(runtimeStatus ?? null) as PwaRuntimeStatus | null` casts
  at every consumer. Type flows naturally.

### Consumer migration: `igloo-home`

`igloo-home/src/App.tsx` lines 156-184 and 298-432 per audit:
- Delete local type declarations `HomeRuntimeStatus`,
  `RuntimeOnboardingStatus`.
- Delete `extractPeerPermissionStates`, `extractRuntimePeers` — replace
  with the `igloo-shared` selectors.
- Remove `as Record<string, unknown>` casts on `runtime_status`.

### Consumer migration: `igloo-chrome`

`igloo-chrome/src/` — audit finding from 2026-04-02 mentions local
re-declarations in `background.ts` and `extension-runtime-host.ts`.
Adopt the shared projections wherever they're used today. Deeper
Chrome cleanup is Bucket J.

### Testing

- `tsc --noEmit` across all consumers — passes with no new `as`
  casts on `runtime_status`.
- Unit tests: each selector has a fixture-based test verifying the
  expected projection.
- Grep regression: `rg 'as PwaRuntime|as HomeRuntime|as Record<string, unknown>' repos/` — matches drop to zero.
- Manual smoke: Run the PWA and Home apps; verify runtime status
  displays correctly (peer counts, pending ops, readiness banner).

---

## G.5 — Consolidate `browser-profile-*` packages

### Current shape (6 top-level modules)

From `ls repos/igloo-shared/src/`:
- `browser-profile/` + `browser-profile.ts` + `browser-profile.test.ts`
- `browser-profile-persistence/` + `browser-profile-persistence.ts` + tests
- `browser-profile-recovery/` + `browser-profile-recovery.ts` + tests
- `browser-profile-save/` + `browser-profile-save.test.ts` (no top-level .ts?)
- `browser-profile-store/` + `browser-profile-store.ts` + tests
- `browser-session-orchestration/` + `browser-session-orchestration.ts` + tests
- `browser-runtime-session/` + `browser-runtime-session.ts` + tests

All six re-export into each other via `export *`. Per Bucket D audit
finding 6: "three entry points a host can reasonably pick to 'save an
imported profile and maybe start the runtime'."

### Target shape

Single `browser-profile/` directory with sub-modules by concern:

```
browser-profile/
  index.ts                    — explicit named exports only
  persistence.ts              — bundle + local-storage write path
  store.ts                    — finalize + reconstruct
  save.ts                     — save + maybe-activate
  recovery.ts                 — recovery-specific flows
  session-orchestration.ts    — session lifecycle glue

  flows/
    bfprofile.ts              — importBfProfile
    bfshare.ts                — importBfShare
    bfonboard.ts              — importBfOnboard
    rotation.ts               — applyRotation
```

Each flow file exposes exactly one public function with a single,
well-named signature. Internal variants (the "maybe-activate",
"save-and-activate", "onboard-connected", "onboard-rotated"
proliferation from audit finding 6) collapse to one canonical flow per
source; the subtle differences between them were boilerplate wrappers.

### Migration strategy (atomic within PR33)

1. Create the new `browser-profile/flows/` structure with the
   consolidated implementations.
2. Update every consumer import across `igloo-pwa`, `igloo-home`,
   `igloo-chrome` in the same PR.
3. **Delete** the five peer-level modules (`browser-profile-persistence.ts`,
   `browser-profile-recovery.ts`, `browser-profile-save/`,
   `browser-profile-store.ts`, `browser-session-orchestration.ts`) along
   with their directories and tests.
4. Update `index.ts` to re-export from `browser-profile/` only.

External consumers that used the `igloo-shared` barrel keep working if
they imported by name (`importBfProfile`, etc.). Any consumer that
imported from a deep path like `igloo-shared/src/browser-profile-save`
gets an atomic rewrite in the same PR — grep-audit:
`rg "from 'igloo-shared/(lib/)?browser-profile-" repos/` must return
zero post-PR33.

### Named exports

`browser-profile/index.ts`:
```ts
export {
  importBfProfile,
  importBfShare,
  importBfOnboard,
  applyRotation,
} from './flows';

export {
  createBrowserPersistedProfileBundle,
  // ... the few internal helpers that hosts actually need
} from './persistence';

export {
  createFinalizedBrowserStoredProfile,
  // ...
} from './store';

export type {
  BrowserProfilePayload,
  BrowserProfileSaveOptions,
  // ... the small set of types hosts touch
} from './types';
```

Everything else is `pub(crate)` (i.e. not in `index.ts`). Going from
"every function in every file is public via export *" to "~10 public
functions" is the main clarity win.

### Error taxonomy consolidation

All four flow functions throw typed errors:

```ts
export class BrowserProfileFlowError extends Error {
  constructor(
    public readonly kind: BrowserProfileFlowErrorKind,
    public readonly detail?: Record<string, unknown>,
  ) {
    super(kind);
    this.name = 'BrowserProfileFlowError';
  }
}

export type BrowserProfileFlowErrorKind =
  | 'decrypt_failed'
  | 'invalid_package'
  | 'activation_failed'
  | 'persistence_failed'
  | 'duplicate_profile';
```

Replaces the five slightly-drifting error variants that audit finding 6
called out (`logSharedSaveFailure` etc. reporting to different logger
domains).

### Testing

- All existing `browser-profile-*.test.ts` tests pass via the shim.
- New `browser-profile/flows/*.test.ts` tests cover one flow each with
  explicit scenarios (happy path, wrong password, malformed package,
  activation conflict).
- Grep regression: `rg '^export \*' src/browser-profile/` should not
  appear outside the transitional shim.
- Line-count check: the consolidation is a net reduction; expect
  `wc -l src/browser-profile-*.ts` to drop by ~30% once shims can be
  deleted.

---

## Critical Files

Modify (`igloo-shared`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/index.ts` (named exports — G.6)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/index.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/runtime.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/onboarding.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/bridge.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/policy.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wire/config.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts` (DELETE in PR30)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm-bridge-node.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/relay-transport.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/onboarding-transport.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/runtime-pump.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/runtime-api.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/runtime-projections.ts` (NEW — G.4)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile/` (populated per G.5)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-persistence.ts` + directory (DELETE in PR33)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-recovery.ts` + directory (DELETE in PR33)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-save/` (DELETE in PR33)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-store.ts` + directory (DELETE in PR33)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-session-orchestration.ts` + directory (DELETE in PR33)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/tests/wire-contract.spec.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/tests/fixtures/*.json` (NEW — WASM-captured wire fixtures)

Modify (consumers):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx` (drop local type declarations, use shared projections)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts` (`runtime_status: RuntimeStatusSummary | null`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/profile-runtime.ts` (BrowserBridgeNode direct typing)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx` (drop local type declarations)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/src/background.ts` (minimal — use shared types where already touched)

Reuse (do not re-invent):
- Existing types in `browser-runtime-core.ts` lines 112-247 are the
  source material — move, don't rewrite.
- Existing `deriveReadinessExplanation` function stays; gets re-exported
  from `runtime-projections.ts`.
- Bucket D's `Secret<T>` and allow-list redactor remain the canonical
  secret-handling surface; G.4's projections compose with them (e.g. a
  peer-pubkey is fine in logs; the projection doesn't wrap it in `Secret`).

## Verification

Per PR:

**PR29 (G.1 + G.6):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared
npm run test:typecheck
npm test
# Every consumer still compiles:
cd /home/cscott/Repos/frostr/frostr-infra
npm --prefix repos/igloo-pwa run test:unit
npm --prefix repos/igloo-home run typecheck
npm --prefix repos/igloo-chrome run test:unit
```
Plus: `rg '^export \*' repos/igloo-shared/src/index.ts` returns no matches.

**PR30 (G.2 — monolith split):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make demo-start && make demo-smoke && make demo-stop
```
Plus:
- `test -f repos/igloo-shared/src/browser-runtime-core.ts` — expects non-existent (deleted).
- `rg "from ['\"].*browser-runtime-core['\"]" repos/` — zero matches.

**PR31 (G.3 — export BrowserBridgeNode):**
```bash
rg 'isBrowserBridgeNode\(' repos/ | grep -v 'function isBrowserBridgeNode'
# Expected: zero matches (only the definition itself).
```
Plus: full demo harness smoke test.

**PR32 (G.4 — typed projections + consumer migration):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
rg 'as PwaRuntimeStatus|as HomeRuntimeStatus|as unknown as' repos/igloo-pwa/src repos/igloo-home/src
# Expected: zero matches.
npm --prefix repos/igloo-pwa run test:e2e  # runs PWA E2E with new types
```

**PR33 (G.5 — browser-profile consolidation):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared
npm run test
ls src/browser-profile-*.ts 2>/dev/null | wc -l  # expects 0 — all old peer modules deleted
ls -d src/browser-profile-*/ 2>/dev/null | wc -l  # expects 0 — all old directories deleted
rg "from ['\"].*browser-profile-(persistence|recovery|save|store|session-orchestration)" repos/  # expects 0
```

**Full-bucket verification:**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```

## Cross-Repo Coordination

Bucket G ships in a **second coordinated release** after Buckets A+B+C+D+E+F.
Rationale:

- A+B+C+D+E+F is the security hardening release. Bucket G is structural
  refactor. Mixing them means (a) large review surface, (b) harder to
  isolate regressions, (c) consumer migrations in G are larger than any
  of A-F and deserve their own focus.
- Bucket G has no operator impact. No re-onboarding, no `.env` migration,
  no scripting break. Purely internal cleanup.
- Bucket G unblocks a future Bucket H (host App.tsx / store.tsx modular
  cleanup). The host-side cleanups benefit from the typed projections
  landed in G.4, and from the reduced `browser-profile-*` surface landed
  in G.5.

Release sequencing:
1. **Release 1** (A+B+C+D+E+F) — 28 PRs, 1 migration event.
2. **Release 2** (G) — 5 PRs, 0 migration events. Can ship whenever G's
   review cycle completes.
3. **Release 3+** (H and beyond) — host-side modularization, `igloo-chrome`
   re-audit, Bucket J doc coherence, etc.

No bifrost-rs changes in Bucket G — the WASM bridge API is unchanged;
only TS-side types move.

## Out-of-Bucket Flags

- **Host App.tsx / store.tsx splits** — `igloo-home/App.tsx` 1,875 lines;
  `igloo-pwa/App.tsx` 1,345 + `store.tsx` 1,147. G.4 migrates the type
  declarations; the structural split is a future "browser host
  modularization" bucket.
- **bifrost-rs-side TS type generation** — generating `.d.ts` from the
  Rust WASM types (via `wasm-bindgen`'s TS output or a custom
  `ts-rs`-style derive). Would replace the hand-authored wire types
  with a single source of truth. Defer.
- **`igloo-chrome` re-audit** — Bucket J.

Note on `NodeWithEvents`: the type alias is deleted atomically in PR31
as part of the hard-cut. No deferred cleanup.

## Summary

Five PRs, ~3,800 lines touched across `igloo-shared` and consumers.
Closes the "every host re-declares the runtime shape locally" pattern
the audit synthesis identified as the cross-cutting root cause.

- **Wire types** extracted to `wire/` module hierarchy: `runtime.ts`,
  `onboarding.ts`, `bridge.ts`, `policy.ts`, `config.ts`. Previously
  internal types (`RuntimeConfig`, `OnboardingRequestBundleWire`,
  `OnboardingDecoded`, `BridgeEnvelope`) promoted to exports.
- **Named exports** replace `export *` in `index.ts`. Adding a new
  export is a visible diff.
- **`browser-runtime-core.ts` 2,189-line monolith** split into five
  focused files (`wasm-bridge-node`, `relay-transport`,
  `onboarding-transport`, `runtime-pump`, `runtime-api`). Each has a
  single responsibility and a target size ≤400 lines. Original file
  deleted atomically in PR30; no transitional shim.
- **`BrowserBridgeNode` class exported directly**, eliminating the 20+
  `isBrowserBridgeNode && typeof node.X === 'function'` runtime guards.
- **Typed projection helpers** in `runtime-projections.ts`:
  `selectActivePeers`, `selectPendingOperations`,
  `selectPeerPermissionStates`, `selectOnboardingStatuses`,
  `selectReadinessExplanation`. `igloo-home` and `igloo-pwa` drop local
  re-declarations and `as PwaRuntimeStatus`/`as HomeRuntimeStatus` casts.
- **`browser-profile-*` consolidation**: six peer-level modules collapse
  into one `browser-profile/` directory with `flows/{bfprofile,bfshare,
  bfonboard,rotation}.ts`. One canonical flow per source. Shared
  `BrowserProfileFlowError` replaces five slightly-drifting error
  taxonomies. Old peer-level modules deleted atomically in PR33 with
  consumer imports rewritten in the same PR; no re-export shims.
- **Wire-contract test** pins the shape of fixture JSON from bifrost-rs
  WASM output so future protocol drift fails CI loudly.

Ships in the second coordinated release. No version bumps on disk
formats. No operator migration. Unblocks the host-side modularization
work tentatively scoped for Bucket H.
