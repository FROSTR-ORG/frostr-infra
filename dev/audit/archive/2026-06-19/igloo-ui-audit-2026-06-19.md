# `igloo-ui` audit

Date: 2026-06-19

Scope: `/Users/cscott/Repos/frostr/frostr-infra/repos/igloo-ui` (full `src/` tree
and `test/` suite; cross-referenced against `igloo-pwa`, `igloo-chrome`, and
`igloo-home` consumers under `repos/`). Typecheck (`npx tsc --noEmit`) passes
clean; line counts and call sites verified by grep/wc.

`igloo-ui` is the shared React presentation layer: design tokens, headless-ish UI
primitives (`components/ui`), flow composites (`components/flows`), and a small
**pure** adapter/selector core (`adapters/runtime-view-models.ts`,
`models/`). That pure core is the healthiest part of the repo — `deriveDashboardState`,
`buildPeerReadinessRows`, and `buildPendingApprovalRows` are single-homed,
documented, and carry genuinely adversarial unit coverage (load-failed precedence,
relay-offline vs signing-blocked exclusivity, pubkey dedup/lowercasing). The barrel
(`src/index.ts`) is hand-curated with no `export *`, and the surface metrics the
prompt flagged (strict TS, ~0 `any`, ~0 TODO, no eslint-disable) hold up.

The debt is **structural and semantic**, concentrated in three places. First, the
flow layer has drifted out of sync with its consumers: four exported, fully-tested
flow components (`CreateImportPanel`, `ManagedProfilesPanel`, `RecoveryWorkspace`,
`DesktopAppShell`, ~734 LOC) have **zero** host consumers — leftover from the Paper
redesign churn — and one of them (`CreateImportPanel`) contains a live secret-leak
defect waiting in the public API. Second, `CreateFlow.tsx` is a 1,727-LOC god file
holding six distinct flows and exporting 18 components + 13 types from one module.
Third, the onboard-handshake panel still ships fabricated placeholder metadata
(`"My Signing Key"`, `"2/3"`, `Share #0`) into a real PWA flow. Supporting these:
pubkey-truncation and timestamp-normalization logic duplicated across 4 sites with
divergent widths, a clipboard copy of secret material with no auto-clear, and the
workspace-wide gaps (no formatter, version stuck at `0.0.0`).

## Findings

### 1. High: Recovered nsec rendered in plaintext while less-sensitive packages beside it are masked

Rule: `SEC-01` (secret material lifecycle)

Files:
- `igloo-ui/src/components/flows/CreateImportPanel.tsx:300-301` (`<dt>Recovered nsec preview</dt><dd>{generatedKeyset.nsec}</dd>`)
- `igloo-ui/src/components/flows/CreateImportPanel.tsx:304` (group package JSON wrapped in `SensitiveTextarea`)
- `igloo-ui/src/components/flows/CreateImportPanel.tsx:320` (share package JSON wrapped in `SensitiveTextarea`)
- `igloo-ui/src/components/flows/CreateImportPanel.tsx:27` (`nsec: string` on `GeneratedKeysetView`)

Why this matters:
- The recovered **nsec** (a full root private key) is rendered unconditionally into
  the DOM in a `<dd>` with no mask, no reveal gate, and no auto-remask — it is
  visible to screenshots, screen-share, and shoulder-surfing the moment the panel
  mounts.
- The component already imports and uses `SensitiveTextarea` for the *less*
  sensitive group-package and share-package JSON two lines below. The single most
  sensitive value on the screen is the one shown in clear — an inverted threat model.
- This is a defect sitting in the public package surface (it is exported from the
  barrel), so any host that adopts `CreateImportPanel` inherits the leak silently.

Smells:
- A field literally labelled "nsec preview" bypassing the masking primitive the same
  file uses for everything else.
- Secret rendered as inert text rather than through the reveal/auto-remask control.

Streamline:
- Route the nsec through `SensitiveField`/`SensitiveTextarea` (masked by default,
  `autoMaskMs` re-mask) like its neighbours, or drop the "preview" entirely — a
  recovered nsec rarely needs to be shown back to the operator at all. Add a flow-level
  test asserting the nsec is not in the initial DOM text (see Finding 8).

