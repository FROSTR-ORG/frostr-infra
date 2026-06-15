# `igloo-pwa` audit

Date: 2026-06-13

Scope: `repos/igloo-pwa` (browser PWA host — source under `src/`, unit tests under `test/frontend/`, E2E specs under the top-level `test/igloo-pwa/`)

`igloo-pwa` is the browser-resident signing client: a React app over a page-memory WASM signer, serving profile create, import, onboard, rotate, and recover flows. The security posture is unusually strong for a browser host — the v2 schema scrubbed share secrets from localStorage, an explicit allow-list controls what reaches `localStorage`, `draftSecrets` fields are kept out of the persist path, and the onboarding handshake no longer leaks `bootstrap.share.seckey` through the poll path. The dominant debt is architectural: two God Files (store + App) accumulate every flow in one place; there is no enforced formatter; two view-state names in the union type have no corresponding render branch; and adversarial-path unit coverage is thin relative to the complexity of the secret-handling logic.

## Findings

### 1. High: `store.tsx` (2067 LOC) and `App.tsx` (1724 LOC) are God Files with many independent reasons to change

Rule: `ARC-01` (Architecture & boundaries)

Files:
- `repos/igloo-pwa/src/lib/store.tsx:1–2067`
- `repos/igloo-pwa/src/App.tsx:1–1724`

Why this matters:
- `store.tsx` owns the full React context, state initialization, hydration normalization, debounced persist logic, the polling effect, the `SessionController` lifecycle, AND 40+ action handlers — every distinct user journey lives in the same `useMemo` closure. Any change to any flow requires reading and reasoning about the entire file.
- `App.tsx` owns routing (18 views), 10+ local state slices, all modal management, all derived view models, UI helpers, and the CSP-sensitive `RecoverPrivateKeyView` component. The known hotspot (`igloo-pwa/src/lib/store.tsx ~2k` LOC) named in the rules has only grown.
- A caller touching the rotate flow must navigate 2000+ lines to find the relevant actions; any regression risk is spread across unrelated state.

Smells:
- `store.tsx` mixes persistence layer, session lifecycle, navigation policy, and 40+ action definitions inside one `useMemo` block over 1400 lines.
- `App.tsx` contains 18 `render*` inner functions, local operator settings state, export modal state, welcome-unlock state, and the full view-dispatch switch — all in `AppShell`.

Streamline:
- Split `store.tsx` along its natural seams: persistence/hydration → `store-persistence.ts`; session lifecycle adapters → pulled up into adapter helpers; per-flow action groups → separate hook files imported by the store provider.
- `App.tsx`: extract `RecoverPrivateKeyView` (already a named export, could be its own file), move the view dispatch into a `<ViewRouter />` component, and co-locate modal state with the flows that own it.

Cross-repo note: `igloo-home/src/App.tsx` exhibits the same monolith pattern. Likely a shared debt.

---

### 2. High: `'settings'` and `'create-choice'` are in the `PwaView` union but have no render branch in `AppShell`

Rule: `LEG-04` (Legacy & deprecation)

Files:
- `repos/igloo-pwa/src/lib/types.ts:14,31`
- `repos/igloo-pwa/src/App.tsx:1696–1712`

Why this matters:
- `'settings'` at line 31 and `'create-choice'` at line 14 are reachable view state values (`store.tsx:688` sets `create-choice`; `store.tsx:409` sets it during hydration normalization) but neither has a corresponding `{store.activeView === 'create-choice' ? ... : null}` branch in the render list. A user landing on either state sees a blank content area — no heading, no controls, no back link.
- `'create-choice'` is set as a bounce-back destination when a mid-create reload loses the pending keyset (line 409), so this is a real user-visible path.
- `'settings'` appears in `types.ts` but there is no code path that navigates to it today; it is dead type-level surface.

