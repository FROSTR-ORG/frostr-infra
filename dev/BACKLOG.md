# Backlog

Curated, forward-looking follow-up work for the `frostr-infra` workspace.
Completed work and the verbatim historical log live in
[`HISTORY.md`](./HISTORY.md); active multi-step plans live in
[`plans/`](./plans).

Format: one item per line, `- [ ] (effort: S|M|L) <summary> — <area> · <link/notes>`.
Group by area. When an item is finished, move a one-line summary to
`HISTORY.md` and delete it here. Dates are absolute (`YYYY-MM-DD`).

> Migration note (2026-06-10): items below were triaged out of the former root
> `FOLLOWUPS.md`. Some may already be resolved by later work — verify against
> the codebase before picking one up. Trivial test-refactor micro-items from the
> 2026-05 sessions were left in the `HISTORY.md` archive rather than carried here.

## Design (Paper ↔ runtime)

- [ ] (effort: S) **Promote the `dashboard-signer` visual entry to `aligned`.** Its
  blocking telemetry (per-peer latency, nonce sparkline, SIGN/ECDH/PING capability
  badges) shipped 2026-06-13 and now renders in `OperatorSignerPanel`. Re-shoot /
  re-diff the visual against Paper's `1-signer-dashboard` and update the entry's
  status — `igloo-paper` + the visual lane.
- [ ] (effort: M) Add a **Browser Settings** group to the Paper `502-0` Settings
  artboard so the PWA-only toggles (Remember browser state / Open signer after
  import / Prefer install prompt) are reflected in the design — `igloo-paper` ·
  surfaced 2026-06-09, the only PWA-only Settings section without a Paper counterpart.
- [ ] (effort: S) Edit Paper so the merged **identity/runtime card is
  dashboard-only** — drop the repeated header from the Permissions/Settings
  artboards (`1c-permissions`, `502-0`) to match the runtime (decided 2026-06-09).
- [ ] (effort: S) Add a **Pending Operations** component to the Paper design system
  to match the runtime `OperatorSignerPanel` card (the runtime card already exists)
  — `igloo-paper`. (The runtime "Diagnostics" card was renamed → **Event Log** to
  match Paper on 2026-06-13.)
- [ ] (effort: S) **Sync the Pending Approvals card + tri-state permissions to Paper.**
  The approval queue shipped 2026-06-14: the Pending Approvals card is now interactive
  (Deny / Allow once / Always allow) and the permissions toggle is tri-state
  (allow → ask → deny → unset, with an amber `ask` state). Re-diff Paper's
  `1-signer-dashboard` + permissions artboard against the runtime — `igloo-paper`.

## bifrost-rs / igloo-shared runtime

- [ ] (effort: L) **Signer bring-up perf: ~18s onboard-ready + ~12s per onboard
  export (unsure how reducible).** Measured 2026-06-17 in the Docker demo: the
  docker build is ~1s; the ~40s "hang" is the signer reaching onboard-ready over
  the relay (`wait_for_onboard_ready` polls ~18s) then a relay-coordinated
  `bfonboard` export per recipient (~12s each). The poll-based readiness in
  `repos/igloo-shell` + relay round-trips dominate. Investigate a deterministic
  ready signal and whether the export can avoid/parallelize round-trips. The native
  `make dev` loop (Thread 1) sidesteps this with a persistent keyset, but it's the
  real cost whenever a device is actually onboarded.

- [x] (effort: L) **Peer telemetry — DONE (2026-06-13).** Per-peer latency (ms,
  last + avg), nonce sparkline, and per-method SIGN/ECDH/PING capability badges, end
  to end: `bifrost-signer` PeerStatus (runtime-only RTT + nonce-history rings, ms
  clock) → `runtime_status()` → igloo-shared wire → igloo-ui adapter +
  OperatorSignerPanel (badges + latency + new Sparkline primitive), threaded through
  the pwa / chrome / home dashboards. Spec items (c)→(a)→(b). The `dashboard-signer`
  visual entry's blocking telemetry has landed — promote it toward `aligned`. Spec:
  [`plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md`](./plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md).
- [x] (effort: L) **Interactive signing-approval queue — DONE (2026-06-14).** A new
  `PolicyOverrideValue::Ask` parks inbound requests in a runtime-only queue until the
  operator resolves them (Deny / Allow once / Always allow), end to end across the Rust
  core (`SignerInput::ResolveApproval` + `pending_approvals` in `runtime_status`), the JS
  bridge (`resolve_approval`), and all three dashboards — including igloo-home, whose
  native (bifrost-bridge-tokio) signer gained Tauri `resolve_approval` / `update_peer_policy`
  commands + editable permissions. Spec item (d). Permissions toggle is now tri-state
  (allow→ask→deny→unset). Verified via `make test-live` (sign-shell + tri-state persistence).
- [x] (effort: S) **Document the `Ask` disposition + approval queue — DONE (2026-06-14).**
  Added an "Interactive Approval (`Ask`)" subsection to `docs/PROTOCOL.md`'s peer-permission
  note: the third policy state, the runtime-only park queue, the three resolution paths,
  timeout/restart drop, and per-device-local semantics.
