//! Quick diagnostic: connect NostrSdkAdapter directly against the live relay
//! and report whether connect()/subscribe()/publish()/next_event() calls return.
//!
//! Run with:
//!   source ~/.config/frostr/rmp-mobile-env.zsh
//!   cd apps/igloo-mobile/rust
//!   cargo run --example nostr_connect_smoke <relay_url>

use bifrost_bridge_tokio::{NostrSdkAdapter, RelayAdapter};
use nostr::Filter;
use std::time::Duration;

fn main() {
    let relay = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "ws://127.0.0.1:8194".to_string());
    eprintln!("[nostr-smoke] using relay: {}", relay);

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("build runtime");
    let started = std::time::Instant::now();
    let result = rt.block_on(async {
        let mut adapter = NostrSdkAdapter::new(vec![relay.clone()]);
        eprintln!("[nostr-smoke] adapter created");
        adapter.connect().await?;
        eprintln!("[nostr-smoke] connect returned");
        let filter: Filter = serde_json::from_value(serde_json::json!({
            "kinds": [20000],
            "authors": [],
            "#p": [],
        }))
        .expect("filter");
        adapter.subscribe(vec![filter]).await?;
        eprintln!("[nostr-smoke] subscribe returned");
        // Try to publish a tiny event to smoke-test the wire.
        let keys = nostr::Keys::generate();
        let event = nostr::EventBuilder::new(nostr::Kind::from(20000), "smoke")
            .build(keys.public_key())
            .sign_with_keys(&keys)
            .expect("sign event");
        adapter.publish(event).await?;
        eprintln!("[nostr-smoke] publish returned");
        // Wait a short period before disconnecting so the relay has time to process.
        tokio::time::sleep(Duration::from_millis(500)).await;
        let _ = adapter.disconnect().await;
        eprintln!("[nostr-smoke] disconnect returned");
        Ok::<(), anyhow::Error>(())
    });

    eprintln!(
        "[nostr-smoke] total elapsed: {:.1}s, result={:?}",
        started.elapsed().as_secs_f64(),
        result
    );
}