Smells:
- `PwaView` union contains names that have no corresponding rendering entry in the App dispatch list (lines 1696–1712).
- Hydration normalization at line 409 can write `activeView: 'create-choice'` to state, making it live rather than hypothetical.

Streamline:
- Either remove `'create-choice'` from the type and change the bounce destination to `'create-generate'`, or add the missing render branch.
- Delete `'settings'` from the `PwaView` union type — settings is a dashboard tab, not a top-level view.

---

### 3. High: `connectOnboardingPackage` error path appends last-20 runtime log lines to the thrown error message

Rule: `SEC-02` (Security — secret leakage through logs/errors)

Files:
- `repos/igloo-pwa/src/lib/page-runtime-host.ts:356–363`

Why this matters:
- On onboarding failure, `page-runtime-host.ts` catches the WASM error, collects the last 20 lines from the in-memory log buffer, and rethrows as: `${message} | runtime_logs=${JSON.stringify(lines)}`. The log lines are formatted by `formatLogLine`, which extracts `error_message` fields from structured runtime events (line 162–163). If a runtime event carries key material in its `error_message` (plausible in WASM error payloads from bifrost-rs), it would ride along in the thrown `Error.message` and surface in the `uiError` state displayed in the UI (via `formatUiError` in `App.tsx`).
- The guard at `formatLogLine` only extracts known fields; it does not redact or allow-list the content. A future bifrost-rs event that includes a share key in its error message would silently leak through.

Smells:
- `runtime_logs=${JSON.stringify(lines)}` embedded in the Error message is a fragile allow-list of safe content — it assumes bifrost-rs will never emit key material in a log event.
- The error path discards the `logs` buffer object but not its content before rethrowing.

Streamline:
- Drop the log appendage from the thrown error. If diagnostics are needed on failure, surface them as a separate structured field (not in the `message` string) so the UI can render them in a controlled code block, not in a general-purpose error banner. At minimum, gate the log appendage on a DEV-mode flag.

---

### 4. Medium: `AppShell` owns 10+ independent local state slices and 18 render methods — mixed responsibilities in one component

Rule: `ARC-02` (Architecture & boundaries)

Files:
- `repos/igloo-pwa/src/App.tsx:495–1715`

Why this matters:
- `AppShell` is a single React component that manages: UI error state, welcome-unlock modal state (profile id, password, error, submitting flag), welcome-delete modal state, recovered-key state, clipboard copy state, export modal state (format, result, busy, error), unsaved-settings navigation state, clear-credentials dialog state, operator settings draft, and the full routing dispatch across 18 views.
- A developer changing the export modal behavior must read the full 1200-line `AppShell` to be sure nothing else is affected. These concerns are genuinely separate — neither the export modal nor the welcome-unlock modal knows or cares about the other.

Smells:
- `AppShell` has more than a dozen `React.useState` calls at the top level, each for a different concern.
- Inner functions `renderError`, `renderRuntimeWarning`, and 18 `render*` view functions are all co-mingled with modal state and the `run` error wrapper.

Streamline:
- Extract welcome-unlock, welcome-delete, export modal, and clear-credentials dialog into their own small components that receive only the props they need.
- Extract the view router (the block at lines 1696–1713) into a `<ViewRouter />` that dispatches to view components, keeping `AppShell` as an orchestrator of modals and the header only.

---

### 5. Medium: `AppShell` re-derives `OperatorSettingsDraft` and `settingsDirty` locally rather than from the store

Rule: `ARC-03` (Architecture & boundaries — host re-derives signer truth)

Files:
- `repos/igloo-pwa/src/App.tsx:112–140,599–620`

Why this matters:
- `buildOperatorSettingsDraft` and `settingsDirty` are both computed in `AppShell` local state. They derive from `selectedProfile` (which lives in the store), recomputing the exact same "what the saved settings look like" logic the store already knows. If a new profile field is added to the operator settings, there are two places to update: the store's `saveOperatorSettings` and the App's `buildOperatorSettingsDraft`.
- The `OperatorSettingsDraft` type (lines 112–123) locally re-declares shape that mirrors `PwaProfile`'s `signer_settings` and is maintained in sync by hand.

