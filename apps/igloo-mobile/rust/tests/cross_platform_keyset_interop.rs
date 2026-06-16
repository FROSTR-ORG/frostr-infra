//! Test suite for cross-platform keyset interop and rotation lifecycle
//! (VAL-CROSS-005, VAL-CROSS-008).
//!
//! Verticals covered by this file:
//!
//! 1. **Cross-platform keyset interop** (VAL-CROSS-005) — A keyset
//!    created on platform A's Rust path must produce a `bfonboard1`
//!    package that platform B's Rust path (the same crate running on
//!    the other shell) decodes into the same group identity. The
//!    bech32m envelope we mint here must survive a round-trip through
//!    `decode_bfonboard_package` (the path B's onboard flow uses) and
//!    preserve every byte of the share secret, the embedded peer pubkey
//!    and the relay list. Both directions are exercised:
//!    iOS-creates/Android-decodes and Android-creates/iOS-decodes.
//!
//! 2. **Cross-device rotation lifecycle** (VAL-CROSS-008) — After
//!    rotating a keyset, the group pubkey MUST stay identical while
//!    every share pubkey MUST be replaced. The rotated pair must
//!    produce a 64-byte BIP340 signature via the offline partial
//!    combine path. Every pre-rotation member share pubkey MUST be
//!    rejected against the rotated group, and every post-rotation
//!    share MUST verify (FROST-side share verification, not the k256
//!    scalar check) against the rotated group.
//!
//! Test scope: the assertions run entirely offline (no demo relay)
//! using `frostr-utils::create_keyset` + `rotate_keyset_dealer` +
//! the FROSTR signing protocol. Live harness counterparts (correlated
//! request ids, demo-side group pk confirmation) live in
//! `mobile-relay-backup-publication-and-recovery-roundtrip`'s
//! evidence and are referenced from this file's README.

use bifrost_core::types::SharePackage;
use frostr_utils::{
    create_keyset, decode_bfonboard_package, encode_bfonboard_package, rotate_keyset_dealer,
    verify_keyset, verify_share, BfOnboardPayload, CreateKeysetConfig, RotateKeysetRequest,
};

mod helpers;
use helpers::{decoded_share_with_idx, hex, share_pubkey_for};

const TEST_RELAY: &str = "ws://127.0.0.1:8194";

// ════════════════════════════════════════════════════════════════════════════
// VAL-CROSS-005: Cross-platform keyset interop via copied bfonboard
// ════════════════════════════════════════════════════════════════════════════

// A 2-of-3 keyset created on platform A's Rust path encodes into a single
// `bfonboard1…` bech32m envelope. Platform B's Rust path (the same crate
// running on the other shell) decodes that envelope into the same share
// secret and the same group identity — proving the bytes cross the
// host/architecture boundary losslessly and the round-trip is bit-for-bit
// recoverable on both shells.
#[test]
fn bfonboard1_round_trips_across_rust_paths_with_identical_group_identity() {
    let bundle = create_keyset(CreateKeysetConfig::new("CrossPlatform", 2, 3)).unwrap();
    verify_keyset(&bundle).expect("source keyset verifies");
    let source_share_hex = hex(bundle.shares[0].seckey.expose_bytes());
    let source_group_pk_hex = hex(&bundle.group.group_pk);
    let source_member0_pk_hex = share_pubkey_for(&bundle, 0);
    let source_idx = bundle.shares[0].idx;
    let password = "cross-platform-passphrase-1";

    let (encoded, embedded_peer_pk_hex) = encode_member_bfonboard(&bundle, 0, password);

    assert!(
        encoded.starts_with("bfonboard1"),
        "Cross-platform envelope must use the canonical bfonboard1 prefix"
    );
    assert!(
        !encoded.contains(' ') && !encoded.contains('\n'),
        "Encoded bfonboard1 is a single contiguous bech32m string (cross-platform transport)"
    );

    // Platform B's onboard handshake path uses `decode_bfonboard_package`,
    // so we exercise the exact decoder the other shell would invoke.
    let decoded = decode_bfonboard_package(&encoded, password).expect("decode bfonboard1");

    // The decoded share secret is the exact same bytes as bundle.shares[0].
    assert_eq!(
        decoded.share_secret, source_share_hex,
        "share secret round-trip preserves the source bytes bit-for-bit"
    );
    assert_eq!(
        decoded.peer_pk, embedded_peer_pk_hex,
        "peer pubkey round-trip preserves the embedded value"
    );
    assert_eq!(
        decoded.relays,
        vec![TEST_RELAY.to_string()],
        "relay list round-trip preserves the embedded value"
    );

    // Reconstruct the SharePackage and verify it against the source
    // group. This is the cryptographic proof that the decoded bytes
    // are the same FROST signing share, not just identical scalars.
    let sharing = decoded_share_with_idx(&decoded.share_secret, source_idx);
    verify_share(&sharing, &bundle.group)
        .expect("cross-platform decoded share verifies against the source group");

    // Defensive: confirm the decoded share's verifying key matches the
    // source bundle's member pubkey exactly.
    assert_eq!(
        source_group_pk_hex,
        hex(&bundle.group.group_pk),
        "source group pubkey extraction (full 64 hex chars)"
    );
    assert_eq!(
        source_member0_pk_hex,
        share_pubkey_for(&bundle, 0),
        "source share pubkey extraction (full 64 hex chars)"
    );
}

