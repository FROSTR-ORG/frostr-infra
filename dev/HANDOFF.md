# Hand-off: MED+ backlog program — Phases 1–6 substantially complete

_Last updated: 2026-06-13_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The **approved multi-phase plan** — "Remediate audit findings +
> complete medium-or-higher backlog (hard-cut)" — is **substantially complete
> across all six phases.** What remains in `BACKLOG.md` is out-of-scope L-effort
> feature builds, a few deliberately-deferred cleanups (onboard→signer seam;
> chrome e2e page-objects; dashboard error/empty screens), and CI/Linux-gated test
> items. See the per-phase sections below for what landed and what was deferred.
>
> NOTE: the plan was never written to disk (`plans/enchanted-leaping-papert.md`
> does not exist — the only git reference is the commit that mentions it). This
> hand-off's phase breakdown below is the sole surviving record of the plan.

## The plan (what we're executing)

Complete every **medium-importance-or-above** backlog item as a hard-cut program
(no compat shims). Three product calls were settled up front:
- **Scope:** remediation + MED+ fixes only. The big L-effort *feature builds*
  (interactive signing-approval queue, peer telemetry, dashboard router) are
  **out of scope** — they stay in `BACKLOG.md`.
- **Lost-device recovery:** **add** a no-passphrase full-threshold reconstruction
  path (Phase 4), on top of the meter-gating fix.
- **Default peer permissions:** **keep permissive**, document the decision
  (Phase 3) — no behavior change.

Full phase breakdown + critical-file anchors live in the plan file.

## ✅ Phase 1 — COMPLETE (correctness / data-loss)

All landed submodule-commit-then-parent-pointer-bump:
- **1.1 onboard data-loss** — `persistProfileToDashboard` flushSync-commits +
  persists synchronously; a just-onboarded device survives an immediate reload
  (was lost in the 250/500 ms debounce). igloo-pwa `0bd1132` → parent `93d87fa`.
- **1.3 typed inbound failures** — inbound sign/ecdh/onboard failures report their
  true op type (not `ping`) + 3 clippy nits. bifrost-rs `2a3e702` → `6c0a55e`.
- **1.2 resilient restore** — bridge re-bootstraps from packages when a snapshot
  fails WASM restore. igloo-shared `ad12f67`. Plus **browser WASM refresh**
  `a3953cc` (blobs were stale at package v1 w/ removed backup API). Parent
  `ca9bc5a`.
- **Backlog audit + cleanup** (50 → 42) and dead relay-backup test removal
  `12162cb`; H4 verified resolved (typecheck + build).

Per-repo checks were green at commit time (igloo-pwa 43/43, bifrost-rs full
suite + clippy/fmt, igloo-shared 142/142 + WASM exports, both apps typecheck).
Phase-1 holistic gate **done**: `make test-demo` green over the refreshed WASM
(chrome demo-harness signs end-to-end; the chrome↔home pairing spec stays a
deliberate Linux-only skip).

## ✅ Phase 2 — COMPLETE (nostr-tools single instance)

Collapsed `nostr-tools` to one instance per app and aligned all repos to 2.23.5,
fixing the split module-level singletons (`useWebSocketImplementation` /
`SimplePool`) caused by the no-hoist + `preserveSymlinks` layout. Landed
submodule-then-pointer:
- **igloo-shared `345e4ac`** — `nostr-tools` `dependency` → `peerDependency`
  (+ devDep for its own vitest), floor `^2.23.3`.
- **igloo-pwa `8d875fd`** — `resolve.dedupe` adds `nostr-tools` (shared by app
  build + vitest via `vite.resolve.ts`); align `^2.23.3`. pwa is the real 2-copy
  case (it imports `nostr-tools/nip49`/`nip19` directly *and* via igloo-shared).
- **igloo-chrome `d97ef04`** — esbuild has no `dedupe`, so an `onResolve` plugin
  re-runs esbuild's resolver anchored at the package root (defers to
  `build.resolve`, preserving browser export conditions); vitest `dedupe` mirror;
  align 2.17.2 → `^2.23.3`. Chrome had no *direct* import (all nostr-tools usage
  is transitive via igloo-shared), so its real fix was the version align; the
  plugin makes chrome's declared dep authoritative + forward-proofs.
- Parent pointer bump **`b7e4a75`**.

Validation: unit + typecheck green (shared 142/142, pwa 43/43, chrome 95/95),
app builds clean, a chrome esbuild **metafile probe** confirmed single-copy
resolution, cross-app `make test-fast` green (pwa 20, chrome 17). Follow-up
logged: pre-existing high-sev **esbuild** advisory (dev-tooling, not runtime) in
`BACKLOG.md`.

## ✅ Phase 3 — COMPLETE (security / hardening)

All landed submodule-commit-then-parent-pointer-bump:
- **Socket-path fallback tests** — extracted pure cores from
  `bifrost-app::native_runtime` (`select_secure_runtime_dir`,
  `relocate_over_budget`, `socket_file_name`) so the env/FS-dependent policy is
  deterministically testable; +13 tests incl. an explicit never-`/tmp` assertion.
  bifrost-rs `3d8ea23`.
