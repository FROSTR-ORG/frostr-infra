# `igloo-ui` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui`

This audit covered the 36 TSX files under `src/components`, the exported barrel at `src/index.ts`, the compiled stylesheet at `src/styles.css`, the build chain under `scripts/build.mjs`, and the Vitest suite under `test/`. The package is almost entirely prop-driven and well-behaved on the React side. The interesting findings cluster around three areas: a host-specific design token and class surface bleeding into the shared library, secret material rendered in clear text by shared workflow cards, and large gaps in both accessibility semantics and test coverage for the components that matter most operationally.

## Findings

### 1. High: `HostShell` hard-codes host-specific CSS classes and the compiled stylesheet ships host-specific rules

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:9`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:32`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:33`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:35`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:36`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:506`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:525`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:537`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:566`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:978`

Why this matters:
- The shared `HostEntryTile` and `LandingIcon` components render class names like `igloo-pwa-entry-tile`, `igloo-pwa-entry-head`, `igloo-pwa-entry-copy`, `igloo-pwa-entry-kicker`, and `igloo-pwa-entry-icon`.
- The compiled stylesheet defines matching rules (`.igloo-pwa-entry-*`) under `@layer components`, so the "PWA" name is now published in the shared package surface.
- This is a visible boundary violation: `igloo-ui` advertises itself as consumer-neutral, but the entry-tile primitive only looks right when the consumer carries the `pwa-entry` visual idiom.

Cross-repo note:
- Any host that does not ship `styles.css` or that themes tiles differently will fail to match the primary/secondary variants because the `.is-primary` selector lives in the shared CSS and cannot be overridden without copying the full rule set.

Smells:
- Host-product prefix (`pwa-entry`) baked into a shared component API.
- `igloo-panel` + `igloo-pwa-entry-tile` composed in JSX rather than exposed through variants.

Streamline:
- Rename the primitive classes to neutral tokens (`igloo-entry-tile`, `igloo-entry-head`, etc.) and update consumers.
- Or move the tile visual to a `className` override surface and let hosts provide their own styles.

### 2. High: create/import/recovery workflow cards render `nsec`, hex signing keys, and raw share JSON in plain text with no redaction seam

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/RecoveryWorkspace.tsx:79`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/RecoveryWorkspace.tsx:83`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateImportPanel.tsx:298`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateImportPanel.tsx:303`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateImportPanel.tsx:320`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/QrPayloadModal.tsx:46`

Why this matters:
- `RecoveryWorkspace` renders the recovered `nsec` and the hex signing key as the `value` of a readonly `Textarea`. The content is selectable, copyable through normal browser affordances, and persisted in the DOM as long as the component is mounted.
- `CreateImportPanel` renders the regenerated `nsec` preview as the `dd` child (`{generatedKeyset.nsec}`), the full group package JSON inside a readonly textarea, and each share package JSON inside a readonly textarea.
- `QrPayloadModal` renders the entire onboarding payload inside a `<pre>` block below the QR-like grid.
- None of these cards offer a reveal gate, redaction, auto-clear on unmount, or prop for the host to override the renderer. The shared library is the place where those seams would most usefully live, because every host renders them identically today.

Cross-repo note:
- Hosts currently have no mechanism to opt into redacted display without forking these components, and nothing in `igloo-ui` signals to consumers that the rendered string is secret.

Smells:
- Presentational defaults treat secret strings identically to public identifiers.
- No "sensitive value" prop or boundary exists in the primitive layer (no masked-text component, no `RevealableField`).

Streamline:
- Introduce a shared `SensitiveTextarea` / `SensitiveField` primitive that masks by default and requires an explicit reveal.
- Default `nsec`, `signing_key_hex`, `share_package_json`, and `bfonboard` payload rendering to the sensitive variant; let hosts opt out deliberately if they already render inside a trusted reveal flow.