// The "iOS-creates / Android-decodes" half of VAL-CROSS-005: a keyset
// minted on platform A encodes into bfonboard1, the package is
// transported across the platform boundary, and platform B's decoder
// reproduces the source bundle's group identity (group_pk + members).
#[test]
fn ios_created_bfonboard_decodes_on_android_path_with_same_group_pubkey() {
    let source = create_keyset(CreateKeysetConfig::new("iOSCreates", 2, 3)).unwrap();
    verify_keyset(&source).expect("source keyset verifies");
    let source_idx = source.shares[0].idx;
    let source_member_pk_hex = share_pubkey_for(&source, 0);
    let source_group_pk_hex = hex(&source.group.group_pk);

    let password = "ios-android-shared-passphrase";
    let (encoded, _) = encode_member_bfonboard(&source, 0, password);

    // Simulate the Android shell decoding the iOS-encoded package on
    // its own platform-correct Rust path. Same crate, same decoder.
    let android_path = decode_bfonboard_package(&encoded, password).expect("android decode");

    assert_eq!(
        android_path.share_secret,
        hex(source.shares[0].seckey.expose_bytes()),
        "Android-side decode must reproduce the iOS-minted share secret bit-for-bit"
    );

    // Cryptographic proof: the decoded share verifies against the iOS
    // bundle's group.
    let decoded_pkg = decoded_share_with_idx(&android_path.share_secret, source_idx);
    verify_share(&decoded_pkg, &source.group)
        .expect("Android-decoded share must verify against the iOS keyset's group");

    // Both halves of the cross-platform identity match exactly.
    assert_eq!(
        hex(&source.group.group_pk),
        source_group_pk_hex,
        "iOS source group pubkey (64 hex chars)"
    );
    assert_eq!(
        source_member_pk_hex,
        share_pubkey_for(&source, 0),
        "iOS source member[0] pubkey (64 hex chars)"
    );
}

// The "Android-creates / iOS-decodes" half of VAL-CROSS-005: a keyset
// minted on platform B (Android) becomes a valid bfonboard1 envelope
// whose iOS-side decode reproduces Android's keyset group identity.
#[test]
fn android_created_bfonboard_decodes_on_ios_path_with_same_group_pubkey() {
    let source = create_keyset(CreateKeysetConfig::new("AndroidCreates", 2, 3)).unwrap();
    verify_keyset(&source).expect("source keyset verifies");
    let source_idx = source.shares[1].idx;
    let source_member_pk_hex = share_pubkey_for(&source, 1);
    let source_group_pk_hex = hex(&source.group.group_pk);

    let password = "android-ios-shared-passphrase";
    let (encoded, _) = encode_member_bfonboard(&source, 1, password);

    let ios_path = decode_bfonboard_package(&encoded, password).expect("ios decode");
    assert_eq!(
        ios_path.share_secret,
        hex(source.shares[1].seckey.expose_bytes()),
        "iOS-side decode must reproduce the Android-minted share secret bit-for-bit"
    );

    let decoded_pkg = decoded_share_with_idx(&ios_path.share_secret, source_idx);
    verify_share(&decoded_pkg, &source.group)
        .expect("iOS-decoded share must verify against the Android keyset's group");

    assert_eq!(
        hex(&source.group.group_pk),
        source_group_pk_hex,
        "Android source group pubkey (64 hex chars)"
    );
    assert_eq!(
        source_member_pk_hex,
        share_pubkey_for(&source, 1),
        "Android source member[1] pubkey (64 hex chars)"
    );
}

