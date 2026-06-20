# Igloo PWA/Home UI/UX Smoke Feedback

Date: 2026-06-19
Status: Live capture
Workflow: `igloo-paper` -> `igloo-ui`

## Goal

Capture UI, UX, copy, and presentation feedback from a smoke review of
`igloo-pwa` and `igloo-home`, then turn the observations into universal fixes
where possible.

The review should preserve rough feedback exactly enough to keep the product
intent, then route each item to the right owning layer:

- shared presentation patterns in `repos/igloo-ui`
- client-specific integration or screen behavior in `repos/igloo-pwa` or
  `repos/igloo-home`
- shared runtime contracts, state names, or package semantics in
  `repos/igloo-shared`
- changed design intent or missing reference coverage in `repos/igloo-paper`
- cross-client smoke, visual capture, or regression coverage in `test/`

## Boundaries

- Treat `repos/igloo-paper` as reference material only.
- Do not import `igloo-paper` into runtime code, package code, or app builds.
- Prefer fixing shared components, tokens, and copy vocabulary once in
  `igloo-ui` when the same issue appears across clients.
- Prefer app-local changes only when the issue is caused by host integration,
  routing, platform shell constraints, persistence, or client-specific state.
- Escalate to `igloo-shared` when UI awkwardness comes from unclear shared data,
  state shape, package naming, or runtime contract vocabulary.

## Capture Fields

Use these fields when an item is ready to triage. During the live walkthrough,
raw fragments are fine.

- `ID`: stable feedback ID, starting at `UX-001`
- `Surface`: screen, modal, flow, component, or copy location
- `Client`: `pwa`, `home`, or `both`
- `Category`: visual, layout, hierarchy, copy, flow, state, accessibility,
  shared contract, paper mismatch, or test coverage
- `Severity`: blocker, high, medium, low, or polish
- `Raw feedback`: what was said or observed
- `Expected intent`: what the experience should communicate or enable
- `Likely owner`: `igloo-ui`, `igloo-pwa`, `igloo-home`, `igloo-shared`,
  `igloo-paper`, `test`, or `docs`
- `Universalization`: shared pattern to fix once, if any
- `Status`: captured, triaged, in progress, fixed, deferred, or rejected

## Captured Items

### UX-001: Inactive info tooltip on Generate New Keyset

- `Surface`: Generate New Keyset entry card / create flow entry
- `Client`: `pwa`
- `Category`: flow, accessibility, copy
- `Severity`: medium
- `Raw feedback`: "There's an icon here for a tooltip but when I hover over it
  nothing appears, so it seems to be an inactive tooltip behind this kind of
  info icon."
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-d0661115-b3e3-41d4-8015-90b792267ac7.png`
- `Expected intent`: If the info icon is visible, it should explain the
  "Generate New Keyset" choice on hover and keyboard focus. If there is no
  useful supplemental help, remove the icon so the title does not imply an
  unavailable interaction.
- `Likely owner`: `igloo-ui`, unless investigation shows `igloo-pwa` is
  rendering a shared component without passing tooltip/help content.
- `Universalization`: audit info/help icons across shared entry cards and flow
  headers so every visible help affordance has accessible hover/focus content,
  or is removed.
- `Status`: captured

### UX-002: Create Keyset field help icons are placeholders

- `Surface`: Create Keyset flow, step 1 form fields
- `Client`: `pwa`
- `Category`: flow, accessibility, copy, paper mismatch
- `Severity`: medium
- `Raw feedback`: "There's a bunch of icon placeholders for tooltips and they
  haven't been implemented. The context needed for these tooltips, is that
  captured inside of igloo_paper or igloo_ui or is this missing at this moment?"
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-ff8c2f2a-479d-43f2-885e-19de3e244735.png`
- `Expected intent`: Field help icons should either open useful hover/focus
  content or be removed. The screen already has helper text below the fields, so
  the tooltip decision should clarify whether the icons add real supplemental
  context or only duplicate visible help.
- `Likely owner`: `igloo-ui` for implementation and shared help behavior;
  `igloo-paper` if product wants field-level tooltip copy captured as design
  reference; `igloo-pwa` only consumes the shared create-flow component here.