### 3. High: workflow components render JSON error strings from `data` blobs without structural bounds and expose `data.constructor.name` through the serializer fallback

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/log-entry.tsx:31`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/log-entry.tsx:36`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/log-entry.tsx:108`

Why this matters:
- `LogEntryComponent` formats `log.data` with `JSON.stringify`, and on failure walks `Object.keys(log.data as object)` and reads `(log.data as object).constructor.name` to build a preview string.
- When the host is bridging runtime diagnostics (which is the documented use), this path can stringify internal bifrost or signer objects the caller did not intend to expose.
- There is no length cap on the pre block contents (`max-h-[500px]` is a CSS clip only; the DOM still holds the full string), and no line cap, so a single unbounded payload can anchor a large serialized blob in the user's page.

Smells:
- Fallback formatter reaches into arbitrary object internals.
- No caller-provided formatter hook.
- No length guard before inserting text into the DOM.

Streamline:
- Accept a `formatter?: (data: unknown) => string` prop and fall back to a bounded, structure-safe serializer.
- Cap both the character and line count before rendering, and indicate truncation in the UI.

### 4. Medium: `peer-list.tsx` is a mixed-responsibility 259-line module with layout, policy state, ping state, and nonce visualization in one file

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx:43`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx:69`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx:140`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx:145`

Why this matters:
- `PeerList` owns a collapse/expand header, a summary bar with online/sign-ready/known counts, and the map of `PeerCard` children. `PeerCard` additionally owns a ping state machine (`pinging`, `latency`), a policy disclosure, and three inline `NonceBar` widgets.
- The ping state machine fires an async `onPing` call and tracks `latency` as component-local state, which is the one real piece of runtime state that has crept into this package. Hosts can not observe or inject that latency into their stores.
- `NonceBar` hard-codes `20` as the denominator for the progress bar (`(value / 20) * 100`). That is a runtime policy number living in a shared UI primitive.

Smells:
- Shared primitive holds runtime policy constants.
- Presentational component owns asynchronous request state.
- One file with three unrelated concerns (list framing, card framing, meter).

Streamline:
- Split into `PeerList`, `PeerCard`, `PeerPolicyDisclosure`, and `NonceMeter` modules.
- Accept `nonceCapacity` as a prop or push latency state up to the host.

### 5. Medium: `Modal` and `ConfirmModal` lack dialog semantics and focus management

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/modal.tsx:13`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/modal.tsx:25`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/confirm-modal.tsx:34`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/confirm-modal.tsx:37`

Why this matters:
- Neither modal wrapper sets `role="dialog"`, `aria-modal`, `aria-labelledby`, or an initial focus target.
- The overlay `<div>` has an `onClick` to dismiss but no keyboard equivalent beyond Escape.
- There is no focus trap, no return-focus logic, and no scroll lock.
- Both modals add their own global key listener, so opening `Modal` from inside `ConfirmModal` (or from within another modal) creates two listeners that both fire on Escape.

Smells:
- Two parallel modal primitives with duplicated Escape logic.
- Accessibility contract missing from a primitive used across all hosts.

Streamline:
- Collapse on a single dialog primitive with `role="dialog"`, `aria-modal`, autofocus of the first focusable child, and return-focus on close.
- Delete the Escape logic in `ConfirmModal` and consume `Modal`.

### 6. Medium: multiple click-only affordances have no keyboard path or role

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/modal.tsx:27`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/confirm-modal.tsx:38`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:82`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx:112`

Why this matters:
- The modal backdrops are plain `div`s with `onClick` and no `role`, `tabIndex`, or keydown handlers. They are invisible to keyboard-only users and screen readers.
- `StepProgress` uses `aria-label="Flow progress"` but the steps carry no `aria-current` to indicate the active step.
- The `HelpCircle` tooltip in `OperatorSignerPanel` is triggered only by a native `title` attribute on a span wrapper, which is not focusable and is invisible to keyboard users.

Smells:
- Accessibility affordances built piecemeal instead of through a small set of primitives.
- No linter or review gate for keyboard parity on click handlers.

Streamline:
- Provide a shared `Backdrop`, `StepIndicator` (with `aria-current`), and `HelpHint` primitive so accessibility is applied once.

### 7. Medium: compile chain pulls a Google Fonts stylesheet at runtime and imports it from the shipped CSS bundle

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/tailwind.config.js:7`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/package.json:20`

Why this matters:
- The shared stylesheet imports Share Tech Mono from `fonts.googleapis.com` via `@import url(...)`. That URL is then baked into the Tailwind-compiled `dist/styles.css` and delivered to every host.
- This creates a third-party network request on every page that renders any `igloo-ui` component, including the Chrome extension surface where `fonts.googleapis.com` may be gated by CSP and the Tauri desktop surface where runtime external-font loads are undesirable.
- The build command also sets `BROWSERSLIST_IGNORE_OLD_DATA=1` and chains three steps (esbuild, tsc, tailwind). There is no verification that the three outputs agree on supported targets.

Smells:
- External CDN dependency shipped inside a library stylesheet.
- Multi-step build without cross-step determinism.

Streamline:
- Vendor the font or leave font loading to the host; do not ship a remote `@import` in the package stylesheet.
- Consolidate the build into one orchestrator with a shared browser target and post-build size/content assertions.

### 8. Medium: the package re-exports primitives with `export *`, and the barrel risks name collisions and drift

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/index.ts:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/index.ts:3`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/index.ts:17`

Why this matters:
- `src/index.ts` re-exports every component module via `export *`. Any new export added to a component file silently becomes part of the public package surface.
- `StatusState`, `StatusDot`, `StatusBadge`, `OperatorMethodPermission`, `OperatorPolicyOverrideValue`, and the various `Shared*` types are exported without curation.
- Without an explicit surface file, host apps can depend on accidental exports that the library did not intend to commit to.

Smells:
- Unscoped `export *` over 38 modules.
- Shared types and components commingled in the same barrel.

Streamline:
- Replace `export *` with an explicit named re-export list or split into `./components`, `./primitives`, and `./types` subpaths.

### 9. Medium: test coverage is thin relative to the workflow surface, and there are no accessibility or visual tests

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/test/CreateFlow.test.tsx:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/test/OperatorPanels.test.tsx:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/test/RecoveryWorkspace.test.tsx:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/vitest.config.ts:1`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/test/setup.ts:1`

Why this matters:
- Six Vitest files cover six out of 13 flow components. The UI primitives layer (22 files) has zero direct tests.
- `PeerList`, `LogEntryComponent`, `EventLog`, `Modal`, `ConfirmModal`, `OperatorPermissionsPanel`, `HostShell`, and `QrPayloadModal` have no direct Vitest coverage even though they carry the largest portion of behavior.
- There is no axe-core / jest-axe assertion anywhere in the suite, no snapshot or visual-regression layer, and no test that asserts the "copy profile / copy share / rotate share / logout" operator-settings contract at the prop level (the existing test just verifies click callbacks fire).
- The `src/test/setup.ts` is a single import of `@testing-library/jest-dom/vitest` and nothing else.

Smells:
- Contract-only tests; no behavior tests around state machines (ping, collapse, override cycles).
- No accessibility gate.
- No test for keyboard interaction in any collapse/expand, tab, or modal primitive.

Streamline:
- Add unit tests for the state machines in `PeerCard`, `LogEntryComponent`, `Collapsible`, `Modal`, and `OperatorPermissionsPanel.nextOverrideValue`.
- Add jest-axe coverage for each exported surface.
- Add keyboard-interaction tests (Enter/Space/Escape) for every click-dismiss surface.

### 10. Low: `CreateFlow.tsx` and `OperatorPermissionsPanel.tsx` are large, parameter-heavy components that will be hard to maintain

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateFlow.tsx:134`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateFlow.tsx:301`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateFlow.tsx:430`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateFlow.tsx:540`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/OperatorPermissionsPanel.tsx:78`

