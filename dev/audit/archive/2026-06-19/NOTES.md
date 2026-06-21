# Audit notes — shared scratchpad

Append-only shared memory for the agents running the current audit pass. Use it
for cross-cutting observations that don't belong to a single target's report:
patterns seen in more than one repo, "this looks like the same issue as X",
questions for the synthesis step, and dead-ends worth not repeating.

**Conventions**

- **Append only.** Don't edit or delete others' entries; add a new one.
- **One entry per observation**, newest at the bottom.
- **Header format:** `## YYYY-MM-DD HH:MM — <agent/target> — <topic>`
- Cite evidence as `repo/path:line` and the relevant rule ID (e.g. `ARC-03`).
- Cross-link with `[[anchor]]`-style references to other entries' topics when
  one observation builds on another.
- This file is reset at the start of each run; the prior run's copy is frozen in
  `archive/<date>/NOTES.md`. See [`TASKS.md`](./TASKS.md) Lifecycle.

---

<!-- Entries begin below. Template:

## 2026-06-13 14:30 — igloo-pwa finder — secret persistence
`igloo-pwa/src/lib/store.tsx:NNN` writes share secrets to localStorage in clear
(SEC-01). Same shape likely in igloo-chrome — flag for that finder to confirm.

-->

## 2026-06-19 12:00 - synthesis - secret lifecycle half-applied (T1)

`SEC-01`/`SEC-03`. Secret hygiene is applied at the onboarding boundary and
abandoned everywhere else. `igloo-shared` wraps the onboarding share secret
(`igloo-shared/src/wire/onboarding.ts:18` `share_secret: ShareSecretHex`) but
passes recovery/rotation shares as bare `string[]` and returns the reconstructed
nsec bare (`igloo-shared/src/rotation.ts:78`, `:150`), and the snapshot wire
carries a bare `seckey` (`igloo-shared/src/wire/runtime.ts:240`). The recovered
nsec then renders in plaintext in the UIs
(`igloo-ui/src/components/flows/CreateImportPanel.tsx:300` — masked beside it,
`igloo-home/src/App.tsx:1719`) and lives as an un-zeroizable JS string in every
frontend (`igloo-pwa/src/lib/types.ts:294`, `igloo-home/src/App.tsx:598`). Chrome
adds the inverse leak: it exports a derived AES master key to a bare base64
string (`igloo-chrome/src/lib/profile-blob.ts:89` `extractable: true`). Recovery
handles more secret material than onboarding with less hygiene. Wrap at the
shared boundary to propagate the discipline to the unwrapped consumers
(`igloo-pwa/.../local-adapter/profile-generate.ts`,
`igloo-chrome/.../background/router-profiles.ts`).

## 2026-06-19 12:00 - synthesis - monolith per host (T2)

`ARC-01`/`ARC-02`. Every host carries one or two god files, all equal-or-larger
than the 2026-06-13 baseline: `igloo-pwa/src/lib/store.tsx` (2161) +
`igloo-pwa/src/App.tsx` (1719), `igloo-home/src/App.tsx` (2086),
`igloo-shared/src/wasm-bridge-node.ts` (1656),
`igloo-ui/src/components/flows/CreateFlow.tsx` (1727), plus the residual
`igloo-chrome/src/pages/Onboarding.tsx` (471). `CreateFlow.tsx` is the shared
module feeding the per-host UIs. They differ sharply in payoff/risk/safety-net —
do NOT treat as one batch. Decomposition order (synthesis R2 ranking):
`CreateFlow.tsx` NOW (low coupling, barrel-level test net), home `App.tsx`
seam-first (pull `extract*` to `lib/runtime-status.ts` first), pwa `store.tsx`
after its decrypt tests, `wasm-bridge-node.ts` DEFER (thin tests, high coupling —
extract pure helpers only).

## 2026-06-19 12:00 - synthesis - one concept, N implementations (T3)

`CQ-04`/`ARC-05`/`ARC-06`/`RS-01`. `toErrorMessage` defined 4× (canonical export
`igloo-shared/src/runtime-internal.ts:81`; copies at
`igloo-shared/.../save/common.ts:14`, `.../session-orchestration/warning.ts:3`
returns `string|null`, `igloo-chrome/src/background/utils.ts`) and pwa adds a 5th
(`formatUiError`, `igloo-pwa/src/App.tsx:99`). Two `PeerPolicy` types collide by
name with divergent shape, bridged by `as` casts
(`igloo-shared/src/wasm-bridge-node.ts:108` vs
`igloo-ui/src/components/ui/peer-list.tsx:7`). Two peer-permission normalizers
re-model one wire shape (`igloo-home/src/lib/dashboard-view.ts:18`
`HomePeerPermissionState` vs `igloo-pwa/src/lib/types.ts:54`
`PwaPeerPermissionState`, both over `RuntimePeerPermissionState`). Pubkey
truncation at three widths across four sites
(`igloo-ui/src/adapters/runtime-view-models.ts:387`,
`OperatorSignerPanel.tsx:323`, `CreateFlow.tsx:853`, `peer-list.tsx:29`).
`downloadText` + the `err instanceof Error ? … : String(err)` idiom in three repos
(`igloo-home/src/App.tsx:198`, `igloo-chrome/.../SettingsPanel.tsx`,
`igloo-pwa/src/lib/file-save.ts`). Chrome's `profileKey` names three things
(`igloo-chrome/src/background/utils.ts:36`, `.../runtime-host/helpers.ts:18`,
`.../controller.rs` field). Several of these are the seams the god-file splits
need — interleave R3 with R2.

