# `igloo-pwa` audit

Date: 2026-06-19

Scope: `/Users/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa` (src/ host code,
repo-local `test/frontend/` unit tests, and the cross-repo `test/igloo-pwa/`
Playwright specs read for coverage. WASM blobs and the igloo-shared/igloo-ui
dependencies were read only where pwa code crosses into them.)

`igloo-pwa` is the browser signing host: a single React tree (`App.tsx`) over a
single context store (`store.tsx`) that drives every flow — create, import,
onboard, rotate, recover, and the operator dashboard. The surface metrics are
genuinely clean (strict TS, `tsc --noEmit` green, ~0 `any`, no `eslint-disable`,
no TODOs), so this pass spent its effort on structure and semantics. The
dominant shape of the debt is **two unsplit monoliths**: `store.tsx` (2161 LOC)
holds ~40 action methods inside one `useMemo` keyed on the whole `state`, and
`App.tsx` (1719 LOC) inlines ~16 per-view render functions plus ~10 view-model
derivers. Both grew relative to the 2026-06-13 baseline. Beneath the god files
the recurring issues are: a 1s polling loop where the in-process runtime already
supports subscription, view-model derivers re-casting an already-typed signer
shape, duplicated error-stringify helpers that now also exist in shared, and an
import/onboard decrypt boundary whose adversarial paths are covered for storage
and WASM but not for a corrupted package. Secret hygiene at rest is good (the
persist allow-list is red-team tested); the open SEC item is the unavoidable
JS-string lifetime of in-memory passphrases/nsec, shared with every other host.

## Findings

### 1. High: `store.tsx` is a 2161-LOC god file; all ~40 actions rebuild on every state change

Rule: `ARC-01` (architecture & boundaries)

Files:
- `igloo-pwa/src/lib/store.tsx:715-2146` (the `value` `useMemo`)
- `igloo-pwa/src/lib/store.tsx:2145` (dep array `[controller, persistProfileToDashboard, selectedProfile, state]`)
- `igloo-pwa/src/lib/store.tsx:312-456` (hydration/normalization)

Why this matters:
- One file owns hydration, debounced persistence, cross-tab sync, a 1s runtime
  poll, the onboard-complete subscription, and the entire action surface for six
  user journeys. Every behavioral change to any flow routes through it.
- The action object is a single `useMemo` whose dependency list includes the
  whole `state` (line 2145). Any keystroke into any draft field rebuilds all ~40
  closures and hands a new object identity to every `useStore()` consumer —
  defeating memoization downstream (this is also CQ-07).

Smells:
- Multiple reasons to change in one module: state machine + I/O + persistence
  policy + polling + protocol-shaped updates.
- 40 methods sharing one closure scope; each `setState` updater re-spreads deeply
  nested `drafts`/`draftSecrets` literals (e.g. lines 792-818, 1184-1225).

Streamline:
- Split along journey seams, each a hook or reducer slice owning its own actions
  and tests: (a) **hydration/normalization** (`normalizeLoadedState*`, lines
  312-456) → a pure module already half-extractable; (b) **persistence + cross-tab
  sync** (effects at 491-545, `persistImmediately` 553-559); (c) **runtime
  lifecycle** (`startSigner`/`stopSigner`/`refreshSigner`/poll effect 566-610);
  (d) **create+distribute** (`generateKeyset`…`finishSetup`); (e) **import**;
  (f) **onboard**; (g) **rotate**; (h) **recover**.
- Move draft-field updates to a single generic `updateDraft(path, value)` /
  `updateSecret(path, value)` reducer so the ~25 near-identical `updateXForm`
  methods collapse (see finding 6). Key the action `useMemo` on stable
  dispatchers, not on `state`, so identity stops churning.

### 2. High: `App.tsx` is a 1719-LOC component mixing 16 view renderers with 10 signer-truth derivers

Rule: `ARC-01` (architecture & boundaries) / `ARC-02` (mixed responsibilities)

