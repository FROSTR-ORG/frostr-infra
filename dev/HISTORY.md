# History

Completed-work log for the `frostr-infra` workspace, newest first. Open work
lives in [`BACKLOG.md`](./BACKLOG.md); full plan docs live in [`done/`](./done)
and [`plans/`](./plans).

Each curated entry is `## YYYY-MM-DD — <title>` with a one-paragraph summary and
links to commits/plans. Below the curated entries is the verbatim archive of the
former root `FOLLOWUPS.md` (migrated 2026-06-10), kept for history; its open
items were triaged into [`BACKLOG.md`](./BACKLOG.md).

## 2026-06-13 — Phase 6: test/CI hardening (high-value items; remainder CI-gated)

Landed the high-value, locally-validatable Phase-6 items (all parent-repo — no
submodule changes). **Stale browser-WASM guard:** the committed
`igloo-shared/public/wasm` blobs once silently lagged bifrost-rs; added
`check-browser-wasm-stamp.sh`, which stamps a deterministic git-tree hash of just
the WASM-relevant crates (native-only `bifrost-app`/`bridge-tokio`/`devtools`
excluded, so a native-only bump doesn't force a rebuild; content-based, so no
rebuild-nondeterminism false positives) into `test/browser-wasm-source.stamp`,
wired into `test:guards:wasm`, with `make browser-wasm-refresh` now rebuilding AND
re-stamping (parent `15a14d1`). **Flaky export e2e:** `exportProfileWithPassword`
now waits for the confirm value to land + the Export button to enable before
clicking, fixing the ExportPackageModal controlled-input race that timed out under
load (parent `626a696`). **fast ≠ behavioral:** documented that the render-only
`make test-fast` gate can hide a broken demo, in AGENTS + test/README (parent
`d659fe6`). Deferred (CI/Linux-gated or low-value, tracked in `BACKLOG.md`):
recover-key desktop smoke, macOS visual/desktop degradation, `pwa-home-pairing`
gate-or-retire, colima chrome `@demo` verify, multi-PWA-tab automation, and the
resilient-restore behavioral test (re-scoped to the integration/demo lane — it
needs a real WASM runtime + relay the unit harness avoids). This substantially
completes the six-phase MED+ remediation program.

## 2026-06-13 — Phase 5: capability/UX gaps + chrome parity (2 items deferred)

