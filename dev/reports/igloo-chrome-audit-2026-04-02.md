# `igloo-chrome` Audit

Date: 2026-04-02

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome`

This audit focused on runtime ownership, background-worker orchestration, storage/state modeling, UI control flow, and the Chrome Playwright harness. The main pattern across the codebase is not one isolated bug; it is control-plane sprawl. Background logic, runtime-host logic, storage snapshots, UI fetch loops, and test compatibility helpers all re-express the same runtime state in different places.

## Findings

### 1. High: `background.ts` is a control-plane monolith and also persists a derived app-state cache

Files:
- `repos/igloo-chrome/src/background.ts:408-465`
- `repos/igloo-chrome/src/background.ts:487-500`
- `repos/igloo-chrome/src/background.ts:966-1424`
- `repos/igloo-chrome/src/extension/storage.ts:195-229`

Why this matters:
- `background.ts` currently owns message dispatch, onboarding, profile activation, profile import/recovery, permission prompts, runtime lifecycle updates, runtime control, state publication, and dashboard actions.
- `buildAppState()` derives a full `ExtensionAppState`, then `publishAppStateUpdated()` stores that derived snapshot back into extension storage before broadcasting it.
- That means the extension has two representations of state:
  - durable primitives in storage such as active profile, lifecycle, permission policies, and desired-active flag
  - a second persisted, derived `ExtensionAppState`
- The derived snapshot is expensive to rebuild and easy to let drift, especially because runtime truth already lives elsewhere.

Smells:
- High fan-in file with unrelated responsibilities.
- Derived state written back to storage instead of being projected on demand.
- Repeated `publishAppStateUpdated()` calls after many actions, causing storage churn and broad invalidation.

Streamline:
- Split the background worker into small services:
  - `ProfileService`
  - `RuntimeCommandService`
  - `PermissionPromptService`
  - `AppStateProjector`
- Stop persisting `ExtensionAppState` unless there is a hard UX requirement for crash recovery of UI-only state. Prefer deriving it on request from primary storage plus the live runtime host.

### 2. High: onboarding lifecycle reporting is misleading, and the failure path contains a real bug

Files:
- `repos/igloo-chrome/src/background.ts:809-868`

Why this matters:
- `handleStartOnboardingRequest()` records `decoding_package`, then runs the whole async onboarding capture, and only after it returns does it write `connecting_peer`, `awaiting_onboard_response`, `snapshot_captured`, and `profile_persisted`.
- Those stages are not real progress updates. They are retrospective bookkeeping after the work is already finished.
- In the `catch` path, the code references `messageText` on `background.ts:861-862`, but that variable is not defined in this function. That is a concrete bug in the error path.

Smells:
- Lifecycle stages are synthetic instead of reflecting actual runtime transitions.
- Error classification is implemented in the wrong place and with a broken local reference.

Streamline:
- Move onboarding lifecycle transitions into the onboarding/runtime path where those transitions actually happen.
- Make onboarding return structured progress/error information instead of trying to infer lifecycle after the fact.
- Fix the undefined `messageText` bug immediately.

### 3. High: `extension-runtime-host.ts` is a second monolith with polling, snapshot churn, and repeated state publication patterns

Files:
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:67-72`
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:226-265`
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:286-297`
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:418-448`
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:457-559`
- `repos/igloo-chrome/src/lib/extension-runtime-host.ts:569-614`

Why this matters:
- The runtime host owns session lifecycle, snapshot persistence, diagnostics, onboarding capture, provider preparation, and runtime status projection in one singleton module.
- `loadUnlockedProfileById()` polls storage for up to 10 seconds waiting for unlock state to appear.
- `waitForNonceSnapshot()` polls the runtime snapshot for usable nonces instead of subscribing to an explicit readiness event.
- `persistSessionSnapshotInBackground()` is triggered after runtime-status events and also from boot, which can create repeated encrypted blob rewrites.

Smells:
- Global mutable singleton state: `signerSessionPromise`, `signerSessionKey`, `runtimePhase`, `pendingBootDiagnostics`.
- Missing shared operation wrapper for common patterns:
  - resolve session
  - run operation
  - persist snapshot
  - recalculate runtime phase
  - emit status
- Polling is compensating for weak sequencing/contracts between storage, runtime, and callers.