### 2. High: Four exported, fully-tested flow components have zero host consumers (Paper-churn orphans)

Rule: `LEG-04` (dead or unreachable code)

Files:
- `igloo-ui/src/components/flows/CreateImportPanel.tsx:1-361` (exported `index.ts:179`; consumers: only `test/CreateImportPanel.test.tsx`)
- `igloo-ui/src/components/flows/ManagedProfilesPanel.tsx:1-164` (exported `index.ts:208`; consumers: only its test)
- `igloo-ui/src/components/flows/RecoveryWorkspace.tsx:1-92` (exported `index.ts:231`; consumers: only its test)
- `igloo-ui/src/components/flows/DesktopAppShell.tsx:1-117` (exported `index.ts:202`; consumers: only its test)

Why this matters:
- A cross-repo grep over `igloo-pwa`, `igloo-chrome`, and `igloo-home` `src/` finds
  no import of any of these four; the only references are each component's own unit
  test. ~734 LOC of public surface that nothing ships.
- The unit tests give *false* coverage confidence — they stay green for code no user
  ever reaches, and they hide the SEC-01 defect in Finding 1 inside a "tested" component.
- `DesktopAppShell` is actively misleading: igloo-home — the desktop host — renders
  `HostFlowShell` (from `HostShell.tsx`, `igloo-home/src/App.tsx:19,1508`), not
  `DesktopAppShell`. A maintainer extending the desktop shell would reasonably edit
  the wrong file.

Smells:
- Exported-and-tested-but-unconsumed; a "Desktop" shell the desktop app doesn't use.
- Tests that exercise a component no integration path renders.

Streamline:
- Removal trigger: if no host imports these by the next release cut, delete the four
  components, their barrel exports (`index.ts:179,202,208,231`), and their tests. If
  one is a planned-but-unwired surface, mark it in the barrel with a one-line
  "not yet consumed; target host X" note so the orphan is intentional, not accidental.
- Resolve Finding 1 before deleting `CreateImportPanel`, or delete it and the leak
  goes with it.

### 3. High: `CreateFlow.tsx` is a 1,727-LOC god file spanning six flows

Rule: `ARC-01` (god file)

Files:
- `igloo-ui/src/components/flows/CreateFlow.tsx:1-1727`
- `igloo-ui/src/index.ts:143-178` (18 component + 13 type re-exports from this one module)

Why this matters:
- One file owns six distinct, independently-changing concerns: keyset **generation**
  (`CreateFlowGenerateCard`, `CreateCounterControl`, ~114-245), **rotation**
  (`RotateKeysetPanel`, ~246-385), **local save / share selection** (`CreateFlowLocalSaveCard`,
  `CreateFlowShareSelection`, ~413-588), **relay + distribution** (`RelayList`,
  `CreateFlowDistribution*`, ~589-1213), **onboard package import** (`OnboardPackageEntry`,
  `ImportProfileEntry`, ~1214-1334), **recovery** (`RecoverCollectSharesPanel`, ~1335-1484),
  and the **onboard-handshake timeline** (`OnboardTimeline`, `OnboardHandshakePanel`,
  `Onboard*Panel`, ~1485-1727).
- It is the single highest-traffic file in the repo: 31 names route through the
  barrel from here, so almost every create/rotate/onboard/recover change touches it,
  and unrelated edits collide.
- Behavior coupling is moderate (these are presentational components with prop-driven
  state, few shared internal closures), which makes the split *low-risk* and high-payoff.

Smells:
- Multiple top-level exported flows in one module; private helpers (`shortKey`,
  `statusLabel`, `packagePreview`, `buildOnboardSteps`) shared opportunistically.
- 31 barrel entries pointing at one path (`RS-05` hidden entry points compound this).

