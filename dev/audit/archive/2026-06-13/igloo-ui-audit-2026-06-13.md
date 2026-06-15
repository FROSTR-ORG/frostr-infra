# `igloo-ui` audit

Date: 2026-06-13

Scope: `repos/igloo-ui` (shared React UI package — components, flows, view-model adapters, design tokens; tests under `test/`; excludes `node_modules/` and untracked `dist/`)

`igloo-ui` is the shared presentation layer consumed by every Igloo host (pwa, chrome, home). Its role is purely view-model rendering — no storage, no runtime transport — and the design of its public API surface (curated `export` list, view-model interfaces, adapter functions) is generally solid. The dominant technical debt falls into two areas: the god-file problem in `CreateFlow.tsx`, which at 1,723 lines bundles more than a dozen distinct UI panels that have no structural relationship to each other; and a parallel-peer-data-model problem where `PeerList` (`PeerPolicy`) and `OperatorSignerPanel` (`PeerReadinessRowModel`) independently describe the same runtime concept with different shapes, with some utility logic (timestamp normalization, clipboard helper) duplicated across both paths. Security-surface findings are confined to a single nsec input that skips masking. Test coverage is render-level and happy-path dominant; the adapter tests are a notable bright spot.

## Findings

### 1. High: `CreateFlow.tsx` bundles 14+ unrelated panels in one 1,723-line file

Rule: `ARC-01` (Architecture & boundaries — god file)

Files:
- `repos/igloo-ui/src/components/flows/CreateFlow.tsx:1–1723`

Why this matters:
- Every change to any Igloo flow (keyset creation, onboarding, rotation, recovery, distribution) routes through this single file, making it a coordination bottleneck.
- The file mixes at least six distinct concerns: keyset-generation form, relay-list management with async ping state, share-distribution cards with permission toggles, onboard timeline UI, recovery share collection, and onboard completion. None of these has a structural dependency on the others.
- ARC-01 nominates this exact file as a known hotspot at ~1.7k lines.

Smells:
- 14 exported symbols covering create, rotate, distribute, onboard, recover, and import flows all living in one module.
- Internal helpers (`shortKey`, `statusLabel`, `packagePreview`, `RelayList`, `CreatePermissionToggles`, `buildOnboardSteps`, `OnboardTimeline`) are not independently importable or testable.
- A single `eslint-disable-next-line react-hooks/exhaustive-deps` at line 628 signals internal complexity where the reviewer gave up on the hooks lint rule.

Streamline:
- Split along the natural seams the current `index.ts` already implies: `create-flow-generate.tsx`, `create-flow-distribution.tsx`, `onboard-flow.tsx`, `recover-flow.tsx`, `rotate-keyset.tsx`. Each can export its own types and keep its private helpers local.

---

### 2. Medium: Two parallel peer-data models for the same runtime concept

Rule: `ARC-05` (Architecture & boundaries — duplicated logic across hosts/crates)

Files:
- `repos/igloo-ui/src/components/ui/peer-list.tsx:7–19` (`PeerPolicy` type)
- `repos/igloo-ui/src/models/view-models.ts:74–95` (`PeerReadinessRowModel` type)
- `repos/igloo-ui/src/components/ui/peer-list.tsx:31–41` (`formatLastSeen`)
- `repos/igloo-ui/src/adapters/runtime-view-models.ts:264–267` (`formatTimestamp`)

Why this matters:
- `PeerList` exposes a `PeerPolicy` shape (with `send`/`receive` booleans, `shouldSendNonces`, `statusLabel`, `lastSeen` as a raw `number`), while `OperatorSignerPanel` consumes `PeerReadinessRowModel` (with `canSign`/`canEcdh`/`canPing`, capability badges, already-formatted labels). These are both views of the same bifrost peer but are maintained independently.
- Hosts that use both widgets must map the same runtime data into two different shapes, with no shared converter. If the runtime peer shape changes, both mappings must be updated.
- The timestamp-normalization heuristic (`value > 10_000_000_000 ? value : value * 1000`) is repeated verbatim in `peer-list.tsx:33` and `runtime-view-models.ts:265`.

Smells:
- `PeerPolicy.lastSeen` is a raw `number | null | undefined`; `PeerReadinessRowModel.lastSeenLabel` is a pre-formatted string — the same fact expressed two different ways.
- `formatLastSeen` in `peer-list.tsx` and `formatTimestamp` in `runtime-view-models.ts` both implement the seconds/milliseconds normalization idiom independently.
- `PeerList` is exported from `index.ts` but `OperatorSignerPanel` renders its own peer rows inline — they serve the same conceptual display.

Streamline:
- Decide on one peer-display model for the shared package; if `PeerList` is the widget and `PeerReadinessRowModel` is the data contract, add an adapter in `runtime-view-models.ts` to convert to `PeerPolicy` and retire the dual-shape situation.
- Extract the timestamp-normalization logic into a single `lib/time.ts` helper and import it from both sites.

---

### 3. Medium: `CreateFlowDistributionSection` declares three dead props (`bannerKicker`, `bannerDescription`, `bannerPoints`)