Landed five of the six Phase-5 items. **Diagnostics → Event Log:** renamed the
`OperatorSignerPanel` third card (title, empty-state, tooltip) to match Paper's
name across both consuming apps; internal `diagnostics` API names unchanged
(igloo-ui `23de9fa`). **PasswordField in chrome onboarding:** the four
import/onboard password inputs now use igloo-ui's reveal-toggle field, placeholders
preserved so the e2e onboarding locators are intact (igloo-chrome `7661a78`).
**Quarantine cap:** `quarantineCorruptState` now keeps only the newest three
`.corrupt.<ts>` copies so a repeatedly-corrupted partition can't grow localStorage
unbounded (igloo-pwa `b5109bc`). **Clear Credentials:** a destructive
`clearDeviceCredentials()` store action — stop the signer, tear down every runtime
session, erase the persisted partition, reset to a clean landing — surfaced as a
Settings action behind a danger `ConfirmDialog` (distinct from logout/single-profile
delete; matches Paper's 3b modal); new `settingsClearCredentials` test id (igloo-ui
`6afc563`, igloo-pwa `0b88270`). **Chrome Settings parity:** migrated chrome's
SettingsPanel off the flat `maintenanceActions` row + inline export-password card
onto the igloo-ui `sections` API (Export Profile / Export Share / Logout) + the
shared `ExportPackageModal` (reveal-toggle password → copy/download), matching the
PWA; also deduped react/react-dom in chrome's vitest so hook-using igloo-ui dist
components (e.g. `ExportPackageModal`) work under test, and updated the chrome
dashboard/rotation e2e specs to the new labels (igloo-chrome `38ed962`). Validation:
igloo-ui 120, pwa unit 48, chrome unit 97, tsc + app builds clean, cross-app
`make test-fast` green (pwa 20, chrome 17). **Deferred by product call** and tracked
in `BACKLOG.md`: the chrome e2e page-object conversion (mechanical, low value) and
the L-effort dashboard error/empty-state screens (a 5-screen feature build that
brushes the plan's out-of-scope boundary).

## 2026-06-13 — Phase 4: recovery/onboarding UX (onboard seam deferred)

Completed Phase 4 except the deliberately-deferred onboard→signer seam refactor.
Beyond the recover meter-gate + lost-device path (next entry), **rotate now
auto-includes the device's own share**: `createRotatedKeyset` takes the device
artifact/passphrase optionally and unshifts the decoded device share into the
reconstruction set (mirroring recover), the store adds an in-memory
`rotateDevicePassphrase` + `rotateDeviceUnlockVerified` with a
`verifyRotateDeviceUnlock()` probe, `generateKeyset`'s rotate branch forwards the
source profile's artifact + passphrase (cleared after a successful rotate), and
the shared `RotateKeysetPanel` gains an optional unlock-gated device-share card so
the operator pastes only the other members' bfshares. All new igloo-ui props stay
optional → igloo-home unchanged. igloo-ui `cbd7f22`, igloo-pwa `f7edf25`. The
**onboard→signer seam refactor was deferred by product call** (2026-06-13): the
2026-06-11 snapshot-restore fix already preserves correctness, so collapsing the
capture-then-relaunch seam is cleanup with real destabilization risk to the
critical onboarding flow — it stays in `BACKLOG.md` for a dedicated pass.
Validation: igloo-ui 120, pwa unit 46, tsc + app builds clean, cross-app
`make test-fast` green.

## 2026-06-13 — Phase 4 (part): lost-device recovery + recover meter gate

Landed the first two items of **Phase 4** (recovery/onboarding UX). **Meter gate:**
the recover "Share #1 (this device) — Validated" state previously counted the
device share toward the threshold the moment the passphrase field was touched;
it now counts only after a real unlock. Added `verifyDeviceShareUnlock()` (a
no-recovery unlock probe), a store `verifyRecoverDeviceUnlock()` action + an
in-memory `recoverDeviceUnlockVerified` flag that resets whenever the passphrase
changes, an on-blur verify + a "Validated/Locked" badge in the panel, and
App-side `collectedCount` computed from the verified state instead of an
unconditional +1. **Lost-device path** (the plan's settled new capability): a
no-passphrase reconstruction route — `recoverNsecFromShares` now takes the device
artifact/passphrase optionally, and in lost-device mode the store omits them so
the key reconstructs from a full threshold of pasted bfshares alone (the existing
threshold check in `recoverSecretKeyFromShares` enforces sufficiency); the shared
`RecoverCollectSharesPanel` gains an optional lost-device toggle. All new igloo-ui
props are optional and default to today's behavior, so igloo-home's single-path
usage is untouched. igloo-ui `affc786`, igloo-pwa `0a0b674`, parent pointer bump.
Validation: igloo-ui 120, pwa unit 45 (incl. lost-device + meter-gate regression
tests), tsc + app build clean, cross-app `make test-fast` green (pwa 20, chrome
17; recover-visual ran). Remaining Phase-4 items (rotate device-share
auto-include; onboard→signer seam refactor) are tracked in `BACKLOG.md`/HANDOFF.

## 2026-06-13 — Phase 3: security / hardening

Landed **Phase 3** of the MED+ backlog program. **Socket-path fallback:**
refactored `bifrost-app::native_runtime` to extract pure, env-parameterized cores
(`select_secure_runtime_dir` → `SecureRuntimeDir` enum, `relocate_over_budget`,
`socket_file_name`) from the impure `secure_runtime_dir`/`shorten_unix_socket_path`,
then added 13 deterministic tests covering pass-through, per-profile determinism,
no-secure-dir/unusable-dir fall-through, the XDG → /run/user → HOME precedence, and
an explicit never-`/tmp` assertion (bifrost-rs `3d8ea23`). **igloo-home clippy
backlog:** default `clippy --all-targets` is now warning-free (~22 → 0) — auto-fixes
plus `path_scope` `slice::from_ref` and reading the previously-dead
`OutsideAllowedRoots::roots` into the Display; the dead-code decision gates
`test_api`/`test_dispatch`/`EVENT_APP_TEST_NAVIGATE` behind
`#[cfg(feature = "test-server")]` (matching the gated `test_mode` that consumes
them) and `#[allow(dead_code)]`s the three contract-only `HomeError` variants
(stable IPC union, exercised by tests); clean with and without the feature
(`747f282`). **Recover-key in-transit exposure:** home returns the plaintext nsec
(crosses the Tauri IPC/webview boundary), unlike igloo-shell's `0o600` file write —
documented via a threat-model note on `recover_group_key_from_shares` and a
persistent in-UI "handle with care" banner; a save-to-file affordance is a logged
follow-up (`c248d99`). **Default peer permissions:** documented the settled
permissive product call — a rationale comment on the canonical
`MethodPolicy::default()` (bifrost-rs `32c620a`), a "Default Peer Permissions" note
in `docs/PROTOCOL.md`, pointer comments at the pwa (`7d9bfe2`) and chrome
(`ba8c6e9`) mirror sites, and a clarification that chrome's all-false
`DEFAULT_METHOD_POLICY` is a fail-closed normalization fallback rather than the
product default. **Chrome multi-context hardening:** reviewed the background
service-worker recovery path and found it well-guarded (two-layer single-flight;
both status and session reads await the in-flight bootstrap instead of reporting a
stale `cold`/`not active`) — locked the two load-bearing invariants in regression
tests rather than change behavior (`016c951`). Landed via parent pointer bump +
docs. New follow-up in `BACKLOG.md`: optional home save-to-file affordance.

## 2026-06-13 — Phase 2: nostr-tools single instance + version align

Landed **Phase 2** of the MED+ backlog program. `nostr-tools` carries
module-level singletons (`useWebSocketImplementation`, `SimplePool` relay pools),
but the no-hoist submodule layout + `preserveSymlinks` made igloo-shared (bundled
from source) resolve its own nested copy while each app resolved another — two
instances, split singletons (the WebSocket-impl injection couldn't reach
igloo-shared's `SimplePool`). Fix: declared `nostr-tools` a **peerDependency** of
igloo-shared (+ devDep for its own vitest), aligned all repos to **2.23.5**
(igloo-chrome was the 2.17.2 laggard), and deduped per app — igloo-pwa via Vite
`resolve.dedupe` (the genuine 2-copy case: it imports `nostr-tools/nip49`/`nip19`
directly *and* through igloo-shared), igloo-chrome via an esbuild `onResolve`
plugin that re-runs the resolver anchored at the package root (deferring to
`build.resolve` to preserve browser export conditions) plus a vitest `dedupe`
mirror. Chrome had no direct import, so its real fix was the version align; the
plugin makes its declared dep authoritative. igloo-shared `345e4ac`, igloo-pwa
`8d875fd`, igloo-chrome `d97ef04`, parent `b7e4a75`. Validation: unit + typecheck
green (shared 142/142, pwa 43/43, chrome 95/95), clean app builds, a chrome
esbuild metafile probe confirmed single-copy resolution, cross-app `make
test-fast` green (pwa 20, chrome 17). New follow-up in `BACKLOG.md`: pre-existing
high-sev esbuild advisory (dev-tooling only).

## 2026-06-13 — Phase 1 correctness/data-loss fixes + backlog audit

Backlog audit (50 → 42): pruned stale relay-backup-removal residue — two
obsolete items, a dead chrome `backup-live` spec + `publishBackup` fixture, and
the `check-bridge-wasm-exports` allowlist (still requiring the deleted
`profile_backup_*` exports + `bf_package_version 1`). Then landed all of
**Phase 1** of `plans/enchanted-leaping-papert.md`. **1.1 — onboard data-loss:**
`persistProfileToDashboard` now `flushSync`-commits and writes synchronously, so
a just-onboarded/created device survives an immediate reload (was lost inside the
250/500 ms debounce); igloo-pwa `0bd1132`, parent `93d87fa`. **1.3 — typed
inbound failures:** `process_event` records inbound sign/ecdh/onboard failures
under their true op type instead of letting the router blind-label them `ping`,
plus three same-area clippy fixes; bifrost-rs `2a3e702`, parent `6c0a55e`.
**1.2 — resilient restore:** the bridge falls back to a clean package bootstrap
when a persisted snapshot fails WASM restore (instead of bricking the session);
`createBrowserRuntimeNodeInit` carries the packages centrally so both browser
hosts are covered with no per-host change; igloo-shared `ad12f67`. Also
**refreshed the browser WASM** (`a3953cc`) — the committed blobs had silently
lagged to package v1 with the removed backup API — bringing browser clients to v2
and carrying the op-type fix; parent `ca9bc5a`. H4 (igloo-home vs igloo-ui skew)
verified resolved via typecheck + build. Remaining Phase-2..6 work and new
follow-ups (snapshot version-tag fast path, restore-fallback behavioral test,
stale-WASM CI guard, remaining router ping-sentinels) are in `BACKLOG.md`.

## 2026-06-13 — Recovery follow-ups (tests, threshold meter, nsec hardening, secure socket path)

Five clean-up tasks on top of the relay-free recovery transition. **Tests:**
igloo-home gained Rust unit coverage for `recover_group_key_from_shares` (happy +
non-member/insufficient/duplicate failures) and `make_rotated_keyset` (happy,
preserves the group public key; non-member source fails), plus a frontend
`RecoverKey.test.tsx`. **Threshold meter:** a passphrase-free `get_profile_threshold`
command (reads the plaintext group package) drives an accurate recover-key meter.
**nsec hardening:** `RecoveredGroupKey` now zeroizes its secret fields on drop +
redacts `Debug` in both hosts, and the home recover-key view clears the key +
inputs on navigation. **SUN_LEN:** the daemon socket-path shortener was consolidated
into a single secure `bifrost-app` helper (`XDG_RUNTIME_DIR` → `/run/user/$UID` →
`0o700 ~/.igloo-shell/run`; never `/tmp`), igloo-shell-core delegates to it, and the
shell test harness pins a short `XDG_RUNTIME_DIR` (proven by 23/23 daemon integration
tests with the env unset). Commits: bifrost-rs `483a74d`, igloo-shell `cf2aedb`,
igloo-home `f0238e6`, parent bump `9d6d12d`. Plan:
`dev/plans/great-suggestions-let-s-draft-kind-canyon.md`. Remaining nits captured in
`BACKLOG.md` (socket-fallback unit test, lane macOS support, home clippy backlog,
meter member-count, nsec file-save parity).

## 2026-06-12 — Relay profile-backup feature removed across the workspace

Completed the relay-published "encrypted profile backup" → local-recovery transition
for the **native hosts** and deleted the now-dead core code (the browser clients +
shared core were done earlier). **igloo-shell** (`f1b6c73`): dropped every
`publish_profile_backup` call + the `profile backup` subcommand; replaced relay
`recover` with a local `recover-key` command (reconstructs the group `nsec` from a
threshold of shares, written `0o600`); rotation sources its group package from the
local profile. **igloo-home** (`12119f8`): removed backup-publish + the bfshare
device-restore; added a `recover_group_key` command + recover-key UI (reusing
igloo-ui `RecoverCollectSharesPanel`); restore = `bfprofile` import; rotation sources
its group from the local profile's plaintext `group_ref`. **bifrost-rs** (`1ad615c`):
deleted `bifrost-profile` `flows/{backup,recovery}.rs`, the `native-relay` feature +
deps, `ProfileBackupPublishResult`; deleted the `frostr-utils` backup helpers,
kind-10000 constants, `EncryptedProfileBackup*`, and the backup-only NIP-44 wrappers
(canonical cipher + KATs remain in `bifrost_core::nip44`). Silences the lingering
"failed to publish encrypted profile backup" warning at its source. Parent bumps
`528be2a`/`67ca114`/`32dbcd7`/`5bc0ec6`. (Was the open BACKLOG item "Remove the relay
profile-backup feature from the native hosts".)

## 2026-06-11 — igloo-pwa `@live` permissions + settings persistence specs (+ override-restore fix)

Closed the two **P1** behavioral-coverage gaps for igloo-pwa: the Permissions
and Settings dashboards previously had only seed-and-screenshot `@visual` specs,
which prove rendering, not behavior. Added `test/igloo-pwa/specs/settings.spec.ts`
(create a keyset → edit signer name/relay/timeout → Save against a live runtime →
reload → assert the form rehydrates from the persisted store) and
`permissions.spec.ts` (onboard against a headless `igloo-shell` co-signer → toggle
a live peer policy → reload → re-boot → assert the manual override persisted). To
drive them through page objects, added stable e2e test-ids on the peer-policy
toggles (`data-peer-pubkey`/`direction`/`method` + `data-allowed`/`data-override`)
and the Settings Device Profile form, plus matching `support/pages.ts` methods.

The permissions spec surfaced a real product bug exactly as this effort intends:
**manual peer-policy overrides persisted on the profile (and inside export
packages) but were never re-applied to the signer runtime on restart** —
`startSession` threaded keys/relays/settings/onboard-snapshot but not
`manual_peer_policy_overrides`, so a reload silently dropped every operator
override. Fixed at the host-adapter layer (`startSession` now re-applies them
after the runtime boots; no `bifrost-rs`/WASM change). The Tier-1
"unlock → running" gap from the original P1 list is already covered by
`profile-inventory.spec.ts` (running dashboard) + `sign-shell.spec.ts`
(`sign_ready` with a cooperating peer), so it was dropped rather than duplicated.
Validated: full igloo-pwa `@live` lane 10/10 green; igloo-ui 120 + igloo-pwa 42
unit tests green; selector/cross-client guards pass. Commits: `igloo-ui 8ee3f38`
(test-ids), `igloo-pwa 7339d53` (override-restore fix), parent `d9c9243` (specs +
pointer bumps).

---

## 2026-06-09 — Paper↔runtime design-sync reconciliation

Re-ran the PWA visual loop after the dashboard/settings/export work landed and
reconciled the tracking: promoted `dashboard-permissions`, `dashboard-settings`,
and `dashboard-export-profile` from `needs-work` → `aligned` in
`test/igloo-pwa/visual-manifest.json` (with notes recording the intentional,
plan-decided deviations), and expanded the `dashboard-signer` note to cover its
structural divergence (it stays `needs-work`, gated on bifrost-rs telemetry —
see [`BACKLOG.md`](./BACKLOG.md)). Repaired the strict design-sync gate by
repointing the `Modal` design-contract entry from the deleted `confirm-modal.tsx`
to `dialog.tsx`. Commits: `igloo-paper 31e343c`, parent `9e0f7a9`. Plan:
[`plans/dashboard-settings-export-paper-redesign-2026-06-01.md`](./plans/dashboard-settings-export-paper-redesign-2026-06-01.md).

---

# Archived follow-up log (migrated from root `FOLLOWUPS.md`, 2026-06-10)

The entries below are the verbatim historical follow-up log. Still-open items
have been triaged into [`BACKLOG.md`](./BACKLOG.md); this section is retained for
provenance and is not actively maintained.

## 2026-06-03 — RESOLVED: Docker follow-up batch (+ igloo-home skew found)

Cleared the loose-ends/issues/adjacent/open-question/future-scope items from the
section below. igloo-shell first (pushed `paper-create-flow-update`: `16d1a99` +
`a6eece3`), then parent.

### Resolved
- [x] ~~Push igloo-shell `16d1a99`~~ — pushed branch `paper-create-flow-update` to
  origin (`16d1a99` + `a6eece3`); parent pointer now resolves.
- [x] ~~`signing_key32: None` stopgap / confirm intent~~ — confirmed `None` is
  correct (the field drives bifrost-rs recovery re-split; igloo-shell has no
  import-from-key CLI). Hardened: call sites use `CreateKeysetConfig::new(...)`
  (`a6eece3`) so future optional-field additions don't churn igloo-shell.
- [x] ~~bifrost-rs↔igloo-shell drift gate~~ — added `make demo-pair-check`
  (`cargo check` both bins) + a CI step before `make test-demo`.
- [x] ~~Trim libssl from the Dockerfile~~ — dropped `pkg-config`/`libssl-dev`
  (builder) + explicit `libssl3` (runtime); both trees confirmed pure rustls.
  (Note: `libssl3` still ships in the `ubuntu:24.04` base — no longer our explicit
  dep, binaries don't link it.)
- [x] ~~Pin `RUST_IMAGE`~~ — `rust:1.95-bookworm` (matches host/CI stable 1.95).
- [x] ~~`make demo-stop` sweep default-project containers~~ — `stop_projects` now
  uses `docker ps -a` and always tears down the default (`frostr-infra`) project.
- [x] ~~Drop redundant host build on `make demo-start`~~ — removed `build_binaries`
  from `start_stack`; demo-start is now Docker-only (images self-build).
- [x] ~~BuildKit cache for CI~~ — `compose.ci.yml` (`type=gha` cache) + CI
  `docker/setup-buildx-action` + `COMPOSE_BAKE=true` + `FROSTR_DEMO_COMPOSE_OVERRIDE`;
  `test-prebuild.sh` threads the override into the demo image build. (Cross-run
  cache efficacy is observable only on a GHA runner.)

### Issues discovered, not fixed
- [ ] **igloo-home is skewed against this branch's igloo-ui** (effort: L) — surfaced
  while running `make test-demo` (chrome lane prebuilds the `home` target).
  igloo-home `eed7b7a` still imports removed igloo-ui exports
  (`OperatorPeerPermissionState`, `OperatorPendingOperation`) and uses the old
  `AppHeaderProps` (`centered`/`subtitle`), `StoredProfileCardModel`, and
  `SharedDistributionResult`/`SharedDistributionAction` shapes from before the Phase B
  igloo-ui changes. **This fails `make test-demo` — a required release-validation
  gate — on the `paper-create-flow-update` branch, independent of the Docker work.**
  Needs igloo-home ported to the current igloo-ui operator/create APIs (Tauri app:
  `src/App.tsx`, `src/pages/CreatePage.tsx`). The chrome `@demo` artifact-dir fix
  itself is verified by proxy (`make test-smoke` uses the identical repo-relative
  bind-mount mechanism and passes).

## 2026-06-03 — after cross-platform Docker demo stack (in-Docker builds)

### Loose ends
- [ ] Push the igloo-shell submodule commit `16d1a99` (branch `paper-create-flow-update`) before/with pushing the parent (effort: S) — parent `bf4679e` bumps the igloo-shell pointer to a local-only commit; until it's pushed, the parent pointer dangles for anyone else (and CI cloning the submodule).
- [ ] Verify the chrome `@demo` lane (`make test-demo`) end-to-end on colima (effort: S) — only `make test-smoke` was run to completion; `demo-harness.ts` got the same repo-relative artifact-dir fix but wasn't executed this session.

### Issues discovered, not fixed
- [ ] igloo-shell `signing_key32: None` is a compat stopgap, not a feature (effort: M, unsure) — `crates/igloo-shell-core/src/shell/rotation.rs:134,538` now hardcode `None`. If bifrost-rs added `signing_key32` to support importing a keyset from a known signing key, igloo-shell's keygen/rotation paths may need to actually thread a real value through rather than always `None`. Confirm with the bifrost-rs change intent.
- [ ] bifrost-rs ↔ igloo-shell submodule pointers drift silently (effort: M) — igloo-shell uses path deps into `../bifrost-rs/crates/*`, so a bifrost-rs API change (like `signing_key32`) breaks igloo-shell with no version gate. Worth a CI check that the pinned submodule pair compiles together, or a documented bump protocol in `dev/docs/RELEASE.md`.

### Adjacent improvements
- [ ] Trim defensive `libssl-dev`/`libssl3` from `services/demo/Dockerfile` (effort: S, unsure) — both bifrost-devtools and igloo-shell-core use rustls (`tokio-tungstenite` `rustls-tls-webpki-roots`); the OpenSSL libs were kept defensively while igloo-shell was uninspected. Now confirmed rustls, so they're likely removable (verify the full igloo-shell dep tree first).
- [ ] Pin `RUST_IMAGE` to an exact stable (e.g. `rust:1.89-bookworm`) instead of floating `rust:1-bookworm` (effort: S) — floating mirrors the repo's `stable` toolchain but makes image builds non-reproducible across time; pin if reproducibility matters, override via the existing ARG.
- [ ] The stale `frostr-infra-dev-relay-1` crash-loop container from the original bug had to be removed by hand this session (effort: S) — consider having `make demo-stop` also sweep the default-project `dev-relay`/`igloo-demo` containers, not just the named demo projects.

### Open questions
- [ ] Should `make demo-start` stop doing the redundant host `build_binaries` now that containers self-build? (effort: M) — carried/sharpened: host binaries are still needed by host `@live` lanes and the smoke's host `igloo-shell`, but a pure `make demo-start` no longer needs them for the containers. Splitting webapp-asset prep from demo-binary prep would make demo-start Docker-only. Needs care around the smoke/`@live` consumers.

### Future scope
- [ ] Add a BuildKit/registry cache for the in-Docker Rust build in CI (effort: M) — CI is ephemeral, so each `release-validation` run now pays a cold compile of bifrost-devtools + igloo-shell inside Docker. A `cache-from`/`cache-to` (GHA cache or registry) or `docker buildx` layer cache would cut that. Local dev already benefits from the cache mounts.

## 2026-06-02 — after the follow-up batch (Event-Log tags/filter, Peers counts, export)

### Loose ends
- [x] ~~No unit test for the `store.clearLogs` → `clearSessionLogs` adapter path~~ — RESOLVED: added `test/frontend/clear-session-logs.test.tsx` covering the active-session clearLogs call + the inactive/no-profile guards.

### Issues discovered, not fixed
- [x] ~~`App.tsx` `lastSeenLabel` skipped the seconds-vs-ms guard~~ — RESOLVED: now formatted via the existing `formatRuntimeTimestamp` helper (same ms-guard + `toLocaleString` as the igloo-ui adapter), fixing both the wrong-time bug and the format inconsistency below.
- [x] ~~`observabilityEventsToEventRows` row id had no index~~ — RESOLVED: id is now prefixed with the array index so same-tick events can't collide on the React key.
- [x] ~~`attachLogBuffer` kept two unbounded buffers~~ — RESOLVED: both `lines` and `events` are capped to the last 500 via `pushCapped`.

### Adjacent improvements
- [x] ~~`refreshSession` diverged from `toRuntimeSnapshot`~~ — RESOLVED: `refreshSession` now builds through `toRuntimeSnapshot` (so `peer_permission_states`/`events` stay in sync) and only annotates the log tail with the refresh marker.
- [x] ~~Peer last-seen formatted two different ways~~ — RESOLVED together with the ms-guard fix (both paths now use `toLocaleString`-style formatting).
- [x] ~~Clear-Log button could render on a stopped session~~ — RESOLVED: `App.tsx` only passes `onClearLogs` while the runtime is active, so the button is hidden when inactive.

### Open questions
- [ ] Filter chips key off `badgeLabel` = domain for structured events but = level (info/warn/error) for the string fallback (effort: S) — the Filter still works for the fallback but filters by level, not domain. Decide whether the fallback should be filterable at all or the chips should hide when events are unstructured.

### Future scope
- [ ] (Carried, unchanged) Per-peer latency / "Avg" latency / nonce sparkline / per-method SIGN·ECDH·PING capability badges — runtime instrumentation in bifrost-rs/igloo-shared; the trigger to promote the `dashboard-signer` manifest entry to `aligned` (documented in its `notes`).

## 2026-06-02 — RESOLVED: Phase B follow-up batch (Event Log structure, Peers counts, export + cleanups)

Cleared the loose-end / issue / adjacent / one open-question items below in a
single pass. igloo-ui first (then dist rebuild), igloo-pwa next, parent pointer.

### Resolved
- [x] ~~Export Download uses an anchor blob with no save confirmation~~ — extracted
  `downloadText`/`saveTextToFile` into `repos/igloo-pwa/src/lib/file-save.ts`;
  `App.tsx` ExportPackageModal `onDownload` now routes through `saveTextToFile`
  (File System Access API confirmed-write + anchor fallback), matching the
  distribution flow. Verified by the export `@live` spec.
- [x] ~~Inline `group_package_json`/`share_package_json` parsing duplicated in
  `App.tsx`~~ — folded into `deriveGroupSummary` + `deriveExportSummary` in
  `src/lib/dashboard-view.ts` (alongside the existing `deriveMemberLabel`/
  `toDashboardKey`), with unit coverage in `test/frontend/dashboard-view.test.tsx`.
- [x] ~~Reconcile Permissions summary pills vs Paper~~ — gated behind a new
  `showPeerSummary` prop on `OperatorPermissionsPanel` (default true for other
  consumers); the PWA passes `showPeerSummary={false}` so the page matches Paper.
- [x] ~~Event Log Clear button was inert in the PWA~~ — wired `onClearLogs` →
  `store.clearLogs()` → `clearSessionLogs` adapter → host-side `session.clearLogs()`.
- [x] **Event Log structured tags + filter** — the host-side log buffer
  (`page-runtime-host.ts`) now retains the raw `ObservabilityEvent` objects it
  already received (no igloo-shared change); threaded `events` through the snapshot/
  types/adapter and rendered via igloo-ui's `observabilityEventsToEventRows`, with a
  domain-tag Filter control in `OperatorSignerPanel`.
- [x] **Peers header counts (UI-only)** — online/total + ready counts and per-row
  last-seen from data the runtime already exposes. Also fixed a latent state-mapping
  bug in `derivePwaPeers` (sign-ready peers were flagged `'warning'`, contradicting
  their `sign-ready` status label and the shared igloo-ui adapter).
- [x] `dashboard-signer` manifest stays `needs-work` with a `notes:` promotion
  trigger documenting the remaining runtime-gated gaps.

### Still future scope (runtime-gated; unchanged)
- [ ] Per-peer latency, "Avg" latency, the nonce sparkline, and per-method
  SIGN/ECDH/PING capability badges (effort: L) — require bifrost-rs/igloo-shared
  runtime instrumentation; the promotion trigger for the dashboard manifest entries.
- [ ] Persisting structured events end-to-end was NOT needed for the log tags — the
  PWA host already receives them; a deeper structured-event *store* (history,
  cross-session) remains future scope if richer Event-Log queries are wanted.

## 2026-06-02 — after Phase B complete (Settings, Export modals, Unsaved-changes guard)

### Loose ends
- [ ] Promote the dashboard family's `needs-work` visual-manifest entries → `aligned` (effort: M) — `dashboard-signer`, `dashboard-permissions`, `dashboard-settings`, `dashboard-export-profile` in `test/igloo-pwa/visual-manifest.json` are all still `needs-work`. They're structurally faithful but gated on the deferred Peers/Event-Log parity (and a deliberate side-by-side review) before honestly flipping to `aligned`.

### Issues discovered, not fixed
- [ ] The export Download uses an anchor-click blob download with no save confirmation (effort: S) — `repos/igloo-pwa/src/App.tsx` ExportPackageModal `onDownload` mirrors the recover flow's optimistic anchor download; unlike `saveTextToFile` in `store.tsx` it doesn't use `showSaveFilePicker`. Consider routing both through the same save helper so "Download" reflects an actual write.
- [ ] Export modal has no busy/disabled treatment on Copy/Download while re-encrypting (effort: S, unsure) — `exportBusy` gates the Export submit but the complete-state actions assume `result` is ready; fine in practice since they only render post-result, but worth confirming no flicker between busy→complete.

### Adjacent improvements
- [ ] Reconcile the Permissions summary pills (Peers / Effective responders) with Paper (effort: S) — carried from step 2; Paper doesn't draw them. Confirm they stay or drop.
- [ ] `deriveExportSummary` + `deriveMemberLabel` + `toDashboardKey` now all parse `group_package_json`/`share_package_json` inline in `App.tsx` (effort: S) — the export summary parse duplicates member/group parsing; could fold into the extracted `src/lib/dashboard-view.ts` for one parsing path + unit coverage.
- [ ] Settings dirty-check compares via `JSON.stringify` of relays/signerSettings (effort: S, unsure) — `settingsDirty` in `App.tsx` relies on key-order-stable stringify; true for these fixed-shape objects, but a structural compare would be more robust if the shapes grow.

### Open questions
- [ ] Should the merged identity/runtime card also top the Permissions + Settings sub-pages? (effort: M) — carried from step 2; Paper shows it on all three, the PWA shows it only on Dashboard. Header nav already gives context; decide the cross-page pattern (and whether to lift the card into a shared page-shell) rather than leave it Dashboard-only.
- [ ] Confirm whether `Export Profile`/`Export Share` should also keep a quick unencrypted copy-to-clipboard alongside the password modal (effort: S) — step 3→4 replaced copy with the modal entirely; some users may want a fast copy. Product call.

### Future scope
- [ ] Dashboard Peers + Event Log full Paper parity (effort: M) — Peers rows (online/ready counts, latency sparkline, per-method badges) + Event Log (type-tagged rows + filter); the trigger to promote the dashboard visual entries to `aligned`.
- [ ] Interactive signing-approval runtime feature behind the Pending Approvals shell (effort: L) — the empty-state card is shipped; real Deny/Allow-once/Always-allow needs runtime hooks in `igloo-shared`/`bifrost-rs`.
- [ ] Deferred dashboard screens: error/empty states (loading, load-failed, all-relays-offline, signing-blocked, signing-failed) + Clear Credentials modal (`3b`) (effort: L) — Clear Credentials needs a new destructive "clear this device's saved profile/share/password/relays" store action.
- [ ] Evaluate a real router for the dashboard pages (effort: L) — header nav still drives `store.activeDashboardTab`; URL deep-linking/back-button is a separate refactor with route-guard considerations.
- [ ] Adopt the new igloo-ui Settings `sections` API + ExportPackageModal in igloo-chrome (effort: M) — chrome still uses the flat `maintenanceActions` row and its own export; aligning it would unify the operator surface, but is out of the PWA-focused Paper pass.

## 2026-06-02 — after Phase B step 2 (Permissions page)

### Open questions
- [ ] Should the merged identity/runtime card also appear at the top of the
  Permissions (and Settings) sub-pages? (effort: M) — Paper's `1c-permissions`
  artboard shows the identity card above the permissions sections, but the PWA
  Permissions page currently renders only the permissions panel (the identity card
  is dashboard-only). The header nav already provides context, so omitting it is
  defensible; decide the cross-page pattern before/with the Settings page so it's
  consistent. If "yes," the merged card likely wants to move into a shared
  page-shell above the tab content rather than be duplicated per panel.

### Adjacent improvements
- [ ] Reconcile the Permissions summary pills (Peers / Effective responders) with
  Paper (effort: S) — the PWA `OperatorPermissionsPanel` shows summary pills Paper
  doesn't draw. Harmless and arguably useful, but confirm whether they stay when
  the page is finalized.

## 2026-06-01 — after Phase B dashboard slice (merged identity card + header nav)

### Loose ends
- [x] ~~Trim the redundant dashboard outer `ContentCard` title~~ — RESOLVED
  (cleanup pass): removed the outer `ContentCard` wrapper entirely (bare surfaces;
  see resolved open question). `dashboardRoot` test-id now sits on a plain `div`;
  the profile label persists via the merged card's `profileName` badge so the
  `expectDashboard`/`expectPwaDashboard` label assertions still hold (verified via
  app-shell + dashboard-visual specs).
- [~] `dashboard-signer` visual manifest stays `needs-work` — REVIEWED 2026-06-02
  (ran `test:visual:report` + a direct side-by-side of the PWA capture vs
  `repos/igloo-paper/screens/dashboard/1-signer-dashboard/screenshot.png`).
  **Structurally faithful** (Dashboard·Permissions·Settings nav + active pill,
  merged identity/runtime card with split npub copy, Peers → Pending Approvals →
  Event Log order). **Remaining fidelity gaps = exactly the deferred work**, so
  `aligned` would be premature:
  1. **Peers rows** — Paper shows online/ready counts, a latency sparkline, avg
     latency, and per-method SIGN/ECDH/PING badges; the PWA shows bare metric tiles.
     (Deferred "Peers full-parity" enhancement.)
  2. **Event Log** — Paper is populated with type-tagged rows + a filter control;
     the PWA seeds an empty log. (Deferred "Event Log parity" enhancement.)
  3. **Pending Approvals** — Paper shows populated approval rows; the PWA shows the
     intentional empty-state shell (interactive approval is the deferred runtime
     feature — working as designed).
  Promote to `aligned` only after the Peers/Event-Log parity pass; until then
  `needs-work` is the accurate status.

### Issues discovered, not fixed
- [x] ~~The split-copy hex/npub caret menu has no outside-click dismiss~~ — RESOLVED
  (cleanup pass): `KeyRow` now registers a `document` `mousedown` listener while the
  menu is open and closes it on an outside click (cleaned up on unmount); covered by
  a new assertion in `OperatorPanels.test.tsx`.
- [x] ~~The npub/hex copy menu can overflow/clip near a card edge~~ — CHECKED, no
  change needed: the menu's container is `overflow-visible` and the merged card has
  ample right-side room; not observed clipping in the 1440px capture. Re-evaluate if
  a narrow-viewport dashboard is ever added.

### Adjacent improvements
- [x] ~~Add an igloo-pwa unit test for `toDashboardKey` / `deriveMemberLabel`~~ —
  RESOLVED (cleanup pass): new `repos/igloo-pwa/test/frontend/dashboard-view.test.tsx`
  covers valid/normalized/malformed inputs for both.
- [x] ~~Extract `toDashboardKey`/`deriveMemberLabel` out of `App.tsx`~~ — RESOLVED
  (cleanup pass): moved to `repos/igloo-pwa/src/lib/dashboard-view.ts` (pure, no
  React/store); `deriveMemberLabel` now takes the share-package-json string directly.
- [x] ~~Reconcile leftover `pulse-animation`/`User` imports in `OperatorSignerPanel`~~
  — CHECKED: `pulse-animation` and `User` are already gone; `Input`/`KeyField` remain
  in deliberate use as the single-copy fallback for consumers without structured keys
  (igloo-chrome). No dead code.

### Open questions
- [x] ~~Remove the dashboard `ContentCard` wrapper in favor of bare surfaces?~~ —
  DECIDED: yes. Wrapper removed this pass; establishes the surfaces-not-boxes pattern
  for the upcoming Permissions/Settings pages.

### Future scope
- [ ] Remaining Phase B steps (all shaped in `dev/plans/dashboard-settings-export-paper-redesign-2026-06-01.md`): Permissions page (step 2), Settings page incl. Advanced section + Replace Share + Logout + Unsaved-Changes guard modal (step 3), Export Profile/Share password modals (step 4) (effort: L).
- [ ] Two remaining Paper-source edits before the Settings pass: "Lock Profile" → "Logout" on artboard `502-0`, and reconcile "Replace Share" terminology (effort: S) — noted in the plan; needs a Paper MCP edit + re-sync.
- [ ] Standardize the rotate→"Replace Share" user-facing rename across igloo-ui/igloo-pwa (flow title "Rotate Key", button "Replace Active Device", Settings action) while keeping internal `rotate*` names (effort: M) — decided this session; lands with the Settings page.
- [ ] Deferred dashboard screens not yet aligned: error/empty states (`1b-loading-profile`, `1b-profile-load-failed`, `2b-all-relays-offline`, `2c-signing-blocked`, `6-signing-failed`), Clear Credentials modal, and the interactive signing-approval runtime feature behind the Pending Approvals shell (effort: L).
- [ ] Dashboard Peers + Event Log full Paper parity (effort: M) — Peers rows want online/ready counts, latency sparkline, avg latency, and per-method SIGN/ECDH/PING badges (vs current bare metric tiles); Event Log wants type-tagged rows + a filter control. This is the trigger to promote the `dashboard-signer` visual manifest entry from `needs-work` → `aligned` (see the 2026-06-01 reviewed loose end).
- [ ] Evaluate a real router for the dashboard pages (effort: L) — currently header nav drives `store.activeDashboardTab`; URL deep-linking/back-button is a separate future refactor with route-guard considerations for sensitive unlocked states.

## 2026-05-31 — after fixing the two-device onboard handshake test

### Resolved
- [x] The live two-device onboard handshake **does** complete locally (~14ms relay
  round-trip). The earlier "handshake never completes" was a false alarm: the test
  helper `onboardPwaDevice` waited for "Onboarding Complete" text and `onboardSave*`
  test-ids that the PWA never renders. The PWA's onboard-save screen is
  `CreateFlowProfileSetup` (title "Save Profile", `saveProfile*` ids), with a
  read-only, package-derived device name. Helper fixed; `onboarding.spec.ts` now
  drives a complete onboard and asserts the request/response crossed the relay;
  `rotation-create.spec.ts` (same helper) also green. The duplicate
  `onboarding-live.spec.ts` was removed.

### Discovered while verifying the `@live` lane (pre-existing, separate from the onboard fix)
- [x] ~~`profile-import.spec.ts` import helper is stale~~ — RESOLVED: `openPwaLoadProfile`
  was rebuilt as `openPwaImportProfile` on the welcome/import test-ids
  (`welcomeEntryImport`, `importProfileInput`, `importPasswordInput`, `importNext`, then
  `saveProfile*`). profile-import is green.
- [x] ~~`rotation-update.spec.ts` (`@live`) drives a stale dashboard rotate-key flow~~ —
  RESOLVED: the rotate-connect/confirm flow was actually current (the spec only failed on the
  now-fixed import helper). Hardened its remaining copy-coupled selectors anyway —
  `connectPwaRotationPackage` uses new `rotationPackageInput`/`rotationPasswordInput` ids and
  `openPwaRotateShare` opens Settings via `dashboardTabSettings`. The full igloo-pwa `@live`
  lane is green (5/5: onboarding, profile-import, profile-inventory, rotation-create,
  rotation-update).

### Resolved — recipients can name their device on onboard
- [x] ~~Onboarded devices are auto-named "Onboarded Device" with a read-only name field~~ —
  FIXED: `CreateFlowProfileSetup` now takes a `lockName` prop (defaulting to `lockIdentity`
  so create/import callers are unchanged), and the igloo-pwa onboard-save screen passes
  `lockName={false}`. The recipient names their own device during onboarding while the keyset
  relays stay locked; `onboarding.spec.ts`/`rotation-create.spec.ts` assert the chosen names.

## 2026-05-30 — after the test-system hard-cut refactor

### Loose ends
- [ ] Convert the igloo-chrome e2e specs to the page-object model (effort: M) — the
  tightened `check-e2e-selector-contracts.sh` scopes the role/label/placeholder/class bans
  to `test/igloo-pwa/specs` because chrome specs (`dashboard.spec.ts`, `provider.spec.ts`,
  `rotation-update.spec.ts`, …) still use raw interaction locators. Build
  `test/igloo-chrome/support/pages/*` reusing the shared registry keys, then broaden the
  guard to chrome. (igloo-chrome **unit** tests are already fixed and green.)
- [x] ~~Decide whether the `@live` two-device specs should run in CI and confirm the live
  onboard handshake there~~ — RESOLVED (see 2026-05-31 above): the handshake completes
  locally; both `@live` two-device specs are green and run in `make test-live` + CI's live lane.

### Issues discovered, not fixed
- [x] ~~The live two-device onboard handshake does not complete in the local sandbox~~ —
  RESOLVED (see 2026-05-31 above): it was a stale test-helper assertion, not a runtime/relay
  problem. The handshake completes in ~14ms; both specs now pass locally and assert the
  request/response crossed the relay.
- [ ] The jsdom-28 `--localstorage-file` Node warning is benign but noisy across unit runs
  (effort: S) — it fires before the setup shim installs; suppress via a vitest pool/Node-option
  tweak if the noise matters.
- [x] ~~chrome e2e lane can't resolve `igloo-shared` from `test/`~~ — FIXED (2026-05-31):
  added `"igloo-shared": "file:../repos/igloo-shared"` to `test/package.json` devDependencies
  (`npm install` materialises the `test/node_modules/igloo-shared` symlink; the `exports` map
  points `.` → `src/index.ts`, which Playwright transforms). The chrome lane now resolves it and
  runs. Root cause was: `test/shared/browser-runtime-host.ts` bare-imports `igloo-shared`
  (only `igloo-chrome/specs/rotation-update.spec.ts` pulls it in); the client repos have the
  symlink but `test/` didn't, and the tsconfig `paths` alias is typecheck-only.
- [x] ~~chrome fast lane drags in the home+demo prebuild it never runs~~ — FIXED (2026-05-31):
  added a `fastPrebuild` set to `test/shared/test-targets.json` (`chrome → ["chrome"]`),
  honoured by `targetsForClient` when `FROSTR_TEST_LANE=fast` (set by the `:fast` npm scripts),
  and added `@cross-client` to the chrome fast `--grep-invert` (matching the pwa fast lane).
  `make test-fast` no longer needs the uninitialized `igloo-home`/`igloo-shell` submodules or
  the Tauri toolchain. (The cross-client pairing specs still run in the full/CI lane.)
- [x] ~~**REAL BUG: chrome profile import fails in the MV3 service worker**~~ — FIXED (2026-06-01):
  `import() is disallowed on ServiceWorkerGlobalScope` when loading the profile/bridge WASM in the
  background service worker (`COMMAND_TYPE.PROFILES_IMPORT` → `router-profiles.ts` → igloo-shared
  `loadConfiguredWasmModule` → `dynamicImportModule`). Fixed in
  `repos/igloo-chrome/src/lib/configure-igloo-shared.ts` by statically importing the two wasm-pack
  glue modules (static import IS allowed in a module worker) and passing them via `preloadedModule`,
  which bypasses the loader's dynamic-import branch. The glue still `fetch`es its `_bg.wasm` from the
  explicit `wasmBinaryUrl` (allowed in a SW); no `.wasm` is inlined. igloo-shared + the PWA (page
  context, dynamic import allowed) are untouched. `profile-import.spec.ts` + `rotation-update.spec.ts`
  now pass; chrome fast lane 17/17 green.

### Adjacent improvements
- [ ] Give the QR-package modal and the onboard "Apply"/connect surfaces explicit copy that
  matches a test-id (effort: S) — the onboard-connect submit is labeled "Next Step" while the
  helper history assumed "Apply Onboarding Package"; the test-id (`onboard-connect-submit`)
  now decouples it, but the label drift is worth reconciling with Paper.
- [ ] Remove the now-stale pre-existing `test/scripts/test-run-sh.sh` WIP from the working tree
  or land it (effort: S) — it is the only remaining dirty parent file and predates this work.

## 2026-05-30 — after WS4 Paper sync, WS5 verify, and e2e spec alignment

### Loose ends
- [ ] Fix `rotation-create.spec.ts` secondary-device isolation so the live onboard handshake completes (effort: M) — after the Finish Setup + label alignment, the test reaches the secondary onboard but `openFreshPwaPage(browser)`'s context shows the seeded "Source Device 1" returning Welcome instead of a clean entry hero, so `onboardPwaDevice` never reaches the onboard screen (times out on "Apply Onboarding Package"). Likely `browser.newContext()` inheriting a global `storageState` from `test/igloo-pwa/playwright.config.ts`; pass an empty `storageState` (or clear localStorage) for the fresh page. The spec's label/structure alignment is staged but left uncommitted until the handshake passes. `app-shell.spec.ts` is fully aligned and green.

### Adjacent improvements
- [ ] Add an e2e assertion that the distributor's share card flips to **Onboarded** after a real peer onboarding (effort: M) — exercises the WS3d onboard-complete event end-to-end; depends on the rotation-create isolation fix above.
- [ ] Give distribution cards a stable test id (effort: S) — `app-shell.spec.ts` now locates the first card positionally because the packaged card no longer renders a password field; a `data-test-id` per share card would make the create/rotation specs less brittle and unblock consolidating the duplicated create→distribute setup already tracked in earlier sections.

## 2026-05-27 — after hard-cut Create flow implementation

### Loose ends
- [ ] Review and commit the multi-repo branch state across root, `repos/igloo-paper`, `repos/igloo-ui`, `repos/igloo-pwa`, `repos/bifrost-rs`, `repos/igloo-shared`, and `repos/igloo-chrome` (effort: M) — this implementation is validated but spans several submodules plus refreshed WASM artifacts, so commit ordering and submodule pointers need a deliberate pass.
- [ ] Decide what to do with the pre-existing untracked `dev/plans/igloo-ui-remaining-paper-sync-hard-cut-plan-2026-05-25.md` before final staging (effort: S) — it still appears in root status and should be either intentionally added, archived, or left out of this branch.

### Issues discovered, not fixed
- [ ] Investigate the PWA visual web-server `NO_COLOR` / `FORCE_COLOR` warning around `test/igloo-pwa/playwright.config.ts:14` (effort: S) — the visual lane still prints the warning even though the config deletes both env keys, and `repos/igloo-pwa/CHANGELOG.md:15` says it was fixed.
- [ ] Investigate the Vitest `--localstorage-file` warning in `repos/igloo-pwa` unit tests (effort: S) — every PWA unit run reports the warning before tests pass, which adds noise to otherwise clean validation output.

### Adjacent improvements
- [ ] Add focused tests for `optionalSigningKeyBytes` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` (effort: S) — Rust covers splitting an existing key and the UI covers the field, but the PWA nsec/hex decoding bridge has no direct test.
- [ ] Decide whether `Launch Signer` should be disabled until every remote share is marked `Done` (effort: S) — the current implementation leaves it enabled so users can enter the signer immediately, but the distribution cards now expose completion state.
- [ ] Extract the repeated Create flow Playwright setup across `test/igloo-pwa/specs/app-shell.spec.ts`, `test/igloo-pwa/specs/rotation-create.spec.ts`, and `test/igloo-pwa/specs/welcome-visual.spec.ts` (effort: M) — the new Select Share / Save Profile path is repeated in several specs and will be easy to drift.
- [ ] Add a small regression test for `repos/igloo-paper/scripts/update_usage_coverage.py` (effort: M) — the command is now part of the Paper workflow, but only the manifest pruning and verifier-count helpers have direct script-level tests.

### Open questions
- [ ] Confirm whether the UI copy for `Existing Private Key (optional)` should explicitly mention 64-character hex as well as nsec (effort: S) — `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` accepts both formats, while the Paper/user-facing label emphasizes nsec.
- [ ] Confirm default peer permissions for new remote shares (effort: S) — `repos/igloo-pwa/src/lib/store.tsx` initializes each remote share with `sign`, `ecdh`, `ping`, and `onboard` enabled, which is permissive and may need product confirmation.

### Future scope
- [ ] Run and archive a visual comparison report with `npm --prefix test run test:visual:report` after design review (effort: M) — the capture lane passed, but the Paper-to-PWA screenshot review artifact is still the next useful review deliverable.
- [ ] Consider a smaller routine WASM validation path for sandboxed agent runs (effort: L) — `wasm-opt` still requires escalation for full browser WASM refresh/build work, which is accurate but slows routine iteration.

## 2026-05-27 — after Create flow Paper redesign

### Loose ends
- [ ] Review and commit the `repos/igloo-paper` export changes, then commit the parent workspace pointer and `test/igloo-pwa/visual-manifest.json` update (effort: S) — this session left validated work on branch `paper-create-flow-update`, but no commits were made.

### Issues discovered, not fixed
- [x] Make `make igloo-paper-sync` run Python with bytecode disabled or clean `__pycache__` before verification (effort: S) — the first sync failed because generated Python caches under `repos/igloo-paper/scripts/` violated the verifier’s cache-artifact guard.
- [x] Teach the Paper export workflow to remove stale generated screen directories when artboards are deleted or renamed (effort: M) — deleting `Generation Progress`, `Distribution Completion`, and renamed shared screens required manual directory cleanup before manifest verification could pass.
- [x] Replace or wrap the hard-coded `artboard-map.json` count checks in `repos/igloo-paper/scripts/verify.py:190` with a less brittle update path (effort: M) — deleting two mapped screens and adding one new screen required manually changing the expected total and screen count.
- [x] Add a documented command for regenerating `design/tokens/usage-coverage.json` from current exports (effort: M) — strict drift coverage had to be regenerated manually after the new Paper nodes introduced and removed prototype-only colors and typography pairs.

### Adjacent improvements
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:40` with a “renaming or deleting artboards” checklist (effort: S) — the current workflow lists files to update when adding artboards, but not stale export cleanup, visual-manifest updates, or manifest rebuild order.
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:55` to recommend `PYTHONDONTWRITEBYTECODE=1 make igloo-paper-sync` until the command handles caches itself (effort: S) — this avoids a known verifier failure mode during Paper sync.
- [x] Add a note in `dev/docs/WORKFLOWS.md` that Paper screen renames may require `test/igloo-pwa/visual-manifest.json` updates (effort: S) — the guard caught stale Paper screenshot paths only after the old exports were removed.

### Open questions
- [x] Decide what the final `Next Step` on `Distribute Shares` should do now that Distribution Completion is removed (effort: S) — the final action is now `Launch Signer` and transitions directly to the signer dashboard.

### Future scope
- [x] Update `igloo-ui` / `igloo-pwa` implementation to match the new four-step Paper design (effort: L) — this pass wires the four-step flow through `igloo-ui` and `igloo-pwa`.

## 2026-05-25 — after Paper welcome label sync and UI workflow cleanup

### Loose ends
- [ ] Push the new root and submodule commits once review is complete (effort: S) — root is ahead of `origin/master` by six commits and `repos/igloo-paper`, `repos/igloo-ui`, and `repos/igloo-pwa` are each ahead by one commit.
- [ ] Document the three UI workflows in a repo-owned guide under `dev/docs/` or `dev/plans/` (effort: M) — `repos/igloo-paper/docs/mcp-edit-workflow.md:16` covers live Paper MCP edits, but does not yet cover choosing between Paper-to-export, export-to-UI screenshot alignment, and dual Paper+UI edits.
- [ ] Create a `frostr-paper-ui-workflows` skill that dispatches agents to the right Paper/UI workflow (effort: M) — the user wants agents to select the correct workflow instead of rediscovering the process each session.

### Issues discovered, not fixed
- [ ] Investigate why full `make igloo-paper-sync` refreshed unrelated dashboard screenshots and non-Welcome reference HTML during a Welcome label change (effort: M) — accepting generated drift is sometimes correct, but unrelated churn makes Paper review noisier.
- [ ] Add progress logging or per-artboard context to `repos/igloo-paper/scripts/paper_mcp.py:84` screenshot export (effort: S) — the retry/context patch helped, but a long timeout still should identify the current artboard before failing.
- [ ] Decide whether onboarding should expose a device-name field again or whether tests should stop passing a label to `onboardPwaDevice` (effort: M) — `test/igloo-pwa/support/ui.ts:66` still accepts `label`, but the current UI no longer uses it and the rotation test now expects `Onboarded Device`.

### Adjacent improvements
- [ ] Extract repeated distribution-card setup into a Playwright helper (effort: M) — `test/igloo-pwa/specs/app-shell.spec.ts:24` and `test/igloo-pwa/specs/rotation-create.spec.ts:52` now duplicate the create-package, QR, and mark-distributed sequence.
- [ ] Add a focused visual comparison report for Paper screenshot versus PWA capture pairs (effort: L) — the current loop relies on manual `view_image` inspection after `npm --prefix test run test:e2e:igloo-pwa:visual`, which works but is hard to audit later.
- [ ] Add a guard or doc note for the scratch WASM ESM `package.json` behavior in `scripts/prepare-browser-wasm.sh:120` (effort: S) — the fix is small and validated, but future refactors could remove it without realizing Node needs the wasm-pack `.js` files treated as ESM.
- [ ] Broaden `scripts/igloo-pwa-dev.sh:65` handling for multiple listeners on port 1430 (effort: S) — the script intentionally prompts for the first PID, but a clearer multi-PID message would help when stale dev servers stack up.

### Future scope
- [ ] Add a workflow command or script that runs the whole Paper-to-PWA alignment loop and writes an artifact bundle under `dev/reports` (effort: L) — this would make the screenshot comparison loop repeatable across Welcome, Onboard, Create, and future screens.

## 2026-05-23 — after split-lane WASM guard implementation

### Loose ends
- [ ] Commit or merge the pending `hard-cut-test-harness-followups` changes after review (effort: S) — the implementation is validated but currently remains uncommitted in the feature branch.
- [ ] Exercise the negative visual-manifest path by temporarily pointing one `paperReference` at a missing screenshot before final commit (effort: S) — `test/scripts/check-pwa-visual-manifest.mjs:79` now enforces existence when `igloo-paper` is populated, but only the passing path has been run so far.

### Adjacent improvements
- [ ] Replace or supplement the grep-based checks in `test/scripts/check-browser-wasm-harness-contracts.sh:25` with a small fixture-backed shell test (effort: M) — the new routine guard is fast, but string assertions can be brittle when equivalent code is refactored.
- [ ] Add `test:guards:wasm:strict` guidance to release-facing docs such as `dev/docs/RELEASE.md` if maintainers should run it outside the full `make test-release` matrix (effort: S) — `test/README.md` documents the split, but release docs still primarily point at `make test-release`.
- [ ] Consider splitting the strict TypeScript pilot into named configs once `test/tsconfig.strict-support.json:11` grows beyond visual/reference specs (effort: M) — the single strict pilot is still manageable, but it now mixes shared helpers, fixtures, and selected specs.

## 2026-05-23 — after agent docs and test-harness cleanup

### Issues discovered, not fixed
- [ ] Make `scripts/reset.sh:23` treat an unavailable Docker daemon as an explicit skip instead of printing a permission-denied error during `make repo-reset` (effort: S) — reset succeeded, but the noisy Docker failure makes cleanup look less healthy than it is.
- [ ] Add cleanup traps to `test/scripts/check-test-prebuild-nonmutating.sh:32` so per-run `.tmp/test-prebuild-nonmutating-*` directories are removed after successful guard runs (effort: S) — repeated WASM guard runs left scratch directories until `make repo-reset` cleared them.

### Adjacent improvements
- [ ] Extend `test/scripts/check-pwa-visual-manifest.mjs:67` to verify that each `paperReference` file exists when `repos/igloo-paper` is populated (effort: M) — the new visual manifest guard validates path shape, but not stale or missing Paper screenshots.
- [ ] Gradually expand `test/tsconfig.strict-support.json:11` beyond support helpers into selected spec files once the current helper strictness stays stable (effort: M) — strict mode is now wired in, but the first pass intentionally keeps the blast radius narrow.

### Future scope
- [ ] Decide whether browser WASM validation should use a cached fixture lane for routine guards and reserve full `wasm-pack` rebuilds for release validation (effort: L) — the current guard is accurate, but it needs unrestricted execution in this sandbox because `wasm-opt` cannot run under the restricted profile.

## 2026-05-28 — after wiring the threshold key-recovery flow

### Loose ends
- [ ] Commit the `recover_secret_key_from_shares` binding in `repos/bifrost-rs/crates/bifrost-bridge-wasm/src/lib.rs` (effort: S) — it is woven into extensive pre-existing `bifrost-rs` WIP (frostr-utils, bifrost-app, signer, router) and was intentionally left uncommitted to avoid fragmenting that work; the consuming repos already vendor the built wasm, so the source change should land with the rest of the bifrost-rs WIP.
- [ ] Wire encrypted export on the Recover Private Key screen (effort: M) — the "Encrypt Key" checkbox + password/confirm fields render for design fidelity, but `RecoverPrivateKeyView` in `repos/igloo-pwa/src/App.tsx` currently saves the plaintext nsec; password-encrypted save/QR is not implemented.

### Issues discovered, not fixed
- [ ] `load-recover` (single-bfshare profile download) is now orphaned (effort: S) — dropping the import `load-choice` screen removed its only entry point in `repos/igloo-pwa/src/App.tsx`; either remove the dead view or give it a dedicated entry.
- [ ] Recover "Collect Shares" reuses `RotateKeysetPanel` with an inert "Source Profile" dropdown (effort: M) — it diverges from Paper `49W` ("Share #1 this device validated" + paste); build a tailored recover collect-shares panel. Until then `recover-collect-shares` legitimately stays `needs-work` in the visual manifest.

### Adjacent improvements
- [x] Design a capture path for the `recover-success` visual entry (effort: M) — resolved 2026-05-29 via a DEV-only `window.__IGLOO_TEST_RECOVERED_KEY__` injection seam (`import.meta.env.DEV`-gated, fake nsec, stripped from prod) that `test/igloo-pwa/specs/recover-visual.spec.ts` sets through `page.addInitScript`.
- [ ] Auto-include the unlocked device's own share in recover/rotate Collect Shares (effort: M) — both flows are currently paste-only; matching Paper's "Share #1 (this device) validated" affordance would save users from pasting their own device share.

### Future scope
- [ ] Reconcile the Welcome Flow-Section board's secondary-CTA labels with the canonical screens (effort: S) — the board embeds read "New Keyset" / "Import Device Profile" / "Onboard" vs the canonical "Generate New Keyset" / "Import Existing Device" / "Onboard New Device".
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — the next planned focus after the recover flow and screenshot review.

## 2026-05-29 — after Alert adoption, Encrypt Key, and Recover-from-Share removal

### Issues discovered, not fixed
- [x] ~~Bring `repos/igloo-chrome` current with the redesigned `igloo-ui` API~~ — RESOLVED
  (2026-05-31): migrated AppHeader (mode + taskLabel/actions), OperatorSignerPanel
  (SignerDashboardViewModel), OperatorPermissionsPanel (PolicyDashboardViewModel +
  onPeerPolicyOverrideChange + PolicyMethodOverrideState/PolicyOverrideValue), and
  StoredProfileCardModel (shortId/state/primaryActionLabel/destructiveActionLabel).
  `tsc --noEmit` clean; build:app succeeds.
- [x] ~~Fix the `repos/igloo-chrome` vitest environment so unit tests run locally~~ —
  RESOLVED: chrome's `vitest.setup.ts` already adopts `igloo-shared/testing/setup-dom`
  `ensureLocalStorage()`; the full unit suite is green locally (24 files / 94 tests).
- [ ] Adopt `PasswordField` (the igloo-ui reveal-toggle input) in `repos/igloo-chrome` import/onboard forms (effort: S) — they still use plain `type="password"` inputs; a small polish item now that the API migration is done.
- [ ] Convert the igloo-chrome e2e specs to page objects + verify the chrome e2e lane (effort: M) — the migration unblocked chrome's typecheck/unit/build, but `playwright test -c igloo-chrome --list` outside the prepared context still hits the tracked "Cannot find package 'igloo-shared'" resolution gap (see 2026-05-30 entry); the chrome `@live`/`@demo` e2e specs run under docker/CI prep and still use raw interaction locators.

### Loose ends
- [ ] Land the accumulated multi-session work in coherent per-repo commits (effort: M) — three uncommitted layers now stack across the submodules (the needs-work hard-cut, this follow-up cut, and the Paper export). Order: `igloo-shared` → `igloo-ui` → `igloo-pwa` + `igloo-chrome` → `igloo-paper` → parent. Commit the `repos/igloo-paper` 67-file diff as its own "Paper export refresh (SVG serialization normalization + Alerts contents/contract)" checkpoint so the intent reads clearly; keep pre-existing parent WIP (`app-shell.spec.ts`, `rotation-create.spec.ts`, `test-run-sh.sh`) out of the feature commits.
- [ ] Commit the `repos/bifrost-rs` WIP (recover binding + `signing_key32` / `CreateKeysetConfig::new()` cleanup) (effort: M) — still the one deliberately-uncommitted submodule carried from the original handoff.
- [ ] Remove the stale `recoverProfileForm` (and legacy `recoverForm`) seed keys from `test/igloo-pwa/specs/app-shell.spec.ts` (effort: S) — harmless (the store ignores unknown drafts) but dead after the Recover-from-Share removal; clean up when that pre-existing WIP is resolved.

### Future scope
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — still the next planned major surface; no audit done yet (carried from prior sessions).

## 2026-05-29 — after Create-Keyset stepper + relay refinements (WS1/WS2)

(Active-plan WS3–WS5 are the next phase and tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Adjacent improvements
- [ ] Validate relay input in the new `RelayList` (`repos/igloo-ui/src/components/flows/CreateFlow.tsx`) before adding (effort: S) — the "Add Relay" field currently accepts any string and only dedupes; reuse the existing relay normalizer (`normalizeRelays` / `normalizeRelayUrls` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`) to require `wss://` and surface an inline error, instead of failing later at profile creation.
- [ ] Clear stale per-URL ping state when a relay is removed in `RelayList` (effort: S) — ping results are kept in component state keyed by URL and not pruned on delete, so removing then re-adding the same URL shows the old status until it re-pings.
- [ ] Add a unit test for `pingRelay` + `RelayList` ping/status behavior (effort: S) — mock `WebSocket` to cover ok/failed/timeout and the auto-ping-on-add path; there is no coverage of the new relay-connectivity code yet.

### Loose ends
- [ ] Decide the fate of the now-redundant `RelayInput` component (`repos/igloo-ui/src/components/ui/relay-input.tsx`) (effort: S) — it predates and overlaps the new `RelayList`; either remove it or consolidate so there's one relay-entry component.

## 2026-05-29 — after Distribute-Shares redesign + onboard-complete event (WS3)

(WS4 Paper sync and WS5 full verify/visual re-capture are the next phase, tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Loose ends
- [ ] Commit the `repos/bifrost-rs` WS3d change with the re-vendored wasm (effort: M) — `CompletedOperation::OnboardServed` (signer `lib.rs:1713`), the bridge-wasm `CompletedOperationJson::OnboardServed` variant, and the bridge-tokio kind arm land in the existing bifrost-rs WIP; the rebuilt `bifrost_bridge_wasm_bg.wasm` is now modified (binary-only; JS/.d.ts unchanged) in all three of `repos/{igloo-pwa,igloo-shared,igloo-chrome}/public/wasm` and must be committed coherently with the Rust source.
- [ ] Remove the dead `.igloo-create-local-share-card` CSS rules in `repos/igloo-ui/src/styles.css` (effort: S) — the local-share card was removed in WS3b but its style rules remain (grouped into shared selectors); cleanest to drop during the WS4 Paper sync that rewrites that area.

### Adjacent improvements
- [ ] Add store-level unit tests for the new distribute lifecycle in `repos/igloo-pwa/src/lib/store.tsx` (effort: M) — `distributeShare` (`prepare/copy/qr/save/mark/cancel/revert`), `startDistributionClient`/`stopDistributionClient`, and `finishSetup` (snapshot-persist → stop → purge secrets → locked Welcome) have no direct coverage; App.test only walks the happy path to Finish Setup.
- [ ] Add coverage for the onboard-complete wiring (effort: M) — `parseOnboardServedCompletion` (`repos/igloo-shared/src/browser-runtime-core.ts`) and the store's peer→share→`onboarded` mapping (prefix-normalized `share_public_key` match) are untested; a bridge-wasm Rust test asserting the `{"OnboardServed":{request_id,peer_pubkey32_hex}}` JSON shape would also lock the serde contract the TS parser depends on.
- [ ] Replace the native `window.confirm` undelivered-shares guard in `renderCreateDistribute` (`repos/igloo-pwa/src/App.tsx`) with a styled modal (effort: S) — the rest of the app uses dedicated modals (e.g. `WelcomeDeleteModal`); the raw `confirm()` is inconsistent and is also why `App.test` has to stub `window.confirm`.
- [ ] Make `OnboardingClientCard`'s peer count meaningful (effort: S) — it currently shows `store.peerPermissionStates.length`, which can read 0 until peers are observed; consider sourcing the count from the runtime snapshot/remaining shares so the summary reflects the live session.
- [ ] Prune stale per-URL ping state is already tracked for `RelayList`; verify the same component-state-keyed-by-URL pattern in the distribute flow does not leak after `cancel`/`revert` (effort: S) — the distribute cards key drafts/results by `member_idx` (fine), but confirm no orphaned `distributionForms` entries survive a `cancel`.

### Open questions
- [ ] Confirm the `onboarded`-from-`draft` promotion semantics (effort: S) — the onboard-complete handler sets a matched share to `onboarded` even if it had no package (no prior `packaged`/`delivered`), materializing a result entry; the plan's assumption said "auto-promotes from any non-Draft state." Current behavior favors never dropping a real onboard signal — confirm that's desired.
- [ ] Confirm the File System Access save semantics (effort: S) — `saveTextToFile` (`repos/igloo-pwa/src/lib/store.tsx`) advances a share to `saved` on a confirmed `showSaveFilePicker` write and keeps status on user-cancel, but the anchor-download fallback (unsupported browsers) optimistically marks `saved` without a write confirmation.