Streamline:
- Split along the six seams into `flows/create/` siblings: `generate.tsx`, `rotate.tsx`,
  `local-save.tsx`, `distribution.tsx`, `onboard-import.tsx`, `recover.tsx`,
  `onboard-handshake.tsx`; hoist the shared `Shared*` types into a `create/types.ts`.
  Re-export from a thin `flows/create/index.ts` so the public barrel surface is
  unchanged. Existing `test/CreateFlow.test.tsx` (786 LOC, render/dispatch) is the
  safety net for the move — it imports through the barrel, so it survives the split.

### 4. Medium: Onboard-handshake ships fabricated placeholder metadata into a real flow

Rule: `RS-06` (inconsistent terminology / fiction vs the domain) — with `DOC-05` overtones

Files:
- `igloo-ui/src/components/flows/CreateFlow.tsx:1541-1542` (`keysetName = 'My Signing Key'`, `thresholdLabel = '2/3'` defaults)
- `igloo-ui/src/components/flows/CreateFlow.tsx:1554` (`'bfonboard1...'` fallback)
- `igloo-ui/src/components/flows/CreateFlow.tsx:1563` (hardcoded `· Share #0`, not even a prop)
- `igloo-pwa/src/App.tsx:1066-1073` (caller passes literal `keysetName="My Signing Key"` / `thresholdLabel="2/3"`)

Why this matters:
- The PWA renders this panel during a *live* onboarding handshake but feeds it the
  literal placeholders `"My Signing Key"` and `"2/3"`; the panel also hardcodes
  `Share #0` with no prop at all. The operator is shown a fabricated keyset name,
  threshold, and share index that have nothing to do with the package being onboarded.
- The reconcile flagged that real metadata is now available post-parse; this is the
  surviving instance. Presenting invented values as runtime truth erodes trust and
  can mask a wrong-package mistake (the operator can't notice "2/3" is wrong because
  it always says "2/3").

Smells:
- Default prop values that are demo copy, not safe fallbacks.
- A share index hardcoded in JSX (`Share #0`) where every real share has a real index.

Streamline:
- Make `keysetName`/`thresholdLabel`/`shareIndex` required (or render the line only
  when supplied), parse them from the onboarding package, and have the PWA pass the
  parsed values. Until real metadata exists, render a neutral "Validating package…"
  line rather than fabricated specifics.

### 5. Medium: Parallel peer-row data models — `PeerPolicy` (peer-list) vs `PeerReadinessRowModel`

Rule: `ARC-05` (duplicated logic across hosts/modules) — with `CQ-04`

Files:
- `igloo-ui/src/components/ui/peer-list.tsx:7-19` (`PeerPolicy` type) and `:71-261` (`PeerList`/`PeerCard`)
- `igloo-ui/src/models/view-models.ts:77-98` (`PeerReadinessRowModel`)
- `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:187-303` (`PeersSection`/`PeerRow` — the model that actually ships)

Why this matters:
- Two side-by-side models describe "a peer row": `PeerReadinessRowModel`
  (`canSign/canEcdh/canPing`, `nonceSeries`, `state` union) drives the live dashboard
  via `OperatorSignerPanel`; `PeerPolicy` (`send`/`receive` booleans, `StatusState`,
  `NonceBar`s) drives the standalone `PeerList` primitive.
- `PeerList`/`PeerPolicy` is exported from the barrel (`index.ts:118-119`) but has
  **no host consumer** — only `test/ui/peer-list.test.tsx` and `test/axe/primitives.test.tsx`
  render it. So this is a second, divergent peer-row implementation kept alive only by
  its tests, while the real peer rendering lives in `OperatorSignerPanel.PeerRow`.
- Both re-derive pubkey truncation and last-seen formatting independently (see Finding 6),
  so they will drift.

Smells:
- Two types, two renderers, one concept; the unused one ships in the public surface.
- Divergent vocabulary for the same field (`send`/`receive` vs `canSign`/`canEcdh`).

Streamline:
- Decide which is canonical. If `OperatorSignerPanel.PeerRow` is the real peer view,
  retire `PeerList`/`PeerPolicy` and its barrel export (treat as a Finding-2 orphan).
  If `PeerList` is meant to be the reusable primitive, have `OperatorSignerPanel`
  consume it and feed it a projection of `PeerReadinessRowModel`, collapsing to one model.