- [x] (effort: M) **Native control-surface / igloo-shell approval parity — DONE (2026-06-14).**
  Added `ResolveApproval` to `bifrost-app`'s control-socket command surface + a
  `DaemonClient::resolve_approval`, and an `igloo-shell runtime resolve-approval` CLI +
  `CliPolicyValue::Ask` (so `policy set-peer-override --value ask` works). `SetPolicyOverride`
  + `runtime status` (with `pending_approvals`) already existed. The shell now reaches the
  queue over the typed control socket rather than only the direct tokio handle.
- [ ] (effort: S) **Approval-queue cleanup: `approval_timeout_secs` runtime-tunability.**
  It is on `DeviceConfig`/`AppOptions` but not `DeviceConfigPatch` or any settings UI, so it
  can't be tuned at runtime. Low value (fixed 300s default is fine) — deferred. (The sibling
  "Always allow" atomicity concern was verified resolved 2026-06-14: all three clients surface
  a partial-failure via their error paths, and resolve-first ordering is correct.)
- [x] (effort: S) **Wire-type drift guard — DONE (2026-06-15).** Kept igloo-ui
  decoupled from igloo-shared (it deliberately copies test setup rather than depend on
  it) and added a compile-time contract instead: igloo-chrome — the one repo that
  depends on both — hosts `src/extension/runtime-types.contract.ts`, which fails
  `tsc --noEmit` when a canonical igloo-shared wire field is not mirrored by chrome's
  local `RuntimeStatusSummary` or igloo-ui's adapter input types (now exported for the
  check). Key-coverage only; intentional skips (chrome's camelCase `StoredPeerPolicy`,
  `onboarding_statuses`) are spelled out as `Omit<>`. The pwa-local minimal mirrors
  remain a smaller smell (not covered).
- [x] (effort: S) **Removed the dead `runtimeStatusToSignerDashboardView` — DONE
  (2026-06-15).** Deleted (no client consumed it; all dashboards use
  `buildPeerReadinessRows`) along with its orphaned `pendingOperationToRow` helper and
  the two DesignAdapters tests.
- [x] (effort: M) **Refactor the onboard→signer handoff to remove the
  capture-then-reinit seam — PWA done (2026-06-13).** The PWA onboard flow now keeps
  the live onboarding node running and *adopts* it as the durable signer (the
  `keepAlive` path on `connectOnboardingPackageAndCaptureProfile` + the
  `SessionController` staged-session slot), removing the capture-snapshot-then-relaunch
  seam and the pwa-local restore plumbing (`startSession` no longer threads a snapshot).
  Rotation keeps the capture-then-shutdown path (it derives a new keyset). — igloo-pwa.
- [ ] (effort: M) **Chrome onboard→signer seam — same collapse for igloo-chrome.**
  `igloo-chrome/.../onboarding-session.ts` still captures a snapshot and shuts the node
  down, but chrome *persists* `runtimeSnapshotJson` in the profile blob (an MV3 service
  worker can be killed/restarted, so it genuinely needs restore-from-persistence). Its
  collapse is a different shape than the PWA's — separate, carefully-reviewed pass. The
  shared bridge `mode:'persisted'` / `restore_runtime` / resilient-restore stays as long
  as chrome relies on it (surfaced 2026-06-13).
- [ ] (effort: S) **Snapshot version tag (fast-path skip on top of the shipped
  restore fallback).** Resilient restore re-bootstraps from packages when a snapshot
  fails to restore, but it still *attempts* the WASM restore first. Stamp a version at
  snapshot write and skip the restore attempt up front on a known mismatch — purely an
  optimization. Now **chrome-only**: the PWA onboard path no longer restores from a
  snapshot (it adopts the live node), so chrome is the sole remaining producer/consumer
  of onboard snapshots. Must stay back-compatible (treat un-versioned snapshots as
  restorable) — igloo-shared + the chrome snapshot write sites (surfaced 2026-06-13).
- [x] (effort: S) **DONE (2026-06-15).** Router Ping-sentinel — `fail_request_and_dispatch`
  now recovers the real op type from `pending_operations[request_id]` (falling back to
  `Ping` only when absent); the `tick` expire / inbound-request sites stay `Ping` as
  adjudicated. Rode the NIP-44 raw-X WASM rebuild — bifrost-rs `c47d76e`.

## igloo-pwa

- [ ] (effort: S) **Gate the dev-scenario seam behind `import.meta.env.DEV`.**
  `repos/igloo-pwa/src/lib/dev-scenario.ts` (`resolveDevScenario`) runs in any
  build when `?__frostr_dev=<scenario>` is present. It's harmless (a fake in-memory
  profile, no real keys/signing), but a production build shouldn't carry the seam —
  wrap it in `import.meta.env.DEV` so it tree-shakes out of prod. (Mirror whatever
  igloo-home does for `resolveVisualScenario`.)
- [ ] (effort: S) **`agent-screenshot.spec.ts` bypasses the page-object selector
  contract.** It uses raw `getByTestId`/`getByRole`, which `check-e2e-selector-
  contracts.sh` flags (de-gated from PRs, but the nightly `test:guards:full` will
  catch it). Exempt `@agent` tool specs from the contract or route them through a
  page object.
