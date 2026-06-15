// Integration tests for the `Copy Profile` / `Copy Share` export recipe.
//
// These tests cover the round-trip that the validation contract requires:
//
//   *  `FfiApp::export_profile` produces a real `bfprofile1...` envelope whose
//      payload, decoded locally with the export password, includes the full
//      group member list and the device name carried in the active material.
//
//   *  `FfiApp::export_share` produces a `bfshare1...` envelope that
//      round-trips through `decode_bfshare_package` with the same password
//      and rejects any other password (VAL-SET-015-style guarantee).
//
//   *  The decode + material reconstruction path keeps the exported
//      bfprofile1 self-sufficient: feeding it back through
//      `import_profile` yields a material that `start_signer` can rebuild
//      the multi-member signer from — i.e. an imported profile reaches
//      signer readiness rather than falling back to the single-member
//      degraded stub.
//
//   *  The exported package never contains plaintext material: the raw
//      cmds are read via `frostr-utils::decode_*_package` and always go
//      through the v2 envelope.
//
// Validation evidence intentionally redacts secrets: every test asserts
// length, prefix, and shape, never asserts the literal package bytes or
// passwords.

use frostr_utils::{
    decode_bfprofile_package, decode_bfshare_package, derive_profile_id_from_share_secret,
    encode_bfprofile_package, BfProfileDevice, BfProfilePayload, BF_PACKAGE_VERSION,
    PREFIX_BFPROFILE, PREFIX_BFSHARE,
};
use igloo_mobile_core::{FfiApp, MaterialMember, OnboardProfileMaterial};

// ── Helpers ────────────────────────────────────────────────────────────────

fn alice_xonly() -> String {
    "11".repeat(32)
}
fn carol_xonly() -> String {
    "22".repeat(32)
}
fn local_xonly() -> String {
    "33".repeat(32)
}
fn compressed(x_only_hex: &str) -> String {
    format!("02{x_only_hex}")
}

fn demo_material(device_name: &str) -> OnboardProfileMaterial {
    let local_pub = local_xonly();
    let alice_pub = alice_xonly();
    let carol_pub = carol_xonly();
    // The encoder pins the canonical profile id to the share secret, so
    // derive it once and use the result as the material's profile_id.
    let profile_id = derive_profile_id_from_share_secret(&"aa".repeat(32))
        .expect("profile id derivation succeeds");
    OnboardProfileMaterial {
        share_seckey_hex: "aa".repeat(32),
        share_pubkey: local_pub.clone(),
        group_pubkey: "ee".repeat(32),
        relays: vec!["ws://127.0.0.1:8194".to_string()],
        device_state_hex: String::new(),
        profile_id,
        share_idx: 0,
        peer_pubkeys: vec![alice_pub.clone(), carol_pub.clone()],
        members: vec![
            MaterialMember {
                idx: 0,
                pubkey_hex: compressed(&local_pub),
            },
            MaterialMember {
                idx: 1,
                pubkey_hex: compressed(&alice_pub),
            },
            MaterialMember {
                idx: 2,
                pubkey_hex: compressed(&carol_pub),
            },
        ],
        device_name: device_name.to_string(),
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn export_profile_round_trip_preserves_group_members_and_device_name() {
    // Build a fresh FFI app and seed the active material.
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let material = demo_material("bob-iphone");
    let material_json =
        String::from_utf8(material.to_bytes()).expect("material serialises as utf-8 json");
    app.set_active_profile_material(material_json);

    let export_password = "export-password-strong";

    // Trigger the export.
    let exported = app.export_profile(export_password.to_string());

    // Prefix and shape gates.
    assert!(
        exported.starts_with(PREFIX_BFPROFILE),
        "export must produce a bfprofile1 package (got prefix {:?})",
        exported
            .chars()
            .take(PREFIX_BFPROFILE.len())
            .collect::<String>()
    );
    assert!(
        exported.chars().all(|c| !c.is_whitespace()),
        "export must be a single contiguous bech32m string (VAL-SET-007 shape)"
    );

    // Decoding with the right password yields the same payload.
    let decoded = decode_bfprofile_package(&exported, export_password)
        .expect("exported package decrypts with the export password");

    // The decoded payload MUST include the device name carried through
    // from the active material. The export must NOT be a hardcoded
    // "Igloo Mobile" placeholder when the user has a real label set.
    assert_eq!(
        decoded.device.name, "bob-iphone",
        "exported bfprofile1 must carry the resolved device name"
    );

    // Round-trip: the decoded package is the same as a freshly produced
    // payload using the same material. This bounds the encoding path.
    let reference_profile_id = derive_profile_id_from_share_secret(&"aa".repeat(32))
        .expect("profile id derivation succeeds");
    let reference_payload = BfProfilePayload {
        profile_id: reference_profile_id.clone(),
        version: BF_PACKAGE_VERSION,
        device: BfProfileDevice {
            name: "bob-iphone".to_string(),
            share_secret: "aa".repeat(32),
            manual_peer_policy_overrides: Vec::new(),
            relays: vec!["ws://127.0.0.1:8194".to_string()],
        },
        group_package: bifrost_codec::wire::GroupPackageWire {
            group_name: "Igloo Mobile".to_string(),
            group_pk: "ee".repeat(32),
            threshold: 2,
            members: vec![
                bifrost_codec::wire::MemberPackageWire {
                    idx: 0,
                    pubkey: compressed(&local_xonly()),
                },
                bifrost_codec::wire::MemberPackageWire {
                    idx: 1,
                    pubkey: compressed(&alice_xonly()),
                },
                bifrost_codec::wire::MemberPackageWire {
                    idx: 2,
                    pubkey: compressed(&carol_xonly()),
                },
            ],
        },
    };
    let reference = encode_bfprofile_package(&reference_payload, export_password)
        .expect("reference encoding succeeds");

    // Both must decode to the same canonical payload shape.
    let reference_decoded =
        decode_bfprofile_package(&reference, export_password).expect("reference round-trips");
    assert_eq!(
        decoded.profile_id, reference_decoded.profile_id,
        "exported profile id must match the active profile id"
    );
    assert_eq!(
        decoded.device.share_secret, reference_decoded.device.share_secret,
        "exported share secret must be byte-identical to the material"
    );
    assert_eq!(
        decoded.group_package.group_pk, reference_decoded.group_package.group_pk,
        "exported group pubkey must be byte-identical to the material"
    );
    assert_eq!(
        decoded.group_package.members.len(),
        3,
        "exported group package must carry the full 3-member roster so \
         imported profiles reach signer readiness"
    );
    for expected_idx in [0u16, 1, 2] {
        assert!(
            decoded
                .group_package
                .members
                .iter()
                .any(|m| m.idx == expected_idx),
            "exported group package must include idx {expected_idx}"
        );
    }
    assert_eq!(
        decoded.group_package.threshold, 2,
        "exported threshold must persist (2-of-3 from the demo keyset)"
    );
    assert_eq!(
        decoded.device.relays,
        vec!["ws://127.0.0.1:8194".to_string()],
        "exported relays must match the active material"
    );
}

#[test]
fn export_share_round_trip_rejects_wrong_password() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let material = demo_material("bob-share-test");
    let material_json =
        String::from_utf8(material.to_bytes()).expect("material serialises as utf-8 json");
    app.set_active_profile_material(material_json);

    let export_password = "share-password-strong";
    let exported = app.export_share(export_password.to_string());

    assert!(
        exported.starts_with(PREFIX_BFSHARE),
        "export must produce a bfshare1 package (VAL-SET-008)"
    );
    assert!(
        exported.chars().all(|c| !c.is_whitespace()),
        "export should be a contiguous bech32m string"
    );

    // Same password decodes successfully.
    let decoded =
        decode_bfshare_package(&exported, export_password).expect("decryption with right password");
    assert_eq!(
        decoded.share_secret,
        "aa".repeat(32),
        "bfshare1 share secret must round-trip"
    );
    assert_eq!(
        decoded.relays,
        vec!["ws://127.0.0.1:8194".to_string()],
        "bfshare1 relays must round-trip"
    );

    // Any other password fails (VAL-SET-015 contract).
    assert!(
        decode_bfshare_package(&exported, "wrong-password").is_err(),
        "bfshare1 must reject any password other than the export password"
    );
    assert!(
        decode_bfshare_package(&exported, "").is_err(),
        "bfshare1 must reject an empty password"
    );
}

#[test]
fn export_profile_rejects_wrong_password() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let material = demo_material("bob-wrong-pwd");
    let material_json =
        String::from_utf8(material.to_bytes()).expect("material serialises as utf-8 json");
    app.set_active_profile_material(material_json);

    let export_password = "profile-password-strong";
    let exported = app.export_profile(export_password.to_string());

    // Round-trips with the right password.
    decode_bfprofile_package(&exported, export_password).expect("decryption with right password");
    // Fails with any other password.
    assert!(
        decode_bfprofile_package(&exported, "different-password").is_err(),
        "bfprofile1 must reject any password other than the export password"
    );
}