Streamline:
- Introduce a `RuntimeController` abstraction with explicit operations and one post-operation pipeline.
- Replace storage polling with explicit sequencing from the caller that unlocks/activates profiles.
- Replace snapshot polling with a real runtime readiness contract from `igloo-shared` if available.
- Debounce or coalesce persisted snapshot writes.

### 4. Medium: app-state and lifecycle synchronization are more expensive and more coupled than they need to be

Files:
- `repos/igloo-chrome/src/background.ts:408-423`
- `repos/igloo-chrome/src/background.ts:450-465`
- `repos/igloo-chrome/src/background.ts:1345-1407`
- `repos/igloo-chrome/src/extension/storage.ts:272-333`

Why this matters:
- Every publish rebuilds app state and performs per-record unlock checks using `Promise.all(records.map(...loadUnlockedProfileKey...))`.
- Runtime-control actions often trigger broad app-state publishes even when only a small runtime field changed.
- Lifecycle updates are written separately from app-state publication, so the system relies on ordering across multiple async writes.

Smells:
- O(n) profile unlock probing on each app-state publish.
- Wide state refreshes for narrow updates.
- Async ordering between lifecycle storage and app-state snapshots.

Streamline:
- Keep a smaller in-memory cache for unlocked profile ids if possible.
- Publish narrow runtime updates to the UI and reserve full app-state rebuilds for profile/storage transitions.
- Treat lifecycle as primary state and app-state as a pure projection, not another durable record.

### 5. Medium: the client and background still carry a half-migrated long-task transport

Files:
- `repos/igloo-chrome/src/extension/client.ts:88-140`
- `repos/igloo-chrome/src/extension/client.ts:196-206`
- `repos/igloo-chrome/src/background.ts:935-964`

Why this matters:
- `sendPortMessage()` is still implemented and the background still listens on `ext.longTask`.
- `startOnboarding()` does not use that transport; it uses normal `sendMessage()` wrapped in a timeout.
- That leaves a dead or half-migrated compatibility path in both the client and the background worker.

Smells:
- Two transports for the same class of work.
- One of them appears unused in production code.

Streamline:
- Pick one transport:
  - if onboarding truly needs a long-lived channel, use the port path consistently
  - otherwise delete the port path and the `onConnect` handler

### 6. Medium: UI pages are acting as controllers, and `Onboarding.tsx` still has production console breadcrumbs

Files:
- `repos/igloo-chrome/src/pages/Signer.tsx:54-166`
- `repos/igloo-chrome/src/pages/Signer.tsx:168-202`
- `repos/igloo-chrome/src/pages/Onboarding.tsx:104-126`
- `repos/igloo-chrome/src/lib/store.tsx:64-142`

Why this matters:
- `Signer.tsx` fetches status and diagnostics, derives peer view state, subscribes to runtime messages, and also polls every 15 seconds.
- That logic sits beside button handlers and presentation state, which makes the page harder to reason about and harder to test.
- `Onboarding.tsx` still emits raw `console.info` and `console.error` breadcrumbs for onboarding submission.

Smells:
- UI layer mixing rendering, transport orchestration, and runtime refresh policy.
- Debug logging left in production UI code.

Streamline:
- Move signer data fetching and refresh policy into the store or a dedicated hook such as `useRuntimeStatus`.
- Keep pages presentation-first.
- Remove the console breadcrumbs or route them through the structured logger.

### 7. Medium: the React store leans on polling, whole-app refetches, and optimistic local mutation

Files:
- `repos/igloo-chrome/src/lib/store.tsx:79-142`
- `repos/igloo-chrome/src/lib/store.tsx:147-257`
- `repos/igloo-chrome/src/lib/store.tsx:260-292`

Why this matters:
- The store does an initial fetch, listens for `APP_STATE_UPDATED`, and also polls every second while unconfigured.
- Most actions follow the same pattern:
  - send one command
  - refetch the entire app state
  - overwrite local state
- `logout()` mutates local state optimistically before background state is confirmed.

Smells:
- Polling is filling gaps in event modeling.
- Whole-state refresh is used as a generic reconciliation tool.
- Optimistic local mutation risks temporary divergence from background truth.

Streamline:
- Collapse repetitive action wrappers into a single helper.
- Remove the unconfigured poll loop if onboarding/profile events can be modeled explicitly.
- Avoid optimistic state rewrites unless the UX needs them and rollback is implemented.

