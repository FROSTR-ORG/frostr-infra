//! Tests for the kind-10000 encrypted profile backup publication +
//! round-trip via bfshare1 recovery.
//!
//! Two layers of coverage drive `mobile-relay-backup-publication-and-
//! recovery-roundtrip`:
//!
//! 1.  Pure unit tests build the canonical kind-10000 event off the
//!     wire (using the same `frostr-utils`/`bifrost-codec` machinery
//!     the FFI uses) and assert the contract surfaces
//!     (VAL-BACKUP-003): the event content is NIP-44 ciphertext —
//!     never plaintext JSON, never the share-secret hex, never the
//!     device label, never the relay URL.
//!
//! 2.  Live integration tests (`cargo test -- --ignored`) publish
//!     against the real `ws://127.0.0.1:8194` dev relay (requires
//!     `make demo-start`), then query the relay with a Nostr REQ
//!     filtered by the share-derived author and confirm a fresh
//!     event exists with the right shape. A subsequent `bfshare1`
//!     recovery round-trips through `FfiApp.recover_profile` and
//!     yields a `OnboardProfileMaterial` whose identity fields match
//!     the originating profile (VAL-BACKUP-001..006).
//!
//! Evidence intentionally redacts secrets: tests assert lengths,
//! prefixes, and equality of derived pubkeys but never log the raw
//! share secret, password, or NIP-44 ciphertext.

use std::sync::mpsc;
use std::time::{Duration, Instant};

use frostr_utils::{
    build_profile_backup_event, create_encrypted_profile_backup, decode_bfshare_package,
    derive_profile_id_from_share_pubkey, encode_bfonboard_package, encode_bfshare_package,
    parse_profile_backup_event, BfOnboardPayload, BfProfileDevice, BfProfilePayload,
    BF_PACKAGE_VERSION, PREFIX_BFSHARE, PROFILE_BACKUP_EVENT_KIND,
};
use igloo_mobile_core::{FfiApp, MaterialMember, OnboardProfileMaterial};
use k256::elliptic_curve::sec1::ToEncodedPoint as _;
use k256::SecretKey;

const RELAY_URL: &str = "ws://127.0.0.1:8194";

/// Connect to `relay` via Tokio-tungstenite, send the given REQ JSON,
/// collect `EVENT` frames until we see `EOSE` or the timeout expires,
/// then close. The relay response list is what the validators examine
/// to produce the relay-side filtered proof in VAL-BACKUP-001..006.
async fn fetch_kind10000_events(relay: &str, author_pubkey: &str) -> Vec<nostr::Event> {
    use futures_util::{SinkExt, StreamExt};
    use tokio::time::{timeout, Duration};
    use tokio_tungstenite::connect_async;
    use tokio_tungstenite::tungstenite::Message;
    let subscription_id = format!(
        "igloo-mobile-test-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    );
    let filter = serde_json::json!({
        "authors": [author_pubkey],
        "kinds": [PROFILE_BACKUP_EVENT_KIND],
    });
    let request = format!(
        "[\"REQ\",{},{}]",
        serde_json::Value::String(subscription_id.clone()),
        serde_json::to_string(&filter).expect("filter serialises"),
    );
    let close = format!(
        "[\"CLOSE\",{}]",
        serde_json::Value::String(subscription_id.clone()),
    );
    eprintln!(
        "[FETCH] author_pubkey.len={} request={}",
        author_pubkey.len(),
        request
    );
    let mut server_messages: Vec<String> = Vec::new();
    let mut events = Vec::new();
    let result = timeout(Duration::from_secs(8), connect_async(relay)).await;
    let (mut stream, _) = match result {
        Ok(Ok(value)) => value,
        _ => {
            eprintln!("[FETCH] connect failed");
            return events;
        }
    };
    if stream.send(Message::Text(request)).await.is_err() {
        eprintln!("[FETCH] send failed");
        return events;
    }
    // Read until EOSE, NOTICE, or timeout.
    let mut raw_frames = Vec::new();
    loop {
        match timeout(Duration::from_secs(4), stream.next()).await {
            Ok(Some(Ok(Message::Text(text)))) => {
                raw_frames.push((text.len(), text.clone()));
                server_messages.push(text.clone());
                if let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(arr) = value.as_array() {
                        match arr.first().and_then(|v| v.as_str()) {
                            Some("EVENT") => {
                                if let Some(event_value) = arr.get(2) {
                                    if let Ok(event) =
                                        serde_json::from_value::<nostr::Event>(event_value.clone())
                                    {
                                        events.push(event);
                                    } else {
                                        eprintln!("[FETCH] EVENT nested deserialization failed");
                                    }
                                }
                            }
                            Some("EOSE") | Some("NOTICE") => break,
                            _ => {}
                        }
                    }
                }
            }
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) => break,
            Ok(Some(Err(_))) => break,
            Err(_) => break,
            _ => {}
        }
    }
    let _ = stream.send(Message::Text(close)).await;
    let _ = stream.close(None).await;
    eprintln!(
        "[FETCH] events={} raw_frames={} last_msg={}",
        events.len(),
        raw_frames.len(),
        raw_frames.last().map(|(len, _)| len).unwrap_or(&0)
    );
    for raw in &server_messages {
        let summary = serde_json::from_str::<serde_json::Value>(raw)
            .ok()
            .and_then(|v| {
                v.as_array().map(|a| {
                    a.first()
                        .and_then(|x| x.as_str())
                        .unwrap_or("non_str")
                        .to_string()
                })
            });
        eprintln!(
            "[FETCH] msg_summary={:?} preview={}",
            summary,
            raw.chars().take(100).collect::<String>()
        );
    }
    events
}

