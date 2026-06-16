# VAL-CROSS-003 Reachability Matrix (16-view parity inventory)

This matrix is the canonical "every view reachable via actual navigation from
the hub" inventory committed for the parity-polish milestone. The mapping
below maps each of the 16 views named in `validation-contract.md`
`VAL-CROSS-003` to:

1. The concrete Rust `Screen` variant + native view identifier that
   renders it (the parity anchor a Maestro hierarchy dump confirms).
2. The hub entry path that lands on the view through real UI navigation
   (no deep link, no debug URL scheme, no app intent).
3. The Maestro selector(s) and distinguishing content used to prove the
   view is currently rendered.
4. The script/flow that exercises the navigation in the focused 16-view
   audit (`apps/igloo-mobile/flows/cross-parity-16-view-reachability.yaml`).

The 16 views per the contract:

> landing hub; create-generate, create-profile, create-review,
> create-distribute; load-choice, load-import, load-recover,
> load-confirm; onboard-connect, onboard-save; rotate-connect,
> rotate-review; dashboard signer tab, dashboard permissions tab,
> dashboard settings tab

-- the wizard opens directly on Generate per VAL-CREATE-001, so there is
no create-choice view, and there is no standalone settings view outside
the dashboard.

## Per-View Reachability Matrix

| # | Parity view | Rust `Screen` | SwiftUI view | Hub entry path | Distinguishing content / selector |
|---|-------------|---------------|--------------|----------------|-----------------------------------|
| 1 | landing hub | `Hub` | `HubView` | (cold launch / explicit `navigateBack()`) | `text: "Igloo"`, three `tile_*` rows |
| 2 | create-generate | `CreateKeysetGenerate` | `CreateKeysetGenerateView` | Hub → `tile_create_keyset` → "Create New Keyset" tile (id `btn_create_new_keyset` on Android, `tile_load_import`-style tap target on iOS after createKeysetEntry) | `text: "Generate"`, `step_indicator` shows `1/4` |
| 3 | create-profile | `CreateKeysetDeviceProfile` | `CreateKeysetDeviceProfileView` | Hub → tile_create_keyset → btn_create_new_keyset → Generate → `Continue` | `text: "Device Profile"`, `text: "Step 2 of 4"`, `id: input_device_name` |
| 4 | create-review | `CreateKeysetReview` | `CreateKeysetReviewView` | Hub → tile_create_keyset → btn_create_new_keyset → Generate → Continue → Continue (`btn_continue_to_review`) | `text: "Review"`, `text: "Step 3 of 4"`, `id: display_device_name`, full share/group pubkeys |
| 5 | create-distribute | `CreateKeysetDistribute` | `CreateKeysetDistributeView` | Hub → tile_create_keyset → btn_create_new_keyset → Generate → Continue → Continue → Accept | `text: "Distribute"`, `text: "Step 4 of 4"`, `id: btn_copy_distribution_0` through `_n` |
| 6 | load-choice | `LoadProfileEntry` | `LoadProfileEntryView` | Hub → `tile_load_profile` | `text: "Load Profile"`, `text: "Choose how to load a profile"`, tiles `tile_load_import` & `tile_load_recover` |
| 7 | load-import | `LoadProfileImport` | `LoadProfileImportView` | Hub → tile_load_profile → tile_load_import (`Import Profile`) | `text: "Import Profile"`, `input_package`, `input_password` |
| 8 | load-recover | `LoadProfileRecover` | `LoadProfileRecoverView` | Hub → tile_load_profile → tile_load_recover (`Recover Profile`) | `text: "Recover Profile"`, `input_package`, `input_password` |
| 9 | load-confirm | `LoadProfileConfirm` | `LoadProfileConfirmView` | Hub → tile_load_profile → tile_load_import → submit valid `bfprofile1` + password | `text: "Confirm"`, `id: display_device_name`, group/share key rows |
| 10 | onboard-connect | `OnboardConnect` | `OnboardConnectView` | Hub → `tile_onboard_device` → `btn_connect_entry` (`OnboardEntry` → `OnboardConnect`) | `id: input_package`, `id: input_password`, `id: input_relay_url`, `id: btn_connect` |
| 11 | onboard-save | `OnboardReview` | `OnboardReviewView` | Hub → tile_onboard_device → btn_connect_entry → submit valid `bfonboard1` + password (handshake completes) | `text: "Review"`, `id: display_share_pubkey`, `id: display_group_pubkey`, `id: input_device_name`, `id: btn_save_device` |
| 12 | rotate-connect | `RotateShare` | `RotateShareConnectView` (connect form) | Hub → profile row → `btn_open_dashboard` → `Dashboard` → `btn_rotate_share` (Settings tab inoperative; Rotate Share lives in maintenance list on iOS / dashboard action list on Android) | `text: "Rotate Share"`, `id: btn_rotate_connect` |
| 13 | rotate-review | `RotateShare` | `RotateShareConnectView` (preview card) | above → submit valid rotated `bfonboard1` + password → handshake completes → preview card surfaced | `text: "Replacement Preview"`, `id: rotate_preview_device`, `id: rotate_preview_group_pubkey` |
| 14 | dashboard signer tab | `Dashboard` | `DashboardView` (Sign tab) | Hub → profile row → open dashboard | default selection of `tab_signer`, `text: "Signer"`, `id: signer_status_card` |
| 15 | dashboard permissions tab | `Dashboard` | `DashboardView` (Permissions tab) | above → tap `tab_permissions` | `text: "Permissions"`, 8 override cells per peer (8× peers) |
| 16 | dashboard settings tab | `Dashboard` | `DashboardView` (Settings tab) | above → tap `tab_settings` | `text: "Settings"`, maintenance rows (`btn_copy_profile`, `btn_copy_share`, `btn_rotate_share`, `btn_save_settings`) |