Rule: `LEG-04` (Legacy & deprecation — dead or unreachable code)

Files:
- `repos/igloo-ui/src/components/flows/CreateFlow.tsx:1166–1168`

Why this matters:
- The three props appear in the prop-type annotation but are absent from the destructuring list, so they are accepted by the component signature but silently ignored. Callers that set them (the test at line 749 sets all three) see no effect.
- This is a discoverability trap: a host setting `bannerKicker="Distribute the Keyset"` gets no rendering and no error.

Smells:
- Props declared in the type object `{ bannerKicker?: string; bannerDescription?: React.ReactNode; bannerPoints?: string[] ... }` but not destructured from the function arguments.
- The test at `test/CreateFlow.test.tsx:748–751` explicitly passes these props; the test then asserts `section.queryByText('Distribute the Keyset')`… `.not.toBeInTheDocument()`, confirming the banner never renders — the dead props are tested and verified dead.

Streamline:
- Remove the three dead prop declarations from the type, and remove the corresponding test assertions. If the banner behavior is still wanted, wire the props to `CreateFlowTaskBanner` as was originally intended.

---

### 4. Medium: `Modal` shim undocumented removal trigger

Rule: `LEG-01` (Legacy & deprecation — compatibility shim without a removal trigger)

Files:
- `repos/igloo-ui/src/components/ui/modal.tsx:1–33`

Why this matters:
- The file is explicitly self-described as "a thin compatibility shim": it wraps `Dialog` to keep existing `Modal` call sites unchanged. There is no removal trigger — no version, no milestone, no tracking reference — so it will stay indefinitely.
- Callers (`ExportPackageModal`, `HostShell`, `WelcomeUnlockModal`, `WelcomeDeleteModal`) could trivially use `Dialog` directly. The shim adds a no-op indirection layer.

Smells:
- JSDoc says "We keep `Dialog` as the single engine and back the original `Modal` API" — the word "keep" signals it is a permanent workaround rather than a timed migration.
- No comment names a condition under which `Modal` can be deleted.

Streamline:
- Either declare the removal trigger (e.g., "remove once all call sites in igloo-pwa and igloo-home import `Dialog` directly — ticket #NNN") or collapse the shim into its callers in a single pass. A no-migration note is acceptable if `Modal` is intentionally exported as a stable API alias, but that should be written down.

---

### 5. Medium: `OperatorSignerPanel` carries a `KeyField` fallback path described as "legacy"

Rule: `LEG-01` (Legacy & deprecation — compatibility shim without a removal trigger)

Files:
- `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx:27–30` (prop comment)
- `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx:131–151` (conditional rendering)
- `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx:398–434` (`KeyField` function)

Why this matters:
- The prop comment at line 27 calls the old code path "the legacy `KeyField` fallback". `KeyField` is a private function at line 398 that renders a plain `Input` with a copy button. The new `KeyRow` renders a structured `DashboardKeyModel` with npub/hex split-copy. Both exist in the same file with no stated migration milestone.
- Consumers that don't supply `groupKey`/`shareKey` silently get the old behavior; the prop type accepts `() => void` for the copy handlers to maintain backward compat. This is a permanent fork masquerading as a transition.

Smells:
- Comment at line 27: "The legacy `KeyField` fallback ignores the argument" — the word "legacy" without a retirement plan.
- Two rendering branches in the same component (`view.groupKey ? <KeyRow...> : <KeyField...>`) that serve the same purpose with different widgets.

Streamline:
- Identify which hosts still supply plain `publicKeyLabel`/`shareLabel` without `groupKey`/`shareKey`, migrate them to the structured model, then delete `KeyField`. Add a removal note with a target if the migration spans a release boundary.

---

### 6. Medium: nsec / private-key input is not masked

Rule: `SEC-01` (Security — secret material lifecycle)

Files:
- `repos/igloo-ui/src/components/flows/CreateFlow.tsx:187–193`

Why this matters:
- `CreateFlowGenerateCard` renders an "Existing Private Key (optional)" input at line 187. The input has no `type="password"` and no `{...passwordManagerOptOutProps}` spread, so the nsec value is rendered in plain text in the DOM, visible to screen readers, shoulder-surfers, and screenshot tools. Every other secret-bearing input in this file (`packagePassword`, `devicePassphrase`, `confirmPassword`) correctly uses `type="password"` with `{...passwordManagerOptOutProps}`.
- An `<EyeOff>` icon is rendered beside it as a visual affordance suggesting masking, but the input itself is an unmasked text field.

Smells:
- `type` attribute is absent from the input — defaults to `text`.
- `passwordManagerOptOutProps` spread is absent, so password managers will see the field and potentially offer to save the nsec.
- Visual EyeOff icon implies masking that does not exist.

Streamline:
- Change the input to `type="password"` and add `{...passwordManagerOptOutProps}`. Since the optional nsec is a secret, consider replacing the plain input with `PasswordField` for consistency with how passphrases are handled throughout the same file.

---

### 7. Medium: No formatter enforced; style is author-decided