## 2026-06-19 12:00 - synthesis - tests render-only / happy-path-only (T4)

`TST-02`/`TST-03`/`TST-05`. Adversarial unlock/decrypt paths are untested across
all three hosts and `make test-fast` is render-only, so green pre-push coexists
with a broken cipher. Chrome's only real crypto is `vi.fn()`-mocked out entirely
(`igloo-chrome/tests/unit/background/profile-service.test.ts:49`;
`igloo-chrome/src/lib/profile-blob.ts` has zero direct tests — no
wrong-password/GCM-tag-flip/KAT). pwa's import/onboard decrypt boundaries are
happy-path only (`igloo-pwa/src/lib/store.tsx:1557`, `:1664`). home's
unlock/onboard/rotate flows have no adversarial frontend test and the
scrub-on-leave it relies on is asserted nowhere (`igloo-home/src/App.tsx:742`).
shared's bridge-node sign/ECDH/ping orchestration is `@live`-only
(`igloo-shared/src/wasm-bridge-node.ts:819-874`). ui has no flow-level assertion
that the nsec is masked (`igloo-ui/test/CreateImportPanel.test.tsx`). This is both
a standalone gap and the safety net the god-file splits depend on.

## 2026-06-19 12:00 - synthesis - dead-but-wired surfaces (T5)

`LEG-04`. Four exported igloo-ui flow components have zero host consumers
(Paper-redesign orphans, ~734 LOC), kept green only by their own tests:
`CreateImportPanel` (`igloo-ui/src/components/flows/CreateImportPanel.tsx`, also
hides the T1 nsec leak), `ManagedProfilesPanel`, `RecoveryWorkspace`,
`DesktopAppShell` (misleading — igloo-home uses `HostFlowShell`, not it). Plus the
unused `PeerList`/`PeerPolicy` primitive (`igloo-ui/.../peer-list.tsx`), a dead
`introMessage` prop (`igloo-ui/.../OperatorSignerPanel.tsx:19`), and dead
`readNumber` (`igloo-pwa/src/App.tsx:281`). Removal trigger: if no host imports
the four flows by the next release cut, delete them + barrel exports + tests
(resolve the nsec leak in `CreateImportPanel` first, or delete it and the leak
goes too).

## 2026-06-19 12:00 - synthesis - fabricated onboarding metadata (T6)

`RS-06`/`DOC-05`. The onboard-handshake panel hardcodes `"My Signing Key"`,
`"2/3"`, and `Share #0` (`igloo-ui/src/components/flows/CreateFlow.tsx:1541`,
`:1563`) and the PWA passes those literals during a *live* handshake
(`igloo-pwa/src/App.tsx:1069`, also `:1092` on the failed panel). A user
onboarding a 3/5 keyset is shown "2/3" as fact — fabricated metadata that can mask
a wrong-package mistake. Thread parsed package metadata or render a neutral
"Validating package…" state.

## 2026-06-19 12:00 - synthesis - Rust-shell contract drift & panic discipline (T7)

`ARC-06`/`CQ-02` (igloo-home only). The test dispatcher re-declares the real
command surface and has drifted: `EXPECTED_DISPATCH_COMMANDS` is missing 5+ real
commands incl. `resolve_approval`, `update_peer_policy`
(`igloo-home/src-tauri/src/app/test_dispatch.rs:303` vs the registration in
`.../app/commands.rs:393`), so the security-relevant permission writes have no
test-dispatch path and the self-test polices the copy, not the drift. Separately,
25 `lock().unwrap()` on IPC-reachable paths turn a poisoned mutex into a backend
crash (`igloo-home/src-tauri/src/session/controller.rs:33`). Derive the expected
set from the real registration; funnel signer-state access through one
poison-mapping helper.

## 2026-06-19 12:00 - synthesis - poll-vs-subscribe re-render churn (T8)

`ARC-03`/`CQ-07`. Hosts poll an in-process/event-pushing runtime on a fixed timer
while a subscription already fires. pwa polls every 1s
(`igloo-pwa/src/lib/store.tsx:602`) though `onOnboardComplete` push exists
(`.../page-runtime-host.ts:113`); home polls every 2s
(`igloo-home/src/App.tsx:789`) though `EVENT_SIGNER_STATUS`/`_LIFECYCLE` already
refresh (`App.tsx:850`). Re-render churn compounds it: pwa's action `useMemo` is
keyed on whole `state` (`store.tsx:2145`) and chrome's whole-store value is one
memo re-rendering all consumers per status tick (`igloo-chrome/src/lib/store.tsx:351`).
Lower-priority; attach to each host's decomposition slice.

## 2026-06-19 12:00 - synthesis - workspace hygiene: formatter + frozen versions (T10)

`AES-06`/`DOC-06`. No prettier/eslint config in ANY of the five TS targets
(`igloo-ui`, `igloo-shared`, `igloo-pwa`, `igloo-chrome`, `igloo-home`), and every
one is version-frozen with a stale/perpetual `[Unreleased]` changelog: igloo-ui
`0.0.0`, igloo-shared `0.1.0`, chrome `0.3.0`, home `0.2.0` — all last-dated
2026-03-27 despite shipped behavior (KDF fix, NIP-04 removal, origin pin, Secret
threading). One workspace-level decision each, not five per-repo fixes; tie the
changelog to `dev/docs/RELEASE.md` and land the formatter baseline BEFORE the
god-file splits so decomposition diffs are pure structure.