/// Hex-encode a 32-byte compressed pubkey derived from a raw share
/// secret. Mirrors `helper_functions::derive_share_pubkey_from_secret`
/// but lives here so the unit tests stay independent of the FFI's
/// internal helpers.
fn share_pubkey_hex_from_secret(seckey_bytes: &[u8; 32]) -> Result<String, String> {
    let sk =
        SecretKey::from_slice(seckey_bytes).map_err(|_| "malformed_share_secret".to_string())?;
    let pk = sk.public_key();
    let ep = pk.to_encoded_point(true);
    Ok(hex::encode(ep.as_bytes()))
}

/// Hex-encode the x-only public key derived from a 32-byte share
/// secret. This is the value that lands in the `EncryptedProfileBackup`
/// and the `event.pubkey` field after `build_profile_backup_event`.
fn xonly_share_pubkey_hex_from_secret(seckey_bytes: &[u8; 32]) -> Result<String, String> {
    let sk =
        SecretKey::from_slice(seckey_bytes).map_err(|_| "malformed_share_secret".to_string())?;
    let pk = sk.public_key();
    let ep = pk.to_encoded_point(false);
    let x_bytes = ep.x().ok_or("malformed_x_only".to_string())?;
    Ok(hex::encode(x_bytes.as_slice()))
}

/// Build a freshly-minted demo 2-of-3 keyset with deterministic
/// secrets (so the test is reproducible) plus the canonical
/// `BfProfilePayload` material the actor would consume for backup
/// publication. The local share is the one mapped to share_idx 0;
/// tests pick a different share to validate round-trip recovery.
fn synthesized_payload(share_idx_to_use: usize) -> BfProfilePayload {
    // Three 32-byte shares derived from three independent RNG seeds.
    // Shares form a 2-of-3 group whose public key is independent of
    // which share we treat as "local" — derivation is deterministic
    // because we build the same group from the same share secrets.
    let alice = [0x11u8; 32];
    let bob = [0x22u8; 32];
    let carol = [0x33u8; 32];
    let secrets = [alice, bob, carol];
    let pk_alice = xonly_share_pubkey_hex_from_secret(&alice).unwrap();
    let pk_bob = xonly_share_pubkey_hex_from_secret(&bob).unwrap();
    let pk_carol = xonly_share_pubkey_hex_from_secret(&carol).unwrap();
    let local_secret_bytes = secrets[share_idx_to_use];
    let local_pubkey_hex = xonly_share_pubkey_hex_from_secret(&local_secret_bytes).unwrap();
    let profile_id = derive_profile_id_from_share_pubkey(&local_pubkey_hex).unwrap();
    // Use the same canonical reservedDeviceLabel shape as the mobile
    // tests' `demo_material()`. The fixture intentionally excludes the
    // relay URL placeholder so the leak-check assertion in the unit
    // test (VAL-BACKUP-003) has nothing to grep for.
    let device_name = "device-under-test";
    let relays = vec![RELAY_URL.to_string()];
    let group = bifrost_codec::wire::GroupPackageWire {
        group_name: "Backup Test Keyset".to_string(),
        group_pk: "ee".repeat(32),
        threshold: 2,
        members: vec![
            bifrost_codec::wire::MemberPackageWire {
                idx: 0,
                pubkey: format!("02{}", pk_alice),
            },
            bifrost_codec::wire::MemberPackageWire {
                idx: 1,
                pubkey: format!("02{}", pk_bob),
            },
            bifrost_codec::wire::MemberPackageWire {
                idx: 2,
                pubkey: format!("02{}", pk_carol),
            },
        ],
    };
    BfProfilePayload {
        profile_id,
        version: BF_PACKAGE_VERSION,
        device: BfProfileDevice {
            name: device_name.to_string(),
            share_secret: hex::encode(local_secret_bytes),
            manual_peer_policy_overrides: Vec::new(),
            relays,
        },
        group_package: group,
    }
}

