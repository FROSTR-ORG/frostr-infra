# `igloo-home` audit

Date: 2026-06-19

Scope: `/Users/cscott/Repos/frostr/frostr-infra/repos/igloo-home` — the Tauri
desktop co-signer host (React frontend under `src/`, Rust shell under
`src-tauri/src/`). Covered: `src/App.tsx`, the `src/lib/*` API + view layer, the
`src-tauri/src` command/session/profile modules, the test dispatcher, and the
frontend test suite. Not covered: the bifrost-rs signing core (separate target),
generated Tauri schema JSON, and the desktop/visual e2e harness runners.

igloo-home is the strongest of the five hosts on surface hygiene: the frontend
typechecks clean (`tsc --noEmit` exits 0), the only `as unknown as` cast is the
documented single IPC boundary in `runtime-status.ts`, and the Rust IPC inputs
already wrap every passphrase in `bifrost_core::secret::Passphrase`
(`ZeroizeOnDrop`) with `Debug` redaction — the secret-at-rest discipline the
2026-04-22 pass asked for is genuinely present on the Rust side. The debt is
**structural**, and it is concentrated. `App.tsx` is a 2086-line monolith that
owns the entire view tree, every flow handler, all runtime-status parsing, and
the polling loop; the dedicated `src/pages/` split exists (one file, `CreatePage`)
but the precedent was never followed for the other six views. The recurring
pattern across this host is *truth re-derived locally*: a 2-second poll where a
status subscription already fires, a per-host `HomePeerPermissionState` model
that re-normalizes the shared wire shape inline, and a hand-maintained test
dispatcher that has already drifted out of sync with the real command surface.
Tests are happy-path-only — no core journey has an adversarial case, and the one
secret-lifecycle behavior the code is proud of (scrub-on-leave) is asserted
nowhere.

## Findings

### 1. High: `App.tsx` is a 2086-line monolith holding every view, flow, parser, and the poll loop

Rule: `ARC-01` (architecture & boundaries)

Files:
- `igloo-home/src/App.tsx:1-2086`
- `igloo-home/src/pages/CreatePage.tsx:1-201` (the one extracted seam)

Why this matters:
- One file owns at least six distinct reasons to change: (a) the seven-view
  router state machine (`ViewKey`, `activeView`, `App.tsx:108-115`), (b) ~20
  async flow handlers (`handleGenerate`, `handleSaveGeneratedProfile`,
  `handleConnectOnboardingPackage`, `handleRotateKey`, … `App.tsx:902-1403`),
  (c) all runtime-status parsing (`extractRuntimePeers`,
  `extractPeerPermissionStates`, `extractPendingOperations`,
  `extractPendingApprovals`, `App.tsx:341-452`), (d) the Tauri event wiring and
  the 2 s poll (`App.tsx:789-900`), (e) ~30 `useState` slices including
  secret-bearing drafts (`App.tsx:516-614`), and (f) the entire JSX for every
  view (`App.tsx:1405-2085`).
- Nearly every behavior change to the desktop host routes through this one file,
  so every edit must re-read state-machine + I/O + parsing + view together. The
  safety net is thin: `App.test.tsx` (292 LOC) renders the landing/dashboard
  shell and exercises peer-refresh, but none of the create/onboard/rotate flow
  handlers are unit-covered.

Smells:
- Same anti-pattern called out for `igloo-pwa/src/lib/store.tsx` and the rule's
  own hotspot list — a "monolith per host."
- A page-split precedent (`src/pages/CreatePage.tsx`) exists and is used for
  exactly one of seven views; the structure to fix this is already in the repo,
  unused.

Streamline:
- Lift each view's JSX + its handlers into `src/pages/` siblings of `CreatePage`
  along the natural seams: `LoadProfilePage`, `RecoverKeyPage`,
  `OnboardConnectPage` + `OnboardSavePage`, `DashboardPage`. Payoff is high (most
  changes route through one of these), risk is moderate (handlers close over
  shared `run()`/`refresh*` state), so pull the runtime-status `extract*`
  functions into `lib/runtime-status.ts` (the existing boundary module) first as
  a low-risk, independently-testable seam, then move the views.