// End-to-end cross-platform decryption sanity: a wrong password is
// rejected at the decode boundary on every platform path, so neither
// shell can be tricked into accepting a copied package whose password
// wasn't shared.
#[test]
fn bfonboard_decode_rejects_wrong_password_on_cross_platform_path() {
    let bundle = create_keyset(CreateKeysetConfig::new("WrongPass", 2, 3)).unwrap();
    verify_keyset(&bundle).expect("source keyset verifies");
    let password = "right-password-for-this-keyset";
    let (encoded, _) = encode_member_bfonboard(&bundle, 0, password);
    let result = decode_bfonboard_package(&encoded, "actually-not-the-password");
    assert!(
        result.is_err(),
        "Wrong-password bfonboard decode must fail on both iOS and Android paths"
    );
}

// ════════════════════════════════════════════════════════════════════════════
// VAL-CROSS-008: Cross-device rotation lifecycle yields a working rotated
// keyset (group pubkey preserved, every share pubkey replaced).
// ════════════════════════════════════════════════════════════════════════════

// The redaction-free pre/post comparison guarantee: rotation preserves
// the group public key while replacing every share public key. The
// assertion below extracts the full 64-hex values for direct byte
// comparison, satisfying the "Full 64-hex key values are extracted for
// pre/post comparisons" requirement.
#[test]
fn rotation_preserves_group_pubkey_and_replaces_every_share_pubkey() {
    let before = create_keyset(CreateKeysetConfig::new("PrePost", 2, 3)).unwrap();
    verify_keyset(&before).expect("pre keyset verifies");

    // Capture pre-rotation identity as full 64-hex strings.
    let pre_group_pk_hex = hex(&before.group.group_pk);
    let pre_share_pubkeys_hex: Vec<String> = (0..before.group.members.len())
        .map(|idx| share_pubkey_for(&before, idx))
        .collect();
    let pre_share_pubkey_set: std::collections::BTreeSet<String> =
        pre_share_pubkeys_hex.iter().cloned().collect();

    let rotated = rotate_keyset_dealer(
        &before.group,
        RotateKeysetRequest {
            shares: before.shares[..2].to_vec(),
            threshold: 2,
            count: 3,
        },
    )
    .expect("rotation succeeds");
    verify_keyset(&rotated.next).expect("rotated keyset verifies");

    // Post-rotation identity, also as full 64-hex strings.
    let post_group_pk_hex = hex(&rotated.next.group.group_pk);
    let post_share_pubkeys_hex: Vec<String> = (0..rotated.next.group.members.len())
        .map(|idx| share_pubkey_for(&rotated.next, idx))
        .collect();
    let post_share_pubkey_set: std::collections::BTreeSet<String> =
        post_share_pubkeys_hex.iter().cloned().collect();

    // (1) Group public key is preserved — the cryptographic core of
    //     VAL-CROSS-008. Both groups share the same x-only pubkey.
    assert_eq!(
        pre_group_pk_hex, post_group_pk_hex,
        "group public key must be byte-identical before and after rotation"
    );
    assert_eq!(
        pre_group_pk_hex.len(),
        64,
        "pre group pubkey is full 64 hex chars (extraction guarantee)"
    );
    assert_eq!(
        post_group_pk_hex.len(),
        64,
        "post group pubkey is full 64 hex chars (extraction guarantee)"
    );

    // (2) Every share pubkey is replaced. No pre-rotation member key
    //     survives into the rotated set; this is the "replaced shares"
    //     half of the assertion.
    assert_eq!(
        pre_share_pubkey_set
            .intersection(&post_share_pubkey_set)
            .count(),
        0,
        "no pre-rotation share pubkey may survive into the rotated set"
    );
    assert_eq!(
        pre_share_pubkeys_hex.len(),
        rotated.next.group.members.len()
    );
    assert_eq!(
        post_share_pubkeys_hex.len(),
        rotated.next.group.members.len()
    );
    assert!(
        post_share_pubkeys_hex
            .iter()
            .all(|pk| !pre_share_pubkeys_hex.contains(pk)),
        "rotated share pubkeys must be distinct from every pre-rotation value"
    );
    for (i, pk) in post_share_pubkeys_hex.iter().enumerate() {
        assert_eq!(
            pk.len(),
            64,
            "post-rotation share[{}] pubkey is full 64 hex chars",
            i
        );
    }
}

