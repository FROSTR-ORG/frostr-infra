# Workspace audit synthesis

Date: 2026-06-19

Scope: the five front-end targets — `igloo-ui`, `igloo-shared`, `igloo-pwa`,
`igloo-chrome`, `igloo-home`. Excluded this pass: `bifrost-rs` (Rust signing
core; its crypto fixes were verified in the reconcile, not re-audited here),
`igloo-shell`, and `igloo-paper` (reference-only). The 2026-06-13 High-severity
correctness/trust-boundary work is confirmed landed by the reconcile pass; this
synthesis is about the durable structural and semantic debt underneath it.

The shape of the front-end debt is consistent and now well-characterized: the
High-urgency *correctness* layer is healthy — the NIP-44 KDF is fixed and
interop-tested, the Chrome page bridge is origin-pinned, the dead NIP-04 surface
is gone, `GeneratedKeyset` zeroizes Rust-side. What remains is **stable
architectural and semantic debt that every per-host signing change has to pay
interest on**, and it concentrates in five recurring patterns rather than
scattering. (1) Every host is a *monolith* — one or two files (`store.tsx`,
`App.tsx`, `CreateFlow.tsx`, `wasm-bridge-node.ts`) own every flow, and every one
is the same size or larger than the 2026-06-13 baseline. (2) The same concepts
are *re-modeled and re-implemented per host* — two `PeerPolicy` types, two
peer-permission normalizers, `toErrorMessage` defined 4–5 times, `downloadText`
in three repos, pubkey-truncation at four widths. (3) *Secret hygiene is
half-applied* — `Secret<T>` stops at the onboarding boundary while
recovery/rotation and every JS-frontend hold bare strings, and the recovered nsec
renders in plaintext in three UIs. (4) *Tests are render-only / happy-path-only*
on exactly the adversarial unlock/decrypt paths a signing host lives by, and
Chrome's only real crypto is mocked out entirely. (5) *Workspace hygiene gaps* —
no enforced formatter and frozen versions/changelogs — exist identically in all
five and should be decided once.

The most important framing for sequencing: the monoliths (theme 2) and the test
gaps (theme 4) are coupled. Several god files have only render-level safety nets,
so decomposition is riskier than it looks; the testing-depth work is the safety
net the decomposition needs, and the dedup work (theme 3) is what makes the seams
extractable. The two genuinely standalone Highs — the `igloo-ui` plaintext-nsec
leak and Chrome's home-rolled, untested cipher — are the only items that are
about *risk now* rather than *cost later*, and should lead.

## Highest-signal items

The cross-cutting issues worth acting on first, in priority order. Each
aggregates the per-target findings it spans.

1. **C1 — Recovered nsec rendered in plaintext across the recovery UIs** —
   `SEC-01`. `igloo-ui/src/components/flows/CreateImportPanel.tsx:300` renders a
   full recovered root private key into a bare `<dd>` while the *less* sensitive
   group/share package JSON two lines below is wrapped in `SensitiveTextarea` — an
   inverted threat model sitting in the public package surface. The same
   bare-string recovered nsec renders in `igloo-home/src/App.tsx:1719-1740` and
   lives in `igloo-pwa` React state (`App.tsx:469`). This is the one defect that
   is a leak *today*, not a cost-later, and it ships from a "tested" component
   (the test asserts the nsec *appears*, never that it is masked). Fix the
   masking and add the masking/scrub assertions (`TST-02`) as the regression net.

2. **C2 — Chrome's home-rolled profile cipher is both divergent and untested** —
   `SEC-03`/`TST-05`/`TST-03`. `igloo-chrome/src/lib/profile-blob.ts:34` is an
   independent PBKDF2-200k + AES-GCM stack outside igloo-shared's `Secret<T>` /
   Argon2id, and it deliberately exports its derived master key to a bare base64
   string (`extractable: true` at `:89`) that then persists as a plain string and
   is reconstructed on every `runtime-status` tick (`snapshot-persistence.ts:25`).
   It is `vi.fn()`-mocked out of every test
   (`profile-service.test.ts:49`), so wrong-password / GCM-tag-failure behavior is
   entirely unasserted — the host's only real crypto rests on nothing. This is the
   single most security-critical module in the five targets and the highest-value
   pairing of a `SEC` and a `TST` finding.