### 2. High: test dispatcher re-declares the command surface and has already drifted from it

Rule: `ARC-06` (cross-repo / contract drift)

Files:
- `igloo-home/src-tauri/src/app/test_dispatch.rs:23-331` (dispatcher + `EXPECTED_DISPATCH_COMMANDS`)
- `igloo-home/src-tauri/src/app/commands.rs:393-668` (the real `#[tauri::command]` surface)
- `igloo-home/src-tauri/src/app/bootstrap.rs:79-` (`generate_handler!` registration)

Why this matters:
- The real `invoke_handler` registers 29 commands; the test dispatcher's
  manually-maintained match arms cover only a subset, and the
  `EXPECTED_DISPATCH_COMMANDS` allow-list (24 entries, `test_dispatch.rs:303-331`)
  is **missing 5+ real commands**: `list_relay_profiles`, `resolve_approval`,
  `update_peer_policy`, `resolve_close_request`, and
  `update_profile_operator_settings` (plus `get_settings`/`update_settings`).
- The reconcile already flagged this as a "scope-bypass"; it is also a silent
  contract-drift hole. The dispatcher's self-test (`every_expected_command_is_recognized`,
  `test_dispatch.rs:383`) only checks that the *listed* commands dispatch — it
  cannot catch a real command that was never added to the list. So the peer-policy
  and approval-resolution surface (the security-relevant permission writes) has no
  test-dispatch path at all, and nothing fails when a new command is added but the
  list isn't.

Smells:
- The rule's canonical example: "a test dispatcher that re-declares the real
  command surface." Two independently-maintained copies of one contract.
- A guard test that asserts the list is sorted/unique but never asserts the list
  *equals* the registered handler set — it polices the copy, not the drift.

Streamline:
- Derive the expected-command set from the real registration rather than a hand
  list — e.g. a single `const COMMANDS: &[&str]` that both `generate_handler!`
  (or a test over it) and the dispatcher consume, or a test that asserts every
  `*_command` in `commands.rs` has a dispatch arm. At minimum, add the five
  missing arms so the permission/approval/settings flows are reachable from the
  desktop e2e dispatcher.

### 3. High: 2-second runtime poll re-derives state that the signer status event already pushes

Rule: `ARC-03` (host re-derives signer truth) / `CQ-07` (re-render-prone state)

Files:
- `igloo-home/src/App.tsx:189` (`ACTIVE_RUNTIME_POLL_INTERVAL_MS = 2_000`)
- `igloo-home/src/App.tsx:789-825` (the `setInterval` poll calling `profileRuntimeSnapshot`)
- `igloo-home/src/App.tsx:850-864` (`EVENT_SIGNER_STATUS` / `EVENT_SIGNER_LOG` / `EVENT_SIGNER_LIFECYCLE` already refresh the snapshot)

Why this matters:
- The Rust shell already emits `signer://status`, `signer://log`, and
  `signer://lifecycle` events, and the frontend already subscribes to all three
  and calls `refreshRuntime` on each (`App.tsx:855-863`). The separate 2 s
  `setInterval` polls the same `profile_runtime_snapshot` command on a fixed
  cadence regardless of whether anything changed — a host-side heuristic standing
  in for the subscription it already has.
- Each poll re-fetches the full snapshot and re-runs every `extract*` +
  `useMemo` derivation (`App.tsx:627-651`), so the dashboard does wasteful work
  every 2 s while a session is active, and the freshest path (event) and the
  polled path can race on `setRuntimeSnapshot`.

Smells:
- "Polling on intervals where a subscription/signer API exists" — the exact ARC-03
  signal. A magic `2_000` cadence with no comment on why a poll is needed *in
  addition to* the events.

Streamline:
- If the events are authoritative, drop the interval and rely on the
  status/lifecycle subscription (optionally a single low-frequency keepalive for
  liveness). If the poll is compensating for a missing "operation progressed"
  event (pending-operation timers tick without a status change), say so in a
  comment and scope the poll to only the views that show live timers — don't poll
  the whole snapshot from the root.

### 4. Medium: `HomePeerPermissionState` is a parallel per-host re-model of the shared wire shape, normalized inline in App.tsx