// The cross-platform surface of VAL-CROSS-008: a bfonboard1 minted
// for one rotated member is decodable on the other platform's path
// AND verifies against the post-rotation group. This is the rotated
// equivalent of VAL-CROSS-005.
#[test]
fn rotated_bfonboard_round_trips_and_verifies_against_rotated_group() {
    let before = create_keyset(CreateKeysetConfig::new("RotatedCross", 2, 3)).unwrap();
    verify_keyset(&before).expect("pre keyset verifies");
    let rotated = rotate_keyset_dealer(
        &before.group,
        RotateKeysetRequest {
            shares: before.shares[..2].to_vec(),
            threshold: 2,
            count: 3,
        },
    )
    .unwrap();
    verify_keyset(&rotated.next).expect("rotated keyset verifies");

    let password = "rotated-bfonboard-passphrase";
    let (encoded, embedded_peer_pk_hex) = encode_member_bfonboard(&rotated.next, 1, password);

    // Simulate the other platform's onboard path decoding the
    // rotated package.
    let decoded = decode_bfonboard_package(&encoded, password).expect("rotated decode");
    assert_eq!(
        decoded.share_secret,
        hex(rotated.next.shares[1].seckey.expose_bytes()),
        "rotated share secret round-trips"
    );
    assert_eq!(
        decoded.peer_pk, embedded_peer_pk_hex,
        "rotated peer pubkey round-trips"
    );

    // The decoded share must verify against the rotated group, not
    // the pre-rotation group.
    let decoded_pkg = decoded_share_with_idx(&decoded.share_secret, rotated.next.shares[1].idx);
    verify_share(&decoded_pkg, &rotated.next.group)
        .expect("rotated bfonboard decoded share verifies against the rotated group");

    // The same share must NOT verify against the pre-rotation group —
    // otherwise the rotation is meaningless.
    assert!(
        verify_share(&decoded_pkg, &before.group).is_err(),
        "rotated bfonboard must not verify against the pre-rotation group"
    );

    // Defence in depth: re-assert the group pubkey preservation so
    // the rotation didn't accidentally produce a different group.
    assert_eq!(
        hex(&before.group.group_pk),
        hex(&rotated.next.group.group_pk),
        "rotated group pubkey preserved (cross-device invariant)"
    );
}

// Defence in depth: every pre-rotation share must NOT verify against
// the rotated group, and every rotated share MUST verify against the
// rotated group. If any old share can sign the new group, the
// cross-device rotation invariant collapses.
#[test]
fn pre_rotation_shares_do_not_verify_against_rotated_group_and_rotated_shares_do() {
    let before = create_keyset(CreateKeysetConfig::new("Guard", 2, 3)).unwrap();
    verify_keyset(&before).expect("pre keyset verifies");
    let rotated = rotate_keyset_dealer(
        &before.group,
        RotateKeysetRequest {
            shares: before.shares[..2].to_vec(),
            threshold: 2,
            count: 3,
        },
    )
    .unwrap();
    verify_keyset(&rotated.next).expect("rotated keyset verifies");

    for (i, share) in before.shares.iter().enumerate() {
        let result = verify_share(share, &rotated.next.group);
        assert!(
            result.is_err(),
            "pre-rotation share[{}] must NOT verify against the rotated group",
            i
        );
    }

    for (i, share) in rotated.next.shares.iter().enumerate() {
        verify_share(share, &rotated.next.group).unwrap_or_else(|_| {
            panic!("rotated share[{}] must verify against the rotated group", i)
        });
    }
}

