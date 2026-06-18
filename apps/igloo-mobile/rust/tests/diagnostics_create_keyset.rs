// ── DiagnosticsCreateKeysetRun — igloo://test-create-keyset URL scheme ──────
//
// mobile-ios-keyset-debug-url-scheme: the iOS shell exposes a debug URL
// scheme that drives the Create Keyset wizard to completion without
// requiring SwiftUI TextField/Button automation (Maestro 2.6.0 cannot
// reliably fill TextFields or trigger Button actions on iOS 26.5).
//
// The URL is of the form:
//
//     igloo://test-create-keyset?group_name=<X>&threshold=<N>&count=<N>\
//         &device_name=<Y>&relay=<ws-url>
//
// The Swift layer parses it and dispatches
// `AppAction::DiagnosticsCreateKeysetRun { ... }` to the Rust actor.
// The actor runs frostr_utils::create_keyset() inline, sets all
// wizard inputs, marks the freshly-built profile Active on the hub,
// populates the dashboard identity block, and emits
// `AppUpdate::StoreKeysetCreatedProfile` so the shell writes the
// decrypted material to native secure storage.
//
// Tests below prove the contract:
//   1. Invalid inputs (threshold > count / count < 2 / threshold < 2 /
//      empty group_name/device_name/relay) → no-op and emit no side
//      effect.
//   2. Valid inputs run the entire wizard inline and emit
//      `StoreKeysetCreatedProfile` with a real, parseable material
//      blob.
//   3. The screen advances directly to `CreateKeysetDistribute`
//      (skipping the DeviceProfile + Review UI picker) so the URL
//      scheme does not depend on SwiftUI affordance taps.
//   4. The hub has the freshly-built profile row marked Active and
//      `dashboard.profile_info` is populated for the embedded signer
//      panel.

use igloo_mobile_core::*;
use k256::elliptic_curve::sec1::ToEncodedPoint;
use k256::SecretKey;

fn dispatch(state: &AppState, action: AppAction) -> AppState {
    let (next, _) = igloo_mobile_core::update(state, &action);
    next
}

fn dispatch_with_effect(
    state: &AppState,
    action: AppAction,
) -> (AppState, Option<igloo_mobile_core::AppUpdate>) {
    igloo_mobile_core::update(state, &action)
}

const VALID_RELAY: &str = "ws://127.0.0.1:8194";

fn deterministic_share(share_idx: u16, byte: u8) -> GeneratedShare {
    generated_share_from_secret(share_idx, [byte; 32])
}

fn deterministic_share_with_prefix(share_idx: u16, start_byte: u8, prefix: &str) -> GeneratedShare {
    for byte in start_byte..=u8::MAX {
        let share = deterministic_share(share_idx, byte);
        if share.share_pubkey_compressed.starts_with(prefix) {
            return share;
        }
    }
    panic!("could not find deterministic share with compressed prefix {prefix}");
}

fn generated_share_from_secret(share_idx: u16, secret: [u8; 32]) -> GeneratedShare {
    let signing_key = SecretKey::from_slice(&secret).expect("deterministic test secret is valid");
    let point = signing_key.public_key().to_encoded_point(true);
    let compressed = hex::encode(point.as_bytes());
    let xonly = hex::encode(&point.as_bytes()[1..]);
    GeneratedShare {
        share_idx,
        share_pubkey: xonly,
        share_pubkey_compressed: compressed,
        share_secret_hex: hex::encode(secret),
        default_label: format!("Share {share_idx}"),
    }
}

#[test]
fn diagnostics_create_keyset_run_noop_when_threshold_exceeds_count() {
    // threshold > count is rejected by the wizard's Generate validation.
    // The diagnostic action must NOT bypass that contract — an early
    // return keeps the state machine consistent so a follow-up normal
    // user flow on the same device does not see a partially-populated
    // wizard.
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "BadShape".into(),
            threshold: 4,
            count: 3,
            device_name: "device-1".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert!(
        side_effect.is_none(),
        "invalid threshold>count must NOT emit StoreKeysetCreatedProfile"
    );
    assert_eq!(
        next.keyset.group_name, "",
        "invalid input must NOT mutate the wizard group_name"
    );
    assert_eq!(
        next.keyset.step,
        KeysetFlowStep::Idle,
        "invalid input must leave wizard at Idle"
    );
    assert!(
        next.hub.profiles.is_empty(),
        "invalid input must NOT insert a hub row"
    );
}