3. **C3 — Monolith per host: four+ god files, all grown since baseline** —
   `ARC-01`/`ARC-02`. `igloo-pwa/src/lib/store.tsx` (2161) + `App.tsx` (1719),
   `igloo-home/src/App.tsx` (2086), `igloo-shared/src/wasm-bridge-node.ts` (1656),
   `igloo-ui/src/components/flows/CreateFlow.tsx` (1727). Every one is equal-or-
   larger than 2026-06-13; `CreateFlow.tsx` is the shared module feeding the
   per-host UIs. These are the dominant structural debt, but they vary sharply in
   payoff/risk/safety-net (see the R2 ranking) — they are *not* a single batch.

4. **C4 — Adversarial unlock/decrypt paths untested across all three hosts** —
   `TST-02`/`TST-03`/`TST-05`. The import/onboard decrypt boundaries
   (`igloo-pwa/src/lib/store.tsx:1557,1664`), Chrome's provider + cipher arms, and
   igloo-home's unlock/onboard/rotate flows (`igloo-home`) all have happy-path-only
   coverage; the bridge node's `signNostrEvent`/`nip44Encrypt`/`pingPeer`
   orchestration (`igloo-shared/src/wasm-bridge-node.ts:819-874`) is `@live`-only.
   `make test-fast` is render-only, so a green pre-push coexists with a broken
   cipher or a bypassed guard. This is both a standalone gap and the safety net
   C3's decomposition depends on.

5. **C5 — `Secret<T>` discipline stops at the onboarding boundary** — `SEC-01`.
   `igloo-shared` wraps the onboarding share secret (`wire/onboarding.ts:18`) but
   passes recovery/rotation shares as bare `string[]` and returns the reconstructed
   nsec bare (`rotation.ts:78,150`); the snapshot wire carries bare `seckey`
   (`wire/runtime.ts:240`). Every JS frontend then holds passphrases/nsec as
   un-zeroizable strings (`igloo-pwa/src/lib/types.ts:294`,
   `igloo-home/src/App.tsx:598`). Recovery handles *more* secret material than
   onboarding with *less* hygiene. Wrapping at the shared boundary is what would
   propagate the discipline outward to the hosts that consume it unwrapped
   (`igloo-pwa/.../profile-generate.ts`, `igloo-chrome/.../router-profiles.ts`).

6. **C6 — One concept, N implementations: `toErrorMessage`, peer models,
   pubkey/timestamp format, `downloadText`** — `CQ-04`/`ARC-05`/`ARC-06`/`RS-01`.
   `toErrorMessage` is defined 4× in shared+chrome and pwa adds a 5th
   (`formatUiError`, `igloo-pwa/src/App.tsx:99`) despite a canonical export at
   `igloo-shared/src/runtime-internal.ts:81`. Two `PeerPolicy` types collide by
   name with divergent shapes (`igloo-shared/.../wasm-bridge-node.ts:108` vs
   `igloo-ui/.../peer-list.tsx:7`, bridged by `as` casts). Two peer-permission
   normalizers re-model one wire shape (`igloo-home/.../dashboard-view.ts:18` vs
   `igloo-pwa/src/lib/types.ts:54`). Pubkey truncation appears at three widths
   across four sites; `downloadText` lives in three repos. These are low-risk,
   high-clarity, and several are the seams the god-file splits need.

7. **C7 — Dead-but-wired surfaces kept alive by their own tests** — `LEG-04`.
   Four exported igloo-ui flow components (`CreateImportPanel`,
   `ManagedProfilesPanel`, `RecoveryWorkspace`, `DesktopAppShell`, ~734 LOC) have
   zero host consumers — leftover Paper-redesign orphans whose unit tests give
   false coverage confidence (and one hides the C1 leak). `DesktopAppShell` is
   actively misleading: igloo-home uses `HostFlowShell`, not it. Plus the unused
   `PeerList`/`PeerPolicy` primitive, a dead `introMessage` prop
   (`OperatorSignerPanel.tsx:19`), and dead `readNumber` (`igloo-pwa/App.tsx:281`).