- [ ] (effort: S) **Enrich the dev-scenario running fixture / add scenarios.** The
  running fixture has empty `pending_approvals`/`pending_operations`/structured
  `events`, so those dashboard cards render empty in `make screenshot`. Add a sample
  approval + a couple observability events, and more scenarios (permissions,
  settings, create) for broader render-and-verify coverage.

- [ ] (effort: M) **Finish the Paper dashboard alignment.** The 2026-06-16 pass
  aligned the **signer tab** (running + stopped) to Paper via semantic
  `.igloo-dashboard-*` CSS in igloo-ui + a restructured `OperatorSignerPanel`.
  Remaining Paper dashboard surfaces are unchanged: the **Permissions** and
  **Settings** tab bodies, the shared status-header across all three tabs, the
  condition banners, the loading/load-failed state screens, and the export /
  clear-credentials / unsaved-changes / signer-policy-prompt modals — igloo-ui +
  igloo-pwa.
- [ ] (effort: M) **Runtime-injection seam for dashboard @visual capture.** The
  signer dashboard's *running* layout (Peers + capacity bars, Pending Approvals,
  Event Log) can't be captured by the storage-only `@visual` lane because the
  runtime snapshot is in-memory (never persisted), so `dashboard-visual.spec.ts`
  captures the *stopped* state. Add a test seam (like igloo-home's
  `currentVisualScenario`) so the running dashboard can be seeded + captured
  against Paper `1-signer-dashboard`. The running layout is already unit-tested in
  `repos/igloo-ui/test/OperatorPanels.test.tsx` — test/igloo-pwa.
- [ ] (effort: M) **RED GATE — `app-shell.spec.ts` seeds the old PWA partition and
  now hard-fails (`make verify`/`make test-fast` red on dev HEAD).** Confirmed
  2026-06-17: two `@fast` specs — *persists settings across reloads* and *…preserving
  saved profiles* — fail at `app-shell.spec.ts:276` (`dashboardRoot` not visible).
  Both seed `localStorage` directly under the old `STORAGE_KEY`/`pwaPartitionKey`
  partition with a v2 profile carrying a *fake* `encrypted_bfshare_artifact`
  (`'bfshare1demo'`) + `activeView:'dashboard'`, then `goto('/')` and `expectDashboard()`.
  After the 2026-06-16 global-profile-store move (two-store model:
  `igloo-pwa.profiles.v1` + `igloo-pwa.session.v1::<id>`) the seeded state no longer
  hydrates to an unlocked dashboard — boot migrates the profile but the fake artifact
  can't reconstruct the share, so the dashboard never renders. Reproduces in a clean
  env; **not** caused by the Thread 3 work (all submodules pristine). The other 18
  pwa `@fast` tests pass. Fix: reseed these specs via the supported two-store helper
  (`test/igloo-pwa/support/state.ts` `buildPwaPersistedState`/`applyPwaSeed`) — or, if
  the dashboard genuinely must hydrate from a stored artifact, fix pwa hydration. Also
  retarget `chrome-pwa-pairing.spec.ts` (`PWA_STORAGE_KEY`), and rework app-shell's
  resume / multi-instance assertions that exercise the removed per-tab partition — test/.
- [ ] (effort: M) **Cross-tab single-active-signer lock.** The 2026-06-16 move to
  a global profile list (shared `igloo-pwa.profiles.v1`, per-tab session in
  `igloo-pwa.session.v1::<id>`) removed the storage partition that *implicitly*
  prevented the same device running in two tabs. Nothing now hard-stops two tabs
  unlocking the same FROST share at once (nonce-reuse / double-sign risk). Add an
  explicit `navigator.locks` per-`profileId` lock acquired **before**
  `adapter.startSession`, with a BroadcastChannel "active in another tab — take
  over?" handshake that stops the other tab's signer before this one starts.
  Start sites: `loadStoredProfile`, `startSigner`, distribution/onboard
  auto-starts; release on stop/logout/delete/unmount — igloo-pwa.
- [x] (effort: L) **DONE (2026-06-15).** Dashboard error/empty states (loading,
  load-failed, all-relays-offline, signing-blocked, signing-failed) — reusable
  igloo-ui screens (`DashboardLoadingScreen` / `DashboardLoadFailedScreen` /
  `DashboardConditionBanner`) + a `deriveDashboardState` selector consumed by all
  three clients (pwa / chrome / home). First-class signals: `last_sign_failure`
  (bifrost-signer, true core field) + bridge-enriched `connected_relays` /
  `configured_relays` (Tokio + browser bridges). Mixed presentation: loading &
  load-failed full-panel; the other three are banners over a usable dashboard.
  Follow-ups below.
- [x] (effort: M) **Dashboard load-failed now reachable in pwa + home — DONE
  (2026-06-15).** A signer-start failure is captured into a `dashboardLoadError`
  state (pwa store / home App) and routes to the dashboard so the full-panel
  load-failed screen shows (Retry / Clear); cleared on success/stop. chrome's
  `runtime_unavailable` stays a soft in-panel state by design. (Native daemon-start
  failures are home-frontend; the `status.last_load_error` wire field is still
  bridge-unfilled — see next item.)