- **igloo-home clippy backlog cleared** — default `clippy --all-targets` now
  warning-free (~22 → 0): auto-fixes + `path_scope` `from_ref`/read-the-`roots`
  field; **decision on the dead-code chain** — gate `test_api`/`test_dispatch`/
  `EVENT_APP_TEST_NAVIGATE` behind `#[cfg(feature = "test-server")]` (matching
  `test_mode`); `#[allow(dead_code)]` on the 3 contract-only `HomeError` variants
  (stable IPC union, exercised by tests). Clean with AND without the feature.
  igloo-home `747f282`.
- **Recover-key in-transit exposure documented** — home returns the plaintext
  nsec (crosses IPC/webview), unlike the shell's `0o600` file write; added a
  threat-model note + a persistent in-UI "handle with care" banner. A save-to-file
  affordance is a logged follow-up (convenience, not hardening). igloo-home
  `c248d99`.
- **Permissive default peer permissions documented** (no behavior change) — the
  settled product call. Comment on the canonical `MethodPolicy::default()`
  (bifrost-rs `32c620a`), a new "Default Peer Permissions" note in
  `docs/PROTOCOL.md`, and pointer comments at the pwa (`7d9bfe2`) + chrome
  (`ba8c6e9`) mirror sites. Also clarified chrome's all-false `DEFAULT_METHOD_POLICY`
  is a fail-closed normalization fallback, NOT the product default.
- **Chrome multi-context hardening — reviewed, found robust** — the background SW
  recovery path is well-guarded (two-layer single-flight; status/session reads
  await the in-flight bootstrap rather than report stale `cold`). Locked the two
  load-bearing invariants in regression tests rather than change behavior.
  igloo-chrome `016c951`.

Validation: bifrost-app 46 tests; igloo-home clippy clean + tests green both
feature configs (45+4 / 53+4) + frontend typecheck/unit (24); chrome tsc + unit
suite green (97). Follow-up: optional home save-to-file affordance (`BACKLOG.md`).

## ✅ Phase 4 — COMPLETE except the deferred seam (recovery / onboarding UX)

Landed (submodule-then-pointer):
- **Recover meter gate** — the "Share #1 (this device) — Validated" state now
  counts toward the threshold only after the device passphrase actually unlocks
  the share. Added `verifyDeviceShareUnlock()` (unlock probe), a store
  `verifyRecoverDeviceUnlock()` + in-memory `recoverDeviceUnlockVerified` flag
  (resets on passphrase change), unlock-on-blur in the panel + a validated badge.