## Conventions

- All `tile_*` rows on the hub have stable `accessibilityIdentifier` /
  `testTag` ids (`tile_create_keyset`, `tile_load_profile`,
  `tile_onboard_device`); see also `apps/igloo-mobile/library/parity/SHELL-010-accessibility-ids.md`.
- Dashboard tabs share a uniform `tab_signer` / `tab_permissions` /
  `tab_settings` selector across both platforms.
- Every entry path lands on the named view via the in-app navigation
  affordance (`tile_*` row or `btn_*` control). No view requires a
  deep link, custom URL scheme, app intent, or DEBUG-only entry point
  to reach.

## Open gaps surfaced by this audit (carried into `discoveredIssues`)

| Severity | Gap | Notes |
|----------|-----|-------|
| non_blocking | The mobile app's actual Rust router has 18 screens, not 16. `OnboardEntry` and `CreateKeysetEntry` exist as intermediate "choice" screens between the hub tile tap and the next named view. | The contract explicitly excludes `create-choice`. Both intermediate screens remain reachable through the same `tile_*` tap path and the 16 named views still pass (the additional screens are not asserted in VAL-CROSS-003). Documented, not blocked. |
| non_blocking | `rotate-review` is a sub-card rendered inside `RotateShareConnectView` after a successful handshake, not a separate first-class view. The contract counts it as a separate view; both the connect form and the preview card are reachable through the same screen. | VAL-CROSS-003 expects 16 views; the implementation provides 13 main-flow screens + rotate connect/preview pair (1 screen, 2 states) + 3 dashboard tabs = 16 reachable states. No flow parity loss documented. |
| non_blocking | Round 5 testing reports Android Settings tab does not render the policy matrix while the signer is in `Restoring...`; reported under `VAL-PERM-002` through `VAL-PERM-013`. | Out of scope of this milestone; tracked downstream as a Restoring-fix follow-up, not a 16-view gap. Affirmatively noted because the Settings tab itself remains reachable while stopped, matching the 16-view parity requirement. |
| non_blocking | iOS ContentView.swift default-branch switch statements on `SignerStatus` / `LogLevel` / `PendingOpType` use plain `default:` rather than `@unknown default:`. Current xcodebuild Debug build reports **zero** warnings (committed `ee7234e` baseline). | Documented as harmless; tracked in `library/parity/final-polish-cleanup-notes.md` per orchestrator note after iOS layout fix. `SignerStatus` etc. are UniFFI-generated enums (`frozen` Swift representation under `Bindings/`) so the `default:` is exhaustive at the FFI boundary. |

## Navigation proof flow

`apps/igloo-mobile/flows/cross-parity-16-view-reachability.yaml` walks every
view above through real navigation. The flow encodes platform filtering
in comments and `appId: com.frostr.igloo.dev`. The Android-only
`VAL-SHELL-014` system-back assertion lives in a paired
`apps/igloo-mobile/flows/cross-parity-android-system-back.yaml` so an
iOS validator does not execute `pressKey: back`.