Rule: `AES-06` (Aesthetics & formatting — no enforced formatter)

Files:
- `repos/igloo-ui/package.json` (no eslint/prettier dependency or script)

Why this matters:
- There is no `prettier`, `eslint`, or any other formatter configured or listed in `devDependencies`. Formatting inconsistencies between the two style regimes in the codebase (BEM-style CSS class names and Tailwind utility classes mixed throughout; some files use trailing commas, others don't) will recur review after review with no automated gate.
- The audit rules call this out explicitly: "A note on tooling: no TypeScript repo here configures eslint/prettier."

Smells:
- `package.json` has no `prettier`, `eslint`, or `lint` script.
- `StoredProfilesLandingCard` in `HostShell.tsx` uses raw Tailwind utility chains (e.g., `className="flex items-start justify-between gap-4"`) while `CreateFlow.tsx` uses BEM-flavored igloo class names (`"igloo-create-profile-form"`). Both styles coexist without a lint gate to prevent drift.

Streamline:
- Add `prettier` with a `.prettierrc` and a `format:check` script gated in CI. Or, if the workspace already gates Prettier from the infra root, document that this repo delegates to it. Either way the answer should be written down and enforced.

---

### 8. Low: `copyToClipboard` helper is duplicated in `SensitiveField` and `SensitiveTextarea`

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-ui/src/components/ui/sensitive-field.tsx:34–38`
- `repos/igloo-ui/src/components/ui/sensitive-textarea.tsx:39–43`

Why this matters:
- Identical four-line functions. If clipboard behavior needs to change (e.g., fallback for browsers without `navigator.clipboard`), both files must be updated.

Smells:
- Byte-for-byte identical function bodies in two sibling files in the same directory.

Streamline:
- Extract to `lib/clipboard.ts` and import from both components. The `lib/utils.ts` pattern already exists for this purpose.

---

### 9. Low: `setup-dom.ts` is a maintained copy, not a shared import

Rule: `CQ-04` (Code quality — duplicated logic); also touches `DOC-04`

Files:
- `repos/igloo-ui/src/test/setup-dom.ts:1–13` (copy notice comment)

Why this matters:
- The file comments that it is "COPIED into igloo-ui… kept in lockstep by `scripts/check-shared-test-setup.sh`". This is an acknowledged dual-maintenance risk. If the canonical file in `igloo-shared` changes and the sync script is not run, the two diverge silently.

Smells:
- The canonical source is in a different submodule (`igloo-shared`); the copy mechanism relies on a manually-run script rather than a package import.
- Comment calls it a copy and names the risk explicitly, but there is no CI gate in igloo-ui's own `package.json` scripts to enforce freshness.

Streamline:
- Either wire the freshness check into `npm test` (pre-test script), or publish `setup-dom.ts` as a named export from `igloo-shared` and import it directly, eliminating the copy entirely.

---

### 10. Low: `package.json` perpetually at `0.0.0` with a single `[Unreleased]` block

Rule: `DOC-06` (Documentation — changelog / version hygiene)

Files:
- `repos/igloo-ui/package.json:3`
- `repos/igloo-ui/CHANGELOG.md:1–17`

Why this matters:
- The package is consumed by three host apps. Consumers have no way to tell what changed between any two snapshots — there are no versioned entries. CHANGELOG has exactly one `[Unreleased]` block.

Smells:
- `"version": "0.0.0"` with no versioning strategy.
- All changelog entries live under `[Unreleased]` with no historical record.

Streamline:
- Adopt a minimal versioning strategy (e.g., semver via `npm version`, or calendar-date tags) and seed the CHANGELOG with at least one real `[x.y.z]` release entry. The workspace release doc at `dev/docs/RELEASE.md` should be the guide.

---

### 11. Low: Dead `eslint-disable` suppressing a legitimate warning in `RelayList`

Rule: `CQ-04` (Code quality); `DOC-04` (Documentation — missing rationale)

Files:
- `repos/igloo-ui/src/components/flows/CreateFlow.tsx:628–629`

Why this matters:
- `// eslint-disable-next-line react-hooks/exhaustive-deps` is used to suppress a missing dependency warning for the `runPing` function in the `RelayList` effect. The suppression has no explanation. Without the comment, `runPing` changing identity on each render would re-trigger the auto-ping effect continuously — the suppression is load-bearing but the reason is not written down.
- There is no eslint configured for this repo (`AES-06` above), so this disable comment is already cargo-culted from an environment that no longer exists.

Smells:
- `eslint-disable-next-line` in a codebase with no eslint configuration.
- No comment explaining why `runPing` is intentionally excluded from the dependency array.

Streamline:
- If eslint is added (`AES-06`), the suppress should carry a why comment. In the interim, either remove the stale comment or replace it with a `// intentional: runPing is excluded to avoid re-pinging on every render; the function identity changes on each render cycle but its effect (deduped by pings[url]) is stable.` comment.

## Summary

| Severity | Count |
|---|---|
| High | 1 |
| Medium | 6 |
| Low | 4 |
| **Total** | **11** |
