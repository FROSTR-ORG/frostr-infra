# Backlog

Curated, forward-looking follow-up work for the `frostr-infra` workspace.
Completed work and historical audit detail live in [`HISTORY.md`](./HISTORY.md),
[`done/`](./done), and archived plans/reports. Active implementation plans live
in [`plans/`](./plans).

Format: one item per line, `- (effort: S|M|L) <summary> — <area> · <why/source>`.
Remove an item when it ships; record durable completion context in
[`HISTORY.md`](./HISTORY.md) or a completed plan when the change needs more than
the commit message.

Last pruned: 2026-06-23. This pass removed completed audit rows, declined
formatter/lint adoption, duplicate follow-ups, stale file/line references, and
low-benefit optional tasks.

## Priority Queue

- (effort: M) Fix create-flow Select Share layout and group-key presentation — `igloo-ui` + `igloo-pwa` · `UX-004`/`UX-005`: half-screen overflow is user-visible, and the group key panel should be info-only with `npub` plus hex.
- (effort: M) Standardize permission chip/toggle colors across create distribution and runtime permissions — `igloo-ui` · `UX-008`/`UX-011`: permission color vocabulary should be shared and visible in active/inactive states.
- (effort: M) Guard the shared-UI consumption contract — `test/` · prevent `igloo-ui/dist`, old `build:ui` paths, local client `theme.extend`, or divergent CSS entrypoints from reappearing after ADR-014.
- (effort: S) Avoid Chrome snapshot ticks decrypting/re-encrypting share plaintext — `igloo-chrome` · the unlock key is now a non-extractable `CryptoKey` with no `sessionKeyB64` (verified 2026-06-26); the remaining concern is that periodic snapshot persistence should not round-trip share plaintext through decrypt/re-encrypt.
- (effort: M) Unify and harden dev-scenario seams — `igloo-shared` + pwa/chrome/home + `test/` · one scenario registry/param, shared fixture coverage beyond `dashboard-running`, reviewer nits, and no production-bundle fixture drift.
- (effort: M) Finish Paper dashboard/runtime settings alignment — `igloo-ui` + pwa/home/chrome + `igloo-paper` · signer dashboard foundation is correct, but permissions/settings should converge on the Paper settings/sidebar model (`UX-010`/`UX-012`).

## Shared UI And Product Polish

- (effort: S) Remove or implement create-flow help/info icons — `igloo-ui` · `UX-001`/`UX-002`: visible help affordances need accessible hover/focus content, otherwise they should not imply an inactive tooltip.
- (effort: M) Add shared interaction, loading, and transition states — `igloo-ui` + clients · `UX-009`: buttons, rows, task steps, and async actions should expose hover/press/focus/disabled/loading states consistently.
- (effort: S) Migrate the PWA recovery "Encrypt Key" control to shared `Checkbox` — `igloo-pwa` + `igloo-ui` · needs a replace-base-row class variant or a small restyle because `igloo-recover-encrypt-toggle` is not the standard `igloo-toggle-row`.
- (effort: S) Fix Home returning-profile Rotate to seed rotate mode — `igloo-home` · the profile menu currently lands on create-new mode instead of a rotate flow seeded with the source profile.
- (effort: S) Add cancel/collapse for Chrome returning-hero Onboard/Import forms — `igloo-chrome` · returning users can reveal either form but cannot dismiss it without reload.
- (effort: S) Remove dead Chrome landing state or wire row-level busy feedback — `igloo-chrome` · `activatingProfileId`/`deletingProfileId` are write-only after the shared landing migration.
- (effort: S) Show structured `groupKey`/`shareKey` rows in the Chrome signer dashboard — `igloo-chrome` · bring Chrome into parity with PWA's split-copy npub/hex dashboard key controls.
- (effort: S) Document `igloo-ui` source-only consumption — `repos/igloo-ui/README.md` · package `main`/`types`/`exports` point at `src/index.ts`; current README still describes compiled stylesheet consumption.

## Dedup And Model Cleanup