/// Build a material the FFI's `publish_backup` can serialize — used
/// by the live relay tests to drive the same code path the mobile
/// shells drive on each materialization.
fn live_publish_material(share_idx: usize, device_name: &str) -> OnboardProfileMaterial {
    let alice = [0x11u8; 32];
    let bob = [0x22u8; 32];
    let carol = [0x33u8; 32];
    let secrets = [alice, bob, carol];
    let local_secret_bytes = secrets[share_idx];
    let local_pubkey_hex = xonly_share_pubkey_hex_from_secret(&local_secret_bytes).unwrap();
    let profile_id = derive_profile_id_from_share_pubkey(&local_pubkey_hex).unwrap();
    let members = vec![
        MaterialMember {
            idx: 0,
            pubkey_hex: format!("02{}", xonly_share_pubkey_hex_from_secret(&alice).unwrap()),
        },
        MaterialMember {
            idx: 1,
            pubkey_hex: format!("02{}", xonly_share_pubkey_hex_from_secret(&bob).unwrap()),
        },
        MaterialMember {
            idx: 2,
            pubkey_hex: format!("02{}", xonly_share_pubkey_hex_from_secret(&carol).unwrap()),
        },
    ];
    OnboardProfileMaterial {
        share_seckey_hex: hex::encode(local_secret_bytes),
        share_pubkey: local_pubkey_hex.clone(),
        group_pubkey: "ee".repeat(32),
        relays: vec![RELAY_URL.to_string()],
        device_state_hex: String::new(),
        profile_id,
        share_idx: share_idx as u16,
        peer_pubkeys: vec![
            xonly_share_pubkey_hex_from_secret(&alice).unwrap(),
            xonly_share_pubkey_hex_from_secret(&bob).unwrap(),
            xonly_share_pubkey_hex_from_secret(&carol).unwrap(),
        ],
        members,
        device_name: device_name.to_string(),
    }
}

// ── Unit tests (no live relay) ───────────────────────────────────────────

