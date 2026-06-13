# `igloo-pwa` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa`

This audit focused on the PWA host's security posture (browser page-memory
runtime, localStorage persistence, asset loading, CSP posture), the `App.tsx`
and `store.tsx` control-plane shape, and the bridge-WASM wiring against
`igloo-shared`. The headline pattern is that the PWA persists nearly all
runtime-adjacent state to `localStorage`, including cleartext share secrets,
device passwords, and live runtime snapshots, with no Content-Security-Policy,
no Subresource Integrity on the WASM blobs, and no service-worker isolation.
Secondary themes are a very large `App.tsx`/`store.tsx` pair with polling-based
runtime reads, and orphaned view states that the renderer never shows.

## Findings

### 1. High: cleartext share secrets and device passwords are written to `localStorage`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/storage.ts:3`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/storage.ts:16`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:256`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:89`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:223`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:224`

Why this matters:
- `savePersistedState(state)` serializes the full `PwaPersistedState` with `JSON.stringify` and writes it to `localStorage` under the key `igloo-pwa.state.v1`.
- That state includes `profiles: PwaProfile[]`, where each profile carries `stored_password: string` (the user's device password) and `share_package_json: string` whose JSON contains the raw `seckey` hex (see `src/lib/local-adapter/profile-generate.ts:50` and `src/lib/local-adapter/common.ts:239`). `localStorage` is origin-visible to any script running in the page (XSS, extension content scripts, dev-tools copy).
- The same persisted state also includes `unlockPhrase` (current session password, `src/lib/store.tsx:622` and `src/lib/store.tsx:964`), `generatedKeyset` (all `shares[*].share_package_json` including every `seckey` for N members), `pendingLoadConfirmation.profile_payload.device.shareSecret`, `pendingOnboardConnection.profile_payload.device.shareSecret`, and `pendingRotationConnection.profile_payload.device.shareSecret`.
- There is no zeroize pattern, no typed-array `fill(0)`, and no WebCrypto unwrap. The runtime "password" check at `src/lib/local-adapter/profile-runtime.ts:39` is `unlockPhrase !== profile.stored_password`, a plain string equality against the same cleartext the storage contains, so the password offers no actual protection of the share.

Smells:
- `remember_browser_state` toggles writing secrets to disk but the default is `true` (`src/lib/store.tsx:136`).
- Draft forms also persist passwords across reloads (`profileForm.password`, `onboardSaveForm.password`, `importProfileForm.password`, `rotateConnectForm.password`) because `drafts` is part of `PwaPersistedState`.
- `clearPersistedState()` only runs when the toggle is off; there is no wipe on logout beyond clearing `unlockPhrase` in memory.

Streamline:
- Treat `share_package_json`, `stored_password`, `unlockPhrase`, `generatedKeyset`, and all `pending*Connection.profile_payload` as non-persistable and strip them from whatever ends up in `localStorage`.
- If at-rest storage of shares is intended, encrypt with a WebCrypto-derived key from the user passphrase and never store the passphrase itself.
- Split persisted state into a durable public-metadata record and an in-memory secrets record.

### 2. High: no Content-Security-Policy, no SRI, no cross-origin isolation

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/index.html:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/vite.config.ts:26`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/public/manifest.webmanifest:1`

Why this matters:
- `index.html` has no `<meta http-equiv="Content-Security-Policy">`, and the Vite config has no header-setting middleware. The app ships with default-open CSP, meaning any injected `<script>` or `eval`able string executes.
- There is no SRI (`integrity=`) on the WASM blobs or the JS loader. The bridge WASM is fetched from `/wasm/bifrost_bridge_wasm_bg.wasm` (same-origin, see `src/lib/configure-igloo-shared.ts:15`), which is good, but a same-origin compromise path (e.g., cache poisoning, CDN swap if hosted behind one, or a malicious build step) would replace the signer core silently.
- No COOP/COEP headers are set, so `crossOriginIsolated` is false and the runtime cannot use `SharedArrayBuffer`. That is probably fine today (the bridge appears to run single-threaded), but the absence of those headers also means no protection against cross-origin window references into this page.
- Given how much secret material lives in page memory and `localStorage`, a missing CSP is the single largest multiplier for any XSS hazard.

Smells:
- No server-side headers are documented for production either; `README.md` and `TESTING.md` do not mention deployment headers.
- The PWA manifest does not constrain `scope` beyond `start_url: "/"`.

Streamline:
- Add a strict CSP via `<meta http-equiv>` or serve it from the host: `default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self' wss:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`.
- Add SRI hashes to the `bifrost_bridge_wasm*` and `bifrost_profile_wasm*` files as part of the sync step in `scripts/sync-bridge-wasm.mjs` and verify them at load.
- Document required production headers (COOP `same-origin`, COEP `require-corp` if SAB is ever needed; otherwise just COOP).

### 3. High: `runtime_snapshot_json` stores bootstrap seed material in `localStorage`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/page-runtime-host.ts:207`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/common.ts:149`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/profile-runtime.ts:44`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:95`

Why this matters:
- `buildSessionSnapshot()` serializes `getRuntimeSnapshot(node)` via `JSON.stringify` into `runtimeSnapshotJson`, which is then attached to the stored profile (`src/lib/local-adapter/common.ts:149`) and persisted as `profile.runtime_snapshot_json`.
- The snapshot shape produced by the bridge contains the bootstrap record (group + share), and the test mock in `src/test/setup.ts:22` confirms the shape includes `share.seckey`. That means restart-restore flow writes raw share secret material to `localStorage` alongside the profile it came from, again without encryption.
- `startSession()` reads this straight back (`src/lib/local-adapter/profile-runtime.ts:44`), so deleting only `stored_password` is not sufficient to revoke access — the snapshot still contains the secret.

Smells:
- The snapshot is stored both inside `profiles[i].runtime_snapshot_json` and echoed again on `runtimeSnapshot.profile.runtime_snapshot_json` (see `src/lib/store.tsx:293`), multiplying at-rest copies.

Streamline:
- Treat `runtime_snapshot_json` as secret. Either encrypt it before persisting, or keep it in `sessionStorage` / memory only and require a fresh bootstrap on reload.
- If persistence is required for UX, wrap it with WebCrypto AES-GCM keyed from a PBKDF2/Argon2 derivation of the user passphrase.

### 4. Medium: runtime snapshot is polled on a 1-second interval instead of subscribed

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:141`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:303-347`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/page-runtime-host.ts:159-170`

Why this matters:
- `ACTIVE_RUNTIME_POLL_INTERVAL_MS = 1_000` drives a `window.setInterval` that calls `adapter.readSession()` → `toRuntimeSnapshot()` → `JSON.stringify(getRuntimeSnapshot(node))` once per second while the signer is active.
- Each pass allocates a new snapshot JSON string and, via `state.settings.remember_browser_state`, triggers a `localStorage.setItem` of the entire persisted state (`src/lib/store.tsx:257`). That is a per-second write of a potentially large payload for the lifetime of the signer.
- `waitForNonceSnapshot()` uses a second 100ms poll loop against `getRuntimeSnapshot(node)` until a 5-second timeout. The adapter already has an event bus (`node.on('message', ...)` in `src/lib/page-runtime-host.ts:182`), so these polls are compensating for missing readiness events.

Smells:
- Two overlapping polling loops (run-loop + readiness-wait) against the same `NodeWithEvents` that emits structured events.
- `localStorage` churn every second is observable and will accumulate I/O under devtools.

Streamline:
- Subscribe to `node` message/error events for runtime updates and invalidate the snapshot only on relevant transitions.
- Debounce or batch the persistence write, and only persist public metadata.
- Replace `waitForNonceSnapshot` with a runtime-readiness event from `igloo-shared` if one exists, or add one.

Cross-repo note: this assumes `igloo-shared` can expose a runtime-readiness event stream or at least a readiness-change callback; if it does not today, that is the place to add the contract.

### 5. Medium: `App.tsx` has grown into a 1,345-line page + controller

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx:139-205`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx:220-320`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx:1313-1336`

Why this matters:
- `App.tsx` declares local types `PwaRuntimePeerStatus`, `PwaRuntimePendingOperation`, `PwaRuntimeReadiness`, and `PwaRuntimeStatus` and keeps `runtime_status` as `unknown` on the store type (`src/lib/types.ts:118`), then casts it at every consumer with `(runtimeStatus ?? null) as PwaRuntimeStatus | null`.
- All view derivation (`derivePwaPeers`, `derivePendingOperations`, `deriveActivationStage`, `deriveActivationUpdatedAt`, `deriveRuntimeSummaryLabel`, `deriveDistributionResults`, `buildOperatorSettingsDraft`) lives in this one file, mixed with thirteen `renderX()` functions and one 280-line `renderDashboard`.
- The renderer function dispatch at `src/App.tsx:1321-1334` is a long chain of `store.activeView === 'X' ? renderX() : null` that duplicates the view enum.

Smells:
- Runtime types declared adjacent to rendering, then cast with `as` on every access.
- Single file owning both shell layout and dashboard controller logic.

Streamline:
- Move `PwaRuntimeStatus` and its sub-types next to the store (or to `igloo-shared` if the shape is stable), and type `runtime_status` in `PwaRuntimeSnapshot` accordingly so casts disappear.
- Split each `renderX` into its own file under `src/views/` and let the shell be a thin router.

### 6. Medium: `store.tsx` is a 1,147-line context with `state` as a memo dependency

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:392`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:1135`

Why this matters:
- The memoized `AppState` value uses `[persistProfileToDashboard, selectedProfile, state]` as its dependency list, so it re-creates every action closure on every state change.
- Every consumer of `useStore()` re-renders on any state change, and the closures inside (`generateKeyset`, `acceptGeneratedProfile`, `distributeShare`, `connectRotationPackage`, ...) read from `state` captured at memo time, which is refreshed each render.
- Because the memo always invalidates with state, the `React.useMemo` is load-bearing only for reference semantics, not memoization.

Smells:
- A single context that both owns data and exposes mutators, with `state` as the last dep.
- Actions close over `state` rather than using functional `setState` callbacks; some actions (e.g., `generateKeyset` at `src/lib/store.tsx:497`) could avoid the `[state]` dependency entirely.

Streamline:
- Split the context into a data context (state) and an actions context (stable reducer + action creators), or migrate to a reducer with refs so action identity is stable.
- Inline small updates with functional `setState` and drop `state` from the memo deps.

### 7. Medium: orphan view states and a dead `startCreateChoice` action

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:11`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts:25`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:428`

Why this matters:
- `PwaView` declares `'create-choice'` and `'settings'`, but `App.tsx`'s view dispatch (`src/App.tsx:1321-1334`) has no branch for either, so navigating to them renders nothing under `PageLayout`.
- `startCreateChoice()` is defined on the store (`src/lib/store.tsx:428`) and exposed through `AppState` (`src/lib/store.tsx:32`), but no caller invokes it. It is dead API surface that will go stale.
- The `'settings'` view constant is also unused; the settings flow is implemented as a `activeDashboardTab === 'settings'` branch in `renderDashboard`.

Smells:
- Enum values that produce blank screens rather than TypeScript errors.
- Public store actions that no UI binds to.

Streamline:
- Remove `'create-choice'` and `'settings'` from `PwaView`.
- Remove `startCreateChoice()` or wire it behind a real entry tile.

### 8. Medium: `stopSession`/`refreshSession` silently throw when the session drifted

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/profile-runtime.ts:69-81`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/profile-runtime.ts:83-104`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx:309-336`

Why this matters:
- `stopSession`, `refreshSession`, `readSession`, `applyPeerPolicy`, and `clearPeerPolicies` all throw `'No active browser signer session is attached to this profile.'` when module-global `activeRuntimeProfileId` does not match.
- The store's 1s poll `syncRuntimeSnapshot` swallows these throws silently (`src/lib/store.tsx:333` catch block comment "Ignore transient read failures"), but `stopSession` is also called from `logout()` (`src/lib/store.tsx:1107`) and `finalizeRotationUpdate()` (`src/lib/store.tsx:940`) where the failure is surfaced as a generic UI error.
- The singleton `activeRuntimeSession` / `activeRuntimeProfileId` (`src/lib/local-adapter/profile-runtime.ts:15`) is module-scoped and is not resilient to multiple tabs or to React StrictMode double-mount during dev.

Smells:
- Module-global runtime handle without lifecycle ownership.
- Error strings duplicated five times in one file.

Streamline:
- Encapsulate session ownership in a class or factory that returns explicit handle + dispose pair.
- Keep `stopSession` idempotent (return null instead of throwing) so logout is robust.

### 9. Medium: WASM loader is fetched from `window.location.origin` with no integrity check

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/configure-igloo-shared.ts:14`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/public/wasm/bifrost_bridge_wasm_loader.mjs:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/scripts/sync-bridge-wasm.mjs:32`

Why this matters:
- `configureWasmBridgeLoader` / `configureWasmProfileLoader` hand URLs built from `window.location.origin` to `igloo-shared`, which dynamic-imports the loader and then `fetch`es the `_bg.wasm` with no `integrity` parameter and no hash comparison.
- `sync-bridge-wasm.mjs` is a plain `fs.copyFile` from `../igloo-shared/public/wasm`; there is no digest captured at sync time.
- If a build pipeline or host substitutes either file, the signer silently boots with the swapped core. This is the single most security-critical binary in the system.

Smells:
- No recorded hash at the sync boundary between repos.
- No runtime verification against a pinned digest.

Streamline:
- Compute SHA-384 at sync time, emit a `wasm.integrity.json` with per-file digests, and verify both WASM blobs post-fetch before calling `WebAssembly.instantiate`.
- Consider inlining the two small WASM blobs into the JS bundle at build time and letting Vite's asset-hashing do SRI implicitly.

Cross-repo note: the verification contract needs to be agreed with `igloo-shared`, since the loaders live there and would be the natural place to check the digest.

### 10. Low: large `setup.ts` mock duplicates runtime shape

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/test/setup.ts:29-378`

Why this matters:
- `src/test/setup.ts` hand-rolls a 385-line mock for `WasmBridgeRuntime`, the profile WASM module, and the browser runtime session. It reimplements payload shapes inline.
- Any drift in `igloo-shared`'s runtime payloads requires manual edits here. Because the mock returns fixed hex strings (`'11'.repeat(32)`, `'22'.repeat(32)`) instead of asserting on what the app actually sent, several failure modes (wrong password, invalid share) are not exercised.

Smells:
- Large bespoke mock that duplicates production contracts.
- No negative tests for WASM-decode failure paths.

Streamline:
- Move the mock into a shared test helper in `igloo-shared` so it tracks the real shape.
- Add at least one test per public error path (`normalizeHex32` failure, wrong password, `decode_bfonboard_package` rejection).

### 11. Low: single `App.test.tsx` covers happy paths only, leans on large inline state

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/test/frontend/App.test.tsx:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/test/frontend/App.test.tsx:54-243`

Why this matters:
- There is one unit test file (`App.test.tsx`, 572 lines) and no tests for `store.tsx`, `page-runtime-host.ts`, or any adapter module directly.
- Tests work by inlining full `PwaPersistedState` blobs into `localStorage`. Those blobs drift against the current type — for example the test at `test/frontend/App.test.tsx:313` writes a `createForm` without `mode`, which is a required field in the current `PwaDraftState`. The normalizer at `src/lib/store.tsx:191` hides the mismatch.
- Failure paths (wrong password, malformed package, signer already active, runtime exception) are absent.

Smells:
- One file, mostly happy-path flows.
- Tests that rely on the normalizer papering over shape drift.

Streamline:
- Add focused unit tests for `store.tsx` reducers/actions and for `local-adapter/common.ts` helpers.
- Factor the inline localStorage fixtures into a builder so type changes break tests explicitly.

### 12. Low: README and TESTING claim `make`-driven flows that this repo does not define

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/README.md:29`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/TESTING.md:11`

Why this matters:
- The PWA README instructs readers to run `make igloo-pwa-build`, `make igloo-pwa-dev`, `make igloo-pwa-test-e2e` as the preferred entrypoints, but there is no `Makefile` in this repo and parent-workspace ownership lives in `./run.sh browser igloo-pwa ...` (per `/home/cscott/Repos/frostr/frostr-infra/CLAUDE.md`).
- A newcomer who clones only the submodule will get `make: *** No targets.` with no pointer to `run.sh`.
- The `page-memory runtime` claim in the README is accurate for the current design, but there is no matching security note that secrets and passwords are currently persisted to `localStorage`.

Smells:
- Doc drift against the parent workspace's command surface.
- No security posture documented in README / TESTING despite the browser-host role.

Streamline:
- Replace `make` references with `run.sh` commands or document both.
- Add a "Security posture" paragraph explaining what is persisted, where, and under what toggle.