- [x] (effort: M) **Native `last_load_error` enrichment — WON'T BUILD (2026-06-15).**
  Architecturally moot: a native restore failure aborts daemon startup
  (`store.load()?` in bifrost-app bootstrap → daemon never starts), so there is no
  running runtime to query — `runtime_status().last_load_error` is unreachable.
  Home correctly drives load-failed from its own start-error state. The wire field
  is kept as a documented reserved slot (a future host that surfaces a load error
  from a *running* runtime could fill it). Comment on the field corrected.
- [x] (effort: M) **Live relay-health re-probe (browser bridge) — DONE (2026-06-15).**
  `refreshRelayHealth()` re-probes on a ~30s interval (started in connect, cleared in
  shutdown), recomputing `connected_relays` so all-relays-offline fires on post-boot
  relay drops/recoveries; pumps a runtime-status event only on change.
- [x] (effort: M) **`@live` e2e for the dashboard banners — DONE (2026-06-15).**
  `test/igloo-pwa/specs/dashboard-states.spec.ts` drives **signing-blocked** (deny the
  peer's request.sign → sign_ready drops) then **all-relays-offline** (close the relay →
  re-probe empties connected_relays; the banner flips, exploiting their precedence).
- [x] (effort: M) **`@live` e2e for the signing-failed banner — WON'T BUILD
  (2026-06-15).** Only the sign *initiator* holds a pending `Sign` op that can fail
  (responders answer immediately, no pending op), so the responder-only PWA dashboard
  can never populate its own `last_sign_failure` without becoming an initiator or a
  test mock. The banner's derivation + render are already covered by the igloo-ui unit
  test (`DashboardStates.test.tsx`). Revisit only if/when a client gains a
  self-initiated sign surface.
- [ ] (effort: S, unsure) Make the Settings dirty-check structural rather than
  `JSON.stringify` of relays/signerSettings, if those shapes grow.
- [ ] (effort: S) Decide the fate of the redundant `RelayInput`
  (`igloo-ui/src/components/ui/relay-input.tsx`) vs the newer `RelayList`.
- [ ] (effort: S) **Onboard-save relay field — vestigial `onRelaysChange` cleanup.**
  The "lock vs honor" decision landed on **lock**: `renderOnboardSave` passes
  `lockIdentity={true}`, so the relay list renders read-only and
  `finalizeOnboardedDevice` (correctly) ignores relay edits — the profile's relays
  come from the onboarding package. Remaining cleanup: a now-pointless
  `onRelaysChange` callback is still wired at `igloo-pwa` `App.tsx:1193`; drop it
  (surfaced 2026-06-13; rescoped 2026-06-15).

- [ ] (effort: S) Rich device labeling/renaming in the instance registry UI
  (initial impl shows the id prefix + null label).

## igloo-chrome

- [ ] (effort: M) Convert the remaining igloo-chrome e2e specs to the page-object
  model — `check-e2e-selector-contracts.sh` already covers chrome, and a few specs
  (e.g. `dashboard`, `rotation-update`) use `support/ui.ts`, but most still inline
  locators.

## igloo-home

- [ ] (effort: S) **Recover-key meter could show member count** — `get_profile_threshold`
  returns just the threshold; optionally widen it to `{ threshold, member_count }` so the
  `RecoverCollectSharesPanel` meter reads "X of threshold (group of N)" (`src-tauri`
  `app/commands.rs` + `src/App.tsx`; surfaced 2026-06-13).
- [ ] (effort: S) **Optional: a "save recovered nsec to file" affordance in home**
  for full parity with the shell's `0o600` file write. The in-transit exposure is
  now documented (the key already crosses into the webview when displayed), so this
  is a convenience, not a hardening — a scoped `0o600` write via the existing
  `tauri-plugin-dialog` + `path_scope` export infra (`src/App.tsx` +
  `src-tauri`; surfaced 2026-06-13).

## Dependencies & packaging

- [ ] (effort: S) **High-severity `esbuild` advisory** surfaced in
  `igloo-chrome` (and igloo-pwa) `npm audit` — "Missing binary integrity
  verification in Deno module enables RCE via `NPM_CONFIG_REGISTRY`". Dev-only
  tooling (esbuild bundler / vitest); not a runtime exposure. Bump esbuild past
  the patched version across the affected repos once a non-breaking release is
  available — surfaced 2026-06-13 during the nostr-tools dedupe pass.

## Test harness / CI

- [ ] (effort: S) **Harden the `make dev` daemon socket path (unsure if it ever
  overflows).** `scripts/dev.sh` puts the igloo-shell control socket under an
  ad-hoc `mktemp -d "${TMPDIR}/frostr-dev.XXXXXX"` rather than the codebase's
  secure path-shortener ([[daemon-socket-sunlen]]). On a deep macOS `TMPDIR`
  (`/var/folders/...`) the resulting `.../igloo-shell-<hash>.sock` lands ~96/104 of
  the unix-socket `sun_path` limit — it fits today but the margin is thin and it
  bypasses the established helper.