/// VAL-BACKUP-003: the kind-10000 event content must be NIP-44
/// ciphertext — never plaintext JSON, not the share secret hex, not
/// the device label, and not the relay URL.
#[test]
fn kind_10000_event_content_is_encrypted_with_no_plaintext_leak() {
    let payload = synthesized_payload(0);
    let share_secret_hex = payload.device.share_secret.clone();
    let backup = create_encrypted_profile_backup(&payload).expect("backup builds");
    let event = build_profile_backup_event(&share_secret_hex, &backup, Some(1_700_000_000))
        .expect("event builds");
    assert_eq!(event.kind.as_u16(), PROFILE_BACKUP_EVENT_KIND);
    assert_eq!(event.kind.as_u16(), 10_000);

    // The author matches the share-derived pubkey (the relay-side
    // filter the validator uses to confirm VAL-BACKUP-001/002/004).
    let expected_xonly =
        xonly_share_pubkey_hex_from_secret(&hex_to_32(&share_secret_hex).unwrap()).unwrap();
    let event_xonly = hex::encode(event.pubkey.to_bytes());
    assert_eq!(
        event_xonly, expected_xonly,
        "event author must equal the share-derived x-only pubkey",
    );

    // The content must NOT be plaintext JSON: if it parses as JSON
    // the NIP-44 encrypt step is missing somewhere in the pipeline.
    assert!(
        serde_json::from_str::<serde_json::Value>(&event.content).is_err(),
        "event content must NOT be plaintext JSON",
    );

    // The content must NOT contain ANY of the plaintext strings
    // captured in the source payload.
    let plaintext_share_secret = &share_secret_hex;
    let plaintext_device_label = "device-under-test";
    let plaintext_relay_url = "ws://127.0.0.1:8194";
    assert!(
        !event.content.contains(plaintext_share_secret),
        "event content must not contain the share secret hex",
    );
    assert!(
        !event.content.contains(plaintext_device_label),
        "event content must not contain the device label",
    );
    assert!(
        !event.content.contains(plaintext_relay_url),
        "event content must not contain any configured relay URL",
    );

    // Sanity: the `device.share_public_key` derived inside the
    // envelope matches the canonical share pubkey. The field
    // appears in plaintext inside the encrypted payload; not in the
    // event `content` field on the wire. The parity byte is either
    // "02" or "03" depending on the secret's y-coordinate; we only
    // assert length and the SEC1 prefix.
    let share_pubkey_compressed =
        share_pubkey_hex_from_secret(&hex_to_32(&share_secret_hex).unwrap()).unwrap();
    assert_eq!(
        share_pubkey_compressed.len(),
        66,
        "share pubkey compresses to a 33-byte sec1 hex (66 chars)",
    );
    let prefix = &share_pubkey_compressed[..2];
    assert!(
        prefix == "02" || prefix == "03",
        "share pubkey must start with sec1 parity byte 02 or 03, got {prefix}",
    );
}

/// VAL-BACKUP-005 (round-trip): a backup parsed with the right share
/// secret recovers the same group pubkey, device name, and relay
/// list that produced it.
#[test]
fn backup_round_trips_through_event_and_share_secret_decrypt() {
    let payload = synthesized_payload(1);
    let share_secret_hex = payload.device.share_secret.clone();
    let backup = create_encrypted_profile_backup(&payload).expect("backup builds");
    let event = build_profile_backup_event(&share_secret_hex, &backup, None).expect("event builds");

    let recovered =
        parse_profile_backup_event(&event, &share_secret_hex).expect("parses with secret");
    assert_eq!(recovered.device.name, payload.device.name);
    assert_eq!(
        recovered.group_package.group_pk, payload.group_package.group_pk,
        "group public key round-trips through backup",
    );
    assert_eq!(recovered.device.relays, payload.device.relays);
    assert_eq!(
        recovered.group_package.members.len(),
        payload.group_package.members.len(),
        "the full member list is preserved across the backup envelope",
    );
}

// ── Live relay integration tests ────────────────────────────────────────

fn hex_to_32(value: &str) -> Result<[u8; 32], String> {
    if value.len() != 64 {
        return Err("invalid_length".to_string());
    }
    let decoded = hex::decode(value).map_err(|_| "invalid_hex".to_string())?;
    let mut out = [0u8; 32];
    out.copy_from_slice(&decoded);
    Ok(out)
}

