//! Live relay integration test for `FfiApp::onboard`.
//!
//! These tests exercise the production `FfiApp::onboard(...)` code path with the
//! real bob/carol demo credentials against the live demo relay + alice co-signer.
//! They are gated behind `--ignored` because they require:
//! - The demo stack (`make demo-start`) running relay + alice on port 8194
//! - Freshly generated credentials in `.tmp/test-harness/onboard-{bob,carol}.txt`
//! - The bob credential matches whatever relay write alice made for the demo
//!   keyset so the live handshake completes against the real provisioner.
//!
//! The test path mirrors what the iOS URL-scheme handler invokes via
//! `injectTestOnboardPackage(...) -> onboardConnect(...) -> performOnboardHandshake(...)`.
//! Run with:
//!
//! ```bash
//! git status --porcelain # clean worktree
//! DEV_RELAY_PORT=8194 make -C ../demo-start
//! DEV_RELAY_PORT=8194 make demo-onboard
//! cd /Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/rust
//! cargo test --workspace -- --ignored onboard_live_relay
//! ```
//!
//! These tests do NOT log secrets. They print only:
//! - success/failure of the call
//! - whether the result arrived within the bounded wait
//! - which credential set was used (file path, not contents)
//! - bob/carol peer's share pubkey length and group pubkey length to confirm
//!   decode/handshake completion without leaking material.

use igloo_mobile_core::FfiApp;
use std::sync::mpsc;
use std::time::{Duration, Instant};

const HARNESS_DIR: &str = "/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness";
const RELAY_URL: &str = "ws://127.0.0.1:8194";

fn read_credential_file(name: &str) -> String {
    let path = std::path::Path::new(HARNESS_DIR).join(name);
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("missing credential at {}: {}", path.display(), e));
    raw.trim().to_string()
}

/// Valid bob credentials against the live demo relay.
/// Exercises the real `FfiApp::onboard(...)` code path the iOS app uses,
/// so a failure here is the same failure mode the running app would hit.
#[test]
#[ignore = "requires live demo stack; run via cargo test -- --ignored"]
fn live_relay_bob_onboard_succeeds_within_45_seconds() {
    let package = read_credential_file("onboard-bob.txt");
    let password = read_credential_file("onboard-bob.password.txt");
    assert_eq!(package.len(), 690, "bob package must be 690 chars");
    assert_eq!(password.len(), 32, "bob password must be 32 chars");

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let (tx, rx) = mpsc::channel();
    let app_for_thread = app.clone();
    let relay = RELAY_URL.to_string();

    // Diagnostic instrumentation via env vars and the controlled flow.
    // The Rust onboard thread stamps a prefix to every log line so the catch_unwind
    // panic and the regular Err branches can be distinguished in captured stderr.
    let handle = std::thread::Builder::new()
        .name("igloo-onboard-bob".into())
        .spawn(move || {
            let start = Instant::now();
            let result = app_for_thread.onboard(package.clone(), password.clone(), relay.clone());
            let elapsed = start.elapsed();
            eprintln!(
                "[DIAG] bob FfiApp::onboard returned in {:.1}s, success={}, error={:?}",
                elapsed.as_secs_f64(),
                result.success,
                result.error
            );
            let _ = tx.send((result, elapsed));
        })
        .unwrap();

    // The handshake must return within 45s (VAL-ONBOARD-007 relay-unreachable
    // bound) when the connect-subscribe-publish-await path completes against the
    // live alice peer. If the result is success, the live handshake completed.
    match rx.recv_timeout(Duration::from_secs(45)) {
        Ok((result, elapsed)) => {
            if !result.success {
                eprintln!(
                    "[DIAG] bob share_pubkey={:?} group_pubkey={:?} relays={:?}",
                    result.share_pubkey, result.group_pubkey, result.relays
                );
                panic!(
                    "FfiApp::onboard against live relay did NOT succeed: error={:?}",
                    result.error
                );
            }
            assert!(
                result.share_pubkey.is_some() && result.share_pubkey.as_ref().unwrap().len() == 64,
                "bob share pubkey must be 64-char hex"
            );
            assert!(
                result.group_pubkey.is_some() && result.group_pubkey.as_ref().unwrap().len() == 64,
                "bob group pubkey must be 64-char hex"
            );
            assert!(
                result.relays.is_some() && !result.relays.as_ref().unwrap().is_empty(),
                "bob relays must be non-empty"
            );
            eprintln!("[DIAG] bob succeeded in {:.1}s", elapsed.as_secs_f64());
        }
        Err(_) => {
            panic!(
                "FfiApp::onboard against live relay MUST return within 45s; \
                 this is the no-return hang we are diagnosing"
            );
        }
    }

    let _ = handle.join();
}