#[test]
fn diagnostics_create_keyset_run_noop_when_threshold_is_one() {
    // threshold == 1 is rejected by `validate_generate()` (ThresholdOne).
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "BelowTwo".into(),
            threshold: 1,
            count: 3,
            device_name: "device-1".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert!(side_effect.is_none(), "threshold==1 must no-op");
    assert_eq!(next.keyset.step, KeysetFlowStep::Idle);
}

#[test]
fn diagnostics_create_keyset_run_noop_when_group_name_empty() {
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "   ".into(),
            threshold: 2,
            count: 3,
            device_name: "device-1".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert!(side_effect.is_none(), "blank group_name must no-op");
    assert_eq!(next.keyset.step, KeysetFlowStep::Idle);
}

#[test]
fn diagnostics_create_keyset_run_noop_when_device_name_empty() {
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DeviceNameTest".into(),
            threshold: 2,
            count: 3,
            device_name: "".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert!(
        side_effect.is_none(),
        "blank device_name must NOT emit StoreKeysetCreatedProfile"
    );
    assert_eq!(next.keyset.step, KeysetFlowStep::Idle);
}

#[test]
fn diagnostics_create_keyset_run_noop_when_relay_empty() {
    let state = AppState::initial();
    let (_, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "RelayTest".into(),
            threshold: 2,
            count: 3,
            device_name: "device-1".into(),
            relay: "".into(),
        },
    );
    assert!(side_effect.is_none(), "blank relay must no-op");
}

#[test]
fn diagnostics_create_keyset_run_emits_store_side_effect_for_valid_inputs() {
    // Happy path: valid inputs → actor runs frostr_utils::create_keyset
    // inline, builds material, populates dashboard, and emits
    // `StoreKeysetCreatedProfile` so the shell can write to Keychain.
    let state = AppState::initial();
    let (_next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert!(
        matches!(
            side_effect,
            Some(AppUpdate::StoreKeysetCreatedProfile {
                ref label,
                ..
            }) if label == "diag-device"
        ),
        "valid inputs must emit StoreKeysetCreatedProfile with the
         diagnostics device_name as label; got: {:?}",
        side_effect
    );
}

#[test]
fn diagnostics_create_keyset_material_carries_xonly_runtime_peers() {
    // The signer runtime subscribes by x-only author pubkey. The stored group
    // members still need compressed SEC1 keys, but `peer_pubkeys` must stay
    // 64-char x-only so onboarding requests from distributed shares are seen.
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeysetPeers".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    let material = match side_effect {
        Some(AppUpdate::StoreKeysetCreatedProfile { material, .. }) => {
            OnboardProfileMaterial::from_bytes(&material).expect("created material parses")
        }
        other => panic!("expected StoreKeysetCreatedProfile, got {:?}", other),
    };
    let mut expected_peer_pubkeys = next
        .keyset
        .bundle
        .as_ref()
        .expect("diagnostic keyset must keep generated bundle")
        .shares
        .iter()
        .filter(|share| share.share_idx != next.keyset.local_share_idx)
        .map(|share| share.share_pubkey.clone())
        .collect::<Vec<_>>();
    expected_peer_pubkeys.sort();

    let mut actual_peer_pubkeys = material.peer_pubkeys.clone();
    actual_peer_pubkeys.sort();
    assert_eq!(actual_peer_pubkeys, expected_peer_pubkeys);
    assert!(
        material
            .peer_pubkeys
            .iter()
            .all(|pubkey| pubkey.len() == 64 && hex::decode(pubkey).is_ok()),
        "runtime peer_pubkeys must be x-only secp256k1 hex"
    );
    assert!(
        material
            .members
            .iter()
            .all(|member| member.pubkey_hex.len() == 66 && hex::decode(&member.pubkey_hex).is_ok()),
        "material members must retain compressed SEC1 keys"
    );
}