8. **C8 — Fabricated onboarding metadata shipped into a live flow** —
   `RS-06`/`DOC-05`. The onboard-handshake panel hardcodes `"My Signing Key"`,
   `"2/3"`, and `Share #0` (`igloo-ui/.../CreateFlow.tsx:1541`) and the PWA passes
   those literals during a live handshake (`igloo-pwa/src/App.tsx:1069`). A user
   onboarding a 3/5 keyset is shown "2/3" as fact — fabricated metadata that can
   mask a wrong-package mistake.

9. **C9 — Test/IPC contract drift and panic discipline in the Rust shell** —
   `ARC-06`/`CQ-02`. `igloo-home`'s test dispatcher re-declares the real command
   surface and has drifted: 5+ real commands (incl. `resolve_approval`,
   `update_peer_policy`) are missing from `EXPECTED_DISPATCH_COMMANDS`
   (`test_dispatch.rs:303`), so the security-relevant permission writes have no
   test-dispatch path. Separately, 25 `lock().unwrap()` sites on IPC-reachable
   paths turn a poisoned mutex into a backend crash (`session/controller.rs:33`).

10. **C10 — Workspace hygiene: no formatter, frozen versions** — `AES-06`/`DOC-06`.
    No prettier/eslint config exists in *any* of the five TS targets, and every
    one is version-frozen with a stale or perpetual `[Unreleased]` changelog
    (igloo-ui `0.0.0`, igloo-shared `0.1.0`, chrome `0.3.0`, home `0.2.0`, all
    last-dated 2026-03-27). These are one workspace-level decision each, not five
    per-repo fixes, and a formatter baseline is worth landing *before* the god-file
    splits so decomposition lands on stable formatting.

## Theme map

| Theme | Domains | Where it shows up |
|---|---|---|
| T1 — Secret lifecycle half-applied | `SEC-01`, `SEC-03` | ui Finding 1 (`CreateImportPanel.tsx:300`); home Finding 5 (`App.tsx:598`); pwa Finding 12 (`types.ts:294`); shared Finding 2 (`rotation.ts:78`, `wire/runtime.ts:240`); chrome Finding 1 (`profile-blob.ts:89` exported master key) |
| T2 — Monolith per host | `ARC-01`, `ARC-02` | pwa Findings 1–2 (`store.tsx`, `App.tsx`); home Finding 1 (`App.tsx`); shared Finding 1 (`wasm-bridge-node.ts`); ui Finding 3 (`CreateFlow.tsx`); chrome Finding 4 (`Onboarding.tsx`, 471 LOC page) |
| T3 — One concept, N implementations | `CQ-04`, `ARC-05`, `ARC-06`, `RS-01` | shared Findings 3–5 (`toErrorMessage`, hex/relay, `PeerPolicy`); pwa Findings 4,6 (`formatUiError`, ~25 draft updaters); chrome Finding 3 (`profileKey` ×3); home Findings 4,9 (peer-permission re-model, `downloadText`); ui Findings 5–6 (dual peer model, pubkey/timestamp ×4) |
| T4 — Tests render-only / happy-path-only | `TST-02`, `TST-03`, `TST-05` | chrome Finding 2 (cipher mocked); pwa Finding 7 (import/onboard decrypt); home Finding 7 (unlock/onboard/rotate); shared Finding 6 (node orchestration); ui Finding 8 (no secret-mask assertion) |
| T5 — Dead-but-wired surfaces | `LEG-04` | ui Findings 2,5,7 (4 orphan flows, unused `PeerList`, dead `introMessage`); pwa Finding 9 (`readNumber`) |
| T6 — Fabricated / misleading data | `RS-06`, `DOC-05` | ui Finding 4 + pwa Finding 10 (`"My Signing Key"`/`"2/3"`/`Share #0`) |
| T7 — Contract drift & panic discipline (Rust) | `ARC-06`, `CQ-02` | home Findings 2,6 (test dispatcher drift; 25 `lock().unwrap()`) |
| T8 — Poll-vs-subscribe re-render churn | `ARC-03`, `CQ-07` | pwa Finding 3 (1s poll); home Finding 3 (2s poll); chrome Finding 10 (whole-store memo); pwa Finding 1 (action memo keyed on state) |
| T9 — Type escapes at boundaries | `CQ-03`, `DOC-04` | shared Finding 9 (`as unknown as` drain casts); pwa Finding 5 (re-cast typed field); chrome Finding 5 (`sessionKeyB64!`) |
| T10 — Workspace hygiene | `AES-06`, `DOC-06` | all five: ui 10–11, shared 10, pwa 11, chrome 8–9, home 8 |
| T11 — Magic values / leaky barrels | `CQ-06`, `ARC-04`, `RS-05` | shared 8 (device-config block); chrome 6–7 (`export *`, PBKDF2/retry consts); pwa 8 (`export *`); ui 9 (`30000` remask) |