/// Valid carol credentials against the live demo relay.
/// Exercises the production code path with the second demo identity; if bob
/// passes but carol fails we know the issue is identity-specific (e.g. peer
/// pubkey tag mismatch). Carol is independent of the iOS gate — the iOS gate
/// uses bob — but this test removes the "is the live handshake itself broken?"
/// ambiguity.
#[test]
#[ignore = "requires live demo stack; run via cargo test -- --ignored"]
fn live_relay_carol_onboard_succeeds_within_45_seconds() {
    let package = read_credential_file("onboard-carol.txt");
    let password = read_credential_file("onboard-carol.password.txt");
    assert_eq!(package.len(), 690, "carol package must be 690 chars");
    assert_eq!(password.len(), 32, "carol password must be 32 chars");

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let (tx, rx) = mpsc::channel();
    let app_for_thread = app.clone();
    let relay = RELAY_URL.to_string();
    let handle = std::thread::spawn(move || {
        let start = Instant::now();
        let result = app_for_thread.onboard(package.clone(), password.clone(), relay.clone());
        let elapsed = start.elapsed();
        let _ = tx.send((result, elapsed));
    });

    match rx.recv_timeout(Duration::from_secs(45)) {
        Ok((result, elapsed)) => {
            eprintln!(
                "[live-relay/carol] onboard returned in {:.1}s, success={}, error={:?}",
                elapsed.as_secs_f64(),
                result.success,
                result.error
            );
            if !result.success {
                panic!(
                    "FfiApp::onboard (carol) against live relay did NOT succeed: error={:?}",
                    result.error
                );
            }
        }
        Err(_) => {
            panic!("FfiApp::onboard (carol) against live relay must return within 45s");
        }
    }
    let _ = handle.join();
}

/// Wrong password against the live demo relay exercises the decode-failure
/// fast path. This must return within seconds (not 45s), proving the no-UI
/// path is healthy when the inbound handshake cannot even start.
#[test]
#[ignore = "requires live demo stack; run via cargo test -- --ignored"]
fn live_relay_bob_onboard_wrong_password_returns_fast() {
    let package = read_credential_file("onboard-bob.txt");
    let bad_password = "0".repeat(32);

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let (tx, rx) = mpsc::channel();
    let app_for_thread = app.clone();
    let relay = RELAY_URL.to_string();
    let handle = std::thread::spawn(move || {
        let start = Instant::now();
        let result = app_for_thread.onboard(package.clone(), bad_password.clone(), relay.clone());
        let elapsed = start.elapsed();
        let _ = tx.send((result, elapsed));
    });

    match rx.recv_timeout(Duration::from_secs(15)) {
        Ok((result, elapsed)) => {
            eprintln!(
                "[live-relay/wrong-pw] onboard returned in {:.1}s, success={}, error={:?}",
                elapsed.as_secs_f64(),
                result.success,
                result.error
            );
            assert!(!result.success, "wrong password must NOT succeed");
            assert_eq!(
                result.error.as_deref(),
                Some("wrong_password"),
                "wrong password must surface wrong_password error kind"
            );
        }
        Err(_) => {
            panic!(
                "wrong password must return within 15s (decode fails fast); \
                 a hang here means FfiApp::onboard is leaking past decode"
            );
        }
    }
    let _ = handle.join();
}