Files:
- `igloo-pwa/src/App.tsx:461-1604` (`AppShell` — one function, 16 nested `renderX` closures)
- `igloo-pwa/src/App.tsx:145-235` (`derivePendingOperations`, `deriveSignerDashboardView`, `derivePolicyDashboardView`, `deriveRuntimeSummaryLabel`)
- `igloo-pwa/src/App.tsx:1692-1708` (the flat `activeView === '…'` render switch)

Why this matters:
- A newcomer changing the onboard layout must scroll past create, import, rotate,
  recover, and the entire dashboard, all in one function body. The 16 `renderX`
  closures (e.g. `renderCreateDistribute` 842-941, `renderDashboard` 1342-1604)
  each capture `store`/`run`/local state, so they cannot move without untangling
  that closure.
- The dashboard view-model derivers (145-235) reshape signer-owned status into UI
  rows *inline in the host*, interleaving protocol shape with React.

Smells:
- A single component holding layout for every route plus the derivation layer.
- `renderDashboard` alone is ~260 lines (1342-1604) with a deeply nested
  settings-section literal.

Streamline:
- Promote each `renderX` to a real component file (`views/CreateDistribute.tsx`,
  `views/Dashboard.tsx`, …) taking explicit props; the `activeView` switch
  (1692-1708) becomes a thin router. Several already pass through to igloo-ui
  panels, so the per-view files would be small.
- Move the `derive*DashboardView` functions (145-235) into a dedicated
  `lib/dashboard-view.ts` neighbor (that file already exists for `toDashboardKey`
  / `deriveExportSummary`) so signer-shape mapping is unit-testable without React.

### 3. Medium: 1s `setInterval` poll of an in-process runtime that already exposes a subscription

Rule: `ARC-03` (host re-derives signer truth) / `CQ-07` (re-render-prone state)

Files:
- `igloo-pwa/src/lib/store.tsx:602-609` (`window.setInterval(..., ACTIVE_RUNTIME_POLL_INTERVAL_MS)`)
- `igloo-pwa/src/lib/store.tsx:246` (`ACTIVE_RUNTIME_POLL_INTERVAL_MS = 1_000`)
- `igloo-pwa/src/lib/page-runtime-host.ts:113-115` (`onOnboardComplete` subscription already exists)

Why this matters:
- The signer runtime runs *in page memory* (README: "signer runtime lives in page
  memory"), and the session object already supports push (`onOnboardComplete`,
  wired at store.tsx:614-643). Yet readiness/status/peer state are pulled on a
  fixed 1s timer via `adapter.readSession`, re-running a full snapshot mapping and
  a `setState` every second whether or not anything changed.
- Per-second `setState` on the top-level store interacts badly with finding 1:
  each tick rebuilds the whole action object.

Smells:
- Polling where a subscription fits; the push primitive is present but unused for
  status.
- Poll interval is a bare constant with no rationale comment on *why 1s*.

Streamline:
- Have the runtime host emit a `onStatusChange`/`onReadinessChange` event (mirror
  the existing `onOnboardComplete` seam) and drive the snapshot sync from it;
  keep the timer only as a coarse fallback. This removes a steady re-render and
  makes the host a reader of signer-pushed truth rather than a poller.

### 4. Medium: error-stringify logic forked five ways, two of them in this repo

Rule: `CQ-04` (duplicated logic) / `ARC-05` (duplicated across hosts)

Files:
- `igloo-pwa/src/App.tsx:99-113` (`formatUiError`)
- `igloo-pwa/src/lib/page-runtime-host.ts:138-145` (`toErrorMessage`, private)
- `igloo-shared/src/runtime-internal.ts:81` (`toErrorMessage`, **exported**)
- `igloo-shared/src/browser-profile/session-orchestration/warning.ts:3` and `igloo-shared/src/browser-profile/save/common.ts:14` (two more private `toErrorMessage`)