## Severity rollup

| Target | H | M | L | Total |
|---|---|---|---|---|
| `frostr-infra` | — | — | — | not audited |
| `bifrost-rs` | — | — | — | not audited (reconcile only) |
| `igloo-shared` | 2 | 6 | 2 | 10 |
| `igloo-ui` | 3 | 5 | 3 | 11 |
| `igloo-pwa` | 2 | 6 | 4 | 12 |
| `igloo-chrome` | 2 | 4 | 4 | 10 |
| `igloo-home` | 3 | 4 | 3 | 10 |
| `igloo-shell` | — | — | — | not audited |
| **Totals** | **12** | **25** | **16** | **53** |

## Prioritized buckets

Findings grouped by *where the change lives* and mapped to remediation buckets
R1–R6.

- **R1 — Quality gate (workspace-level)** — adopt one shared prettier (+ light
  eslint) config the five leaves extend, gate it in `make verify`, and convert
  the frozen versions/changelogs to an `[Unreleased]`-accruing, release-bumped
  process tied to `dev/docs/RELEASE.md`. Aggregates `AES-06`/`DOC-06` from all
  five (ui 10–11, shared 10, pwa 11, chrome 8–9, home 8). One decision, five
  consumers. Land before R2 so decomposition diffs aren't noise.

- **R2 — God-file decomposition (per host, ranked — see table)** — the C3
  monoliths. These are *not* one batch; payoff/risk/safety-net differ per file.
  See the ranking table below for RECOMMEND-NOW vs DEFER.

- **R3 — Dedup / consolidation (shared + cross-host)** — C6. Promote one
  `toErrorMessage` (`igloo-shared/src/runtime-internal.ts:81`) and delete the 4
  copies; one peer-permission normalizer in shared/ui consumed by both hosts;
  resolve the `PeerPolicy` collision (rename or collapse to one typed read model);
  one `lib/format.ts` for pubkey-truncation + epoch-normalization; one shared
  `downloadText` + error-coercion util; rename chrome's `profileKey` ×3 by
  meaning. Several of these are the seams R2 needs, so interleave.

- **R4 — Dead-surface removal (mostly igloo-ui)** — C7. Removal trigger: if no
  host imports the four orphan flow components by the next release cut, delete them
  + barrel exports + tests (`igloo-ui` Findings 2,5); delete dead `introMessage`
  (`OperatorSignerPanel.tsx:19`) and `readNumber` (`igloo-pwa/App.tsx:281`).
  Resolve C1 inside `CreateImportPanel` *before* deciding its fate, or delete it
  and the leak with it.

- **R5 — Secret hygiene (shared boundary + UIs)** — C1 + C5 + C8. Mask the
  recovered nsec in all three recovery UIs (the C1 leak first); thread
  `ShareSecretHex`/`Secret`-wrapping through rotation/recovery and decide the
  snapshot-wire `seckey` policy in igloo-shared; introduce a minimal JS
  transient-secret helper for the browser/Tauri frontends; replace the fabricated
  onboard-handshake metadata with parsed values or a neutral state. Chrome's
  exported-master-key half of C2 lives here too (keep the `CryptoKey`
  non-extractable, pass the handle not a base64 string).

