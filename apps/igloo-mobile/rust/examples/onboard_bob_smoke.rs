//! Standalone diagnostic: exercise bifrost-app's
//! `complete_onboarding_with_adapter` directly against the live demo relay,
//! using the current redacted bob credential pair.
//!
//! This bypasses the FfiApp onboarding wrapper so we can isolate whether the
//! rust-level handshake (decode + connect + subscribe + publish + await) is
//! the failure boundary.
//!
//! Run with:
//!   source ~/.config/frostr/rmp-mobile-env.zsh
//!   cd apps/igloo-mobile/rust
//!   cargo run --example onboard_bob_smoke

use bifrost_bridge_tokio::NostrSdkAdapter;
use frostr_utils::decode_bfonboard_package;
use std::time::{Duration, Instant};

const HARNESS_DIR: &str = "/Users/plebdev/Desktop/Projects/frostr-infra/.tmp/test-harness";
const RELAY_URL: &str = "ws://127.0.0.1:8194";

fn main() {
    let package = std::fs::read_to_string(format!("{HARNESS_DIR}/onboard-bob.txt"))
        .expect("bob package")
        .trim()
        .to_string();
    let password = std::fs::read_to_string(format!("{HARNESS_DIR}/onboard-bob.password.txt"))
        .expect("bob password")
        .trim()
        .to_string();
    eprintln!(
        "[onboard-bob-smoke] package len={} password len={} relay={}",
        package.len(),
        password.len(),
        RELAY_URL
    );

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("build runtime");

    let started = Instant::now();
    let result = rt.block_on(async move {
        let decoded = match decode_bfonboard_package(&package, &password) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("[onboard-bob-smoke] decode failed: {e}");
                return Err(anyhow::anyhow!("decode failed: {e}"));
            }
        };
        eprintln!(
            "[onboard-bob-smoke] decoded: {} relays, peer_pk prefix {}",
            decoded.relays.len(),
            &decoded.peer_pk[..8]
        );

        let adapter = NostrSdkAdapter::new(vec![RELAY_URL.to_string()]);
        let completion = bifrost_app::onboarding::complete_onboarding_with_adapter(
            adapter,
            decoded,
            Duration::from_secs(180),
        )
        .await;
        completion
    });

    eprintln!(
        "[onboard-bob-smoke] elapsed: {:.1}s, result={:?}",
        started.elapsed().as_secs_f64(),
        result.as_ref().err().map(|e| format!("{e}"))
    );
    if let Ok(c) = result {
        eprintln!(
            "[onboard-bob-smoke] SUCCESS group={:?} bootstrap_nonces={} peer_pubkey={}",
            c.group.group_pk,
            c.bootstrap_nonces.len(),
            c.peer_pubkey
        );
    }
}