- [ ] (effort: M) **`make dev`: verify in-browser + zero-import auto-seed.** The
  native loop is verified up to vite serving (HTTP 200); the in-browser
  import-of-`dev-device.bfprofile` + signing against the native relay is unverified
  (manual for now). Fold into Thread 5b: build the `PwaProfile` from
  `dev/fixtures/dev-device.bfshare` and seed `igloo-pwa.profiles.v1` directly so the
  device is provisioned with zero manual import, and verify the running dashboard
  headlessly via `make screenshot`.
- [ ] (effort: S) **Decide nightly `test:guards:full` fate (premise corrected
  2026-06-17).** Re-checked after the lean-CI cut: the doc/command-surface guards
  actually **pass** — `check-doc-command-surfaces.sh`, `check-doc-surfaces.sh`, and
  `check-markdown-links.mjs` are all green (even with the new `make install` /
  `make bump-pointers` targets). The *only* thing making nightly `test:guards:full`
  red is `check-e2e-selector-contracts.sh` flagging `agent-screenshot.spec.ts`
  (already tracked in the igloo-pwa section). So this is no longer a docs-drift fix:
  either exempt `@agent` tool specs from the selector contract (greens the nightly)
  or formally demote `test:guards:full` to advisory. (The broader "delete the
  de-gated guards" item below still stands.)
- [ ] (effort: M) **Finish throwing out the de-gated visual + low-value guards.**
  2026-06-17 removed them from the PR gate but kept the files. Once the screenshot
  capability is recast as `make screenshot` (Thread 5b), delete
  `test/igloo-pwa/visual-manifest.json`, `check-pwa-visual-manifest*.{mjs,sh}`,
  `report-pwa-visual-comparison.mjs`, and the low-value guard scripts (markdown-
  links, doc-command-surfaces, workflow-node24, client-scoped-submodules,
  shared-setup, cross-client-imports, e2e-selector-contracts) + their `package.json`
  entries.
- [ ] (effort: S) **Make `make verify` affected-aware.** It currently runs the full
  pwa+chrome `@fast` lanes; route through `scripts/test-affected.sh` so it scales to
  the touched client.
- [ ] (effort: S) **Playwright leaks `bifrost-devtools relay` processes.** Found
  2026-06-17: ~16 orphaned `bifrost-devtools relay --host 127.0.0.1 --port <ephemeral>`
  processes (PPID 1, dated back to May 31 / Jun 8) accumulating across e2e/`@live`
  runs — a relay spawned by a spec/webServer isn't torn down when its parent dies.
  Harmless but unbounded (port/FD pressure over time); killed this batch with
  `pkill -f "bifrost-devtools relay"`. Find the spawn site (likely a `@live`/demo
  fixture or webServer) and ensure relay teardown on suite end / process exit.
- [ ] (effort: M) **WASM watch + drop committed-WASM double-maintenance.** Browser
  WASM is committed to git AND regenerated on every prepare. Add `make wasm-watch`
  (cargo-watch/watchexec) and build-on-demand for dev; the cheap stamp guard can
  stay in the lean gate or move to nightly. (Deferred from the 2026-06-17 hot-reload
  pass, which did igloo-ui CSS watch only.)

- [x] (effort: S) **DONE (2026-06-16).** Export-package `@live` flake under load.
  `exportProfileWithPassword` (`test/igloo-pwa/support/pages.ts`) now re-fills both
  password fields and polls the confirm value via `expect.poll` at
  `LIVE_EXPECT_TIMEOUT_MS` (20s) before waiting for the Export button to enable —
  robust against the controlled-input onChange lagging past the default 10s under
  back-to-back-run CPU contention. Test-harness-only.
- [x] (effort: S) **DONE (2026-06-15).** The cross-repo `demo-pair-check` guard
  missed igloo-shell test drift: it ran `cargo check --bin` (bin-only), so it never
  compiled igloo-shell-core/cli **test fixtures**. bifrost-rs struct-field additions
  silently rotted the shell's struct-literal fixtures twice (2026-06-13 `PeerStatus`,
  2026-06-15 the four `RuntimeStatusSummary` host/bridge fields). Strengthened the
  `Makefile` `demo-pair-check` target to `cargo check --locked --all-targets` for the
  whole igloo-shell workspace (and bifrost-devtools), so test/bench targets compile at
  pointer-bump time. Verified it catches a dropped fixture field and passes clean.
- [x] (effort: M) **DONE (2026-06-16).** igloo-shell full approval round-trip
  integration test — `crates/igloo-shell-cli/tests/approval_roundtrip.rs`. Two daemons
  over a relay (alice invites bob via bfonboard so the handshake seeds mutual
  sign-readiness); bob gates alice with `respond.sign = ask`; the deny path makes
  alice's blocking `runtime sign` fail, the approve path completes with a verified
  Schnorr signature. Concurrent blocking-sign + resolve driven via
  `std::thread::scope`; `request_id` read from `pending_approvals` (no new CLI — the
  optional `runtime approvals` list was skipped to keep the cut tight). Surfaced
  2026-06-14.