- **R6 — Testing depth (per host + shared)** — C2 + C4. Highest-value: a direct
  `profile-blob.test.ts` for Chrome (round-trip, wrong-password reject, GCM-tag
  flip, KAT vector) and unwrap the mocks; adversarial import/onboard decrypt tests
  in pwa and home (wrong password, corrupted package → error view + secret
  cleanup); a secret-mask/scrub assertion in ui and home (asserts the nsec is *not*
  in initial DOM, and is cleared on view-leave); failure-path unit tests for the
  bridge node's sign/ECDH/ping orchestration in shared, added *as each seam is
  extracted* in R2.

Rust-shell items (C9: home test-dispatcher drift `test_dispatch.rs:303`,
`lock().unwrap()` poison discipline) sit alongside R6/R3 but are igloo-home-local;
derive the expected-command set from the real registration and funnel signer-state
access through one poison-mapping helper.

### R2 — God-file decomposition ranking

| File | LOC | Seams | Payoff | Risk | Test safety-net | Recommendation |
|---|---|---|---|---|---|---|
| `igloo-ui/src/components/flows/CreateFlow.tsx` | 1727 | 6 (generate / rotate / local-save / distribution / onboard-import / recover / onboard-handshake) | High — shared module, 31 barrel entries route through it, almost every create/rotate/onboard change touches it | **Low** — presentational, prop-driven, few shared closures | Good — `test/CreateFlow.test.tsx` (786 LOC) imports through the barrel and survives a re-export-preserving split | **RECOMMEND NOW** — best payoff/risk ratio; low coupling + a barrel-level net make the six-way split mechanical |
| `igloo-pwa/src/lib/store.tsx` | 2161 | 8 journey slices (hydration / persistence / runtime-lifecycle / create / import / onboard / rotate / recover) + a generic `updateDraft`/`updateSecret` collapse of ~25 methods | High — every pwa flow + the action-memo-keyed-on-state re-render bug route here | **Medium** — 40 methods share one closure scope; secret/persistable partition must be preserved across the split | Partial — unit suite exists but the riskiest decrypt boundaries are happy-path-only (C4) | **RECOMMEND NOW (staged)** — start with the pure hydration/normalization slice + the `updateDraft`/`updateSecret` collapse (mechanical, shrinks the file materially), but add the import/onboard adversarial tests (R6) before touching those slices |
| `igloo-shared/src/wasm-bridge-node.ts` | 1656 | 6 (relay-lifecycle / 3 bootstrap modes / onboarding round-trip / pump / command-chain / NIP-44) | High — every host's signing path routes through it | **High** — heavy behavior-coupling, `emit`/`emitLog` side effects throughout `pumpRuntime`; header asserts concerns "not separable without a behavior-changing rewrite" | **Thin** — no unit coverage of the four bootstrap modes, sign/ECDH/ping, or pump dispatch; a seam cut leans on `@live` only | **DEFER (extract pure helpers only)** — pull the already-pure pieces (`requestOnboardResponse`, device-config builder, `buildProfileBootstrap`) with a test added per extraction; defer the `connect`-mode split until the R6 failure-path tests exist |
| `igloo-home/src/App.tsx` | 2086 | 7 views + `extract*` runtime-status parsers + poll loop | High — nearly every desktop change routes here | **Medium** — handlers close over shared `run()`/`refresh*`; a page-split precedent (`CreatePage.tsx`) already exists for 1 of 7 views | Thin — `App.test.tsx` (292 LOC) renders shell + peer-refresh; no flow handler is unit-covered | **RECOMMEND NOW (seam-first)** — pull the `extract*` parsers into `lib/runtime-status.ts` (low-risk, independently testable) first, then lift views into `src/pages/` following the existing precedent |
| `igloo-pwa/src/App.tsx` | 1719 | 16 `renderX` view closures + 10 dashboard-view derivers | High — every pwa route's layout | **Medium** — `renderX` closures capture `store`/`run`/local state | Partial — same suite as store.tsx; render-level | **RECOMMEND NOW (after store.tsx)** — move the `derive*DashboardView` functions to `lib/dashboard-view.ts` (React-free, unit-testable) first, then promote `renderX` to `views/*.tsx`; do after the store split so the props each view needs are settled |
| `igloo-chrome/src/pages/Onboarding.tsx` | 471 | 6 flows (connect / save / import / activate / unlock / delete) sharing one error slot | Medium — chrome already decomposed its background well; this is the residual page monolith | Low-Medium — per-flow state is fairly independent | Decent — 24 unit suites, though the crypto path is mocked (C2) | **DEFER** — smaller than the others and lower-traffic; fold into the per-flow split after C2's cipher tests land so the unlock flow can be split with real coverage |