#[test]
fn create_keyset_accept_material_preserves_compressed_member_prefixes() {
    // Regression for native-created onboarding packages: source-side material
    // must preserve the dealer's real 02/03 SEC1 member keys. Guessing
    // `02 + xonly` makes recipients whose actual key starts with `03` reject
    // the onboard response as a group/member mismatch, which the UI surfaces
    // as provisioner_offline.
    let share_a = deterministic_share(1, 0x11);
    let share_b = deterministic_share_with_prefix(2, 0x33, "03");

    let mut state = AppState::initial();
    state.keyset.bundle = Some(KeysetBundleRecord {
        group_name: "PrefixParity".into(),
        threshold: 2,
        count: 2,
        group_pubkey: "44".repeat(32),
        shares: vec![share_a.clone(), share_b.clone()],
    });
    state.keyset.local_share_idx = share_a.share_idx;
    state.keyset.device_name = "prefix-source".into();
    state.keyset.relays = vec![VALID_RELAY.into()];

    let (_next, side_effect) = dispatch_with_effect(&state, AppAction::CreateKeysetAccept);
    let material = match side_effect {
        Some(AppUpdate::StoreKeysetCreatedProfile { material, .. }) => {
            OnboardProfileMaterial::from_bytes(&material).expect("created material parses")
        }
        other => panic!("expected StoreKeysetCreatedProfile, got {:?}", other),
    };

    let mut expected_members = vec![
        (share_a.share_idx, share_a.share_pubkey_compressed),
        (share_b.share_idx, share_b.share_pubkey_compressed),
    ];
    expected_members.sort_by_key(|entry| entry.0);
    let mut actual_members = material
        .members
        .iter()
        .map(|member| (member.idx, member.pubkey_hex.clone()))
        .collect::<Vec<_>>();
    actual_members.sort_by_key(|entry| entry.0);

    assert_eq!(
        actual_members, expected_members,
        "created profile material must preserve actual compressed member pubkeys"
    );
}

