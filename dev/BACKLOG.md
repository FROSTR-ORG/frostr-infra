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

- [ ] (effort: S) **Export-package `@live` e2e still flakes under load.** The
  `profile-import.spec.ts › exports an encrypted profile package` test intermittently
  times out on `expect(getByTestId('export-confirm')).toHaveValue(...)` — the
  ExportPackageModal controlled-input value doesn't land within 10s under resource
  contention (observed 2026-06-15 on the 2nd of two back-to-back `make test-live`
  runs; passes in isolation and on a fresh run). A wait-hardening already shipped
  (parent `626a696`) but is insufficient under load. Make `exportProfileWithPassword`
  fill-and-poll the confirm value (or raise its wait) so it's robust under contention.
- [x] (effort: S) **DONE (2026-06-15).** The cross-repo `demo-pair-check` guard
  missed igloo-shell test drift: it ran `cargo check --bin` (bin-only), so it never
  compiled igloo-shell-core/cli **test fixtures**. bifrost-rs struct-field additions
  silently rotted the shell's struct-literal fixtures twice (2026-06-13 `PeerStatus`,
  2026-06-15 the four `RuntimeStatusSummary` host/bridge fields). Strengthened the
  `Makefile` `demo-pair-check` target to `cargo check --locked --all-targets` for the
  whole igloo-shell workspace (and bifrost-devtools), so test/bench targets compile at
  pointer-bump time. Verified it catches a dropped fixture field and passes clean.
- [ ] (effort: M) **igloo-shell full approval round-trip integration test.** The shell
  path's approval coverage is only smoke-level today (`policy_integration.rs`: an `ask`
  override persists; `runtime resolve-approval` on an unknown id is a no-op success). Add
  the shell analog of `test/igloo-pwa/specs/approval-queue.spec.ts`: two daemons, one
  initiates a sign against an `ask`-gated peer so it parks, then `runtime resolve-approval`
  (deny → fails; approve → completes a verifiable signature). Optionally add an ergonomic
  `runtime approvals` list (today operators read `pending_approvals` from `runtime status`
  JSON). Surfaced 2026-06-14.
- [ ] (effort: S) **igloo-home visual/desktop lanes are Linux-only** — `repos/igloo-home/test/visual/run.mjs`
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

- [ ] (effort: S) **Zeroize `GeneratedKeyset.nsec`.** It's a plain `String` while
  the sibling `RecoveredGroupKey` is `ZeroizeOnDrop` with a redacted `Debug`; the
  `generatedKeyset` React state is also never nulled on view-exit (unlike
  `recoveredKey`). Thread the existing pattern to both — igloo-home ·
  audit 2026-06-13.
- [ ] (effort: M) **Apply the `Secret<T>` wrapper in production.** `Secret<T>` /
  `SecretBytes` are exported but used only in tests; every production
  share-secret / seckey is a bare `string`. Thread the wrapper (or the branded
  `ShareSecretHex`/`Passphrase` aliases) to consumers for leak-greppability and
  type hygiene — igloo-shared (and likely the pwa/chrome consumers) ·
  audit 2026-06-13.

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