### 6. Medium: Pubkey truncation and timestamp normalization duplicated across 4 sites with divergent widths

Rule: `CQ-04` (duplicated logic) — with `RS-01`

Files:
- `igloo-ui/src/adapters/runtime-view-models.ts:386-387` (`shortPubkey`, `6/4`) and `:416-418` (`formatTimestamp`, seconds/ms normalize)
- `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:323-325` (`shortKey`, `6/4`)
- `igloo-ui/src/components/flows/CreateFlow.tsx:853-857` (`shortKey`, `10/6` — same name, different width)
- `igloo-ui/src/components/ui/peer-list.tsx:29` (`formatPubkey`, `14/8`) and `:31-41` (`formatLastSeen`, re-derives the same `> 10_000_000_000` normalization)
- `igloo-ui/src/components/flows/ManagedProfilesPanel.tsx:37` (`new Date(value * 1000)` — a *third* timestamp convention, no guard)

Why this matters:
- Four independent pubkey truncators with three different widths (`6/4`, `10/6`,
  `14/8`) — a key shown one way on the dashboard, another in the create flow, another
  in the peer list. A reader can't predict how a key will render.
- Two functions named `shortKey` with *different* bodies (`6/4` vs `10/6`) — RS-01:
  same name, different behavior, defeating grep-to-understand.
- The `value > 10_000_000_000 ? value : value * 1000` seconds-vs-ms heuristic is
  copy-pasted twice and a third site (`ManagedProfilesPanel`) assumes seconds with no
  guard — a latent bug if it ever receives ms.

Smells:
- Magic seconds/ms threshold (`10_000_000_000`) repeated, unnamed (`CQ-06`).
- One concept ("short a pubkey for display") with N implementations.

Streamline:
- Add `lib/format.ts` with `truncatePubkey(value, opts?)` and `formatEpoch(value)`
  (one home for the seconds/ms normalization, with the threshold a named constant),
  import everywhere. Pick a single canonical truncation width unless a surface has a
  documented reason to differ.

### 7. Medium: Dead `introMessage` prop accepted but never rendered

Rule: `LEG-04` (dead or unreachable code)

Files:
- `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:19-21` (declared in `Props`, "no longer rendered")
- `igloo-ui/src/components/flows/OperatorSignerPanel.tsx:44-62` (not destructured in the function signature)

Why this matters:
- `introMessage` is declared on the public `Props` with a comment "Retained for API
  compatibility … no longer rendered," but it is not destructured and not referenced
  anywhere in the body, and a cross-repo grep finds **no host** that passes it.
- "Retained for API compatibility" with no consumer and no removal trigger is the
  LEG-01/LEG-04 anti-pattern: permanent debt wearing a temporary label. It widens the
  public prop surface with a prop that does nothing.

Smells:
- A documented-dead prop kept "just in case"; comment explains *what it was*, not why
  it must stay.

Streamline:
- Delete `introMessage` from `Props` (no caller passes it; TS will confirm). If a
  future intro banner is planned, that's a new prop when it ships — git remembers this one.

### 8. Medium: Core journeys (create / import / onboard / rotate / recover) covered only at the render/dispatch layer; no adversarial or secret-masking assertions

Rule: `TST-02` (happy-path-only) — with `TST-01`

Files:
- `igloo-ui/test/CreateFlow.test.tsx:1-786` (titles are "renders … / dispatches …")
- `igloo-ui/test/CreateImportPanel.test.tsx:1-43`
- `igloo-ui/test/ui/sensitive.test.tsx:1-120` (masking *is* tested — but only on the primitive in isolation)

Why this matters:
- The flow tests assert that props wire to callbacks and that copy renders — they do
  not assert behavior under wrong/hostile input, nor that secret material is masked
  *in the flow that renders it*. `SensitiveTextarea` masking is proven for the
  primitive, but nothing asserts `CreateImportPanel` actually routes the nsec through
  it — which is exactly why Finding 1's leak passes the suite green.
- For a signing-key UI, "the generated share / recovered nsec is not in the initial
  DOM text" is a core invariant and is currently unprotected.