Rule: `ARC-05` (duplicated logic across hosts) / `TST-05` (hand-maintained normalizer drift)

Files:
- `igloo-home/src/lib/dashboard-view.ts:18-41` (`HomePeerPermissionState`, `HomePendingOperation`)
- `igloo-home/src/App.tsx:341-440` (`extractPeerPermissionStates` / `extractPendingOperations` re-mapping `RuntimePeerPermissionState`)
- `igloo-pwa/src/lib/types.ts:54-66` + `igloo-pwa/src/lib/local-adapter/common.ts:124-207` (`PwaPeerPermissionState`, `toPwaPeerPermissionState`)

Why this matters:
- `igloo-shared` already exports `RuntimePeerPermissionState` /
  `RuntimePendingOperation` as the canonical wire shapes (imported at
  `App.tsx:5-10`). igloo-home re-declares its own `HomePeerPermissionState` and
  re-normalizes the wire value field-by-field with `?? 'unset'` and `Boolean(...)`
  coercion across ~60 inline lines (`App.tsx:346-403`); igloo-pwa independently
  maintains `PwaPeerPermissionState` + `toPwaPeerPermissionState` for the same
  shape. Two hosts, two hand-maintained normalizers of one contract.
- The dashboard-view comment (`dashboard-view.ts:18-20`) openly states these are
  "narrow copies" kept per-host. A field added to the shared policy shape must be
  threaded through both normalizers by hand, and either can silently fall behind —
  exactly the mock-drift TST-05 warns about, but in production parsing rather than
  a mock.

Smells:
- "Parallel data models … name BOTH sites" — `HomePeerPermissionState`
  (this repo) vs `PwaPeerPermissionState` (igloo-pwa) for one
  `RuntimePeerPermissionState`.
- Inline defaulting (`?? 'unset'`, `Boolean(...)`) duplicated for request and
  respond directions across four methods — one rule expressed eight times.

Streamline:
- Promote one normalizer (`runtimeStatus → row models`) into `igloo-shared` or
  `igloo-ui` and have both hosts consume it; if the host shapes must stay
  distinct, at least move home's `extract*` mappers out of `App.tsx` into a
  tested `lib/` module so the coercion is asserted once.

Cross-repo note: igloo-home `HomePeerPermissionState` and igloo-pwa
`PwaPeerPermissionState` are parallel re-models of `igloo-shared`'s
`RuntimePeerPermissionState`; consolidate the normalizer. (Mirrored into NOTES.)

### 5. Medium: recovered group `nsec` lives as a bare JS string in React state and renders in plaintext, with no test for the scrub-on-leave it relies on

Rule: `SEC-01` (secret material lifecycle) / `TST-02` (happy-path-only)

Files:
- `igloo-home/src/App.tsx:598-600` (`recoveredKey` state), `App.tsx:1171-1184` (`handleRecoverGroupKey` sets it), `App.tsx:1719-1740` (renders `recoveredKey.nsec` / `signing_key_hex`)
- `igloo-home/src/App.tsx:742-748` (the scrub-on-leave effect)
- `igloo-home/src-tauri/src/models.rs:213-229` (`RecoveredGroupKey` — Rust side correctly `ZeroizeOnDrop` + `Debug`-redacted)
- `igloo-home/test/frontend/RecoverKey.test.tsx:122-145` (asserts the key renders; never asserts it is cleared)

Why this matters:
- The Rust side scrubs its heap copy of the reconstructed nsec on drop, but once
  it crosses the IPC boundary the frontend holds it as a plain `string` in the
  `recoveredKey` state and the landing/recover passphrases as bare strings
  (`landingPassphrases`, `passphrase`, the onboard/save/load drafts). There is no
  JS-side `Secret<T>`/`SecretBytes` analog, so the group secret key sits in the
  React fiber and any captured closure until GC.
- The host's only defense is the scrub-on-leave effect (`App.tsx:742-748`) that
  clears `recoveredKey` when `activeView !== 'recover-key'`. That behavior is
  load-bearing for secret hygiene and is asserted by **no test** — the RecoverKey
  test asserts the nsec *appears* and stops there. A refactor that reorders the
  effect deps or an early-return could silently leave the nsec resident and
  nothing would go red.

