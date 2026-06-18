# Test fixtures & shared harness modules

How the cross-repo harness builds profiles, secrets, processes, and captures —
and which module owns each concern. Ownership boundary: shared building blocks
live in `test/shared/`; client-specific wiring lives under `test/igloo-<client>/`.

## Profile seeds (skip onboarding)

E2E specs fabricate a stored profile so they can boot straight to a dashboard
instead of running the full onboarding flow.

- **Contract:** `PersistableStoredProfile` + `PERSISTABLE_PROFILE_KEYS` are owned by
  **igloo-shared** (`src/persist-contract.ts`). igloo-pwa derives its localStorage
  persist allow-list from them (a compile-time guard binds `PwaProfile`), and the
  harness types its seeds against them — so a seed that sets a field the app would
  not persist (raw share secret, stored password, runtime snapshot) is a **compile
  error**, not silent dead state.
- **Builders:** `test/shared/browser-artifacts.ts` — `createGeneratedBrowserArtifacts`
  (real WASM keygen), `createOnboardingPackage`, and `createPwaStoredProfileSeed`
  (returns a `PersistableStoredProfile`). The PWA seed is applied via
  `test/igloo-pwa/support/state.ts` (`buildPwaPersistedState` + `applyPwaSeed`).
- **Chrome** seeds an encrypted blob via `test/igloo-chrome/fixtures/helpers/seed-*.ts`;
  **home** seeds inline over its RPC (`import_profile_from_raw`).

## Test secrets

`test/shared/test-secrets.ts` is the single source for the three canonical
passwords — never inline the literals:

- `PROFILE_BLOB_PASSWORD` — profile-blob seeds + browser keygen / unlock.
- `RPC_PROFILE_PASSWORD` — igloo-home + cross-client RPC profile imports.
- `LIVE_SIGNER_PASSWORD` — the headless igloo-shell co-signer.

(Per-test ephemeral onboarding-package passwords stay inline and varied by design.)

## Processes, ports, teardown

- **Ports:** `test/shared/port-allocation.ts` — `allocatePort()` via `listen(0)`.
  The single source; never pick a random/fixed port.
- **Teardown:** `test/shared/process-lifecycle.ts` — `closeChild()` (idempotent
  SIGTERM→SIGKILL escalation, always resolves).
- **Orphan reaper:** `test/shared/process-registry.ts` records spawned helper PIDs;
  `test/shared/global-teardown.ts` (wired via `defineFrostrPlaywrightConfig`) reaps
  any that outlived their spec — run-scoped, never a blanket `pkill`.
- **Relay:** `test/shared/local-relay.ts` (`startLocalRelay`) uses all three above.

## Visual / agent capture

`test/shared/visual-harness.ts`:

- `captureVisual(page, { client, section, name })` → `.tmp/visual/<client>/<section>/`
  for storage-seeded `@visual` snapshots (the pwa `visual-manifest.json` paths).
- `captureAgentArtifact(page, { client, state, baseName? })` → `.tmp/agent/` for the
  `make screenshot` tool (PNG + visible-text dump + `screenshot.json`).

## Fixture entry points per client

| Client | Fixtures |
|--------|----------|
| pwa | `test/igloo-pwa/support/` (state, ui, flows, page objects) |
| chrome | `test/igloo-chrome/fixtures/` (extension, live-signer, demo-harness) |
| home | `test/igloo-home/fixtures/` (app harness, demo harness) |