## Suggested sequence

Single-threaded order, highest marginal signal first.

1. **C1 + the masking test (R5 + R6, ~hours).** Mask the recovered nsec in
   `CreateImportPanel`, `igloo-home/App.tsx`, and the pwa recovery view, and land
   the "nsec not in initial DOM / cleared on leave" assertions. This is the only
   *leak-now* item and the test becomes the regression net for everything after.

2. **C2 cipher tests, then de-divergence (R6 → R5, ~1–2 days).** Add the direct
   `profile-blob.test.ts` and unwrap the mocks first (proves the current cipher),
   *then* decide the KDF home and stop exporting the master key to a bare string.
   Tests before the change so the security-critical refactor has a net.

3. **R1 quality gate (~half a day, one decision).** Land the shared formatter +
   `[Unreleased]` changelog convention before the big splits so decomposition
   diffs are pure structure, not reformatting.

4. **R3 dedup of the seams the splits need (~1–2 days).** Consolidate
   `toErrorMessage`, the peer-permission normalizer, the `PeerPolicy` collision,
   and `lib/format.ts`. These shrink the god files and unblock clean extraction.

5. **R2 in ranked order (~1–2 weeks, staged).** `CreateFlow.tsx` first (lowest
   risk, best ratio), then igloo-home `App.tsx` (seam-first), then pwa `store.tsx`
   (after its R6 decrypt tests) and `App.tsx`. Hold `wasm-bridge-node.ts` and
   chrome `Onboarding.tsx` until their failure-path tests exist — extract only the
   pure helpers from the bridge node in the meantime.

6. **R4 dead-surface removal at the release cut.** Delete the four orphan ui
   flows + tests (after C1 resolves `CreateImportPanel`), `introMessage`,
   `readNumber`, and the unused `PeerList` if `OperatorSignerPanel.PeerRow` is
   confirmed canonical.

7. **C9 Rust-shell items (igloo-home, ~1 day).** Derive the test-dispatch command
   set from the real registration (catches the 5+ missing arms), and funnel
   `lock().unwrap()` through one poison-mapping helper.

8. **Remaining C4/C5/C8 tail.** Adversarial decrypt tests in pwa/home, the
   shared-boundary `Secret<T>` threading, the JS transient-secret helper, and the
   fabricated onboard-metadata fix — folded into the relevant R2 slice as it lands.

## Graduating to backlog

Move to `../BACKLOG.md`, grouped by remediation bucket (fixes are not written
here): C1/C2 as the two near-term security items (R5/R6); the R2 god-file ranking
as a single "monolith decomposition" epic with the RECOMMEND-NOW/DEFER calls
captured; R1 as one "workspace formatter + changelog convention" decision; R3 as a
"cross-host dedup" item naming the five consolidations; R4 as a release-cut
"dead-surface removal" checklist gated on the orphan-import trigger; C9 as two
igloo-home Rust-shell items. The poll-vs-subscribe (T8) and type-escape (T9)
findings are lower-priority follow-ups to attach to the relevant host's
decomposition slice rather than standalone work.