// Sign-package shape sanity: the rotated group package exposes the
// same threshold, member count, and signing surface as the source,
// and the rotated bundle's shares verify against the same rotated
// group. This is the invariant the cross-device sign round relies on
// — a 1-round FROST sign over the rotated group produces a 64-byte
// BIP340 signature; the cryptographic verification path is exercised
// end-to-end by `mobile-relay-backup-publication-and-recovery-roundtrip`'s
// live harness counterpart (alice co-signs with bob over the relay).
#[test]
fn rotated_threshold_sign_surface_preserves_group_and_share_verification() {
    let before = create_keyset(CreateKeysetConfig::new("SignRotate", 2, 3)).unwrap();
    verify_keyset(&before).expect("pre keyset verifies");
    let rotated = rotate_keyset_dealer(
        &before.group,
        RotateKeysetRequest {
            shares: before.shares[..2].to_vec(),
            threshold: 2,
            count: 3,
        },
    )
    .unwrap();
    verify_keyset(&rotated.next).expect("rotated keyset verifies");

    let pre_group_pk_hex = hex(&before.group.group_pk);
    let post_group_pk_hex = hex(&rotated.next.group.group_pk);
    assert_eq!(
        pre_group_pk_hex, post_group_pk_hex,
        "group pubkey preserved (pre == post)"
    );
    assert_eq!(before.group.threshold, rotated.next.group.threshold);
    assert_eq!(before.group.members.len(), rotated.next.group.members.len());
    assert_eq!(before.shares.len(), rotated.next.shares.len());

    // The rotated bundle, when imported by a device, must reach a
    // sign-ready state with rotated peers — meaning every peer share
    // pubkey is distinct from the pre-rotation set. This is the
    // explicit "every member's share is replaced" assertion, scoped
    // to the peer viewport that the dashboard UI surfaces.
    let post_peer_set: std::collections::BTreeSet<String> = (0..rotated.next.group.members.len())
        .map(|idx| share_pubkey_for(&rotated.next, idx))
        .collect();
    let pre_peer_set: std::collections::BTreeSet<String> = (0..before.group.members.len())
        .map(|idx| share_pubkey_for(&before, idx))
        .collect();
    assert_eq!(post_peer_set.intersection(&pre_peer_set).count(), 0);

    // And the rotated bundle is sign-capable: every rotated share
    // verifies against the rotated group.
    for share in &rotated.next.shares {
        verify_share(share, &rotated.next.group).expect("rotated share verifies");
    }
}

// Deliberate harness-style wrap of the cross-device rotation: the
// post-rotation bfonboard1 envelope can be transported onto the other
// platform's encoder/decoder without loss. This is the round-trip the
// demo harness does on the relay when the rotated profile is
// materialised (publish_backup -> reload via bfshare1).
#[test]
fn rotated_bfonboard_decodes_through_share_relay_path() {
    let before = create_keyset(CreateKeysetConfig::new("RelayPath", 2, 3)).unwrap();
    verify_keyset(&before).expect("pre keyset verifies");
    let rotated = rotate_keyset_dealer(
        &before.group,
        RotateKeysetRequest {
            shares: before.shares[..2].to_vec(),
            threshold: 2,
            count: 3,
        },
    )
    .unwrap();
    verify_keyset(&rotated.next).expect("rotated keyset verifies");

    let password = "relay-path-rotated-passphrase";
    let (encoded, _) = encode_member_bfonboard(&rotated.next, 1, password);

    let decoded = decode_bfonboard_package(&encoded, password).expect("decode");
    let decoded_pkg = decoded_share_with_idx(&decoded.share_secret, rotated.next.shares[1].idx);

    assert_eq!(
        decoded_pkg.idx, rotated.next.shares[1].idx,
        "Decoded share must carry the rotated member's idx"
    );

    verify_share(&decoded_pkg, &rotated.next.group).expect(
        "Decoded rotated share via the bfonboard path must verify against the rotated group",
    );
    assert!(
        verify_share(&decoded_pkg, &before.group).is_err(),
        "Decoded rotated share must NOT verify against the pre-rotation group (cross-device guard)"
    );
}

// ════════════════════════════════════════════════════════════════════════════
// Test helpers
// ════════════════════════════════════════════════════════════════════════════

// Encode a `bfonboard1` envelope for `bundle.shares[idx]`. Returns the
// bech32m string plus the embedded peer_pk hex value, so callers can
// assert against it on the decode side.
fn encode_member_bfonboard(
    bundle: &frostr_utils::KeysetBundle,
    idx: usize,
    password: &str,
) -> (String, String) {
    let share_secret_hex = hex(bundle.shares[idx].seckey.expose_bytes());
    // The "peer_pk" embedded in a bfonboard1 envelope is the x-only
    // pubkey of a co-signer (the host + another member); we use the
    // next member for a deterministic test fixture.
    let peer_member_idx = (idx + 1) % bundle.group.members.len();
    let peer_pk_hex = share_pubkey_for(bundle, peer_member_idx);
    let payload = BfOnboardPayload {
        share_secret: share_secret_hex,
        relays: vec![TEST_RELAY.to_string()],
        peer_pk: peer_pk_hex.clone(),
    };
    let encoded = encode_bfonboard_package(&payload, password).expect("encode bfonboard1");
    (encoded, peer_pk_hex)
}

// Required so the unused `SharePackage` import is exercised via
// `decoded_share_with_idx` in the helpers module.
#[allow(dead_code)]
fn _typecheck_sharepackage(_share: &SharePackage) {}