- [x] (effort: S) **DONE (2026-06-16).** Pre-existing selectors-guard violation in
  `dashboard-states.spec.ts` (it called `page.getByTestId(...)` directly at three
  banner-assertion sites). Added `DashboardPage.conditionBanner` /
  `expectConditionBanner` / `expectNoConditionBanner` (over the dynamic
  `dashboard-banner-<kind>` id) and routed the spec through them. Full
  `npm --prefix test run test:guards` is green again; the `@live` spec still passes.
  hardcodes `/usr/bin`/`/snap` chromium paths and the desktop lane needs `xvfb-run` +
  ImageMagick `identify` + X11 `xwininfo`, so neither runs on macOS (homebrew chromium at
  `/opt/homebrew/bin`, no ImageMagick). Probe the homebrew path and degrade gracefully when
  `identify` is absent so local macOS dev can at least capture screenshots (surfaced
  2026-06-13; the `recover-key` visual scenario is registered and CI/Linux will screenshot it).
- [ ] (effort: S) **Desktop smoke for recover-key** — once the desktop lane runs (CI/Linux),
  add a `repos/igloo-home/test/desktop` step that dispatches `recover_group_key` and
  screenshots the recover-key view; today it's covered by Rust unit + a vitest
  behavioral test only (`igloo-home`; surfaced 2026-06-13).
- [ ] (effort: M) **Behavioral test for the resilient-restore fallback.** Phase-1.2
  added a re-bootstrap-from-packages fallback when a persisted snapshot fails WASM
  restore; only the package-carrying half (`createBrowserRuntimeNodeInit`) is
  unit-tested. A true behavioral test needs a real WASM runtime + relay, which the
  igloo-shared unit harness deliberately avoids — so this belongs in the
  integration/demo lane (feed a structurally-valid but incompatible snapshot, assert
  it emits `restore_fallback_to_profile` and comes up sign-ready), not a unit test
  (re-scoped M, 2026-06-13) — Test harness.
- [ ] (effort: S) Verify the chrome `@demo` lane (`make test-demo`) end-to-end on
  colima — only `make test-smoke` was completed previously.
- [ ] (effort: S) Silence the jsdom `--localstorage-file` Node warning in igloo-pwa
  unit runs.
- [ ] (effort: S) Investigate the PWA visual web-server `NO_COLOR`/`FORCE_COLOR`
  warning (`test/igloo-pwa/playwright.config.ts`) — config deletes both keys yet it
  still prints.
- [ ] (effort: S) Add a small regression test for
  `repos/igloo-paper/scripts/update_usage_coverage.py`.
- [ ] (effort: S) **Harden `.tsx`-only vitest include globs (igloo-ui).** igloo-pwa
  was fixed 2026-06-13 (`vitest.config.ts` now `*.test.{ts,tsx}`). **igloo-ui** still
  has the `test/**/*.test.tsx`-only glob (`repos/igloo-ui/vitest.config.ts`) — no
  `.ts` test today, but a future one would be silently dropped. Broaden it to
  `{ts,tsx}` and consider a workspace guard (e.g. extend `check-shared-test-setup.sh`)
  that flags a committed `*.test.ts` no project glob matches (surfaced 2026-06-13;
  pwa half resolved, rescoped to igloo-ui 2026-06-15).
- [ ] (effort: M) **`pwa-home-pairing` is effectively dead** — it's `@cross-client`
  (runs in NO CI lane), DISPLAY-gated, and until 2026-06-11 read the runtime
  snapshot from localStorage where it is never persisted. It now uses the corrected
  DOM-based `expectPwaSignerSignReady`, but is still unverified + ungated, and it's
  the only PWA↔native nonce-hydration coverage. Run it (xvfb), confirm it passes,
  then gate `@cross-client` in `release-validation` — or retire it — Test harness/CI.
- [ ] (effort: M) Promote the manual multi-PWA-tab signature to an automated spec
  (two browser contexts + igloo-shell initiator) once the manual flow is stable —
  Test harness · see the `pwa-multisig-demo` scaffolding.
- [ ] (effort: S) **Optional race-safety: enrich the sign-miss response.** Today a stale-nonce
  sign converges once the resetting peer's next ping conveys its new generation. For the
  narrow window where an initiator signs *before* receiving that ping, have the responder
  return its current generation + fresh nonces on a `NonceUnavailable` miss so the initiator
  prunes-and-retries immediately instead of waiting for the ping — bifrost-rs.

## Code-health audit (2026-06-13)

Curated from the 2026-06-13 workspace code-health audit (full 81 findings —
18H/38M/25L — in the `audit/` run dated 2026-06-13; entry point
`audit/.../workspace-audit-synthesis-2026-06-13.md`). All High findings were
adversarially re-verified before landing here: severity-inflated items were
reframed and one false-rationale item (the NIP-44 "wrong KDF" claim) was
corrected. The remaining Medium/Low findings stay in the per-target reports.

### Correctness / CI (highest confidence)

- [x] (effort: S) **`release-validation.yml` never fires on merge — DONE (2026-06-15).**
  The `push` trigger now includes `master` (the default branch), so the release
  matrix runs post-merge, not only on PRs.