Smells:
- Render-only tests standing in for behavior (`TST-05`); a green suite over a leaking
  component (Finding 1).

Streamline:
- Add flow-level assertions: generated share and recovered nsec are masked by default
  (not present in `container.textContent` before reveal); reveal exposes them; invalid
  package text surfaces the error affordance. These also become the regression net for
  the Finding 1 fix and the Finding 3 split.

### 9. Low: Secret copied to clipboard with no auto-clear, and the copy/auto-remask logic is duplicated

Rule: `SEC-01` (secret lifecycle) — with `CQ-04`, `CQ-06`

Files:
- `igloo-ui/src/components/ui/sensitive-textarea.tsx:39-43` (`copyToClipboard`) and `:54,76-84` (`autoMaskMs = 30000`, remask timer)
- `igloo-ui/src/components/ui/sensitive-field.tsx:35-36` (duplicate `copyToClipboard`) and `:49,70-77` (duplicate `autoMaskMs = 30000` timer)

Why this matters:
- The reveal auto-remasks after 30s, but the **copy** writes the secret to the system
  clipboard with no expiry — the share/nsec persists in the clipboard indefinitely,
  readable by any later paste or clipboard-history tool. The UI's main secret-lifecycle
  guarantee (auto-remask) has no clipboard counterpart.
- `copyToClipboard` and the entire reveal/auto-remask timer block are duplicated
  verbatim across the two sensitive components, and `30000` is an unnamed magic literal
  in both — they will drift.

Smells:
- One half of the secret-lifecycle story (reveal) hardened, the other (clipboard) not.
- Copy-pasted timer + clipboard logic; magic `30000`.

Streamline:
- Factor the reveal/auto-remask/copy behavior into one `useSensitiveReveal` hook (or a
  shared base) consumed by both components; name the delay (`SENSITIVE_AUTO_MASK_MS`).
  Consider a best-effort clipboard clear after a timeout, or at minimum document that
  copied secrets are not auto-cleared so the host can warn.

### 10. Low: No enforced formatter in a TS-only package

Rule: `AES-06` (no enforced formatter)

Files:
- `igloo-ui/package.json:1-60` (no `prettier`/`eslint` dep, no `lint`/`format` script)
- repo root: no `.prettierrc*`, `.eslintrc*`, or `eslint.config.*`

Why this matters:
- Style is per-author, so the aesthetic findings here (and the inconsistent comment
  banners, see below) are doomed to recur and reviews re-argue formatting.
- This is the cross-cutting gap the reconcile noted across all five targets; calling it
  here keeps the per-repo record complete.

Smells:
- A 5.5k+ LOC TS package with no automated style gate.

Streamline:
- Adopt the workspace-standard prettier config (a workspace decision, not a per-repo
  one) and add a `format:check` gate. Cross-target — see Finding 11.

Cross-repo note: identical absence in `igloo-pwa`, `igloo-chrome`, `igloo-home`,
`igloo-shared`. Mirror into NOTES.md as a single workspace-level formatter decision.

### 11. Low: Version stuck at `0.0.0` with a perpetual `[Unreleased]` changelog

Rule: `DOC-06` (changelog / version hygiene)

Files:
- `igloo-ui/package.json:13` (`"version": "0.0.0"`)
- `igloo-ui/CHANGELOG.md:7` (only ever an `[Unreleased]` block)

Why this matters:
- The README calls the package "Beta," but `0.0.0` and a never-versioned changelog
  give consumers (the three hosts that vendor it) no way to tell what changed between
  two pointer bumps — and submodule bumps are the actual release mechanism here.

Smells:
- Permanent `[Unreleased]`; `0.0.0` on a package three apps depend on.

Streamline:
- Cut a real version on the next coordinated release and roll `[Unreleased]` into a
  dated entry; tie it to the submodule-pointer bump process in `dev/docs/RELEASE.md`.

Cross-repo note: same `0.0.0` + perpetual-`[Unreleased]` pattern across the igloo-*
clients. Mirror into NOTES.md.

## Summary

| Severity | Count |
|---|---|
| High | 3 |
| Medium | 5 |
| Low | 3 |
| **Total** | **11** |
