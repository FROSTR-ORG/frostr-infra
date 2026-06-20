# Settings Onboard Sponsor Unblock Plan - 2026-06-19

This plan unblocks the only Settings-sidebar requirement that is not complete:
`Settings -> Onboard a Device` should become a real post-setup sponsor flow
instead of the current safe package-producer boundary panel.

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
- `igloo-pwa` intentionally passes sponsorship readiness as unavailable:
  saved browser profiles retain this device's encrypted local share only.
- `make igloo-paper-verify STRICT=1` passes, which means the current Paper file
  does not contain unclassified/unexported sponsor artboards.
- A live Paper MCP inspection on 2026-06-20 found 70 current artboards in
  `igloo-ui-shared`; none are the sponsor IDs previously documented in the
  AppHeader usage notes.

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

1. Restore, recreate, or explicitly retire the sponsor artboards documented by
   `repos/igloo-paper/design/components/navigation-layout/app-header.md`. As of
   the 2026-06-20 live Paper inspection, these IDs are stale references and are
   not present in the current file:
   - `1B3Q-0` Onboard Sponsor - 1. Configure Device
   - `1B5X-0` Onboard Sponsor - 2. Package Handoff
   - `1B84-0` Onboard Sponsor - 2b. Device Onboarded
   - `1BAB-0` Onboard Sponsor - 2c. Onboarding Failed
   - `1BCI-0` Onboard Sponsor - 2d. Cancel Confirm (Modal)
2. Confirm whether these older sponsor output paths are still canonical:
   - `onboard-sponsor/1-configure-device`
   - `onboard-sponsor/2-package-handoff`
   - `onboard-sponsor/2b-device-onboarded`
   - `onboard-sponsor/2c-onboarding-failed`
   - `onboard-sponsor/2d-cancel-confirm-modal`
3. If canonical, add them to `repos/igloo-paper/artboard-map.json` with
   sponsor-specific output paths under `screens/onboard-sponsor/`.
4. Update `repos/igloo-paper/export-metadata.json`,
   `repos/igloo-paper/design-contract.json`, and any verifier expectations that
   need the new mapped screens.
5. Run:

```bash
make igloo-paper-sync
make igloo-paper-verify STRICT=1
```

## Phase 2 - Define Settings Source-Material Capability

Owner: `igloo-shared`

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

Implement the sponsor flow from the exported Paper screens as reusable
components. Expected states:

- Configure Device
- Package Handoff
- Device Onboarded
- Onboarding Failed
- Cancel Confirm

The flow should accept a producer capability/result from `igloo-shared` rather
than directly depending on `igloo-pwa` or `igloo-paper`.

## Phase 4 - Wire PWA Settings

Owner: `igloo-pwa`

Replace the Settings boundary dialog only when a real producer is available.

Keep current behavior when no producer exists:

- show Package Producer Required
- show required source material
- offer Export Share and Replace Share safe paths
- never expose Configure Device from a saved-profile local-share-only state

Add visual coverage for the sponsor flow after Paper references exist.

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

This blocker is resolved only when:

- Paper sponsor screens are exported and referenced by the visual manifest.
- `igloo-shared` exposes a real producer/source-material contract.
- `igloo-ui` renders the sponsor flow from shared components.
- `igloo-pwa` opens the sponsor flow from Settings when a producer is available.
- Saved-profile local-share-only PWA state still shows the safe boundary panel.
- Visual report shows the Settings sponsor flow with existing Paper and PWA
  captures.
