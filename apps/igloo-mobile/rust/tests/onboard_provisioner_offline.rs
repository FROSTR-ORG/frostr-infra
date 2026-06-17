//! Integration test for the provisioner-offline timeout path of `FfiApp::onboard`.
//!
//! mobile-onboard-provisioner-offline-timeout-retry-fix (VAL-ONBOARD-014):
//!
//! This test exercises the production `FfiApp::onboard` code path with a
//! self-contained, freshly minted `bfonboard1` package that:
//!   - Decodes successfully (valid package, valid password).
//!   - Targets a real, reachable relay (`ws://127.0.0.1:8194`).
//!   - Names a SYNTHETIC responder pubkey (a random 64-char x-only hex) so
//!     no signer will ever publish an onboard response. This isolates the
//!     "relay reachable, provisioner offline" failure mode that
//!     VAL-ONBOARD-007 (unreachable relay) cannot reproduce and that
//!     VAL-ONBOARD-014 explicitly owns.
//!
//! Without this isolation, the only way to force a provisioner-offline failure
//! against the live demo stack is to `docker stop frostr-infra-igloo-demo-1`
//! while keeping `dev-relay` up; that mutates shared demo infra and is
//! reserved for serialized real-device E2E runs (validator-side). The
//! synthetic-pubkey approach gives us a deterministic Rust-only test that
//! the production code path returns `provisioner_offline` (NOT
//! `relay_unreachable`) within the 45-second VAL-ONBOARD-014 bound.
//!
//! Run with:
//!
//! ```bash
//! git status --porcelain   # clean worktree
//! DEV_RELAY_PORT=8194 make -C ../demo-start   # starts dev-relay WITHOUT alice
//! cargo test --test onboard_provisioner_offline -- --ignored
//! ```
//!
//! Specifically, the test does NOT require the igloo-demo (alice) container
//! to be running, because the synthetic responder pubkey has no signer
//! anywhere. Only the dev-relay is required.

use igloo_mobile_core::FfiApp;
use std::sync::mpsc;
use std::time::{Duration, Instant};

const HARNESS_DIR: &str = "/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness";
const RELAY_URL: &str = "ws://127.0.0.1:8194";
// VAL-ONBOARD-014 contract bound.
const PROVISIONER_OFFLINE_BUDGET_SECS: u64 = 45;

/// Mint a deterministic, fully-decodable `bfonboard1` package whose provisioner
/// pubkey points at a synthetic random signer that will never publish a
/// response. The package bytes are derived via frostr-utils:
/// 1. Synthesize a 2-of-3 FROSTR keyset (via `create_keyset`).
/// 2. Use share 0 as the local member, share 1's pubkey as the (synthetic)
///    provisioner responder — exactly the way a real alice-published
///    invite would, but with the responder replaced by a deterministic hex
///    string so no real signer is involved.
/// 3. Encode as `bfonboard1...` text using the same encoder the harness
///    uses (`encode_bfonboard_package`) with a 32-char password matching the
///    real credential lengths.
///
/// The package deliberately uses a SYNTHETIC responder (NOT share 1's real
/// pubkey) to ensure no signer on the demo relay will ever respond. If the
/// test ever starts succeeding, the most likely cause is that the synthetic
/// responder coincidentally matches a real signer pubkey on the relay; in
/// that case change the seed in the function below.
fn mint_synthetic_offline_provisioner_package() -> (String, String) {
    use rand::rngs::StdRng;
    use rand::{Rng, SeedableRng};

    // Synthesize the keyset used to generate the local share.
    let bundle = frostr_utils::create_keyset(frostr_utils::CreateKeysetConfig::new(
        "synthetic offline provisioner",
        2,
        3,
    ))
    .expect("create synthetic 2-of-3 keyset");
    let local_share = bundle.shares[0].clone();
    // Deterministic 32-byte "never-responding" responder pubkey. Hex-encoded
    // (x-only 64 chars). This is the bit that matters: by picking bytes that
    // have no signer backend, the relay accepts/subscribes/publishes but
    // await_onboard_response gets nothing and times out at 45s.
    let mut rng = StdRng::seed_from_u64(0xDEAD_BEEF_C0FF_EEBE);
    let mut responder_bytes = [0u8; 32];
    for chunk in responder_bytes.chunks_mut(8) {
        let v: u64 = rng.gen();
        let bytes = v.to_le_bytes();
        let n = chunk.len().min(bytes.len());
        chunk[..n].copy_from_slice(&bytes[..n]);
    }
    let responder_pubkey_hex = hex::encode(responder_bytes);

    let payload = frostr_utils::BfOnboardPayload {
        share_secret: hex::encode(local_share.seckey.expose_bytes()),
        relays: vec![RELAY_URL.to_string()],
        peer_pk: responder_pubkey_hex.clone(),
    };
    // 32-char password matching the real harness credential style (ASCII,
    // mixed-case + digits — bech32m-friendly, no spaces or hyphens).
    let password = "SYNTHETICPASSWORDSARE32CHARSLONG".to_string();
    assert_eq!(password.len(), 32, "synthetic password must be 32 chars");
    let package_text = frostr_utils::encode_bfonboard_package(&payload, &password)
        .expect("encode synthetic bfonboard package");

    // Sanity-check shape: package is well-formed bech32m, decode succeeds.
    let decoded = frostr_utils::decode_bfonboard_package(&package_text, &password)
        .expect("decode our own bfonboard package");
    assert_eq!(
        decoded.share_secret,
        hex::encode(local_share.seckey.expose_bytes())
    );
    assert_eq!(decoded.relays, vec![RELAY_URL.to_string()]);
    assert_eq!(decoded.peer_pk, responder_pubkey_hex);

    (package_text, password)
}