Why this matters:
- The same "turn `unknown` into a user string" rule is implemented five times
  across pwa + shared, each subtly different (`formatUiError` adds a
  `JSON.stringify` branch; the shared export uses a different default). A change
  to redaction or formatting policy would have to be made in all five and stay in
  sync.
- igloo-shared *already exports* a canonical `toErrorMessage`, so pwa's two copies
  are avoidable duplication, not a missing primitive.

Smells:
- A copy-pasted transform with drifting defaults; an exported shared helper that
  the consumers don't consume.

Streamline:
- Consume `toErrorMessage` from igloo-shared in `page-runtime-host.ts`; fold the
  `JSON.stringify` fallback into the shared helper (or a thin UI wrapper) and
  delete `formatUiError`. Track the two private shared copies for the igloo-shared
  pass.

Cross-repo note: `toErrorMessage` is defined 4× and `formatUiError` adds a 5th;
the canonical exported one is `igloo-shared/src/runtime-internal.ts:81`. Same
pattern the reconcile flagged as a missed 3rd shared dup, now confirmed leaking
into pwa.

### 5. Medium: `RuntimeStatusSummary`/`RuntimeReadiness` cast over a field that is already that type

Rule: `CQ-03` (type escapes)

Files:
- `igloo-pwa/src/App.tsx:146` (`as RuntimeStatusSummary | null`)
- `igloo-pwa/src/App.tsx:181-182` (two more)
- `igloo-pwa/src/App.tsx:1349` (a fourth)
- `igloo-pwa/src/lib/types.ts:142-143` (`runtime_status: RuntimeStatusSummary | null; readiness: RuntimeReadiness | null;`)

Why this matters:
- `PwaRuntimeSnapshot.runtime_status` is *already declared* `RuntimeStatusSummary
  | null` (types.ts:142), yet four call sites re-cast it. `derivePendingOperations`
  (145) even casts a parameter typed `unknown` that callers always pass the typed
  field to. These casts are pure noise that suppress the type system's help and
  would mask a real future shape change.

Smells:
- `as` over an already-correctly-typed value; an `unknown` parameter where a typed
  one is available at every call site.

Streamline:
- Type `derivePendingOperations(runtimeStatus: RuntimeStatusSummary | null)` and
  drop the four `as RuntimeStatusSummary`/`as RuntimeReadiness` casts; the field
  already carries the type. If a genuine boundary remains, narrow once at the
  snapshot's construction in `local-adapter`, not at each read.

### 6. Medium: ~25 near-identical draft-update actions, each re-spreading nested literals

Rule: `CQ-04` (duplicated logic) / `RS-02` (over-long mechanical surface)

Files:
- `igloo-pwa/src/lib/store.tsx:758-1132` (`updateCreateForm`, `updateRotationForm`, `updateRotationSource`, `updateProfileForm`, `updateImportProfileForm`, `updateImportSaveForm`, `updateOnboardConnectForm`, `updateOnboardSaveForm`, `updateRotateConnectForm`, …)
- `igloo-pwa/src/lib/store.tsx:1139-1147`, `1719-1727`, `1548-1556` (the `[field === 'password' ? … : …]` secret-routing variants)

Why this matters:
- Every form has a `updateXForm` (writes `drafts.xForm`) and a `updateXPassword`
  (writes `draftSecrets`) that differ only by which nested key they spread into.
  The secret/non-secret split is good and must be preserved, but it is currently
  re-expressed by hand ~25 times, each a fresh chance to write a secret into the
  persistable partition by mistake.

Smells:
- Parallel implementations of one transform; the only varying part is a path.

Streamline:
- Two generic dispatchers — `updateDraft(formKey, field, value)` and
  `updateSecret(secretKey, value)` — with the secret/persistable partition
  enforced in one place (and asserted by one test) rather than per-method. This
  also shrinks finding 1's god file materially.

### 7. Medium: import/onboard decrypt boundary has only happy-path coverage

Rule: `TST-02` (happy-path-only) / `SEC-04` (input validation)

