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
- [ ] (effort: S) Confirm whether `Export Profile`/`Export Share` should keep a
  quick unencrypted copy-to-clipboard alongside the password modal — product call.

## bifrost-rs / igloo-shared runtime

- [ ] (effort: L) **Peer telemetry**: per-peer latency, "Avg" latency, nonce
  sparkline, and per-method SIGN/ECDH/PING capability badges — requires
  bifrost-rs + igloo-shared instrumentation; the trigger to promote the
  `dashboard-signer` visual entry to `aligned`. Spec:
  [`plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md`](./plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md).
- [ ] (effort: L) **Interactive signing-approval queue** (Deny / Allow once /
  Always allow) behind the shipped Pending-Approvals shell — per-method allow/deny
  policy already exists; this adds a wait-for-approval queue. Same spec as above.
- [ ] (effort: M) **Refactor the onboard→signer handoff to remove the
  capture-then-reinit seam.** Onboarding runs a *separate* transient runtime, then
  `connectOnboardingPackageAndCaptureProfile` snapshots it and the signer relaunches.
  The 2026-06-11 fix preserves the pool by restoring from that ephemeral snapshot, but
  the cleaner architecture is for the onboard runtime to *be* the durable signer (no
  capture/relaunch seam to lose state). Would also simplify the snapshot plumbing
  threaded through store → finalize → startSession. — igloo-shared + igloo-pwa.
- [ ] (effort: S) **Snapshot version tag (fast-path skip on top of the shipped
  restore fallback).** Resilient restore now re-bootstraps from packages when a
  snapshot fails to restore, but it still *attempts* the WASM restore first. Stamp
  a version at snapshot write and skip the restore attempt up front on a known
  mismatch — purely an optimization now that the fallback guarantees correctness.
  Must stay back-compatible (treat un-versioned snapshots as restorable) —
  igloo-shared + the snapshot write sites (surfaced 2026-06-13).
- [ ] (effort: S) **Remaining router Ping-sentinels.** The inbound-request failure
  path is now correctly typed, but `BridgeCore::tick`'s expire-tick failure and
  `fail_request_and_dispatch`'s internal failure still hardcode
  `PendingOpType::Ping` (`bifrost-router` ~257, ~519). Type them where the op is
  known; expire is a background tick so Ping may stay (surfaced 2026-06-13).

## igloo-pwa

- [ ] (effort: L) Adopt a real router for the dashboard pages — header nav still
  drives `store.activeDashboardTab`; URL deep-linking / back-button is a separate
  refactor with route-guard considerations for sensitive unlocked states.
- [ ] (effort: L) Deferred dashboard screens: error/empty states (loading,
  load-failed, all-relays-offline, signing-blocked, signing-failed). A multi-screen
  UI build; brushes the plan's "big L-effort feature builds out of scope" boundary.
  (The Clear Credentials modal `3b` + its destructive "clear this device" store
  action shipped 2026-06-13.)
- [ ] (effort: S, unsure) Make the Settings dirty-check structural rather than
  `JSON.stringify` of relays/signerSettings, if those shapes grow.
- [ ] (effort: S) Decide the fate of the redundant `RelayInput`
  (`igloo-ui/src/components/ui/relay-input.tsx`) vs the newer `RelayList`.

### igloo-pwa per-tab isolation — deferred sub-items (see 2026-06-10 plan)

- [ ] (effort: S) Rich device labeling/renaming in the instance registry UI
  (initial impl shows the id prefix + null label).

## igloo-chrome

- [ ] (effort: M) Adopt the igloo-ui Settings `sections` API + `ExportPackageModal`
  in igloo-chrome (still uses the flat `maintenanceActions` row + its own export).
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

- [ ] (effort: S) **igloo-home visual/desktop lanes are Linux-only** — `test/visual/run.mjs`
  hardcodes `/usr/bin`/`/snap` chromium paths and the desktop lane needs `xvfb-run` +
  ImageMagick `identify` + X11 `xwininfo`, so neither runs on macOS (homebrew chromium at
  `/opt/homebrew/bin`, no ImageMagick). Probe the homebrew path and degrade gracefully when
  `identify` is absent so local macOS dev can at least capture screenshots (surfaced
  2026-06-13; the `recover-key` visual scenario is registered and CI/Linux will screenshot it).