Why this matters:
- `CreateFlow.tsx` is 599 lines and exports six components, several of which accept 10+ callback props (`CreateFlowGenerateCard`, `CreateFlowLocalSaveCard`, `CreateFlowDistributionCards`, `CreateFlowDistributionSection`).
- `OperatorPermissionsPanel` is 446 lines and accepts 15 callable/render props, plus a branching render path for `peerPermissionStates` vs. `peerPermissions`.
- Both files show the same pattern: presentational layer also specifies detailed prop contracts for a large state tree the host has to thread through every interaction.

Smells:
- Long prop lists are a hint that the component is doing more than layout.
- Dual render paths chosen at the top level by presence of an optional prop.

Streamline:
- Collapse the prop surface by accepting a `state` object and a discriminated `event` callback.
- Split into sub-components by panel concern and compose them behind a single section wrapper.

### 11. Low: `CHANGELOG.md` has a single `[Unreleased]` block and no dated releases; the package is `0.0.0`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/CHANGELOG.md:7`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/package.json:3`

Why this matters:
- Version is pinned at `0.0.0` and the changelog has no historical entries, so hosts cannot pin against a known-good version and cannot review what has moved between consumptions.
- `README.md` lists "Beta" status but no migration guidance.

Smells:
- Shared library without semver or release cadence.
- Host repos all consume via workspace link today, but any future external consumer will have nothing to track.

Streamline:
- Stamp the first dated changelog entry and move to a real semver tag as part of the next coordinated release.

## Bottom Line

`igloo-ui` is structurally close to what the README claims: a stateless, prop-driven React library. The code issues are mostly boundary hygiene and secret-awareness, not architecture. The three highest-value fixes are (a) purging `igloo-pwa-*` tokens from the shared component surface, (b) introducing a sensitive-field primitive and defaulting `nsec`, hex keys, and raw share JSON to masked rendering, and (c) adding dialog semantics and accessibility tests to the modal and peer/permission primitives that every host renders.