- [x] (effort: S) **bifrost-rs CI rewritten to the current layout — DONE (2026-06-15).**
  The whole `checks` matrix tested a vanished node-era architecture (bifrost-node /
  bifrost-transport-ws / bifrost-dev, devnet/test-node-e2e/tui scripts,
  node_ws_multi_peer_example) — bigger than wrong crate names. Replaced the dead
  `test-*` shards with one `cargo test --workspace` (covers every real crate incl.
  the NIP-44 KATs; rot-proof), dropped the gone runtime-e2e/check-example steps +
  the bifrost-dev regressions job, kept fmt/clippy/check/coverage/security-audit.
  **NB:** the (unchanged) clippy `-D warnings` job now surfaces pre-existing
  bifrost-profile lints — see the new item below.
- [x] (effort: S) **DONE (2026-06-15).** bifrost-profile `clippy::too_many_arguments`
  cleared with `#[allow(...)]` + rationale on the three builder/import functions
  (and a `bifrost-app` `items_after_test_module` lint that the same `-D warnings` job
  surfaced), so CI's clippy job is green. Rode the NIP-44 raw-X WASM rebuild —
  bifrost-rs `acab2b0`.

### Crypto / secret seam

- [x] (effort: M) **DONE (2026-06-15).** Hand-rolled-crypto port audit + ECDH KATs.
  Prompted by the threshold-ECDH Lagrange regression (a silent TS→Rust porting
  divergence), audited every EC/scalar operation in the core crates for the same risk.
  **Conclusion:** `bifrost-core/src/ecdh.rs` was the ONLY hand-rolled elliptic-curve
  math (now fixed + consolidated onto `frost::Identifier`); everything else delegates
  to vetted primitives — signing → `frost::round2::sign`/`aggregate`, nonces →
  `frost::round1::commit`, cosigner-message ECDH → `k256::ecdh::diffie_hellman`, NIP-44
  cipher → ChaCha20/HMAC/HKDF (pinned by `nip44_kat.rs`/`nip44_protocol_kat.rs` against
  the official vectors), event signing → k256 Schnorr, package encryption →
  XChaCha20Poly1305/Argon2 (pinned by `package_kats.rs`). No refactor needed. Locked
  the ECDH surface with spec-anchored + frost-anchored KATs (bifrost-rs `50e729a`):
  a pinned fixed-input→raw-X vector cross-checked by independent k256, asserted across
  quorums; and a reconstruct-anchored check over (2,3)/(3,5)/(3,4). Tests only — no
  blob change (stamp re-written, blobs untouched). — bifrost-rs.
- [x] (effort: M) **DONE (2026-06-15).** Unified app-facing NIP-44 on the standard
  raw-X derivation (it was a real interop bug). bifrost-core `combine_ecdh_packages`
  now returns the raw X-coordinate of the combined threshold point instead of
  `SHA256(point)` (bifrost-rs `89ee694`); since the combined point equals the point a
  normal ECDH with the group key produces, the app-facing
  `window.nostr.nip44.{encrypt,decrypt}` conversation key now matches what any
  standard nostr client derives. `deriveConversationKeyFromSharedSecret` already does
  HKDF-Extract, so it needed no code change — only its warning comment was flipped to a
  match-confirmation. **Blast radius:** the threshold secret flows only outbound to the
  app-facing NIP-44 / native `EcdhResult`; cosigner protocol messages use the *share*
  secret via `event_shared_x` (already raw-X) and were unaffected, so no flag-day and
  the NIP-44 KATs were untouched. Hard cut (alpha — no flags/migration). Coverage: a
  Rust source test pinning threshold-combine == standard ECDH raw-X
  (`combine_returns_standard_raw_x_ecdh_secret`) and a TS interop regression test
  (`igloo-shared/src/nip44-interop.test.ts`) proving FROSTR↔nostr-tools round-trips
  both directions. WASM rebuilt + re-stamped + re-vendored (shared/pwa/chrome). A real
  `@live` provider-vs-nostr-tools behavioral check remains a (non-blocking) follow-up.
  — bifrost-rs + igloo-shared.
- [x] (effort: M) **DONE (2026-06-15).** `@live` NIP-44 interop behavioral test
  (gold-standard for the raw-X fix) — added to
  `test/igloo-chrome/specs/provider-live-nip44.spec.ts`: a live 2-of-3 group encrypts
  via `window.nostr.nip44.encrypt` and a standard `nostr-tools` client decrypts it
  (and vice versa), against an external non-member counterparty. **It caught two more
  real interop bugs that the unit/source tests could not, both now fixed:**
  (1) app-facing `nip44Encrypt` emitted *unpadded* base64 (strict standard decoders
  reject it) — fixed in igloo-shared `8fccc0b`; (2) the threshold ECDH was missing
  Lagrange interpolation, so for any t-of-n with t>1 the combined secret was
  `(Σ shares)·C` not `group_secret·C` — undecryptable by a standard peer. FROSTR V1
  (`@vbyte/frost`) applies `calc_lagrange_coeff`; the Rust port had dropped it (the
  `members` quorum was threaded in but unused). Restored in bifrost-rs `d8264a4`
  (+ cross-quorum test `38bbba3`); WASM rebuilt + re-stamped + re-vendored.
  **Net:** app-facing NIP-44 now interoperates with standard nostr clients for real
  threshold groups, not just threshold-1. NIP-44 is chrome-extension-only (the PWA has
  no app-facing nip44 surface), so the test is chrome-only. — test/igloo-chrome +
  bifrost-rs + igloo-shared.