Files:
- `igloo-pwa/src/lib/store.tsx:1557-1596` (`loadBfProfile` — its `catch` routes to `load-error`)
- `igloo-pwa/src/lib/store.tsx:1664-1706` (`connectOnboardingPackage` — `catch` → `onboard-failed`)
- `igloo-pwa/test/frontend/App.test.tsx:726` ("accepts a real-looking bfonboard package" — success only)
- `test/igloo-pwa/specs/profile-import.spec.ts:9` ("imports a bfprofile package" — success only)

Why this matters:
- `loadBfProfile` and `connectOnboardingPackage` decrypt attacker-supplied package
  text. Both have explicit failure branches (the `load-error` / `onboard-failed`
  screens), but no test exercises a **corrupted/truncated ciphertext** or a
  **wrong import password** through these paths. The covered adversarial cases are
  elsewhere: wrong *unlock* password (App.test.tsx:174), corrupt *storage* blob
  (instance-storage.test.tsx:55), tampered *WASM* (wasm-integrity.spec.ts:28).
- The import error screen even hard-codes a generic message; a regression that
  silently advanced past a bad package (skipping the `catch`) would not go red.

Smells:
- The two riskiest trust boundaries have only a golden-path assertion; the
  error-screen routing they implement is untested.

Streamline:
- Add unit tests that feed `importBfProfile`/`connectOnboardingPackage` a
  corrupted package and a wrong password and assert the `load-error` /
  `onboard-failed` view + preserved-secret cleanup, mirroring the existing
  wrong-unlock-password test.

### 8. Medium: `local-adapter` barrel re-exports three modules wholesale via `export *`

Rule: `ARC-04` (leaky package boundary) / `RS-05` (hidden entry points)

Files:
- `igloo-pwa/src/lib/local-adapter/index.ts:5-9` (`export * from './profile-generate'` / `'./profile-packages'` / `'./profile-runtime'`)
- `igloo-pwa/src/lib/local-adapter.ts:4` (`export * from './local-adapter/index'`)

Why this matters:
- `store.tsx` reaches the adapter as `import * as adapter from './local-adapter'`
  (store.tsx:12) and calls ~20 functions off it. The double `export *` means the
  store sees the entire interior of three modules with no curated surface; finding
  "where does `adapter.adoptStagedOnboardSession` live" is a two-hop guess through
  two barrels.

Smells:
- Whole-module `export *` chained through two files; consumer sees the drawer, not
  a designed API.

Streamline:
- Replace `export *` with an explicit named re-export list in `index.ts` (the
  curated adapter surface the store actually uses), so the boundary is a
  designed contract and grep lands on the definition in one hop.

### 9. Low: `readNumber` is dead code (defined, never called)

Rule: `LEG-04` (dead/unreachable code)

Files:
- `igloo-pwa/src/App.tsx:281-288` (`function readNumber`)

Why this matters:
- The function has exactly one occurrence in the tree (its own definition). `tsc`
  stays green only because `noUnusedLocals` is not configured, so the compiler
  does not flag unused module-level functions. It reads as a live helper a future
  editor might wire up or "fix".

Smells:
- A zero-caller function sitting next to the live `parseJsonObject`/`readNumber`
  cluster; no `noUnusedLocals` guard to catch it.

Streamline:
- Delete `readNumber` (git remembers it). Consider enabling `noUnusedLocals` in
  tsconfig so this class of drift fails the typecheck rather than accumulating.

### 10. Low: hard-coded "My Signing Key" / "2/3" placeholders on the onboard handshake & failed panels

Rule: `RS-06` (terminology vs domain) / `DOC-05` (misleading literal)

Files:
- `igloo-pwa/src/App.tsx:1069-1070` (`keysetName="My Signing Key"` `thresholdLabel="2/3"` in `renderOnboardHandshake`)
- `igloo-pwa/src/App.tsx:1092-1093` (same pair in `renderOnboardFailed`)
- `igloo-pwa/src/App.tsx:265` (`label: profile.label || 'My Signing Key'`)