#[test]
fn diagnostics_create_keyset_run_advances_to_distribute_skipping_ui_pickers() {
    // The URL scheme must not depend on SwiftUI affordance taps, so the
    // actor routes the wizard from Idle directly to Distribute (skipping
    // the DeviceProfile + Review screens that require local-share picker
    // and Accept button taps).
    let state = AppState::initial();
    let (next, _side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert_eq!(
        next.router.screen,
        Screen::CreateKeysetDistribute,
        "diagnostic path must reach CreateKeysetDistribute so the shell's \
         StoreKeysetCreatedProfile handler can advance to Dashboard"
    );
    assert_eq!(
        next.keyset.step,
        KeysetFlowStep::Distribute,
        "wizard step must be Distribute after diagnostics run"
    );
}

#[test]
fn diagnostics_create_keyset_run_pins_accepted_profile_id_for_finish_router() {
    // mobile-create-keyset-distribute-routing proof: the wizard's
    // accepted_profile_id pin must be set so the DistributeFinish handler
    // routes to the freshly-built dashboard (not hub.profiles.first()).
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    let profile_id = match side_effect {
        Some(AppUpdate::StoreKeysetCreatedProfile { profile_id, .. }) => profile_id,
        other => panic!(
            "expected StoreKeysetCreatedProfile side effect, got {:?}",
            other
        ),
    };
    assert!(
        !profile_id.is_empty(),
        "StoreKeysetCreatedProfile must carry a non-empty profile_id"
    );
    assert_eq!(
        next.keyset.accepted_profile_id, profile_id,
        "wizard must pin accepted_profile_id to match the emitted profile_id"
    );
}

#[test]
fn diagnostics_create_keyset_run_inserts_active_row_to_hub() {
    let state = AppState::initial();
    let (next, _) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert_eq!(
        next.hub.profiles.len(),
        1,
        "diagnostic run must insert exactly one hub row"
    );
    assert_eq!(
        next.hub.profiles[0].label, "diag-device",
        "hub row label must mirror the diagnostics device_name"
    );
    assert_eq!(
        next.hub.profiles[0].status,
        ProfileStatus::Active,
        "freshly-built profile row must be marked Active"
    );
}

#[test]
fn diagnostics_create_keyset_run_populates_dashboard_profile_info() {
    // The Distribute step's embedded dashboard identity block (and the
    // signer's Identities tab after Finish) read dashboard.profile_info.
    // The diagnostic action must populate it so the UI never shows an
    // empty identity block for a freshly-built keyset.
    let state = AppState::initial();
    let (next, _) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    let info = next
        .dashboard
        .profile_info
        .expect("dashboard.profile_info must be populated after diagnostic run");
    assert_eq!(info.device_name, "diag-device");
    assert!(
        !info.share_pubkey.is_empty(),
        "dashboard.profile_info.share_pubkey must be derived from the local share"
    );
    assert!(
        !info.group_pubkey.is_empty(),
        "dashboard.profile_info.group_pubkey must be derived from the bundle"
    );
}

#[test]
fn diagnostics_create_keyset_run_builds_distribute_rows_for_non_local_shares() {
    // Distribute rows (one per non-local share) must be populated so
    // the per-share envelope encoding UI has data to render.
    let state = AppState::initial();
    let (next, _) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    assert_eq!(
        next.keyset.distribute.len(),
        2,
        "2-of-3 keyset with local at idx 0 must leave 2 non-local rows"
    );
    assert!(
        next.keyset
            .distribute
            .iter()
            .all(|r| matches!(r.status_chip, DistributeStatus::Pending)),
        "freshly-built distribute rows must start Pending"
    );
}

#[test]
fn diagnostics_create_keyset_distribute_qr_submit_updates_row_package_and_chip() {
    // VAL-QR-001: the distribution QR action must produce a bfonboard1
    // payload for the requested non-local share and leave the user on the
    // Distribute surface with the row marked as QR-delivered.
    let state = AppState::initial();
    let (post_diag, _) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeysetQr".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    let share_idx = post_diag
        .keyset
        .distribute
        .first()
        .expect("diagnostic keyset must create a non-local distribute row")
        .share_idx;
    let expected_peer_pk = post_diag
        .keyset
        .bundle
        .as_ref()
        .expect("diagnostic keyset must keep its generated bundle")
        .shares
        .iter()
        .find(|share| share.share_idx == post_diag.keyset.local_share_idx)
        .expect("diagnostic keyset must keep the selected local share")
        .share_pubkey
        .clone();
    let password = "qr-package-pass".to_string();
    let state = dispatch(
        &post_diag,
        AppAction::CreateKeysetDistributeSetPassword {
            share_idx,
            password: password.clone(),
        },
    );
    let state = dispatch(
        &state,
        AppAction::CreateKeysetDistributeSetConfirm {
            share_idx,
            confirm: password,
        },
    );
    let (state, side_effect) = dispatch_with_effect(
        &state,
        AppAction::CreateKeysetDistributeSubmit {
            share_idx,
            method: "qr".into(),
        },
    );
    match side_effect {
        Some(AppUpdate::PerformKeysetDistribution {
            share_idx: actual_share_idx,
            peer_pk_hex,
            method,
            ..
        }) => {
            assert_eq!(actual_share_idx, share_idx);
            assert_eq!(
                peer_pk_hex, expected_peer_pk,
                "distribution packages must embed the selected local share as the provisioning peer"
            );
            assert_eq!(method, "qr");
        }
        other => panic!("expected PerformKeysetDistribution, got {:?}", other),
    }

    let next = dispatch(
        &state,
        AppAction::CreateKeysetDistributePackageProduced {
            share_idx,
            package: "bfonboard1qrproof".into(),
            method: "qr".into(),
        },
    );
    let row = next
        .keyset
        .distribute_row(share_idx)
        .expect("package-produced must keep the distribute row");
    assert_eq!(row.last_package, "bfonboard1qrproof");
    assert_eq!(row.status_chip, DistributeStatus::Qr);
    assert_eq!(next.router.screen, Screen::CreateKeysetDistribute);
}

#[test]
fn encode_distribute_onboard_embeds_nonzero_provisioning_peer_pk() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let password = "qr-package-pass";
    let peer_pk = "22".repeat(32);

    let package = app.encode_distribute_onboard(
        "11".repeat(32),
        peer_pk.clone(),
        vec![VALID_RELAY.into()],
        "Remote Device".into(),
        password.into(),
    );

    assert!(
        package.starts_with("bfonboard1"),
        "valid distribution input must encode a bfonboard package, got {package}"
    );
    let decoded =
        frostr_utils::decode_bfonboard_package(&package, password).expect("decode package");
    assert_eq!(decoded.peer_pk, peer_pk);
}

