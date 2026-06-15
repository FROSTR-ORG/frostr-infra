//! Diagnostic: recreate the FfiApp::onboard wrapping exactly
//! (tokio::time::timeout on adapter.connect + tokio::time::timeout on
//! complete_onboarding_with_adapter) to see if the wrapping itself
//! breaks the relay handshake.

use bifrost_bridge_tokio::{NostrSdkAdapter, RelayAdapter};
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

    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("build runtime");
    eprintln!("[diag] using multi_thread runtime");

    let started = Instant::now();

    // First, decode the package; if it fails, return early (mimics FfiApp).
    let decoded = match decode_bfonboard_package(&package, &password) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[diag] decode failed: {e}");
            return;
        }
    };
    eprintln!("[diag] decoded: {} relays", decoded.relays.len());

    // Now run the same async inside block_on but without the FfiApp
    // outer timing machinery, so we can compare.
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        rt.block_on(tokio::time::timeout(Duration::from_secs(200), async {
            let mut adapter = NostrSdkAdapter::new(vec![RELAY_URL.to_string()]);
            eprintln!("[diag] adapter created");

            let connect_outcome =
                tokio::time::timeout(Duration::from_secs(15), adapter.connect()).await;
            eprintln!("[diag] connect outcome: {:?}", connect_outcome);
            match connect_outcome {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    eprintln!("[diag] connect Err: {e}");
                    return Err(anyhow::anyhow!("{e}"));
                }
                Err(_) => {
                    eprintln!("[diag] connect timed out");
                    return Err(anyhow::anyhow!("timeout"));
                }
            }

            // Run the same handshake as FfiApp.
            let handshake_outcome = bifrost_app::onboarding::complete_onboarding_with_adapter(
                adapter,
                decoded.clone(),
                Duration::from_secs(180),
            )
            .await;
            eprintln!(
                "[diag] handshake outcome: {:?}",
                handshake_outcome.as_ref().err().map(|e| format!("{e}"))
            );
            handshake_outcome
        }))
    }));

    match outcome {
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&'static str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "<panic payload of unknown type>".to_string()
            };
            eprintln!("[diag] catch_unwind CAUGHT PANIC: {msg}");
        }
        Ok(tokio_outcome) => match tokio_outcome {
            Ok(Ok(c)) => eprintln!(
                "[diag] SUCCEEDED in {:.1}s, group_pk first bytes: {:?}, bootstrap_nonces: {}",
                started.elapsed().as_secs_f64(),
                &c.group.group_pk[..8],
                c.bootstrap_nonces.len()
            ),
            Ok(Err(_)) => eprintln!("[diag] async returned; handshake errored"),
            Err(_elapsed) => eprintln!("[diag] tokio 200s timeout fired"),
        },
    }
    eprintln!(
        "[diag] total elapsed: {:.1}s",
        started.elapsed().as_secs_f64()
    );
}