Why this matters:
- The handshake panel renders *during* the connect call (before
  `pendingOnboardConnection` resolves) and the failed panel renders *after* a
  thrown connect (so no preview exists) — so unlike the reconcile's framing, the
  real keyset name/threshold are genuinely not in hand at these two points. But
  the literal `"2/3"` is still shown to a user whose keyset may be e.g. 3/5,
  presenting fabricated metadata as fact.
- The igloo-ui panel already accepts these as props with neutral fallbacks, so the
  hard-coded values are a deliberate placeholder, not a missing prop.

Smells:
- A fixed `"2/3"` threshold string on a security flow where the value is unknown;
  reads as real data.

Streamline:
- Either drop the `keysetName`/`thresholdLabel` props at these two call sites so
  the panel shows its neutral state, or thread through whatever the entered
  package text already reveals (the onboard package carries group metadata that
  can be parsed before the live handshake). Reserve concrete labels for the
  `onboard-save` step where the parsed preview is in hand.

### 11. Low: no enforced formatter (no prettier/eslint config)

Rule: `AES-06` (no enforced formatter)

Files:
- `igloo-pwa/` (no `.prettierrc*`, `.eslintrc*`, or `eslint.config.*`; `package.json` has no lint script)

Why this matters:
- Consistent with every other TS repo in the workspace: style is per-author, so
  aesthetic drift recurs and reviews re-argue formatting. The two god files would
  benefit most from a mechanical baseline before they are split.

Smells:
- A signing-host app with no `npm run lint` / `format:check` gate.

Streamline:
- Add a shared prettier + a light eslint config (workspace-wide, not pwa-only) and
  a CI `format:check`, so the AES findings above become a tool's job and the
  decomposition work lands on a stable baseline. Track at the workspace level.

Cross-repo note: applies to all five TS targets; raise once in synthesis rather
than per-repo.

### 12. Low: in-memory passphrase/nsec/share secrets are bare JS strings with no scrubbing

Rule: `SEC-01` (secret material lifecycle)

Files:
- `igloo-pwa/src/lib/types.ts:171,187` (`passphrase: string` on in-memory connection types)
- `igloo-pwa/src/lib/types.ts:294-303` (`profileFormPassword`, `distributionPasswords`, `onboard*Password`, … all `string`)
- `igloo-pwa/src/lib/store.tsx:124,1007-1035` (`recoverKeyFromShares` returns `{ nsec, signingKeyHex }` as bare strings)
- `igloo-pwa/src/App.tsx:469,538-541` (`recoveredKey` nsec held in React state)

Why this matters:
- Passphrases, the reconstructed nsec, and the per-source share passwords live as
  immutable JS strings in React state and draft objects. Unlike Rust's
  `Secret<T>`/`SecretBytes`, a JS string cannot be zeroized — it persists in the
  GC heap until collected. The code does the reachable best (never persists them;
  the persist allow-list is red-team tested at App.test.tsx:1198/1311; the
  recovered key auto-clears from state after 60s at App.tsx:318-321), so this is a
  platform-level residual, not a leak.

Smells:
- "only one type zeroizes" pattern at the workspace level: Rust hosts thread
  `Secret<T>`, the browser host cannot, and there is no shared minimal
  secret-string wrapper to at least centralize lifetime/length discipline.

Streamline:
- Accept the JS limitation but narrow the blast radius: keep secrets in the
  `draftSecrets` partition only (already done), prefer `Uint8Array` for any value
  that *can* be a byte buffer (so it can be `.fill(0)`-wiped), and minimize how
  long the recovered nsec sits in component state. A shared "transient secret"
  helper would let all hosts express the same intent.

Cross-repo note: identical residual in igloo-home (reconcile: "frontend
passphrases still bare strings, no Secret<T> analog"). A shared transient-secret
convention would serve both browser and Tauri frontends.

## Summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 6 |
| Low | 4 |
| **Total** | **12** |