Smells:
- `OperatorSettingsDraft` type in `App.tsx` re-declares `sign_timeout_secs`, `ping_timeout_secs`, `request_ttl_secs`, `state_save_interval_secs`, `peer_selection_strategy` — a subset of `PwaSignerSettings`.
- `settingsDirty` (lines 614–621) serializes two objects to JSON strings for comparison, which is fragile and order-dependent.

Streamline:
- Lift the operator settings draft into the store as a `PwaDraftState` sub-key or a separate context, so the dirty check and the save action operate on the same state atom.
- Replace the JSON-stringify dirty check with a typed field-by-field comparison or a deep-equal helper.

---

### 6. Medium: No enforced formatter (no ESLint / Prettier config) in a 3800-LOC TypeScript repo

Rule: `AES-06` (Aesthetics & formatting)

Files:
- `repos/igloo-pwa/package.json` (no `eslint`, `prettier`, or `@eslint/*` devDependencies)
- `repos/igloo-pwa/` (no `.eslintrc*`, `.prettierrc*` files)

Why this matters:
- `tsconfig.json` provides type checking but no style enforcement. With two 1700+ LOC files, style consistency already varies by author. Without a formatter gate, AES findings in `store.tsx` and `App.tsx` will recur on every PR.
- The rules note explicitly: "no TypeScript repo here configures eslint/prettier" — this confirms the pattern is workspace-wide, but igloo-pwa is the host where it bites hardest.

Smells:
- DevDependencies include TypeScript, Vite, Vitest but no lint or format tooling.
- Line density and import ordering vary noticeably between `store.tsx` (dense, minimal blank lines in action handlers) and `page-runtime-host.ts` (well-spaced with clear sections).

Streamline:
- Add Prettier with a minimal config and a `format:check` script; wire it into the CI pre-push gate alongside `tsc`. ESLint with `react-hooks` plugin would catch stale-dependency array bugs in the many `useEffect` and `useCallback` calls in `store.tsx` and `App.tsx`.

Cross-repo note: No other igloo-* client has a formatter either. Workspace-level decision.

---

### 7. Medium: Adversarial-path unit tests are thin relative to the complexity of the secret-handling state machine

Rule: `TST-02` (Testing — happy-path-only coverage)

Files:
- `repos/igloo-pwa/test/frontend/App.test.tsx:1–1277`
- `repos/igloo-pwa/test/frontend/session-controller.test.ts:1–383`

Why this matters:
- The `toPersistable` allow-list tests (lines 950–1099) and the `share_package_json` red-team tests are excellent and cover the primary secret-leakage vector. However, adversarial paths on the state machine itself are absent: wrong passphrase on unlock (the welcome-unlock test at line 686–701 only mocks a success path); relay URL injection; profile corruption leading to quarantine; `rotateDeviceUnlockVerified` resetting on passphrase change is tested but the equivalent for `recoverDeviceUnlockVerified` is not. The rotation and recovery flows have unit tests for happy paths but no "wrong passphrase" or "corrupted artifact" assertions.
- The error path in `connectOnboardingPackage` (where `activeView` flips to `onboard-failed`) is tested visually in E2E but has no unit assertion on the error-to-state mapping.

Smells:
- `App.test.tsx` contains 15 tests, most of which are navigation/render checks or storage migration assertions. Only the `recoverKeyFromShares` and `verifyRecoverDeviceUnlock` tests probe actual security gates.
- No unit test asserts that a wrong passphrase on `startSigner` surfaces an error rather than crashing.