### 8. Medium: protocol and state shapes are too broad for one local file and are vulnerable to drift

Files:
- `repos/igloo-chrome/src/extension/protocol.ts:1-325`

Why this matters:
- `protocol.ts` contains message types, provider types, lifecycle types, runtime summary types, snapshot types, app-state types, prompt types, and runtime control types in one file.
- Some of these shapes are close to shared runtime concepts but are re-expressed locally inside the extension.

Smells:
- One large schema bag for unrelated concepts.
- Local copies of runtime-facing types increase drift risk against `igloo-shared`.

Streamline:
- Split protocol into focused modules:
  - `messages.ts`
  - `lifecycle.ts`
  - `runtime-types.ts`
  - `provider-types.ts`
- Re-export shared runtime types from `igloo-shared` where possible instead of redefining them.

### 9. Medium: Playwright still contains a compatibility RPC layer and duplicates runtime readiness rules

Files:
- `test/igloo-chrome/fixtures/extension.ts:680-786`
- `test/igloo-chrome/support/runtime.ts:49-121`

Why this matters:
- The fixture still translates compatibility RPC names like `runtime.snapshot`, `runtime.status`, and `runtime.prepare_sign`.
- The readiness rule `canProceedWhileDegraded()` is implemented both in the fixture and in `support/runtime.ts`.
- This makes test semantics another place where runtime rules can drift from production.

Smells:
- Large fixture acting as a translation layer instead of thin test plumbing.
- Duplicated readiness policy logic across test helpers.

Streamline:
- Delete the compatibility RPC shim once all specs use current extension APIs directly.
- Centralize readiness assertions and degraded-reason policy in one test helper.

### 10. Low: the Chrome test harness is large enough to deserve its own cleanup pass

Files:
- `test/igloo-chrome/fixtures/extension.ts`
- `test/igloo-chrome/fixtures/live-signer.ts`
- `test/igloo-chrome/specs/runtime-lifecycle.spec.ts`
- `test/igloo-chrome/support/onboarding.ts`

Why this matters:
- The largest fixture files are now comparable to small subsystems.
- The harness clearly carries meaningful business logic, not just test utilities.

Smells:
- Maintenance-heavy custom test framework.
- Harder onboarding for future contributors debugging failures.

Streamline:
- Extract reusable helpers into smaller support modules.
- Keep fixtures thin and push assertions into focused test helpers.

## Recommended Cleanup Order

### Phase 1: fix correctness hazards
- Fix the undefined `messageText` bug in `handleStartOnboardingRequest()`.
- Remove or unify the dead long-task transport.
- Remove UI console breadcrumbs from `Onboarding.tsx`.

### Phase 2: reduce control-plane duplication
- Stop persisting the derived `ExtensionAppState`, or at least demote it from primary storage-backed state.
- Extract background responsibilities into smaller services.
- Introduce a shared runtime-operation wrapper in `extension-runtime-host.ts`.

### Phase 3: simplify state flow
- Move signer runtime fetching/subscription logic out of `Signer.tsx`.
- Replace whole-app refetch patterns in the store with narrower updates or typed action helpers.
- Remove the unconfigured poll loop once explicit onboarding/profile transitions are modeled.

### Phase 4: retire compatibility and test debt
- Delete the compatibility RPC layer in Playwright fixtures.
- Deduplicate readiness/degraded-reason logic.
- Break up the largest test fixtures into smaller support modules.

## Suggested Target Architecture

The current system would be simpler if it followed this split:

- Background worker:
  - message routing
  - permission prompts
  - profile commands
  - runtime command dispatch
- Runtime controller:
  - single owner of live runtime session
  - status/readiness projection
  - snapshot persistence
  - onboarding capture
- Storage layer:
  - durable primitives only
  - no full derived app-state snapshots
- UI/store:
  - subscribe to explicit updates
  - minimal transport logic
  - no polling except where Chrome platform behavior truly requires it
- Tests:
  - direct use of current extension APIs
  - one readiness/assertion helper library

## Bottom Line

`igloo-chrome` is no longer dominated by the old offscreen design, but the code still carries the shape of a migration: large orchestrator modules, derived-state persistence, compatibility transport leftovers, polling as glue, and test helpers that reimplement production rules.

The most valuable cleanup is not micro-optimization. It is reducing duplicate ownership of runtime state and collapsing broad orchestration flows into a smaller number of explicit, well-bounded services.