Smells:
- The reconcile's "frontend passphrases still bare strings (no Secret<T> analog)"
  — confirmed, and extended to the recovered nsec itself.
- Golden-path-only coverage of a security-relevant flow: the one test renders the
  secret and never exercises the clear.

Streamline:
- Add a test that navigates away from `recover-key` (and from `create`, which has
  the twin scrub at `App.tsx:753-760`) and asserts the secret-bearing state is
  emptied. Longer-term, thread a minimal JS secret-holder (clear-on-read /
  explicit `.dispose()`) for the recovered nsec and chosen passphrases so the
  scrub is a property of the type, not of one `useEffect`.

### 6. Medium: signer-session mutex is unwrapped on a request-reachable path — a poisoned lock panics the backend

Rule: `CQ-02` (panic / unwrap discipline)

Files:
- `igloo-home/src-tauri/src/session/controller.rs:33` (`state.signer.lock().unwrap()` inside `start_profile_session`, an IPC command path)
- `igloo-home/src-tauri/src/app/commands.rs:233,262,374` (`refresh_runtime_peers`, `active_bridge`, `resolve_session_log_runtime_dir`)
- 25 total `.lock().unwrap()` across `src-tauri/src` (profiles.rs ×6, session/controller.rs ×6, paths.rs ×3, …)

Why this matters:
- `start_profile_session`, `refresh_runtime_peers`, `resolve_approval`,
  `update_peer_policy`, and others all reach a `state.signer.lock().unwrap()`.
  If any thread holding that mutex panics while the lock is held, the mutex is
  poisoned and every subsequent `.unwrap()` panics — turning one transient fault
  into a hard backend crash for the whole desktop session, on paths driven
  directly by operator IPC calls.
- The rule names this exact case ("a poisoned mutex crashing the backend"). The
  shell holds genuine signer state behind these locks, so a panic here is not an
  impossible-state assertion — it is a recoverable condition being treated as
  fatal.

Smells:
- 25 `.lock().unwrap()` with no `PoisonError` recovery and no comment justifying
  the panic as an invariant.

Streamline:
- Funnel signer-state access through one helper that maps `PoisonError` to a
  typed `HomeError` (e.g. `Runtime { message }`) — or recovers the guard via
  `into_inner()` where the protected state is still consistent — so a poisoned
  lock surfaces as an error the frontend already knows how to render, not a crash.

### 7. Medium: core journeys covered only on the happy path — no wrong-passphrase, corrupted-package, or unlock/onboard/rotate adversarial test

Rule: `TST-02` (happy-path-only) / `TST-01` (core journey coverage)

Files:
- `igloo-home/test/frontend/App.test.tsx:162-291`, `CreatePage.test.tsx:1-38`, `RecoverKey.test.tsx:114-146`, `api.test.ts:9-95`, `home-error-surface.test.ts:17-80`

Why this matters:
- Of the six core journeys (create, unlock, rotate, import/load, onboard,
  replace/recover), the frontend tests exercise create/rotate-mode toggle,
  recover (happy), peer-refresh, and landing render. **Unlock (start session),
  onboard finalize, and rotate-apply have no end-to-end frontend test**, and
  *every* existing test asserts success only.
- The security-relevant failure modes are untested at the host layer: a
  wrong-passphrase `invalid_passphrase` rejection, a corrupted/garbage `bfprofile`
  or `bfonboard` package, a mismatched package-password confirmation
  (`App.tsx:1046`, `App.tsx:1118` throw paths). `home-error-surface.test.ts`
  proves the *mapper* renders each `HomeError` kind, but no test proves a real
  rejected `invoke` actually surfaces that message to the operator through
  `run()`/`rethrowHomeError`.

Smells:
- "Tests that only assert success; no cases for wrong passphrase, corrupted
  ciphertext, hostile envelopes" — the TST-02 checklist, unticked.

Streamline:
- Add adversarial frontend cases: mock `startProfileSession` /
  `importProfileFromBfprofile` to reject with each `HomeErrorPayload` kind and
  assert the user-facing banner; assert the confirm-password-mismatch and
  empty-passphrase guards in the onboard/save and load flows. These pin the
  failure paths a signing host lives by, at the cheap unit layer.