Streamline:
- Add adversarial-path unit tests: wrong passphrase on `loadStoredProfile` should surface an error not a crash; `connectOnboardingPackage` error sets `activeView: 'onboard-failed'`; a corrupted `isPlausiblePersistedState` blob quarantines and boots clean; `normalizeLoadedStateFromStorage` exception branch clears state.
- Cross-check the `recoverDeviceUnlockVerified` reset-on-change invariant in a parallel test to the existing rotate test.

---

### 8. Medium: `'onboard-handshake'` render shows hardcoded `keysetName="My Signing Key"` and `thresholdLabel="2/3"` — static values not derived from the live connection state

Rule: `DOC-05` / `CQ-06` (Stale misleading data / magic values)

Rule: `CQ-06` (Code quality — magic values)

Files:
- `repos/igloo-pwa/src/App.tsx:1109–1128,1130–1153`

Why this matters:
- `renderOnboardHandshake()` at line 1109 and `renderOnboardFailed()` at line 1130 pass hardcoded `keysetName="My Signing Key"` and `thresholdLabel="2/3"` to the UI components. The handshake is in progress — the actual keyset name and threshold are not yet known — but "2/3" would be wrong for any group that isn't exactly threshold 2 of 3, and "My Signing Key" is a generic placeholder, not the group name from the onboarding package.
- A user onboarding into a 3-of-5 group sees "2/3" during the handshake. This is a minor UX lie, but it is the kind of thing that erodes trust in security-sensitive flows.

Smells:
- Magic string `"My Signing Key"` and magic ratio `"2/3"` appear in exactly two render functions, both of which have access to `store.drafts.onboardConnectForm.packageText` where the true data lives.
- The same values appear on both `renderOnboardHandshake` and `renderOnboardFailed`, suggesting they were left as placeholders that were never wired up.

Streamline:
- If the decoded keyset metadata is not available at handshake time, replace the literals with a loading indicator or omit them. If `pendingOnboardConnection` is already populated (as it is in some flow states), derive `keysetName` and `thresholdLabel` from it. At minimum, document why the placeholder is intentional.

---

### 9. Low: `AppShell` stores active poll state in React state (`runtimeSnapshotRef`) alongside a 1-second `setInterval` — polling where subscription might fit

Rule: `CQ-07` (Code quality — mutation-heavy / re-render-prone state)

Files:
- `repos/igloo-pwa/src/lib/store.tsx:238,495–539`

Why this matters:
- The 1-second poll (`ACTIVE_RUNTIME_POLL_INTERVAL_MS = 1_000`) calls `adapter.readSession` on every tick, which calls `session.read()` on the WASM node. Every non-null result triggers a `setState` with a new snapshot object, which re-renders the entire `AppStore.Provider` tree including all consuming components. There is no structural equality check to skip re-renders when the snapshot has not changed.
- `runtimeSnapshotRef` is a ref used to break stale-closure cycles in the interval callback, but it requires careful synchronization with the effect dependency array.

Smells:
- `syncRuntimeSnapshot` calls `setState` unconditionally when `runtimeSnapshot` is non-null, even if the returned value is byte-equal to the previous snapshot.
- `ACTIVE_RUNTIME_POLL_INTERVAL_MS = 1_000` is documented but the bifrost-rs session already emits events — an event-driven subscription would be more efficient.

Streamline:
- Add a shallow-equality guard before calling `setState` in `syncRuntimeSnapshot` (compare at least `runtime_log_lines.length` and a status hash) to avoid forcing a re-render every second when nothing changed.
- Investigate whether the `BrowserRuntimeSession` contract can be extended with a change-event subscription so the poll interval can be widened or removed.

---

### 10. Low: `PwaProfile` carries `profile_string` and `share_string` fields that are excluded from the persist allow-list but their purpose is undocumented on the type

Rule: `DOC-04` (Documentation — missing rationale for non-obvious choices)

Files:
- `repos/igloo-pwa/src/lib/types.ts:111–112`
- `repos/igloo-pwa/src/lib/persist-allowlist.ts:26–44`

