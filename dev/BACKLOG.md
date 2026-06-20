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
- [ ] (effort: M) Add a **Pending Operations** component to the Paper design
  system, then align the runtime `OperatorSignerPanel` card to it; rename the
  runtime "Diagnostics" card → **Event Log** to match Paper at the same time —
  `igloo-paper` + `igloo-ui`.
- [ ] (effort: S) Confirm whether `Export Profile`/`Export Share` should keep a
  quick unencrypted copy-to-clipboard alongside the password modal — product call.
- [ ] (effort: L) Define and implement post-setup **Onboard a Device** sponsorship
  from Settings — the current sidebar action can only show an explanatory modal
  because stored browser profiles do not retain undistributed remote share secrets.
  `igloo-shared` now exposes the readiness/status helper used by PWA and a
  source-share package builder for callers that already hold the correct remote
  member source material. The `bfonboard` producer itself is already defined:
  `igloo-pwa` uses `createOnboardingPackageForShare` during create/distribute,
  `igloo-home` exposes `createGeneratedOnboardingPackage`, and `bifrost-rs`
  owns `encode_bfonboard_package`. The missing work is the Paper sponsor flow
  and a Settings-time way to obtain explicit target-member source material after
  setup.
  Restore/create/export the Paper sponsor screens first; current `igloo-paper`
  metadata includes recipient Onboard screens only. `igloo-paper`'s AppHeader
  component doc records sponsor artboards `1B3Q-0`, `1B5X-0`, `1B84-0`,
  `1BAB-0`, and `1BCI-0`, but a live Paper MCP inspection on 2026-06-20 found
  those IDs are stale references absent from the current `igloo-ui-shared` file.
  Then add a shared/app capability that can drive the existing builder from
  explicit source material without persisting raw remote shares.
  Preserve the secret boundary; do not fake this by cloning the local share. Audit:
  [`settings-sidebar-alignment-audit-2026-06-19.md`](./reports/settings-sidebar-alignment-audit-2026-06-19.md).
  Unblock plan:
  [`settings-onboard-sponsor-unblock-plan-2026-06-19.md`](./plans/settings-onboard-sponsor-unblock-plan-2026-06-19.md).
  — `igloo-paper` + `igloo-ui` + `igloo-shared` +
  `igloo-pwa` · surfaced 2026-06-19 during Settings sidebar alignment.

## bifrost-rs / igloo-shared runtime

- [ ] (effort: L) **Peer telemetry**: per-peer latency, "Avg" latency, nonce
  sparkline, and per-method SIGN/ECDH/PING capability badges — requires
  bifrost-rs + igloo-shared instrumentation; the trigger to promote the
  `dashboard-signer` visual entry to `aligned`. Spec:
  [`plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md`](./plans/bifrost-rs-peer-telemetry-and-approval-spec-2026-06-10.md).
- [ ] (effort: L) **Interactive signing-approval queue** (Deny / Allow once /
  Always allow) behind the shipped Pending-Approvals shell — per-method allow/deny
  policy already exists; this adds a wait-for-approval queue. Same spec as above.
- [ ] (effort: M) **Resilient runtime-snapshot restore**: the bootstrap now
  discards structurally-corrupt snapshots (`createBrowserRuntimeNodeInit`), but a
  snapshot that parses yet is semantically incompatible with the current runtime
  still fails at WASM restore. Add a snapshot version tag + a restore-failure
  fallback (catch the restore throw and re-bootstrap from the profile packages)
  across the browser hosts (igloo-shared + page-runtime-host + the chrome
  controller). Surfaced 2026-06-10 (per-tab isolation work, C.6).
- [ ] (effort: M) **Refactor the onboard→signer handoff to remove the
  capture-then-reinit seam.** Onboarding runs a *separate* transient runtime, then
  `connectOnboardingPackageAndCaptureProfile` snapshots it and the signer relaunches.
  The 2026-06-11 fix preserves the pool by restoring from that ephemeral snapshot, but
  the cleaner architecture is for the onboard runtime to *be* the durable signer (no
  capture/relaunch seam to lose state). Would also simplify the snapshot plumbing
  threaded through store → finalize → startSession. — igloo-shared + igloo-pwa.
- [ ] (effort: S) **Sign-miss op is mislabeled `ping` in runtime failures.** A failed
  inbound *sign* request surfaces as `failure op_type="ping" message="nonce unavailable"`
  in the runtime log (cost us real diagnosis time). Fix the host-side op-type classification
  so sign/ecdh misses aren't reported as pings — bifrost-rs (host).
