# Settings Onboard Sponsor Unblock Plan - 2026-06-19

This plan records the Settings-sidebar sponsor flow unblock:
`Settings -> Onboard a Device` became a real post-setup sponsor flow that uses
explicit source material instead of the former safe package-producer boundary
panel.

## 2026-06-22 Status Update

The PWA/UI/source-material portion of this unblock plan has landed. Settings
now opens the shared sponsor dialog, requires explicit protected `bfshare`
source material, and uses the existing `bfonboard` producer without cloning the
current local share. Paper now exports the current sponsor configure and handoff
screens as dashboard modal states.

Follow-up decision: no separate Settings sponsor artboards are needed for
Device Onboarded, Onboarding Failed, or Cancel Confirm in the current product
model. Settings creates a package handoff; it does not run or observe the
recipient-side onboarding handshake. Package Handoff is the canonical terminal
state, creation failures are inline form alerts, handoff copy/save/QR failures
are inline status alerts, and dirty cancel uses the shared confirmation dialog.
If product later adds live recipient tracking to the Settings sponsor flow, that
would be a new Paper state rather than missing coverage for this flow.

## Current State

- The Paper Settings sidebar itself is implemented in `igloo-ui` and consumed by
  `igloo-pwa`.
- `igloo-shared` exposes:
  - sponsorship readiness status for saved-profile local-share-only hosts
  - a package builder for callers that already hold explicit remote member
    source material
- The package producer is already defined in the implementation:
  - `igloo-shared`: `createBrowserOnboardSponsorshipPackage`
  - `igloo-pwa`: `createOnboardingPackageForShare` in the create/distribute flow
  - `igloo-home`: `createGeneratedOnboardingPackage` /
    `create_generated_onboarding_package_command`
  - `bifrost-rs`: `encode_bfonboard_package`
  These paths all take explicit target-member share material. The Settings gap
  is how to obtain that material after setup, not how to encode `bfonboard`.
- `igloo-pwa` now opens the shared Settings sponsor dialog and requires explicit
  protected `bfshare` source material before producing a `bfonboard` handoff.
- `repos/igloo-paper` now exports the current sponsor screens as
  `screens/dashboard/3d-onboard-device-modal` and
  `screens/dashboard/3e-onboard-package-handoff-modal`.
- A live Paper MCP inspection on 2026-06-22 found 72 current artboards in
  `igloo-ui-shared`, including `PA0-0` and `PA1-0`. The older
  `onboard-sponsor/*` paths are retired unless product design intentionally
  restores those states.

See
[`../reports/settings-sidebar-alignment-audit-2026-06-19.md`](../reports/settings-sidebar-alignment-audit-2026-06-19.md)
for the requirement audit and validation evidence.

## Non-Negotiable Boundary

Do not implement sponsorship by cloning the current local share.

A valid sponsor flow must create a package for a remote member from one of:

- an nsec-derived keyset plan
- a threshold of source shares
- an outside-runtime package producer with explicit remote-member source
  material

Saved PWA profiles alone do not satisfy that requirement.

## Phase 1 - Confirm Paper Sponsor Source

Owner: `igloo-paper`

Status: complete for the current canonical sponsor source. The live Paper file
and `igloo-paper` export use dashboard modal screens:

- `screens/dashboard/3d-onboard-device-modal`
- `screens/dashboard/3e-onboard-package-handoff-modal`

The older `onboard-sponsor/*` artboard IDs and output paths are retired in the
current source-of-truth docs. Device Onboarded and Onboarding Failed remain
recipient-side onboarding states, not Settings sponsor states; Settings sponsor
cancel/failure states are covered by shared dialog/form treatments.

Validation:

```bash
make igloo-paper-sync
make igloo-paper-verify STRICT=1
```

## Phase 2 - Define Settings Source-Material Capability

Owner: `igloo-shared`

Status: complete for the PWA explicit-`bfshare` source path.

Define how Settings can supply explicit target-member source material to the
existing package producer without persisting raw remote shares in saved PWA
profiles.

The capability should answer:

- Which remote members can be sponsored?
- What source material can Settings obtain for that target member?
- Is the source re-entered, reconstructed from threshold material, generated
  from an nsec-derived plan, imported as a source-share bundle, or only
  available before setup finishes?
- Which relays and peer pubkey should the package use?
- How is the package password supplied?
- What preview data can the UI show without leaking secrets?

Reuse `createBrowserOnboardSponsorshipPackage` as the low-level primitive; only
extend the shared readiness/capability model once Settings has a concrete
source-material path.

## Phase 3 - Build Shared UI Flow

Owner: `igloo-ui`

Status: complete for Configure Device, Package Handoff, failure, loading, and
cancel-confirm states in the shared sponsor dialog. Configure Device and Package
Handoff are exported Paper modal states; cancel-confirm uses the shared
confirmation dialog pattern; creation and handoff failures remain inline alert
states inside the same modal.

Implement the sponsor flow from the exported Paper screens as reusable
components. Expected states:

- Configure Device
- Package Handoff
- Cancel Confirm

Earlier notes listed Device Onboarded and Onboarding Failed here, but those are
recipient-side onboarding outcomes. They are not sponsor-package states unless
Settings grows live recipient tracking.

The flow should accept a producer capability/result from `igloo-shared` rather
than directly depending on `igloo-pwa` or `igloo-paper`.

## Phase 4 - Wire PWA Settings

Owner: `igloo-pwa`

Status: complete for explicit `bfshare` source-material re-entry. PWA opens the
shared sponsor dialog from Settings, creates the package while the signer is
running, and covers create/copy/save/QR plus error/loading/cancel states in unit
tests.

Replace the Settings boundary dialog only when a real producer is available.

Keep this behavior when no producer exists:

- show Package Producer Required
- show required source material
- offer Export Share and Replace Share safe paths
- never expose Configure Device from a saved-profile local-share-only state

Visual coverage exists for both the configure modal and package handoff. The
package handoff row is `dashboard-settings-onboard-handoff` in
`test/igloo-pwa/visual-manifest.json`, backed by
`repos/igloo-paper/screens/dashboard/3e-onboard-package-handoff-modal/screenshot.png`.

## Required Validation

Run the focused checks first:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/browser-onboarding.test.ts
npm --prefix repos/igloo-shared run test:typecheck
npm --prefix repos/igloo-ui test -- test/OperatorPanels.test.tsx
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
npm --prefix repos/igloo-pwa run build:app
```

Then refresh visual evidence:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:guards:visual
npm --prefix test run test:guards:visual:captures
npm --prefix test run test:visual:report
```

Finish with:

```bash
npm --prefix test run test:guards:docs
git diff --check
```

## Completion Criteria

This blocker is resolved for PWA Settings when:

- Paper sponsor configure screen is exported and referenced by the visual
  manifest.
- Paper sponsor handoff screen is exported and referenced by the visual
  manifest.
- `igloo-shared` / PWA use an explicit source-material contract and do not clone
  the current local share.
- `igloo-ui` renders the sponsor flow from shared components.
- `igloo-pwa` opens the sponsor flow from Settings and verifies create/handoff
  behavior.

Remaining non-blocking cleanup: none for the current Settings sponsor-package
flow.