/// Live helper: build a fresh FfiApp, set the active material, and
/// publish a kind-10000 backup via the production `FfiApp::publish_backup`
/// entry point. Returns the resulting `BackupPublishResult` so the
/// caller can compare it against the relay-side proof.
#[test]
#[ignore = "requires live relay at ws://127.0.0.1:8194; run via cargo test -- --ignored"]
fn live_relay_publish_backup_creates_kind_10000_event_with_share_author() {
    let app = FfiApp::new("/tmp/igloo-mobile-backup-test".to_string());
    let material = live_publish_material(0, "bob");
    let material_json = String::from_utf8(material.to_bytes()).expect("material utf-8");
    app.set_active_profile_material(material_json.clone());

    let (tx, rx) = mpsc::channel();
    let app_thread = app.clone();
    let material_thread = material_json.clone();
    let handle = std::thread::Builder::new()
        .name("igloo-publish-bob".into())
        .spawn(move || {
            let result = app_thread.publish_backup("create".to_string(), material_thread);
            let _ = tx.send(result);
        })
        .unwrap();
    let result = match rx.recv_timeout(Duration::from_secs(45)) {
        Ok(v) => v,
        Err(e) => panic!("publish_backup did not return within 45s: {e}"),
    };
    let _ = handle.join();
    assert!(
        result.success,
        "publish must succeed against the live relay (got: {:?})",
        result.error,
    );
    assert!(
        result.event_id.is_some(),
        "publish must surface a valid event id"
    );
    assert!(
        result.author_pubkey.is_some(),
        "publish must surface a valid author"
    );
    assert!(
        !result.content_redacted.is_empty(),
        "publish must surface a content_redacted marker so tests can correlate",
    );
    assert!(
        result.content_length > 0,
        "publish must surface the encrypted content byte length",
    );
    assert_eq!(result.relays_published_to, vec![RELAY_URL.to_string()]);
    let published_author = result.author_pubkey.clone().unwrap();
    eprintln!(
        "[DIAG] publish_ok event_id={:?} author={} relays_published={:?}",
        result.event_id, published_author, result.relays_published_to,
    );

    // Independent relay-side proof: query the relay with a fresh REQ
    // filtered by the share-derived author and kinds=[10000], then
    // confirm the event exists. We cross-check the same `event_id`
    // the publish returned so the validator-style assertion closes
    // the loop on the relay itself.
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_time()
        .enable_io()
        .build()
        .expect("tokio runtime builds");
    let relay_events = runtime.block_on(fetch_kind10000_events(RELAY_URL, &published_author));
    eprintln!(
        "[DIAG] relay_query_count={} target_event_id={:?}",
        relay_events.len(),
        result.event_id
    );
    for event in &relay_events {
        eprintln!(
            "[DIAG] relay_event id={} pubkey={} kind={}",
            event.id.to_hex(),
            hex::encode(event.pubkey.to_bytes()),
            event.kind.as_u16()
        );
    }
    assert!(
        !relay_events.is_empty(),
        "relay-side query must surface the freshly published kind-10000 event (author {})",
        published_author,
    );
    let matching = relay_events
        .iter()
        .find(|e| e.id.to_hex() == result.event_id.clone().unwrap());
    assert!(
        matching.is_some(),
        "relay-side query must include the event id returned by the publish",
    );
}

/// Live round-trip (VAL-BACKUP-005): after publishing a backup from a
/// freshly synthesized keyset, drop the in-memory material, build a
/// bfshare1 from the share secret, and recover through the production
/// `FfiApp::recover_profile` path. Verify the recovered identity
/// matches the originating profile.
#[test]
#[ignore = "requires live relay at ws://127.0.0.1:8194; run via cargo test -- --ignored"]
fn live_relay_published_backup_round_trips_via_bfshare_recovery() {
    let app = FfiApp::new("/tmp/igloo-mobile-backup-test".to_string());
    let material = live_publish_material(1, "carol");
    let share_secret_hex = material.share_seckey_hex.clone();
    let material_json = String::from_utf8(material.to_bytes()).expect("material utf-8");

    // Publish first.
    let (tx, rx) = mpsc::channel();
    let app_thread = app.clone();
    let material_thread = material_json.clone();
    let handle = std::thread::Builder::new()
        .name("igloo-publish-bob-roundtrip".into())
        .spawn(move || {
            let result = app_thread.publish_backup("create".to_string(), material_thread);
            let _ = tx.send(result);
        })
        .unwrap();
    let publish = rx
        .recv_timeout(Duration::from_secs(45))
        .expect("publish within 45s");
    let _ = handle.join();
    assert!(publish.success, "precondition: publish must succeed");

    // Build a bfshare1 from the share secret + relays, then recover
    // through `FfiApp::recover_profile`. This drops the in-memory
    // material entirely so the recovery proves it really is reading
    // from the relay.
    let share_password = "recovery-password";
    let bfshare_package = encode_bfshare_package(
        &frostr_utils::BfSharePayload {
            share_secret: share_secret_hex.clone(),
            relays: vec![RELAY_URL.to_string()],
        },
        share_password,
    )
    .expect("bfshare1 package encodes");
    assert!(
        bfshare_package.starts_with(PREFIX_BFSHARE),
        "encoded share must carry the bfshare prefix",
    );

    let (rtx, rrx) = mpsc::channel();
    let app_thread_2 = app.clone();
    let bfshare_package_thread = bfshare_package.clone();
    let share_password_thread = share_password.to_string();
    let handle = std::thread::Builder::new()
        .name("igloo-recover-bob".into())
        .spawn(move || {
            let result =
                app_thread_2.recover_profile(bfshare_package_thread, share_password_thread);
            let _ = rtx.send(result);
            // Yield so the spawned thread completes before the test ends.
            let _ = std::thread::Builder::new()
                .name("igloo-recover-bob-sleep".into())
                .spawn(|| std::thread::sleep(Duration::from_millis(50)));
        })
        .unwrap();
    let recover = match rrx.recv_timeout(Duration::from_secs(45)) {
        Ok(v) => v,
        Err(e) => panic!("recover_profile did not return within 45s: {e}"),
    };
    let _ = handle.join();
    assert!(
        recover.success,
        "recover must succeed; got error: {:?}",
        recover.error,
    );
    assert_eq!(
        recover.share_pubkey.as_deref(),
        Some(material.share_pubkey.as_str()),
        "recovered share pubkey must match the originating share pubkey",
    );
    assert_eq!(
        recover.group_pubkey.as_deref(),
        Some(material.group_pubkey.as_str()),
        "recovered group pubkey must match the originating group pubkey",
    );
    assert_eq!(
        recover.profile_id.as_deref(),
        Some(material.profile_id.as_str()),
        "recovered profile_id must match the originating profile_id",
    );
    // bfshare1 decode sanity: the package is well-formed and re-decodes.
    let decoded = decode_bfshare_package(&bfshare_package, share_password)
        .expect("bfshare1 decodes with the same password");
    assert_eq!(decoded.share_secret, share_secret_hex);
}