- `Universalization`: replace bare `HelpCircle`/`Info` icons in shared flow
  components with `HelpHint` when content exists; otherwise remove the icon.
  Define field-level help copy once for shared create/rotate/recover surfaces if
  the icon stays.
- `Status`: captured

### UX-003: Create flow background hue shifts between steps

- `Surface`: Create Keyset flow, transition from step 1 to step 2
- `Client`: `pwa`
- `Category`: visual, paper mismatch
- `Severity`: polish
- `Raw feedback`: "When I go to the second step in this create flow all of a
  sudden the background gradient changes to be a slightly different hue."
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-3ad387a2-2563-4747-aa4a-1033b888df1a.png`
- `Expected intent`: The create flow should feel like one continuous task. Step
  changes should not make the page background appear to shift color unless that
  shift is an intentional state transition.
- `Likely owner`: `igloo-ui` for the shared public task shell/background and
  create-flow surfaces; `igloo-pwa` only if the app wrapper is applying
  route-specific background behavior.
- `Universalization`: verify every public task step uses the same shell,
  background treatment, and viewport framing, then capture the create-flow
  sequence in visual review so hue shifts are visible before release.
- `Status`: captured

### UX-004: Select Share step overflows in half-screen width

- `Surface`: Create Keyset flow, step 2 Select Share
- `Client`: `pwa`
- `Category`: layout, accessibility, test coverage
- `Severity`: high
- `Raw feedback`: "I have this open on a half screen view and the UI is
  overflowing off screen so this appears to not be fully responsive but I did
  not have this issue with the last screen."
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-3ad387a2-2563-4747-aa4a-1033b888df1a.png`
- `Expected intent`: The Select Share step should fit and remain usable in a
  half-screen desktop window. Long group/share public keys, action labels, and
  status pills should wrap, truncate, stack, or scroll within the shared task
  width instead of pushing the whole page off screen.
- `Likely owner`: `igloo-ui`, specifically shared Create Flow layout and
  responsive CSS. The PWA renders the shared `CreateFlowShareSelection` surface.
- `Universalization`: audit create/rotate/recover task panels that display long
  keys or package IDs. Shared rows should constrain long mono text, allow
  wrapping or ellipsis, and stack actions on narrow desktop widths.
- `Status`: captured

### UX-005: Make Select Share group key panel info-only and show npub plus hex

- `Surface`: Create Keyset flow, step 2 Select Share, Group Public Key panel
- `Client`: `pwa`
- `Category`: hierarchy, copy, shared contract
- `Severity`: medium
- `Raw feedback`: "For this section showing the group public key and making it
  available to copy let's just leave this as an info section on this page and
  also show the npub along with the raw hex group public key that we're
  currently showing. So just an info section don't need the copy button but show
  both formats."
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-4f476518-67b9-4940-86ad-d24153a1a4fa.png`
- `Expected intent`: The group key panel should explain identity context without
  presenting a primary action. It should display both user-facing Nostr `npub`
  and raw hex group public key values, with no "Copy group public key" button on
  this step.
- `Likely owner`: `igloo-ui` for the shared `CreateFlowShareSelection` layout
  and API; `igloo-pwa` for passing the encoded `npub` or a structured key model.
  Existing PWA dashboard helpers already derive `npub` from hex.
- `Universalization`: use the same key-format vocabulary as the dashboard
  identity card: `npub` for default human-facing identity, hex for raw
  technical/debug identity. Avoid introducing another copy-control pattern on
  intermediate create-flow info panels.
- `Status`: captured

### UX-006: Correction - Select Share count matches current default

- `Surface`: Create Keyset flow, step 2 Select Share
- `Client`: `pwa`
- `Category`: correction
- `Severity`: none
- `Raw feedback`: Earlier feedback said the Select Share step only offered two
  choices for an expected 2-of-3 keyset.
- `Correction`: User retracted this on 2026-06-19. The default flow was
  creating a 2-of-2 keyset, not 2-of-3, so two selectable shares was correct.
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-dffcc801-6182-48f4-8a71-f3d9b23fcc06.png`
- `Expected intent`: No implementation change. For 2-of-2, showing two local
  share candidates is correct.