/// Real bob credentials against an UNREACHABLE relay.
/// mobile-onboard-error-path-hardening-fix: VAL-ONBOARD-007 requires that the
/// unreachable-relay path returns an explicit relay_unreachable error within
/// 45 seconds. The bug being fixed is that on Android, the "Connecting..."
/// indicator stayed visible past 75 seconds for `ws://10.0.2.2:9` despite a
/// 15s Rust connect_timeout; the path leaked past `adapter.connect()` into
/// the full 180s handshake_timeout because nostr-sdk's `client.connect()`
/// does not block on TCP reachability on Android (it queues connection
/// attempts and returns immediately).
///
/// The fix adds a pre-flight TCP probe using std::net::TcpStream before
/// entering the tokio runtime, so an unreachable endpoint is detected in
/// 5-10s regardless of the nostr-sdk threading model. This test exercises
/// that probe path with REAL decoded credentials (no mock), so it proves
/// both:
///   1. The decode path is healthy (bob's password decrypts successfully).
///   2. The pre-flight probe rejects the unreachable port within seconds.
///
/// This is gated behind `#[ignore]` because the demo stack must be running
/// for `read_credential_file("onboard-bob.txt")` to resolve, but the
/// unreachable-relay probe itself does NOT depend on the demo relay being
/// up — we override `relay_url` to a TCP-dead endpoint that has no
/// listener. Run with:
///
/// ```bash
/// DEV_RELAY_PORT=8194 make demo-onboard   # populate .tmp/test-harness/
/// cd apps/igloo-mobile/rust
/// cargo test --test onboard_live_relay -- --ignored live_relay_unreachable
/// ```
#[test]
#[ignore = "requires live demo stack; run via cargo test -- --ignored"]
fn live_relay_unreachable_returns_within_15_seconds_with_relay_unreachable_error() {
    let package = read_credential_file("onboard-bob.txt");
    let password = read_credential_file("onboard-bob.password.txt");
    assert_eq!(package.len(), 690, "bob package must be 690 chars");
    assert_eq!(password.len(), 32, "bob password must be 32 chars");

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let (tx, rx) = mpsc::channel();
    let app_for_thread = app.clone();
    // Port 9 is reserved as the "discard" service and has no reliable listener
    // on either iOS simulator (`127.0.0.1:9` from host loopback) or Android
    // emulator (`10.0.2.2:9` from the Android host loopback alias). The exact
    // same address is what the validation contract uses for VAL-ONBOARD-007.
    let relay = "ws://127.0.0.1:9".to_string();
    let handle = std::thread::spawn(move || {
        let start = Instant::now();
        let result = app_for_thread.onboard(package.clone(), password.clone(), relay.clone());
        let elapsed = start.elapsed();
        let _ = tx.send((result, elapsed));
    });

    // VAL-ONBOARD-007 contract: unreachable-relay onboarding must fail within
    // 45 seconds with an explicit relay_unreachable error. The pre-flight TCP
    // probe gets this under 15 seconds; we use 15s as the upper bound here so
    // the test fails fast if the probe regresses back into the slow path.
    match rx.recv_timeout(Duration::from_secs(15)) {
        Ok((result, elapsed)) => {
            eprintln!(
                "[live-relay/unreachable] onboard returned in {:.1}s, success={}, error={:?}",
                elapsed.as_secs_f64(),
                result.success,
                result.error
            );
            assert!(!result.success, "unreachable relay must NOT succeed");
            assert_eq!(
                result.error.as_deref(),
                Some("relay_unreachable"),
                "unreachable relay must surface relay_unreachable error kind (got {:?})",
                result.error
            );
            // Belt-and-braces: confirm we cleared the 45s contract bound.
            assert!(
                elapsed <= Duration::from_secs(15),
                "unreachable relay must return within 15s; elapsed={:?}",
                elapsed
            );
        }
        Err(_) => {
            panic!(
                "FfiApp::onboard against ws://127.0.0.1:9 must return within 15s; \
                 a hang past 45s breaks VAL-ONBOARD-007. Debug: pre-flight TCP \
                 probe regressed or fallback 180s handshake_timeout leaked past."
            );
        }
    }
    let _ = handle.join();
}