### Secret hygiene ("decide once, propagate")

- [x] (effort: S) **DONE (2026-06-16).** Zeroize `GeneratedKeyset` (igloo-home).
  `GeneratedKeyset` + `GeneratedKeysetShare` now derive `Zeroize`/`ZeroizeOnDrop`
  with a redacted `Debug` (mirroring `RecoveredGroupKey`), scrubbing the group `nsec`
  and each share's `share_package_json`; the `generatedKeyset` React state + its
  secret-bearing form drafts are nulled on create-view exit (mirroring the
  recover-key cleanup). + a Debug-redaction unit test. — igloo-home `7498e15`.
- [x] (effort: M) **PARTIAL/DONE (2026-06-16) — top flows; broader sweep remains.**
  Applied `Secret<T>` in production for the two highest-value flows end-to-end:
  profile-package decrypt/encrypt password (`Passphrase`) and onboarding shareSecret
  (`ShareSecretHex`), wrapped at the call sites and `.expose()`d only at the WASM
  boundary (igloo-shared `e247473`; pwa `3a2f6b0`; chrome `561cb49`). Bounded
  deliberately to those flows.
  - [ ] (effort: M) **Remaining `Secret<T>` sweep.** Thread the wrappers through the
    rest of the bare-`string` secret sites — chrome extension message types
    (`ProfilesUnlock/Import/ExportPackage`, `Onboarding*`), pwa session controllers,
    and the other package/onboarding call chains — for full leak-greppability ·
    surfaced 2026-06-16.

### Trust boundaries

- [x] (effort: M) **Origin-pinned the `window.postMessage` page bridge — DONE
  (2026-06-15).** The content script + injected provider now post with
  `window.location.origin` (not `'*'`) and validate `event.origin ===
  window.location.origin` on both inbound handlers, closing the cross-origin
  sniff + forge vectors. Chose origin-pin over a MessageChannel handshake (the
  audit's documented minimum; smaller diff). Unit test asserts a foreign-origin
  response is dropped — igloo-chrome.
- [x] (effort: S) **Redacted the runtime-log suffix on thrown errors — DONE
  (2026-06-15).** The breadcrumb appended to the surfaced error is now an
  allow-list of structured fields (`domain.event` + `request_id`) built from the
  observability events — never the verbatim `error_message` — igloo-pwa.

### UI correctness

- [x] (effort: S) **`activeView` dead branches removed — DONE (2026-06-15).**
  Dropped `'create-choice'` and `'settings'` from the `PwaView` union (neither had
  a render branch); the mid-create reload fallback that set `'create-choice'` (the
  blank pane) now bounces to `'landing'`, and the unused `startCreateChoice` action
  is gone — igloo-pwa.

### Demo / test hardening (low prod risk, factual)

- [x] (effort: S) **Demo passphrase off argv — DONE (2026-06-15).** `import` and
  `daemon start` now read the passphrase from a `0600` `mktemp /tmp` file via
  `--passphrase-file` (removed from `/proc/<pid>/cmdline`), cleaned up on exit.
  **Deliberately NOT done:** the `chmod 0777`/`a+rwX` on the artifact dir + socket
  are load-bearing for the demo's Docker cross-UID/mount access, and tightening
  them risks breaking the (ephemeral, hardcoded-passphrase) harness for ~nil real
  gain — frostr-infra.

### Code health (large / cross-cutting)

- [ ] (effort: L) **Break up the per-host god files.** Each control plane is a
  named coordination bottleneck: bifrost-signer `lib.rs` (4948 LOC), igloo-home
  `App.tsx` (2006), igloo-pwa `store.tsx` (2073) + `App.tsx` (1741), igloo-shared
  `BrowserBridgeNode` (1572), igloo-ui `CreateFlow.tsx` (1723). Split along
  responsibility seams, one target at a time — all targets · audit 2026-06-13.
- [ ] (effort: M) **Adopt a workspace TS formatter + lint gate.** No TypeScript
  target configures Prettier/ESLint; formatting is per-author. Add Prettier +
  ESLint (`react-hooks`) with a CI gate — this also retires the stale
  `eslint-disable` in `CreateFlow.tsx` that suppresses a rule with no ESLint
  present. Rust analog: a `rustfmt.toml` + `cargo fmt --check` gate for
  igloo-shell — workspace · audit 2026-06-13 (AES-06).

### Deprecation

- [x] (effort: S) **Removed the dead NIP-04 provider surface — DONE (2026-06-15).**
  Deleted the `nip04.{encrypt,decrypt}` provider methods, routing, permission
  labels, and the throwing execution branch (they prompted then hard-threw "not
  planned for v2") — igloo-chrome.

## Open questions

- [ ] (effort: S) Event Log Filter chips key off `badgeLabel` = domain for structured
  events but = level for the string fallback — decide whether the fallback should be
  filterable or the chips hidden when unstructured.
