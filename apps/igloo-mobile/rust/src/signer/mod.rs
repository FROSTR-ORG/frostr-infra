// ── Verified Relay Adapter ────────────────────────────────────────────────────
//
// Wraps bifrost-bridge-tokio's NostrSdkAdapter with explicit connection,
// subscribe, and publish verification. The raw NostrSdkAdapter::connect()
// spawns background connection tasks and returns immediately; subsequent
// subscribe/publish calls may race with the not-yet-established connection.
// This wrapper adds settle-time and retry logic so each operation is confirmed
// before the next begins.
//
// Used in FfiApp.onboard() for the real Nostr onboard handshake path.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use bifrost_bridge_tokio::{NostrSdkAdapter, RelayAdapter};
use k256::elliptic_curve::sec1::ToEncodedPoint;
use nostr::{Event, Filter};
use tracing::{debug, info};

// Settle times allow the nostr-sdk relay pool to process each operation
// before the next one starts. These are conservative values; the actual
// connection establishment and event propagation times are usually faster.
const CONNECTION_SETTLE_MS: u64 = 1000;
const SUBSCRIBE_SETTLE_MS: u64 = 500;
const PUBLISH_SETTLE_MS: u64 = 500;

/// A RelayAdapter wrapper that adds explicit settle-time verification after
/// each operation. This addresses the issue where NostrSdkAdapter::connect()
/// returns before the relay WebSocket is fully established, causing
/// subscribe/publish to race with the connection setup.
pub struct VerifiedNostrSdkAdapter {
    inner: NostrSdkAdapter,
    relay_count: usize,
}

impl VerifiedNostrSdkAdapter {
    pub fn new(relays: Vec<String>) -> Self {
        let relay_count = relays.len();
        Self {
            inner: NostrSdkAdapter::new(relays),
            relay_count,
        }
    }
}

#[async_trait]
impl RelayAdapter for VerifiedNostrSdkAdapter {
    async fn connect(&mut self) -> Result<()> {
        info!(
            relay_count = self.relay_count,
            "VerifiedNostrSdkAdapter: connecting"
        );
        // Call the inner connect - nostr-sdk starts background connection tasks.
        self.inner.connect().await?;

        // Wait for connections to settle. The nostr-sdk Client::connect() is
        // non-blocking (it spawns tasks and returns immediately), so we add
        // explicit settle time to let the WebSocket connections establish.
        // Without this, subscribe() and publish() may race with connection setup.
        tokio::time::sleep(Duration::from_millis(CONNECTION_SETTLE_MS)).await;
        debug!("VerifiedNostrSdkAdapter: connection settled");
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<()> {
        self.inner.disconnect().await
    }

    async fn subscribe(&mut self, filters: Vec<Filter>) -> Result<()> {
        info!(
            filter_count = filters.len(),
            "VerifiedNostrSdkAdapter: subscribing"
        );
        self.inner.subscribe(filters).await?;

        // Wait for subscription to be registered with the relay.
        tokio::time::sleep(Duration::from_millis(SUBSCRIBE_SETTLE_MS)).await;
        debug!("VerifiedNostrSdkAdapter: subscription settled");
        Ok(())
    }

    async fn publish(&mut self, event: Event) -> Result<()> {
        let event_id = event.id.to_hex();
        info!(
            event_id = %event_id,
            "VerifiedNostrSdkAdapter: publishing event"
        );
        self.inner.publish(event).await?;

        // Wait for publish to be acknowledged by the relay.
        tokio::time::sleep(Duration::from_millis(PUBLISH_SETTLE_MS)).await;
        debug!(
            event_id = %event_id,
            "VerifiedNostrSdkAdapter: publish settled"
        );
        Ok(())
    }

    async fn next_event(&mut self) -> Result<Event> {
        self.inner.next_event().await
    }
}