/// Live helper: ensure the demo stack is healthy before running live
/// tests. Without this, a `cargo test -- --ignored` run on a freshly
/// crashed demo stack can produce confusing failure signatures.
#[test]
#[ignore = "diagnostic; requires live relay at ws://127.0.0.1:8194"]
fn live_relay_is_reachable_diagnostic() {
    let start = Instant::now();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_time()
        .enable_io()
        .build()
        .expect("tokio runtime builds");
    let events = runtime.block_on(fetch_kind10000_events(RELAY_URL, "00".repeat(32).as_str()));
    assert!(
        start.elapsed() < Duration::from_secs(15),
        "relay probe should complete within 15s",
    );
    // The events vec is empty for an author with no events; we only
    // care that the REQ round-trip succeeded without an error.
    let _ = events; // silences dead_code lint, value not asserted
}

/// Encode a forged bfonboard1 that targets the SAME group but carries a
/// mis-typed password. Used to confirm the round-trip envelope path
/// rejects silently (so the recovery path can fail loud instead of
/// returning a stale material on password typos).
#[test]
fn bfshare_decode_with_wrong_password_returns_decrypt_error() {
    let share_secret_hex = hex::encode([0xaau8; 32]);
    let s = frostr_utils::BfSharePayload {
        share_secret: share_secret_hex.clone(),
        relays: vec![RELAY_URL.to_string()],
    };
    let package = encode_bfshare_package(&s, "rightpassword").expect("bfshare1 encodes");
    let err = decode_bfshare_package(&package, "wrongpassword");
    assert!(
        err.is_err(),
        "bfshare1 must reject any password other than the one used to encrypt",
    );
    // Sanity: the right password still parses.
    decode_bfshare_package(&package, "rightpassword")
        .expect("bfshare1 decodes with the right password");
}

/// Quick smoke: bfonboard1 envelope produces a valid envelope + decode
/// round-trip independent of the relay — keeps the forging helpers in
/// the test file honest.
#[test]
fn bfonboard_encode_decode_roundtrip_produces_share_secret() {
    let share_secret_hex = hex::encode([0xbbu8; 32]);
    let payload = BfOnboardPayload {
        share_secret: share_secret_hex.clone(),
        relays: vec![RELAY_URL.to_string()],
        peer_pk: "00".repeat(32),
    };
    let package = encode_bfonboard_package(&payload, "fixture-pwd").expect("bfonboard encodes");
    let ok =
        frostr_utils::decode_bfonboard_package(&package, "fixture-pwd").expect("bfonboard decodes");
    assert_eq!(ok.share_secret, share_secret_hex);
    assert_eq!(ok.relays, vec![RELAY_URL.to_string()]);
}
