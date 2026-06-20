# Settings Sidebar Alignment Audit - 2026-06-19

Point-in-time audit for the first smoke-test goal: bring the Paper Settings
sidebar reference into `igloo-ui`, the shared contracts in `igloo-shared` where
needed, and the consuming `igloo-pwa` runtime.

## Scope

Source request:

- Paper reference: `repos/igloo-paper/screens/dashboard/3-settings-lock-profile/`
- Component reference: `repos/igloo-paper/design/components/settings-sidebar/`
- Runtime path: `repos/igloo-pwa` Settings tab opens the shared `igloo-ui`
  sidebar over the signer dashboard

This audit covers the Settings sidebar and the sidebar-launched Settings
actions. It does not claim broader dashboard parity.

## Requirement Audit

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Settings must be a Paper-style right-side sidebar, not the old routed tab layout. | `repos/igloo-ui/src/components/flows/OperatorSettingsSidebar.tsx`; `repos/igloo-pwa/src/App.tsx`; visual captures `dashboard-settings`, `dashboard-settings-security`, `dashboard-settings-mobile`. | Achieved for PWA Settings. |
| Sidebar must contain the Paper section order: Device Profile, Group Profile, Onboard Device, Replace Share, Export and Backup, Profile Security. | `repos/igloo-ui/test/OperatorPanels.test.tsx`; `test/igloo-pwa/support/pages.ts`; `test/igloo-pwa/visual-manifest.json` rows for `dashboard-settings` and `dashboard-settings-security`. | Achieved. |
| Device Profile must expose profile name, profile password action, relays, add/remove relay controls, and local share context. | Shared sidebar component and package-local tests; PWA settings visual capture. | Achieved. |
| Group Profile must show read-only keyset metadata. | `deriveGroupSummary` PWA path, `OperatorSettingsSidebarGroupProfile`, App unit tests, and visual capture. | Achieved. |
| Runtime-only advanced settings and browser settings must not appear in the Paper sidebar. | PWA passes `showAdvancedSettings={false}`; App unit test asserts `Advanced`, Browser Settings, and reset/wipe controls are absent. | Achieved for PWA. |
| Save controls should appear only when settings are dirty. | App unit test covers hidden default state, dirty message, and disabled save while signer state prevents live apply. | Achieved. |
| Copy/export actions should use Paper modal treatments. | `ExportPackageModal`, profile password dialog, visual rows `dashboard-export-profile` and `dashboard-profile-password`. | Achieved for visible Settings export/password entry points. |
| Clear Credentials must use a Paper-style destructive confirmation and actually clear the selected profile. | Shared `ClearCredentialsDialog`, App confirm path, App unit test, and visual row `dashboard-clear-credentials`. | Achieved. |
| Lock Profile must be the visible Paper row, while legacy logout wiring remains compatible. | PWA passes `lockProfileAction` with `Lock Profile` / `Lock`; `OperatorSettingsSidebar` prefers `lockProfileAction` over legacy `logoutAction`; tests cover both paths. | Achieved. |
| Replace Share must launch the Paper-aligned package-entry and runtime state panels. | Shared replace panels in `igloo-ui`; PWA DEV visual seams; visual rows `dashboard-replace-share-entry`, `dashboard-replace-share-applying`, `dashboard-replace-share-failed`, `dashboard-replace-share-success`. | Achieved for Settings-launched replace flow. |
| The Settings sidebar must be usable on narrow viewports without horizontal overflow. | `dashboard-settings-mobile` capture and page-object overflow assertions for document, panel, and scroll body. | Achieved. |
| Onboard Device from Settings must not fake a sponsor package by cloning the local share. | `igloo-shared` readiness helper returns unavailable for saved-profile local-share-only state; PWA uses explicit `SETTINGS_ONBOARD_SPONSORSHIP_INPUT`; UI/PWA tests assert no `Ready to Onboard Device` or `Configure Device` state appears. | Safe boundary achieved; final sponsor flow not achieved. |
| Onboard Device from Settings should eventually create the real post-setup sponsor package flow. | No checked-in sponsor Paper screens exist for the referenced sponsor artboards; backlog tracks missing Paper sponsor screens and app-side producer/source-material contract. | Not achieved; requires Paper/source-material work. |

## Verification Evidence