- (effort: S) Finish `toErrorMessage` consolidation — `igloo-shared` + `igloo-chrome` + pwa · `igloo-shared` has the canonical helper, but Chrome still has local forks in background/runtime-host helpers and PWA still has a thin UI wrapper worth reviewing.
- (effort: M) Resolve peer-policy/readiness model divergence — `igloo-shared` + `igloo-ui` + pwa/home/chrome · converge peer permission/readiness inputs on the shared projections and retire the unused `PeerList`/`PeerPolicy` primitive once `OperatorSignerPanel` rows are confirmed canonical.
- (effort: S) Centralize pubkey/timestamp formatting decisions — `igloo-ui` · existing truncation widths differ intentionally in places; decide canonical helpers and preserve deliberate exceptions instead of blindly deduping.
- (effort: S) Finish low-level shared helper cleanup — `igloo-shared` · `downloadText` is consolidated; remaining value is narrowing `normalizeHex32`/`hexToBytes32` and reconciling throwing vs non-throwing relay normalization APIs.
- (effort: S) Lift remaining accidental dashboard view-model duplicates — `igloo-ui`/`igloo-shared` + clients · adopt shared projections where they remove local copies, while keeping host glue local.

## Security And Secret Hygiene

- (effort: M) Complete the remaining post-beta `Secret<T>`/secret-wrapper sweep — C5 beta scope is closed for snapshot restore plus shared rotation/recovery; still open: Chrome message types, PWA session-controller bare-string paths, and any broader frontend transient-secret helper work that is not required for the beta gate.
- (effort: S) Add a browser/Tauri transient-secret convention — pwa/home/shared · passphrases, nsec values, and share passwords need a common lifetime/scrub discipline where JS can actually wipe bytes.
- (effort: S) Factor sensitive reveal/copy behavior — `igloo-ui` · share the auto-remask timer, remove duplicate copy/remask blocks, and either best-effort clear clipboard secrets or explicitly document why not.
- (effort: S) Add the remaining create-flow generated-share mask assertion — `igloo-ui` · recovery-view nsec masking is covered; the generated-share flow-level assertion is still the open part of the R6.1 safety net.
- (effort: M) Add the remaining adversarial decrypt-path tests (C4 tail) — `igloo-pwa` · shared NIP-44 wrapper and Home unlock/rotate/recover handler coverage are in place; remaining tail is a real-WASM (un-mocked) wrong-password/corrupted-package test in PWA.
- (effort: M) Add explicit single-active-signer locking across PWA tabs — `igloo-pwa` · global profile storage removed the implicit same-device isolation; acquire a per-profile lock before starting signer sessions.
- (effort: S) Provide per-repo or org-level community-health files — `FROSTR-ORG` · Phase 0 added `SECURITY.md` + `CODE_OF_CONDUCT.md` only at the workspace root, but the launch clients go public as separate repos; add an org `.github` repo (or per-repo copies) and enable **GitHub Private Vulnerability Reporting** on every repo before the public flip.

## Runtime And Browser Lifecycle

- (effort: L) Investigate signer bring-up performance — `bifrost-rs` + `igloo-shell` + test harness · demo onboarding spends roughly 18s reaching onboard-ready and about 12s per onboard export; identify deterministic ready signals or parallelizable relay work.
- (effort: M) Collapse Chrome's onboard-to-signer seam where possible — `igloo-chrome` + `igloo-shared` · PWA now adopts the live onboarding node; Chrome still captures/restores snapshots because of MV3 lifecycle, so it needs a separate careful design.
- (effort: S) Add snapshot version tags for Chrome restore fast-paths — `igloo-shared` + `igloo-chrome` · skip doomed WASM restore attempts on known incompatible snapshots while treating unversioned snapshots as restorable.
- (effort: L, spike first) Evaluate moving `igloo-home` signer hosting to a sidecar daemon — `igloo-home` + `bifrost-app` + test harness · could decouple the native signer from Tauri and simplify desktop test orchestration.
- (effort: M) Add a behavioral resilient-restore fallback test — integration/demo lane · feed an incompatible but structurally valid snapshot, assert `restore_fallback_to_profile`, and reach sign-ready with real WASM + relay.

## Test Harness And CI