Why this matters:
- `PwaProfile` has `profile_string: string` and `share_string: string` (lines 111–112). These fields contain the encrypted `bfprofile1`/`bfshare1` bech32m strings and are intentionally excluded from the persist allow-list (not in `PROFILE_ALLOWED_KEYS`). But neither the type definition nor the allow-list comment explains what these fields are for while in-memory, who populates them, or why they're on the profile record but not persisted.
- A future contributor might add them to `PROFILE_ALLOWED_KEYS` reasoning that they're "just export strings, they should survive a reload" — not knowing that the encryption key is the local passphrase.

Smells:
- `profile_string` and `share_string` have no doc comment on `PwaProfile` explaining why they're non-persisted.
- `PROFILE_ALLOWED_KEYS` comment at line 7–23 of `persist-allowlist.ts` explains many decisions but does not call out these two fields.

Streamline:
- Add a brief inline comment on both fields in `types.ts` explaining: encrypted under local passphrase; in-memory only; used for export and rotation; excluded from the persist allow-list to avoid confusion about re-encryption at rest.

---

### 11. Low: `vite.config.ts` serves the dev server on `0.0.0.0` with no auth — the WASM-backed signer is reachable from any network interface on the dev machine

Rule: `SEC-07` (Security — defence-in-depth at the shell boundary)

Files:
- `repos/igloo-pwa/vite.config.ts:56–57`

Why this matters:
- `host: '0.0.0.0'` binds the dev server to all interfaces. On a developer machine connected to a shared network, any peer on the same LAN can reach the running signer session, which holds the decrypted share in page memory.
- The production deployment docs (`README.md:74–80`) correctly call for CSP and COOP/COEP headers. The dev server does configure COOP/COEP headers (lines 69–73), but the network-wide binding is still broader than needed.

Smells:
- `host: '0.0.0.0'` in a dev config for a cryptographic signing app, without a note about the exposure.

Streamline:
- Change the default dev `host` to `127.0.0.1` (loopback only). Document a `IGLOO_PWA_HOST=0.0.0.0` escape hatch for developers who intentionally want LAN access during mobile/device testing. The workspace `Makefile` target `igloo-pwa-dev` can pass the override explicitly when needed.

---

### 12. Low: Commented-out code absent but `onboarding_package` field on `PwaProfile` type appears to be dead — always `null` on new profiles, never read

Rule: `LEG-04` (Legacy & deprecation)

Files:
- `repos/igloo-pwa/src/lib/types.ts:116`
- `repos/igloo-pwa/src/lib/local-adapter/common.ts:185`
- `repos/igloo-pwa/src/lib/local-adapter/profile-packages.ts:56,97,142`

Why this matters:
- `PwaProfile.onboarding_package?: string | null` is set to `null` in every `createStoredProfileFromPayload` call (line 185 of `common.ts`) and in every fixture in the tests. It is never read by any adapter function in `igloo-pwa`. The field name suggests it was intended to persist an onboarding package string, but there is no code path that uses it after creation.
- The field travels through import/export paths (`profile-packages.ts:56,97,142`) as a passthrough, inflating the profile record size.

Smells:
- `onboarding_package: null` appears verbatim in every profile fixture and every `createStoredProfileFromPayload` call.
- No adapter function in `igloo-pwa` reads `onboarding_package` — `grep -r "onboarding_package" src/lib/` returns only writes.
- The field is absent from `PROFILE_ALLOWED_KEYS`, so it is never persisted either.

Streamline:
- Confirm with `igloo-shared` whether `onboarding_package` is consumed downstream (it may be a `createFinalizedBrowserStoredProfile` contract field). If not, remove it from `PwaProfile` and all construction sites. If it is a shared contract field, document its purpose and why igloo-pwa always passes `null`.

## Summary

| Severity | Count |
|---|---|
| High | 3 |
| Medium | 5 |
| Low | 4 |
| **Total** | **12** |