fn relay_reachable() -> bool {
    use std::net::ToSocketAddrs;
    let stripped = RELAY_URL.strip_prefix("ws://").unwrap_or(RELAY_URL);
    let addrs: Vec<std::net::SocketAddr> = stripped
        .to_socket_addrs()
        .map(|iter| iter.collect())
        .unwrap_or_default();
    for addr in &addrs {
        if std::net::TcpStream::connect_timeout(addr, Duration::from_secs(2)).is_ok() {
            return true;
        }
    }
    false
}

/// Live test: provisioner-offline response times out within 45 seconds and
/// surfaces the contract-visible `provisioner_offline` error kind (NOT
/// `relay_unreachable`). This is the Rust land unit-of-evidence for
/// VAL-ONBOARD-014, separately from the relay-unreachable case asserted by
/// `live_relay_unreachable_returns_within_15_seconds_with_relay_unreachable_error`
/// in `tests/onboard_live_relay.rs`.
///
/// Run ONLY when the dev-relay is up (and alice can be either up or down —
/// the synthetic responder never produces a response). The package we
/// generate specifically points at a pubkey that DOES NOT exist, so the
/// success path is impossible — exactly the failure mode we are proving.
#[test]
#[ignore = "requires live demo stack (relay only); run via cargo test -- --ignored"]
fn live_relay_provisioner_offline_returns_within_45_seconds_with_provisioner_offline_error() {
    // Pre-flight check: relay must be reachable. Skip the test if not, so the
    // suite still passes on machines without the dev-relay running.
    if !relay_reachable() {
        eprintln!(
            "[live-relay/provisioner-offline] SKIP: dev-relay at {RELAY_URL} is not reachable; \
             bring up via `DEV_RELAY_PORT={} scripts/demo.sh relay-up`",
            8194
        );
        return;
    }

    let (package, password) = mint_synthetic_offline_provisioner_package();
    assert!(
        package.len() > 100,
        "synthetic package must be at least 100 chars; got {}",
        package.len()
    );
    assert_eq!(password.len(), 32, "synthetic password must be 32 chars");

    eprintln!(
        "[live-relay/provisioner-offline] synthetic package length={}, password length={}",
        package.len(),
        password.len()
    );

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let (tx, rx) = mpsc::channel();
    let app_for_thread = app.clone();
    let relay = RELAY_URL.to_string();
    let handle = std::thread::spawn(move || {
        let start = Instant::now();
        let result = app_for_thread.onboard(package.clone(), password.clone(), relay.clone());
        let elapsed = start.elapsed();
        eprintln!(
            "[live-relay/provisioner-offline] FfiApp::onboard returned in {:.1}s, success={}, error={:?}",
            elapsed.as_secs_f64(),
            result.success,
            result.error
        );
        let _ = tx.send((result, elapsed));
    });

    // VAL-ONBOARD-014 contract: the no-responder case must return within 45s.
    // We use 50s as the rx.recv_timeout safety net so the test fails fast if
    // the timeout regresses. The handshake_timeout was tightened from 180s
    // to 45s in this fix so the await_onboard_response path fails within
    // the contract bound.
    match rx.recv_timeout(Duration::from_secs(PROVISIONER_OFFLINE_BUDGET_SECS + 5)) {
        Ok((result, elapsed)) => {
            assert!(
                !result.success,
                "provisioner-offline onboard must NOT succeed"
            );
            // The classifier maps the bifrost-app error string
            // "timed out waiting for onboard response from <pk>" to the
            // contract-visible "provisioner_offline" kind via
            // classify_handshake_error. This MUST NOT be
            // "relay_unreachable" — the relay was reachable and the
            // adapter.connect() succeed; only the provisioner response
            // never arrived.
            assert_eq!(
                result.error.as_deref(),
                Some("provisioner_offline"),
                "provisioner-offline onboard must surface 'provisioner_offline' (got {:?})",
                result.error
            );
            assert!(
                elapsed <= Duration::from_secs(PROVISIONER_OFFLINE_BUDGET_SECS),
                "provisioner-offline onboard must return within 45s; elapsed={:.1}s",
                elapsed.as_secs_f64()
            );
            eprintln!(
                "OK: provisioner-offline surfaced as 'provisioner_offline' in {:.1}s",
                elapsed.as_secs_f64()
            );
        }
        Err(_) => {
            panic!(
                "FfiApp::onboard against ws://127.0.0.1:8194 with a synthetic no-responder \
                 pubkey MUST return within 50s; a hang past 45s breaks VAL-ONBOARD-014. \
                 Debug: handshake_timeout regressed back above 45s, or the relay \
                 probe/threading layer is leaking past the 45s outer bound."
            );
        }
    }

    let _ = handle.join();
    // The harness dir contains the synthetic package/password (NOT printed,
    // NOT committed; only the side-effect of the encoder run). We don't
    // write anything to disk — pure in-memory.
    let _ = std::path::Path::new(HARNESS_DIR);
}