- (effort: M) Add signed macOS DMG release flow for `igloo-home` — `igloo-home` + release tooling · Developer ID signing, notarization, staple validation, and credential documentation are deferred until after the unsigned beta artifact primitive ships.
- (effort: M) Add Linux deb/rpm packages for `igloo-home` — `igloo-home` + release tooling · beta release only requires AppImage; distro-specific packages are post-beta packaging polish.
- (effort: M) Add GitHub Actions release workflow for `igloo-home` artifacts — release tooling · run the root package primitive and upload the staged directory to a draft release once local artifact/checksum staging is proven.
- (effort: M) Finish the test-secrets/seed-builder consolidation — `test/` · replace remaining inline canonical password literals, add a guard banning reintroduction, and converge Chrome/Home seed builders on one input model where practical.
- (effort: M) Finish the cross-client visual manifest/guard — `test/` + home/chrome · shared capture helper exists, but only PWA has a manifest-level visual inventory.
- (effort: S) Fix or explicitly exempt `@agent` screenshot specs from selector-contract guards — `test/` · this is the live blocker for making `test:guards:full` green without demoting it to advisory.
- (effort: M) Upgrade `igloo-pwa` to Vite 8 to clear the dev-server esbuild advisory — `igloo-pwa` · a breaking major bump; the remaining `npm audit` finding is dev-only (esbuild dev-server CORS) and not in the shipped static bundle, so it is deferred rather than rushed.
- (effort: S) Fix Home `dashboard-signer` visual scenario so it renders a running dashboard — `igloo-home` · current injected scenario still shows a loading/restoring state.
- (effort: S) Find and stop leaked `bifrost-devtools relay` processes — `test/` · local live/demo runs have left orphaned relays; identify the fixture or webServer path and add teardown.
- (effort: S) Resolve the igloo-ui showcase tag/gate mismatch — `test/` · the spec is tagged `@fast` but does not run in the normal `make verify` fast lane.
- (effort: M) Gate or retire the cross-client pairing specs — `test/` · `chrome-pwa-pairing` and `pwa-home-pairing` are valuable but outside default lanes; re-run after WASM provenance fixes and either gate them in release validation or delete them.
- (effort: S) Make `make verify` affected-aware — root scripts + `test/` · route through affected-client selection instead of always running full PWA + Chrome fast lanes.
- (effort: S) Enrich `.tmp/agent/verify.json` with per-command results — root scripts + `test/` · agents should not need to scrape logs to identify the failing lane.
- (effort: M) Improve `make dev` verification and auto-seeding — root scripts + PWA/test · seed the dev profile directly and prove the running dashboard headlessly after the native loop starts.
- (effort: S) Harden `make dev` daemon socket path — root scripts · use the established socket path-shortener instead of a deep `TMPDIR` path near macOS `sun_path` limits.
- (effort: S) Exercise `make bump-pointers PUSH=1` against a real remote once — root scripts · stage/commit/dry-run paths are tested; the push-submodules path still needs one real validation before release reliance.
- (effort: M) Add WASM watch/build-on-demand and revisit committed-WASM maintenance — root scripts + shared/PWA/Chrome · reduce double-maintenance while preserving provenance checks.
- (effort: S) Refresh dependency audit and update dev tooling if still applicable — JS clients · the old esbuild advisory was dev-tooling only; verify current `npm audit` before doing any package churn.

## Design / Paper

- (effort: S) Promote the `dashboard-signer` visual entry to aligned — `igloo-paper` + visual lane · blocking peer telemetry shipped; re-shoot and update status against Paper `1-signer-dashboard`.
- (effort: M) Add Browser Settings to Paper Settings artboard `502-0` — `igloo-paper` · PWA-only settings need a design counterpart before settings-sidebar convergence.
- (effort: S) Make identity/runtime card dashboard-only in Paper — `igloo-paper` · remove repeated header treatment from Permissions/Settings artboards to match runtime direction.
- (effort: S) Add Pending Operations to the Paper design system — `igloo-paper` · runtime already has the card; Paper should carry the component contract.
- (effort: S) Sync Pending Approvals and tri-state permissions to Paper — `igloo-paper` · approval queue and allow/ask/deny/unset controls shipped in runtime.

## Open Questions

- (effort: S) Decide Event Log fallback filtering semantics — `igloo-ui` · structured events filter by domain, string fallback events label by level; choose whether fallback chips are useful or should be hidden.