- [ ] (effort: S) Pre-existing clippy nits surfaced near the nonce code: "very complex
  type" on `NoncePool`'s `HashMap<u16, HashMap<..>>` fields (factor a type alias),
  `sort_by` → `sort_by_key` in `outgoing_public_nonces`, and `&[x.clone()]` →
  `slice::from_ref` in the onboard handler — bifrost-core / bifrost-signer.

## igloo-pwa

- [ ] (effort: L) Adopt a real router for the dashboard pages — header nav still
  drives `store.activeDashboardTab`; URL deep-linking / back-button is a separate
  refactor with route-guard considerations for sensitive unlocked states.
- [ ] (effort: L) Deferred dashboard screens: error/empty states (loading,
  load-failed, all-relays-offline, signing-blocked, signing-failed).
- [ ] (effort: M) Tailored Recover "Collect Shares" panel (Paper `49W`) instead of
  reusing `RotateKeysetPanel` with an inert Source-Profile dropdown; until then
  `recover-collect-shares` stays `needs-work`.
- [ ] (effort: M) Wire encrypted export on the Recover Private Key screen — the
  Encrypt-Key checkbox/password fields render but `RecoverPrivateKeyView` saves
  plaintext nsec.
- [ ] (effort: M) Auto-include the unlocked device's own share in recover/rotate
  Collect Shares (both are paste-only today; matches Paper's "Share #1 validated").
- [ ] (effort: S) Remove or re-entry the now-orphaned `load-recover` view (dropping
  the import `load-choice` screen removed its only entry point in `App.tsx`).
- [ ] (effort: S, unsure) Make the Settings dirty-check structural rather than
  `JSON.stringify` of relays/signerSettings, if those shapes grow.
- [ ] (effort: S) Decide the fate of the redundant `RelayInput`
  (`igloo-ui/src/components/ui/relay-input.tsx`) vs the newer `RelayList`.

### igloo-pwa per-tab isolation — deferred sub-items (see 2026-06-10 plan)

- [ ] (effort: S) Rich device labeling/renaming in the instance registry UI
  (initial impl shows the id prefix + null label).
- [ ] (effort: S) Prune/cap `*.corrupt.*` quarantine copies beyond keep-newest-N.
- [ ] (effort: M) A Settings-screen affordance to delete a stored device/partition.

## igloo-chrome

- [ ] (effort: M) Deeper multi-context hardening beyond the bootstrap snapshot fix
  (see 2026-06-10 plan C.6) — review the shared background service-worker recovery
  path for stale/partial state.
- [ ] (effort: M) Adopt the igloo-ui Settings `sections` API + `ExportPackageModal`
  in igloo-chrome (still uses the flat `maintenanceActions` row + its own export).
- [ ] (effort: M) Convert the igloo-chrome e2e specs to the page-object model and
  broaden `check-e2e-selector-contracts.sh` to cover chrome.
- [ ] (effort: S) Adopt `PasswordField` (reveal-toggle input) in the chrome
  import/onboard forms (still plain `type="password"`).

## igloo-home

- [ ] (effort: L) **igloo-home is skewed against the current igloo-ui** — `eed7b7a`
  imports removed exports (`OperatorPeerPermissionState`, `OperatorPendingOperation`)
  and uses pre-Phase-B `AppHeaderProps`/`StoredProfileCardModel`/`SharedDistribution*`
  shapes; fails `make test-demo` (a required gate). Port to the current
  operator/create APIs (`src/App.tsx`, `src/pages/CreatePage.tsx`).

## Dependencies & packaging

- [ ] (effort: M) **Make `nostr-tools` a peerDependency of `igloo-shared` +
  dedupe/version-align across the igloo-\* apps.** Today it's a plain `dependency`
  of `igloo-shared` (consumed from source), and with the no-hoist submodule layout
  + `preserveSymlinks`, igloo-shared resolves its *own* copy while each app resolves
  another → two instances of a library with module-level singleton state
  (`useWebSocketImplementation`, relay pools). Consequences: split singletons (the
  WebSocket-impl injection can't reach igloo-shared's `SimplePool` — surfaced
  2026-06-10 while isolating unit-test relay I/O), likely two copies in the prod
  bundle (`vite.config.ts` only dedupes react/react-dom), and version skew
  (igloo-chrome on 2.17.2 vs igloo-pwa/shared on 2.23.3). Fix: declare it `peer` in
  igloo-shared (keep a dev/local install for its own tests), align the version in
  each consuming app, and add `resolve.dedupe: ['nostr-tools']` to app + test
  configs. Needs an install + build + e2e validation pass across all apps.

## Test harness / CI

- [ ] (effort: M) Extract the repeated Create-flow Playwright setup shared across
  `app-shell`, `rotation-create`, and `welcome-visual` specs.
- [ ] (effort: S) Give distribution cards a stable `data-test-id` so create/rotation
  specs stop locating positionally.
- [ ] (effort: S) Verify the chrome `@demo` lane (`make test-demo`) end-to-end on
  colima — only `make test-smoke` was completed previously.
- [ ] (effort: S) Silence the jsdom `--localstorage-file` Node warning in igloo-pwa
  unit runs.
- [ ] (effort: S) Investigate the PWA visual web-server `NO_COLOR`/`FORCE_COLOR`
  warning (`test/igloo-pwa/playwright.config.ts`) — config deletes both keys yet it
  still prints.
- [ ] (effort: S) Add a small regression test for
  `repos/igloo-paper/scripts/update_usage_coverage.py`.
- [ ] (effort: M) **P1** Add `@live` behavioral spec: welcome **Unlock → running,
  sign-ready** signer — unlock is only screenshotted today (`welcome-visual`) —
  Test harness · needs a cooperating peer online to reach `sign_ready`.
- [ ] (effort: M) **P1** Add `@live` behavioral spec: **Permissions** toggle
  round-trip — toggle a peer send/receive policy and assert it persists and is
  reflected in runtime peer state (`permissions-visual` only screenshots) — Test harness.
- [ ] (effort: M) **P1** Add `@live` behavioral spec: **Settings save** round-trip
  — edit signer name/relays/settings, save, reload, assert persistence through the
  real store (`settings-visual` only screenshots) — Test harness.
- [ ] (effort: M) **P2** Add `@live` behavioral spec: **Recover execution** —
  reconstruct the nsec from threshold shares; `recover-visual` injects a fake key
  via `window.__IGLOO_TEST_RECOVERED_KEY__` and only screenshots the success
  screen — Test harness.
- [ ] (effort: M) **`pwa-home-pairing` is effectively dead** — it's `@cross-client`
  (runs in NO CI lane), DISPLAY-gated, and until 2026-06-11 read the runtime
  snapshot from localStorage where it is never persisted. It now uses the corrected
  DOM-based `expectPwaSignerSignReady`, but is still unverified + ungated, and it's
  the only PWA↔native nonce-hydration coverage. Run it (xvfb), confirm it passes,
  then gate `@cross-client` in `release-validation` — or retire it — Test harness/CI.
- [ ] (effort: S) Track down the recurring `failed to publish encrypted profile
  backup: passphrase not provided` warning seen throughout the `@live` runs — likely
  benign test-path noise, but confirm it isn't masking a real backup-publish bug —
  Test harness.
- [ ] (effort: S) Close the loop on the local pre-push gate: `make test-fast` is
  render-only (seeded `@visual` specs), so a green fast run can hide a broken demo.
  Either add a minimal `@live` smoke (load profile → running dashboard) to a gate
  contributors actually run, or document plainly that fast ≠ behavioral — Test harness/CI.
- [ ] (effort: M) Promote the manual multi-PWA-tab signature to an automated spec
  (two browser contexts + igloo-shell initiator) once the manual flow is stable —
  Test harness · see the `pwa-multisig-demo` scaffolding.
- [ ] (effort: M) **Add a browser-*reload* `@live` sign test (validate the generation
  self-heal).** The onboard-handoff fix (preserve the nonce pool into the signer) and the
  bifrost-rs per-pool-generation self-heal both landed 2026-06-11; the onboard sign path is
  now hard-asserted by `sign-shell.spec.ts`. The generation resync (for a genuine reset —
  a browser reload that drops the in-memory pool) is unit-tested in bifrost-signer but not
  yet exercised end-to-end. Add an `@live` spec that signs, reloads the PWA tab (fresh
  generation), and signs again to prove the peer discards stale nonces and re-syncs — Test harness.
- [ ] (effort: S) **Optional race-safety: enrich the sign-miss response.** Today a stale-nonce
  sign converges once the resetting peer's next ping conveys its new generation. For the
  narrow window where an initiator signs *before* receiving that ping, have the responder
  return its current generation + fresh nonces on a `NonceUnavailable` miss so the initiator
  prunes-and-retries immediately instead of waiting for the ping — bifrost-rs.

## Open questions

- [ ] (effort: S) Event Log Filter chips key off `badgeLabel` = domain for structured
  events but = level for the string fallback — decide whether the fallback should be
  filterable or the chips hidden when unstructured.
- [ ] (effort: S) Confirm default peer permissions for new remote shares — the store
  initializes `sign`/`ecdh`/`ping`/`onboard` all enabled (permissive); product call.
