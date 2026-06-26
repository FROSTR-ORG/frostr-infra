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

## 2026-06-22 Update

The implementation has moved past the safe-boundary-only state described in
this point-in-time audit. `igloo-pwa` now opens the shared
`OnboardDeviceSponsorDialog` from Settings, accepts explicit protected
`bfshare` source material, creates a `bfonboard` package through
`createSettingsOnboardingPackageFromBfshare`, and tests create/copy/save/QR,
loading, cancel-confirmation, password mismatch, and source-material failure
states. Paper source cleanup is complete for the current sponsor model:
Configure Device and Package Handoff are the canonical Settings modal states,
with cancel-confirm and failure states covered by shared dialog/form treatments.
Device Onboarded and Onboarding Failed remain recipient-side onboarding states,
not Settings sponsor-package states unless product later adds live recipient
tracking.

## Requirement Audit

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Settings must be a Paper-style right-side sidebar, not the old routed tab layout. | `repos/igloo-ui/src/components/flows/OperatorSettingsSidebar.tsx`; `repos/igloo-pwa/src/App.tsx`; visual captures `dashboard-settings`, `dashboard-settings-security`, `dashboard-settings-mobile`. | Achieved for PWA Settings. |
| Sidebar must contain the Paper section order: Device Profile, Group Profile, Onboard Device, Replace Share, Export and Backup, Profile Security. | `repos/igloo-ui/test/OperatorPanels.test.tsx`; `test/igloo-pwa/support/pages.ts`; `test/igloo-pwa/visual-manifest.json` rows for `dashboard-settings` and `dashboard-settings-security`. | Achieved. |
| Device Profile must expose profile name, profile password action, relays, add/remove relay controls, and local share context. | Shared sidebar component and package-local tests; PWA settings visual capture. | Achieved. |
| Group Profile must show read-only keyset metadata. | `deriveGroupSummary` PWA path, `OperatorSettingsSidebarGroupProfile`, App unit tests, and visual capture. | Achieved. |
| Runtime-only advanced controls must not appear in the Paper sidebar; PWA browser preferences should appear as their own Paper-backed group. | PWA passes `showAdvancedSettings={false}` while passing `browserPreferences`; the Paper `502-0` Settings artboard now includes Browser Settings for Remember Browser State, Open Signer After Import, and Prefer Install Prompt. | Achieved for PWA. |
| Save controls should appear only when settings are dirty. | App unit test covers hidden default state, dirty message, and disabled save while signer state prevents live apply. | Achieved. |
| Copy/export actions should use Paper modal treatments. | `ExportPackageModal`, profile password dialog, visual rows `dashboard-export-profile` and `dashboard-profile-password`. | Achieved for visible Settings export/password entry points. |
| Clear Credentials must use a Paper-style destructive confirmation and actually clear the selected profile. | Shared `ClearCredentialsDialog`, App confirm path, App unit test, and visual row `dashboard-clear-credentials`. | Achieved. |
| Lock Profile must be the visible Paper row, while legacy logout wiring remains compatible. | PWA passes `lockProfileAction` with `Lock Profile` / `Lock`; `OperatorSettingsSidebar` prefers `lockProfileAction` over legacy `logoutAction`; tests cover both paths. | Achieved. |
| Replace Share must launch the Paper-aligned package-entry and runtime state panels. | Shared replace panels in `igloo-ui`; PWA DEV visual seams; visual rows `dashboard-replace-share-entry`, `dashboard-replace-share-applying`, `dashboard-replace-share-failed`, `dashboard-replace-share-success`. | Achieved for Settings-launched replace flow. |
| The Settings sidebar must be usable on narrow viewports without horizontal overflow. | `dashboard-settings-mobile` capture and page-object overflow assertions for document, panel, and scroll body. | Achieved. |
| Onboard Device from Settings must not fake a sponsor package by cloning the local share. | PWA requires explicit protected `bfshare` source material and routes package creation through `createSettingsOnboardingPackageFromBfshare`; UI/PWA tests cover source-package fields, source-material failure, and create/copy/save/QR handoff states. | Achieved for the PWA explicit-source flow. |
| Onboard Device from Settings should eventually create the real post-setup sponsor package flow. | Paper now exports `PA0-0` / `PA1-0` as `screens/dashboard/3d-onboard-device-modal` and `screens/dashboard/3e-onboard-package-handoff-modal`; PWA visual manifest includes both the configure modal and package handoff modal; App tests cover create/copy/save/QR handoff behavior. | Achieved. |

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
- `dashboard-settings-onboard-device`: `aligned`, Paper exists, PWA exists
- `dashboard-settings-onboard-handoff`: `aligned`, Paper exists, PWA exists

The Settings Onboard row is no longer a boundary-panel placeholder. It tracks
the shared explicit-`bfshare` sponsor configure modal; package handoff is also
captured against the exported
`screens/dashboard/3e-onboard-package-handoff-modal` Paper screen.

## Open Gap

The original Settings-specific blocker, post-setup Onboard Device sponsorship
from Settings, is resolved for the PWA explicit-source path and the current
Paper source.

Current source-material boundary:

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
- The Settings source-material path is now explicit re-entry of a protected
  target-member `bfshare`; PWA does not persist raw remote shares or clone the
  current local share.
- Current Paper exports include `PA0-0` / `PA1-0` as
  `screens/dashboard/3d-onboard-device-modal` and
  `screens/dashboard/3e-onboard-package-handoff-modal`. The previous
  `onboard-sponsor/*` paths have been retired in the current source-of-truth
  docs.
- Device Onboarded and Onboarding Failed belong to recipient-side onboarding,
  not the Settings sponsor-package flow. Settings creates a package handoff and
  returns to the dashboard; it does not observe the recipient handshake.
- Dirty cancel uses the shared confirmation dialog. Creation failures are inline
  form alerts, and copy/save/QR failures are inline handoff status alerts inside
  the same Package Handoff modal.
- `make igloo-paper-verify STRICT=1` passed Paper reconciliation in this
  workspace during the original audit. Current live Paper inspection on
  2026-06-22 shows 72 artboards, including `PA0-0` and `PA1-0`.

Required next work: keep the PWA explicit-`bfshare` source-material boundary
intact as future Settings polish continues.

Implementation path:
[`../plans/settings-onboard-sponsor-unblock-plan-2026-06-19.md`](../plans/settings-onboard-sponsor-unblock-plan-2026-06-19.md).

## Completion Decision

Do not mark the full goal complete yet.

The Paper Settings sidebar and the PWA Settings Onboard configure/handoff flow
are implemented and verified in PWA. Do not mark the broader smoke-polish goal
complete from this audit alone: Paper source cleanup, live runtime telemetry,
and other dashboard/recover follow-ups remain outside this Settings-only scope.