- **Lost-device recovery path** (the plan's settled new capability) — a
  no-passphrase route: `recoverNsecFromShares` takes the device artifact/passphrase
  optionally; in lost-device mode the store omits them and the key reconstructs
  from a full threshold of pasted bfshares (the existing `recoverSecretKeyFromShares`
  threshold check gates sufficiency). Panel gains an optional lost-device toggle.
- **Rotate device-share auto-include** — mirror of the recover auto-include in the
  rotate flow: `createRotatedKeyset` takes the device artifact/passphrase optionally
  and unshifts the decoded device share; the store adds `rotateDevicePassphrase` +
  `rotateDeviceUnlockVerified` (+ `verifyRotateDeviceUnlock`); `RotateKeysetPanel`
  gains an optional device-share card. Operator pastes only the *other* members'.
- igloo-ui `cbd7f22` / igloo-pwa `f7edf25` (rotate), on top of igloo-ui `affc786`
  / igloo-pwa `0a0b674` (recover). All new igloo-ui props optional → igloo-home
  unchanged. Validation: igloo-ui 120, pwa unit 46 (lost-device + meter-gate +
  rotate regression tests), tsc + app builds clean, cross-app `make test-fast`
  green (pwa 20, chrome 17; recover-visual ran).

**Remaining in Phase 4 — deferred by product call (2026-06-13):**
- **Onboard→signer seam refactor** (M) — make the onboard runtime *be* the durable
  signer instead of capture-snapshot-then-relaunch. **Deliberately deferred**:
  correctness is already preserved by the 2026-06-11 snapshot-restore fix, so this
  is cleanup with real destabilization risk to the critical onboarding flow (the
  live onboard node exists *before* the profile is finalized/saved, so collapsing
  the seam means restructuring the connect→preview→name→finalize→start ordering).
  Tracked in `BACKLOG.md`; take it as a dedicated, carefully-reviewed pass.

## ✅ Phase 5 — COMPLETE except deferred items (capability/UX gaps + chrome parity)

Landed (submodule-then-pointer):
- **Diagnostics card → Event Log** — renamed the `OperatorSignerPanel` third card
  (title + empty-state + tooltip) to match Paper; internal `diagnostics` API names
  unchanged. Covers pwa + chrome. igloo-ui `23de9fa`.
- **PasswordField in chrome onboarding** — the four import/onboard password inputs
  now use the reveal-toggle field; placeholders preserved (e2e locators intact).
  igloo-chrome `7661a78`.
- **Quarantine-copy cap** — `quarantineCorruptState` keeps only the newest 3
  `.corrupt.<ts>` copies. igloo-pwa `b5109bc`.
- **Clear Credentials** (delete-device) — destructive `clearDeviceCredentials()`
  store action (stop signer, tear down sessions, erase the partition, reset to
  landing) behind a danger `ConfirmDialog`; new `settingsClearCredentials` test id.
  igloo-ui `6afc563`, igloo-pwa `0b88270`.
- **Chrome Settings `sections` + `ExportPackageModal`** — migrated chrome's
  SettingsPanel off the flat `maintenanceActions` row + inline export-password card
  onto the igloo-ui `sections` API (Export Profile / Export Share / Logout) + the
  shared `ExportPackageModal` (reveal-toggle password → copy/download), matching the
  PWA. Also deduped react/react-dom in chrome's vitest so hook-using igloo-ui dist
  components work under test. igloo-chrome `38ed962` (+ e2e label updates).
- Validation: igloo-ui 120, pwa unit 48, chrome unit 97, tsc + app builds clean,
  cross-app `make test-fast` green (pwa 20, chrome 17).

**Remaining in Phase 5 — deferred by product call (2026-06-13):**
- **Chrome e2e page-object conversion** (M) — most chrome specs still inline
  locators; convert to the page-object model. Mechanical, low user-facing value;
  deferred. Tracked in `BACKLOG.md`.
- **Dashboard error/empty states** (L) — a 5-screen UI build (loading, load-failed,
  all-relays-offline, signing-blocked, signing-failed). Brushes the plan's
  "big L-effort feature builds out of scope" boundary; deferred. Tracked in `BACKLOG.md`.

## ✅ Phase 6 — high-value items done; CI/Linux-gated remainder deferred (test/CI)

Landed (all parent-repo — no submodule pointer changes this phase):
- **Stale browser-WASM guard** — `test/scripts/check-browser-wasm-stamp.sh` stamps a
  deterministic git-tree hash of just the WASM-relevant bifrost-rs crates (native-only
  crates excluded → no needless rebuilds; content-based → no rebuild-nondeterminism
  false positives) into `test/browser-wasm-source.stamp`; wired into `test:guards:wasm`,
  and `make browser-wasm-refresh` now rebuilds **and** re-stamps. Prevents a recurrence
  of the Phase-1 silent WASM drift. Parent `15a14d1`.
- **Flaky export e2e fix** — `exportProfileWithPassword` now waits for the confirm value
  to land + the Export button to enable before clicking (the ExportPackageModal
  controlled-input race). Parent `626a696`.
- **fast ≠ behavioral documented** — flagged the render-only `make test-fast` gate in
  AGENTS + test/README so a green fast run isn't mistaken for behavioral coverage.
  Parent `d659fe6`.
- Validation: guard self-validated (write / pass / fail-on-drift / recover); pwa test
  typecheck + doc guards green (18 guards).

**Deferred (CI/Linux-gated or low-value — tracked in `BACKLOG.md`):**
- recover-key desktop smoke + macOS visual/desktop graceful degradation (Linux desktop
  lane / ImageMagick); `pwa-home-pairing` gate-or-retire (xvfb); verify chrome `@demo`
  on colima; automate multi-PWA-tab signature (M feature); resilient-restore behavioral
  test (re-scoped to the integration/demo lane — needs real WASM+relay); minor warning
  cleanups (jsdom `--localstorage-file`, NO_COLOR).

---

**Program status:** the MED+ remediation program (Phases 1–6) is **substantially
complete**. Everything still open in `BACKLOG.md` is either an explicitly out-of-scope
L-effort feature build (signing-approval queue, peer telemetry, dashboard router,
dashboard error/empty screens), a deliberately-deferred cleanup (onboard→signer seam,
chrome e2e page-objects), or a CI/Linux-gated test item that can't run on macOS dev.

## Working notes (the WHY)

- **Who / how:** maintainer **cmdruid** — moves fast, **no new PRs**; commit
  inside the submodule first, then bump the pointer in the parent; proper fixes
  over patches; capture follow-ups in `BACKLOG.md`.
- **WASM on macOS:** Apple `clang` can't target `wasm32`. Build browser WASM with
  Homebrew LLVM: `CC_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/clang
  AR_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/llvm-ar
  PATH=/opt/homebrew/opt/llvm/bin:$PATH npm --prefix repos/igloo-shared run
  build:browser-wasm`. The committed blobs had drifted from the Rust source —
  a stale-WASM CI guard is now a `BACKLOG.md` item.
- **Obsolete context warning:** relay-backup is **gone**; recurring leftovers keep
  surfacing (dead specs, WASM export allowlist). Do not reintroduce kind-10000 /
  `publish_profile_backup` / `bfshare`-from-relay recovery.
- **Resilient restore is fallback-centric:** correctness comes from re-bootstrap-
  on-restore-failure; the version tag is only a deferred fast-path optimization
  (see `BACKLOG.md`), not required.
- **Pre-existing:** `dev/PAPER-SECURITY-RECONCILE.md` shows as ` D` in parent git
  status — predates this work; leave it untouched.