- `Likely owner`: none
- `Universalization`: none
- `Status`: rejected

### UX-007: Correction - Distribute Shares count matches current default

- `Surface`: Create Keyset flow, step 4 Distribute Shares
- `Client`: `pwa`
- `Category`: correction
- `Severity`: none
- `Raw feedback`: Earlier feedback said Distribute Shares only prompted one
  remote package for an expected 2-of-3 keyset.
- `Correction`: User retracted this on 2026-06-19. The flow was actually
  2-of-2, so after saving one local share, one remote distribution package is
  correct.
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-a9bc4f42-d7fe-4122-a1b1-aa7f1c763126.png`
- `Expected intent`: No implementation change. For 2-of-2, one saved local
  share plus one remote package is correct.
- `Likely owner`: none
- `Universalization`: none
- `Status`: rejected

### UX-008: Distribution permission chips do not follow strict permission colors

- `Surface`: Create Keyset flow, step 4 Distribute Shares, Permissions chips
- `Client`: `pwa`
- `Category`: visual, paper mismatch, accessibility
- `Severity`: medium
- `Raw feedback`: "When I am creating the package to distribute there is the
  small bit of permissions UI that has the four different permissions that can
  be enabled and disabled and this is not fully following the color scheme that
  we have where there is a strict color scheme for these permissions. They need
  to show up and glow brighter or be dimmed when they are deactivated."
- `Evidence`: `/var/folders/dq/xkm6n6s1687cdwkx1tcthdxh0000gn/T/codex-clipboard-cd78e17f-ff27-4ad0-bf69-27782788ea98.png`
- `Expected intent`: `SIGN`, `ECDH`, `PING`, and `ONBOARD` should use the
  canonical permission colors in both active and inactive states. Active chips
  should read as enabled with brighter/glowing colored treatment; inactive chips
  should remain visibly tied to their permission color while clearly dimmed.
- `Likely owner`: `igloo-ui` Create Flow distribution permission chip styling.
  Paper already shows strict permission-color references for distribution and
  peer policy chips.
- `Universalization`: extract or standardize a shared permission-chip treatment
  so distribution, dashboard permissions, signer state tags, and policy prompts
  use the same color vocabulary and active/inactive contrast rules.
- `Status`: captured

### UX-009: Missing button feedback, loading states, and transitions across flows

- `Surface`: Cross-app shared UI, with recent examples in Create Keyset,
  Select Share, Save Profile, and Distribute Shares
- `Client`: `both`
- `Category`: interaction, state, accessibility, visual
- `Severity`: high
- `Raw feedback`: "Another generic set of feedback across these recent
  screens, but this will also apply across all screens, is that the button
  feedback and interactions are non-existent and there seems to be a huge lack
  of loading states and transition states between states within a screen and
  then moving between screens."
- `Evidence`: Live smoke walkthrough observation across recent create-flow
  screens.
- `Expected intent`: Buttons and controls should feel tactile and responsive:
  hover, focus, pressed, disabled, submitting, success, and error states should
  be visible. Async actions should expose loading states instead of appearing
  frozen. Step changes and within-screen state changes should transition with
  enough motion to preserve context without feeling slow or decorative.
- `Likely owner`: `igloo-ui` for shared button/control primitives, task-shell
  transitions, and common loading affordances; `igloo-pwa` and `igloo-home` for
  passing pending/submitting state from their host workflows.
- `Universalization`: define a shared interaction-state contract for buttons,
  icon buttons, cards, list rows, permission chips, and task-step transitions.
  Prefer interruptible CSS transitions for hover/press/focus/toggle states,
  subtle `scale(0.96)` press feedback where appropriate, explicit loading
  labels/spinners for async boundaries, and split/staggered enter transitions
  for step content.
- `Status`: captured

### UX-010: Signer screen still uses test/prototype layout instead of Paper layout

- `Surface`: Signer dashboard / operator signer screen
- `Client`: `both`
- `Category`: layout, hierarchy, visual, paper mismatch
- `Severity`: high
- `Raw feedback`: "This signer screen seems to have a test layout and it does
  not have the official layout that we had mapped out originally in igloo paper
  and then it should also be an igloo UI. So this needs a total refactor and
  overhaul."
- `Evidence`: Live smoke walkthrough observation.
- `Expected intent`: The signer screen should be implemented as the official
  Paper-derived dashboard surface, not a temporary or test-style operator panel.
  It should align with the original `igloo-paper` signer dashboard structure,
  hierarchy, status hero, peer/readiness presentation, policy/permission
  sections, pending approvals, logs, and runtime controls.
- `Likely owner`: `igloo-ui` for the canonical `OperatorSignerPanel` layout and
  reusable dashboard primitives; `igloo-pwa` and `igloo-home` for wiring the
  shared panel to their runtime state; `igloo-shared` or `bifrost-rs` only where
  missing telemetry prevents the Paper layout from being populated honestly.
- `Universalization`: treat this as a hard-cut signer dashboard alignment pass:
  compare `repos/igloo-paper/screens/dashboard/1-signer-dashboard` plus
  `repos/igloo-paper/design/patterns/signer-states-*` against the current
  `igloo-ui` signer panel, replace prototype-only composition with shared
  dashboard primitives, and explicitly track any runtime data gaps.
- `Status`: captured

## Universalization Queue

Use this section after the walkthrough to combine repeated feedback into fewer,
better implementation slices.

- Shared component fixes:
  - Ensure visible info/help icons expose accessible hover/focus content, or
    remove the icon when no help content exists. See `UX-001`.
  - Replace bare help icons in Create Flow fields with real `HelpHint`
    affordances, or remove them where visible helper text is sufficient. See
    `UX-002`.
  - Keep public task shell background and framing consistent between create-flow
    steps. See `UX-003`.
  - Make shared key/package summary rows responsive at half-screen desktop
    widths. See `UX-004`.
  - Convert Select Share group public key from a copy action row into an
    info-only key details panel that shows `npub` and hex. See `UX-005`.
  - Standardize permission-chip active/inactive styling against the Paper color
    vocabulary for `SIGN`, `ECDH`, `PING`, and `ONBOARD`. See `UX-008`.
  - Add shared tactile interaction states and async loading affordances to
    buttons, icon buttons, rows, cards, permission chips, and public task
    screens. See `UX-009`.
  - Replace the prototype/test-style signer panel with the official
    Paper-aligned signer dashboard primitives. See `UX-010`.
- Shared copy/vocabulary fixes:
  - Decide whether Create Keyset field-level tooltip copy is canonical design
    content. Paper has helper text and a generic tooltip pattern, but not a full
    per-field tooltip contract for the current screen. See `UX-002`.
- Shared flow/state fixes:
  - Reuse the dashboard key-format model where possible so Create Flow presents
    group public keys consistently as `npub` plus hex. See `UX-005`.
  - Audit every async create/import/onboard/distribute transition so users see a
    pending/submitting/loading state before the next screen or state appears.
    See `UX-009`.
  - Identify signer dashboard data gaps separately from layout gaps so the UI
    can distinguish missing runtime telemetry from incomplete component design.
    See `UX-010`.
- App-specific fixes:
- Paper/reference follow-ups:
- Test or visual-harness follow-ups:
  - Add or extend visual coverage for the create-flow sequence at a narrow
    desktop viewport so step-to-step hue changes and horizontal overflow are
    caught. See `UX-003` and `UX-004`.
  - Include a visual assertion or screenshot review point for permission-chip
    active/inactive color states on Distribute Shares. See `UX-008`.
  - Add interaction-state review coverage for shared buttons and task-flow async
    boundaries: hover/focus/pressed/disabled/loading and step transitions. See
    `UX-009`.
  - Add a signer-dashboard Paper comparison pass for PWA and Home once the
    `OperatorSignerPanel` overhaul lands. See `UX-010`.

## Validation Targets

Use the smallest check that proves each fix. For Paper-to-UI visual alignment,
the default comparison loop is:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

The Markdown comparison report is written to:

```bash
.tmp/visual/igloo-pwa/comparison-report.md
```