- [ ] (effort: S) **Desktop smoke for recover-key** — once the desktop lane runs (CI/Linux),
  add a `test/desktop` step that dispatches `recover_group_key` and screenshots the
  recover-key view; today it's covered by Rust unit + a vitest behavioral test only
  (`igloo-home`; surfaced 2026-06-13).
- [ ] (effort: M) **Guard against stale committed browser WASM.** The
  `igloo-shared/public/wasm` blobs had silently lagged `bifrost-rs` — committed at
  `bf_package_version 1` still exporting the removed relay-backup API, only caught
  by a manual rebuild (2026-06-13). Add a CI check that the committed blobs match a
  fresh build from the current `bifrost-rs` pointer (e.g. rebuild + `git diff
  --exit-code public/wasm`, or hash the bifrost-rs source/pointer into a stamp) so
  the browser runtime can't drift from the Rust source — Test harness/CI.
- [ ] (effort: S) **Behavioral test for the resilient-restore fallback.** Phase-1.2
  added a re-bootstrap-from-packages fallback when a persisted snapshot fails WASM
  restore; only the package-carrying half (`createBrowserRuntimeNodeInit`) is
  unit-tested. Add an integration test that feeds a structurally-valid but
  incompatible snapshot and asserts the runtime re-bootstraps (emits
  `restore_fallback_to_profile` and comes up sign-ready) — Test harness.
- [ ] (effort: S) **Flaky export test**: `profile-import.spec.ts` › "exports an encrypted
  profile package from settings" intermittently times out under load — the Export modal's
  Confirm Password fill does not land before the (disabled) Export button is clicked, so it
  waits out the timeout. Passes in isolation. Harden the `exportProfileWithPassword` page
  object (refill/verify confirm, or wait for the button to enable) or fix the
  `ExportPackageModal` controlled-input race — Test harness.
- [ ] (effort: S) Verify the chrome `@demo` lane (`make test-demo`) end-to-end on
  colima — only `make test-smoke` was completed previously.
- [ ] (effort: S) Silence the jsdom `--localstorage-file` Node warning in igloo-pwa
  unit runs.
- [ ] (effort: S) Investigate the PWA visual web-server `NO_COLOR`/`FORCE_COLOR`
  warning (`test/igloo-pwa/playwright.config.ts`) — config deletes both keys yet it
  still prints.
- [ ] (effort: S) Add a small regression test for
  `repos/igloo-paper/scripts/update_usage_coverage.py`.
- [ ] (effort: M) **`pwa-home-pairing` is effectively dead** — it's `@cross-client`
  (runs in NO CI lane), DISPLAY-gated, and until 2026-06-11 read the runtime
  snapshot from localStorage where it is never persisted. It now uses the corrected
  DOM-based `expectPwaSignerSignReady`, but is still unverified + ungated, and it's
  the only PWA↔native nonce-hydration coverage. Run it (xvfb), confirm it passes,
  then gate `@cross-client` in `release-validation` — or retire it — Test harness/CI.
- [ ] (effort: S) Close the loop on the local pre-push gate: `make test-fast` is
  render-only (seeded `@visual` specs), so a green fast run can hide a broken demo.
  Either add a minimal `@live` smoke (load profile → running dashboard) to a gate
  contributors actually run, or document plainly that fast ≠ behavioral — Test harness/CI.
- [ ] (effort: M) Promote the manual multi-PWA-tab signature to an automated spec
  (two browser contexts + igloo-shell initiator) once the manual flow is stable —
  Test harness · see the `pwa-multisig-demo` scaffolding.
- [ ] (effort: S) **Optional race-safety: enrich the sign-miss response.** Today a stale-nonce
  sign converges once the resetting peer's next ping conveys its new generation. For the
  narrow window where an initiator signs *before* receiving that ping, have the responder
  return its current generation + fresh nonces on a `NonceUnavailable` miss so the initiator
  prunes-and-retries immediately instead of waiting for the ping — bifrost-rs.

## Open questions

- [ ] (effort: S) Event Log Filter chips key off `badgeLabel` = domain for structured
  events but = level for the string fallback — decide whether the fallback should be
  filterable or the chips hidden when unstructured.