#[test]
fn encode_distribute_onboard_rejects_all_zero_peer_pk() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());

    let package = app.encode_distribute_onboard(
        "11".repeat(32),
        "00".repeat(32),
        vec![VALID_RELAY.into()],
        "Remote Device".into(),
        "qr-package-pass".into(),
    );

    assert_eq!(package, "error:invalid_peer_pk");
}

#[test]
fn diagnostics_create_keyset_run_then_distribute_finish_routes_to_dashboard() {
    // End-to-end meaningfulness proof: after the URL-scheme path the
    // storeKeysetCreatedProfile shell handler dispatches
    // CreateKeysetAccepted → which then (in diagnostic mode)
    // auto-finishes to Dashboard via the existing
    // CreateKeysetDistributeFinish action. This matches the
    // mobile-create-keyset-distribute-routing-fix contract.
    let state = AppState::initial();
    let (post_diag, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "DiagKeyset".into(),
            threshold: 2,
            count: 3,
            device_name: "diag-device".into(),
            relay: VALID_RELAY.into(),
        },
    );
    let (profile_id, label, short_id, material, relays) = match side_effect {
        Some(AppUpdate::StoreKeysetCreatedProfile {
            profile_id,
            label,
            short_id,
            material,
            relays,
        }) => (profile_id, label, short_id, material, relays),
        other => panic!("expected StoreKeysetCreatedProfile, got {:?}", other),
    };

    // Shell side: write to Keychain then dispatch CreateKeysetAccepted.
    let post_accept = dispatch(
        &post_diag,
        AppAction::CreateKeysetAccepted {
            profile_id: profile_id.clone(),
            label: label.clone(),
            short_id: short_id.clone(),
        },
    );
    assert_eq!(
        post_accept.router.screen,
        Screen::CreateKeysetDistribute,
        "CreateKeysetAccepted must keep the user on Distribute until \
         the diagnostic auto-finish dispatches DistributeFinish"
    );

    // Diagnostic gate: after CreateKeysetAccepted, the Swift shell
    // (URL-scheme gate) auto-dispatches CreateKeysetDistributeFinish.
    let post_finish = dispatch(&post_accept, AppAction::CreateKeysetDistributeFinish);
    assert_eq!(
        post_finish.router.screen,
        Screen::Dashboard,
        "diagnostic CreateKeysetDistributeFinish must route to Dashboard"
    );
    assert_eq!(
        post_finish.keyset.step,
        KeysetFlowStep::Idle,
        "VAL-CREATE-021 reset: wizard must be Idle after Finish"
    );

    // The freshly-built profile row must still be Active (defense
    // against hub.profiles.first() brittleness with multiple rows).
    let row = post_finish
        .hub
        .profiles
        .iter()
        .find(|p| p.profile_id == profile_id)
        .expect("freshly-built profile row must persist through DistributeFinish");
    assert_eq!(row.status, ProfileStatus::Active);

    // Sanity: the material is non-empty (Keychain write payload).
    assert!(
        !material.is_empty(),
        "store_profile material must be non-empty"
    );
    assert_eq!(relays, vec![VALID_RELAY.to_string()]);
}

#[test]
fn diagnostics_create_keyset_run_does_not_mutate_release_state_when_inputs_blank() {
    // Defense-in-depth: even if the Swift gate is bypassed and the
    // Rust action is dispatched with entirely blank inputs, the actor
    // must NOT emit StoreKeysetCreatedProfile (no side-effect leak).
    let state = AppState::initial();
    let (next, side_effect) = dispatch_with_effect(
        &state,
        AppAction::DiagnosticsCreateKeysetRun {
            group_name: "".into(),
            threshold: 0,
            count: 0,
            device_name: "".into(),
            relay: "".into(),
        },
    );
    assert!(side_effect.is_none(), "blank inputs must no-op");
    assert!(next.hub.profiles.is_empty(), "hub must remain empty");
    assert_eq!(next.keyset.step, KeysetFlowStep::Idle);
}