### 8. Low: `[Unreleased]` changelog accumulates shipped work while the package stays at 0.2.0

Rule: `DOC-06` (changelog / version hygiene)

Files:
- `igloo-home/CHANGELOG.md:7-16` (`[Unreleased]` carries Changed/Fixed entries)
- `igloo-home/package.json` + `igloo-home/src-tauri/tauri.conf.json` (both pinned `0.2.0`, last dated release `2026-03-27`)

Why this matters:
- The shell, landing, onboarding, and dashboard rework described under
  `[Unreleased]` has clearly shipped (it is the current behavior audited above),
  but neither the npm version nor the Tauri app version has moved since
  2026-03-27. A consumer can't tell from the version what desktop build they have.

Smells:
- The cross-cutting "perpetual `[Unreleased]` block + version stagnation" the
  reconcile flagged across all five hosts; present here too.

Streamline:
- Cut the `[Unreleased]` block to a dated, version-bumped section as part of the
  next coordinated release, and align `package.json` + `tauri.conf.json` versions.

Cross-repo note: changelog/version stagnation is shared by all five hosts;
handle once in the release process. (Mirrored into NOTES.)

### 9. Low: `formatError` / `splitTextarea` / `downloadText` re-implemented locally instead of shared

Rule: `CQ-04` (duplicated logic)

Files:
- `igloo-home/src/App.tsx:257-259` (`formatError`), `App.tsx:191-196` (`splitTextarea`), `App.tsx:198-208` (`downloadText`)
- `igloo-chrome/src/components/options/SettingsPanel.tsx:75,134,158,175` + `igloo-pwa/src/lib/file-save.ts` (parallel `err instanceof Error ? … : String(err)` and `downloadText`)

Why this matters:
- The `err instanceof Error ? err.message : String(err)` idiom is inlined ~10
  times across home/chrome/pwa; `downloadText` exists as a named helper in three
  repos (`igloo-home/App.tsx`, `igloo-chrome SettingsPanel`,
  `igloo-pwa/lib/file-save.ts`) with the same Blob→anchor→revoke body. Low
  individual risk, but it is the same trivial behavior maintained in N places.

Smells:
- Copy-pasted small utilities that have an obvious shared home (`igloo-shared`).

Streamline:
- Batch these into a shared util in `igloo-shared` (error-message coercion,
  text download) and import; not urgent, safe to fold into the next shared-util
  pass.

Cross-repo note: `downloadText` + the error-coercion idiom are duplicated in
igloo-home, igloo-chrome, and igloo-pwa; one shared util. (Mirrored into NOTES.)

### 10. Low: `activeProfileId` derived twice and several flow handlers run 60+ lines of setup+work inline

Rule: `RS-02` (over-long functions) / `CQ-04`

Files:
- `igloo-home/src/App.tsx:625` and `App.tsx:793` (`activeProfileId` recomputed inline in an effect instead of reusing the memo above)
- `igloo-home/src/App.tsx:902-961` (`handleGenerate`, ~60 lines), `App.tsx:1003-1091` (`handleDistributeGeneratedShare`, ~90 lines mixing 7 action branches)

Why this matters:
- `handleDistributeGeneratedShare` is a single ~90-line function dispatching on
  seven string actions (`mark`/`revert`/`cancel`/`prepare`/`copy`/`qr`/`save`)
  with secret-package construction inlined in the middle — you must hold all
  seven branches and the package-build to read any one.
- The `activeProfileId` value is computed once as a top-level expression
  (`App.tsx:625`) and then recomputed identically inside the poll effect
  (`App.tsx:793`); minor, but it is the same derivation expressed twice.

Smells:
- Functions past ~60 lines doing setup + work + branching inline with no
  extraction; one derivation written twice.

Streamline:
- Split `handleDistributeGeneratedShare` into a small action-router plus
  per-action helpers (the `prepare` package-build is the part worth isolating and
  testing). Reuse the existing `activeProfileId` memo inside the effect rather
  than recomputing.

## Summary

| Severity | Count |
|---|---|
| High | 3 |
| Medium | 4 |
| Low | 3 |
| **Total** | **10** |