Commands run during the current Settings alignment pass:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/browser-onboarding.test.ts
npm --prefix repos/igloo-shared run test:typecheck
npm --prefix repos/igloo-ui test -- test/OperatorPanels.test.tsx
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
npm --prefix repos/igloo-pwa run build:app
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
npm --prefix test run test:guards:visual
npm --prefix test run test:guards:visual:captures
npm --prefix test run test:guards:docs
make igloo-paper-verify STRICT=1
git diff --check
```

The latest visual report at `.tmp/visual/igloo-pwa/comparison-report.md` shows:

- `dashboard-settings`: `aligned`, Paper exists, PWA exists
- `dashboard-settings-security`: `aligned`, Paper exists, PWA exists
- `dashboard-settings-mobile`: `aligned`, Paper exists, PWA exists
- `dashboard-settings-onboard-device`: `needs work`, Paper exists, PWA exists

The `needs work` Settings row is intentional. It records the boundary panel
until the real post-setup sponsor flow exists.

## Open Gap

The only Settings-specific gap that blocks a full completion claim is
post-setup Onboard Device sponsorship from Settings.

Current hard boundary:

- Saved PWA profiles retain only this device's encrypted local share.
- A valid remote onboarding package needs another member's source material.
- The app must not clone the current local share to sponsor a new device.
- The package producer itself is already defined outside Paper:
  `igloo-shared` exposes `createBrowserOnboardSponsorshipPackage`,
  `igloo-pwa` calls it from `createOnboardingPackageForShare` during the
  create/distribute flow, `igloo-home` exposes
  `createGeneratedOnboardingPackage`, and `bifrost-rs` owns
  `encode_bfonboard_package`. Those paths all require explicit target-member
  share material.
- The Settings gap is not the `bfonboard` format or encoder. The missing piece
  is a Settings-time source-material path for the target remote member after
  setup has purged `pendingKeyset` / generated share secrets.
- No checked-in Paper sponsor screens currently exist. `repos/igloo-paper/artboard-map.json`
  exports recipient Onboard screens only (`8SU-0`, `8FO-0`, `8JF-0`, `O61-0`),
  and `repos/igloo-paper/export-metadata.json` lists only Input Package,
  Onboard Device, Onboarding Failed, and Save Profile sections for the Onboard
  design group. A live Paper MCP inspection on 2026-06-20 found 70 current
  artboards in `igloo-ui-shared` and none of the sponsor IDs below. The stale
  `repos/igloo-paper/design/components/navigation-layout/app-header.md` doc
  still records AppHeader usage for sponsor artboards `1B3Q-0`, `1B5X-0`,
  `1B84-0`, `1BAB-0`, and `1BCI-0`, but those artboards are absent from the
  current live file, not exported as canonical sponsor screens, and not
  represented in the design contract. The sponsor flow is also named in the
  older hard-cut plan as
  `onboard-sponsor/1-configure-device`, `onboard-sponsor/2-package-handoff`,
  `onboard-sponsor/2b-device-onboarded`,
  `onboard-sponsor/2c-onboarding-failed`, and
  `onboard-sponsor/2d-cancel-confirm-modal`.
- `make igloo-paper-verify STRICT=1` passed Paper reconciliation in this
  workspace. That verifier fails when a live Paper artboard is neither exported
  nor classified in `artboard-policy.json`, so the missing sponsor flow is not a
  simple stale-export omission in the current Paper file.

Required next work:

1. Confirm or export the Paper sponsor screens.
2. Define the Settings source-material capability: re-enter/generate/import the
   target member share material, or intentionally route the user back to
   create/rotate while that material is still in memory.
3. Reuse `igloo-shared`'s existing sponsorship package builder with that real
   source material.
4. Replace the boundary panel with the Paper sponsor flow in `igloo-ui` and
   `igloo-pwa`.

Implementation path:
[`../plans/settings-onboard-sponsor-unblock-plan-2026-06-19.md`](../plans/settings-onboard-sponsor-unblock-plan-2026-06-19.md).

## Completion Decision

Do not mark the full goal complete yet.

The Paper Settings sidebar itself is implemented and verified in PWA, but the
Onboard Device action still intentionally opens a safe boundary panel instead
of the final sponsor flow. That is the correct current behavior until Paper and
runtime source-material contracts exist.