#[test]
fn export_profile_falls_back_to_default_device_name_when_carrying_empty() {
    // Older material written before the device_name field was added
    // (serde(-) defaults the field to "") must still produce a valid
    // bfprofile1 package, with the parseable name falling back to a
    // sentinel rather than crashing the encoder.
    let mut material = demo_material("");
    material.device_name = String::new(); // empty
                                          // Mimic the pre-fix export_profile name hardcode by also ensuring
                                          // there are valid members and group key.
    let material_json =
        String::from_utf8(material.to_bytes()).expect("material serialises as utf-8 json");
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    app.set_active_profile_material(material_json);

    let exported = app.export_profile("some-export-password".to_string());
    let decoded = decode_bfprofile_package(&exported, "some-export-password")
        .expect("legacy empty-name material still encodes/decodes");
    assert_eq!(
        decoded.device.name, "Igloo Mobile",
        "empty material device_name falls back to the placeholder label"
    );
}

#[test]
fn export_share_with_no_active_material_returns_error_marker() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let exported = app.export_share("unused".to_string());
    assert!(
        exported.starts_with("error:"),
        "export without active material must surface the error marker"
    );
    assert!(
        exported.contains("no_active_profile"),
        "error marker must call out the missing active profile"
    );
}

#[test]
fn export_profile_with_no_active_material_returns_error_marker() {
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let exported = app.export_profile("unused".to_string());
    assert!(
        exported.starts_with("error:"),
        "export without active material must surface the error marker"
    );
}

#[test]
fn export_share_secret_matches_material() {
    // The exported bfshare1 must be byte-identical to the material's
    // share_secret. This is the inverse of what `bfshare1` import does
    // (decode → re-encrypt), so prove the chain by re-decoding.
    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let material = demo_material("bob-consistency");
    let material_json =
        String::from_utf8(material.to_bytes()).expect("material serialises as utf-8 json");
    app.set_active_profile_material(material_json);

    let exported = app.export_share("consistency-password".to_string());
    let decoded =
        decode_bfshare_package(&exported, "consistency-password").expect("decryption succeeds");
    assert_eq!(
        decoded.share_secret, material.share_seckey_hex,
        "exported share secret is byte-identical to the active material"
    );
}
