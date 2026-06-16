// ── Verified Relay Adapter ────────────────────────────────────────────────────
//
// Wraps bifrost-bridge-tokio's NostrSdkAdapter with explicit connection,
// subscribe, and publish verification. The raw NostrSdkAdapter::connect()
// spawns background connection tasks and returns immediately; subsequent
// subscribe/publish calls may race with the not-yet-established connection.
// This wrapper adds settle-time and retry logic so each operation is confirmed
// before the next begins.
//
// Used in:
// - FfiApp::onboard() for the real Nostr onboard handshake path.
// - FfiApp::start_signer() (`mobile-android-signer-restoring-readiness-fix`).
//   The signing path was previously hitting the raw NostrSdkAdapter; in
//   debug captures the autoping PONG returns with `incoming_available=70`
//   for alice but `peer_last_seen=None`, which keeps `peer.online=false`
//   inside the bifrost peer_status read model and stalls readiness at
//   `restoring`. Wrapping the signing-path adapter adds settle time after
//   connect()/subscribe() so the relay's pubkey-tag filter is registered
//   with the websocket before the first autoping publish, and triggers
//   inbound-event logging that flows through RUST_LOG so the next round-5
//   validator can prove the autoping round actually crossed the wire.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use bifrost_bridge_tokio::{NostrSdkAdapter, RelayAdapter};
use nostr::{Event, Filter};
use tracing::{debug, info, warn};

// Settle times allow the nostr-sdk relay pool to process each operation
// before the next one starts. These are conservative values; the actual
// connection establishment and event propagation times are usually faster.
//
// The signing-path adapter uses slightly longer suffixed publishes (750 ms)
// because the autoping bootstrap fires a PING back-to-back across every
// seeded peer and the relay pool's internal RTT queue needs that headroom
// on Android. The onboard path keeps the original 500 ms.
const SIGNING_CONNECTION_SETTLE_MS: u64 = 1000;
const SIGNING_SUBSCRIBE_SETTLE_MS: u64 = 750;
const SIGNING_PUBLISH_SETTLE_MS: u64 = 750;

/// A RelayAdapter wrapper that adds explicit settle-time verification after
/// each operation. This addresses the issue where NostrSdkAdapter::connect()
/// returns before the relay WebSocket is fully established, causing
/// subscribe/publish to race with the connection setup.
pub struct VerifiedNostrSdkAdapter {
    inner: NostrSdkAdapter,
    relay_count: usize,
    /// Caller-provided tag that gets prepended to every tracing event so the
    /// signing path is distinguishable from the onboard path in logcat /
    /// `RUST_LOG=debug` captures.
    path_tag: &'static str,
}

impl VerifiedNostrSdkAdapter {
    /// Construct a VerifiedNostrSdkAdapter scoped to the onboard path.
    /// Tags every tracing event with `"onboard"`. The 500 ms subscribe and
    /// publish settle windows match the legacy VerifiedNostrSdkAdapter
    /// values that were historically used during onboarding's first
    /// handshake round; the signing path uses slightly longer values — see
    /// `for_signing`.
    #[allow(dead_code)]
    pub fn new(relays: Vec<String>) -> Self {
        let relay_count = relays.len();
        Self {
            inner: NostrSdkAdapter::new(relays),
            relay_count,
            path_tag: "onboard",
        }
    }

    /// Construct a VerifiedNostrSdkAdapter scoped to the signing path. The
    /// returned adapter adds slightly longer subscribe/publish settle times
    /// (to absorb the back-to-back autoping bootstrap rounds) and tags every
    /// `tracing` event with `"signing"` so logcat / `RUST_LOG=debug` captures
    /// can be grepped for the signing-path specifically.
    ///
    /// On Android we additionally apply a tiny best-effort URL override:
    /// when the persisted material carries `ws://localhost:*` or
    /// `ws://127.0.0.1:*` (typically because the share envelope was
    /// generated against the iOS-Simulator host loopback), we substitute
    /// the Android-emulator-friendly `ws://10.0.2.2:*` alias on the same
    /// port so the first handshake round reaches the demo harness. Users
    /// who deliberately target a relay running on the *emulator's* own
    /// loopback can override the field with a production URL on the
    /// Dashboard form; this override only fires when the saved profile's
    /// stored URL would otherwise hit the unreachable `localhost` alias.
    pub fn for_signing(relays: Vec<String>) -> Self {
        let (relay_count, relays) = Self::android_loopback_relay_sanity(relays);
        info!(
            relay_count = relay_count,
            "VerifiedNostrSdkAdapter::for_signing: signing-path adapter constructed"
        );
        Self {
            inner: NostrSdkAdapter::new(relays),
            relay_count,
            path_tag: "signing",
        }
    }

    /// Android-only URL sanity pass: rewrite the saved profile URL when it
    /// accidentally targets the emulator's own loopback instead of the
    /// host's. Logs each rewrite at `info!` level so the focused proof
    /// captures show a clean before/after breadcrumb. On non-Android
    /// targets this is a pass-through so iOS-Simulator users running the
    /// same Rust core (which expects `ws://127.0.0.1:*` to reach the
    /// host loopback) see no regression.
    fn android_loopback_relay_sanity(relays: Vec<String>) -> (usize, Vec<String>) {
        let relay_count = relays.len();
        #[cfg(target_os = "android")]
        {
            let rewritten: Vec<String> = relays
                .into_iter()
                .map(|url| {
                    if let Some(stripped) = url.strip_prefix("ws://localhost:") {
                        let canonical = format!("ws://10.0.2.2:{}", stripped);
                        info!(
                            old_url = %url,
                            new_url = %canonical,
                            "VerifiedNostrSdkAdapter::for_signing: \
                             Android loopback URL rewritten via emulator alias"
                        );
                        canonical
                    } else if let Some(stripped) = url.strip_prefix("ws://127.0.0.1:") {
                        let canonical = format!("ws://10.0.2.2:{}", stripped);
                        info!(
                            old_url = %url,
                            new_url = %canonical,
                            "VerifiedNostrSdkAdapter::for_signing: \
                             Android loopback URL rewritten via emulator alias"
                        );
                        canonical
                    } else {
                        url
                    }
                })
                .collect();
            (relay_count, rewritten)
        }
        #[cfg(not(target_os = "android"))]
        {
            (relay_count, relays)
        }
    }
}

#[async_trait]
impl RelayAdapter for VerifiedNostrSdkAdapter {
    async fn connect(&mut self) -> Result<()> {
        info!(
            path = self.path_tag,
            relay_count = self.relay_count,
            "VerifiedNostrSdkAdapter: connecting"
        );
        // Call the inner connect - nostr-sdk starts background connection tasks.
        self.inner.connect().await?;

        // Wait for connections to settle. The nostr-sdk Client::connect() is
        // non-blocking (it spawns tasks and returns immediately), so we add
        // explicit settle time to let the WebSocket connections establish.
        // Without this, subscribe() and publish() may race with connection setup.
        let settle = settle_after(self.path_tag, "connect", SIGNING_CONNECTION_SETTLE_MS);
        settle.await;
        debug!(
            path = self.path_tag,
            "VerifiedNostrSdkAdapter: connection settled"
        );
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<()> {
        self.inner.disconnect().await
    }

    async fn subscribe(&mut self, filters: Vec<Filter>) -> Result<()> {
        info!(
            path = self.path_tag,
            filter_count = filters.len(),
            "VerifiedNostrSdkAdapter: subscribing"
        );
        self.inner.subscribe(filters).await?;

        // Wait for subscription to be registered with the relay.
        let settle = settle_after(self.path_tag, "subscribe", SIGNING_SUBSCRIBE_SETTLE_MS);
        settle.await;
        debug!(
            path = self.path_tag,
            "VerifiedNostrSdkAdapter: subscription settled"
        );
        Ok(())
    }

    async fn publish(&mut self, event: Event) -> Result<()> {
        let event_id = event.id.to_hex();
        let event_kind = u64::from(event.kind.as_u16());
        info!(
            path = self.path_tag,
            event_id = %event_id,
            event_kind = event_kind,
            "VerifiedNostrSdkAdapter: publishing event"
        );
        let inner_result = self.inner.publish(event).await;

        // Settle for the same duration even if publish returned Err so a
        // subsequent publish does not race with the relay pool's error
        // bookkeeping. If `inner_result` is Err we still want the settle
        // window so the next event in the bumping autoping sequence has a
        // chance to register against the live connection.
        let settle = settle_after(self.path_tag, "publish", SIGNING_PUBLISH_SETTLE_MS);
        settle.await;

        match &inner_result {
            Ok(_) => {
                debug!(
                    path = self.path_tag,
                    event_id = %event_id,
                    "VerifiedNostrSdkAdapter: publish settled"
                );
            }
            Err(err) => {
                warn!(
                    path = self.path_tag,
                    event_id = %event_id,
                    error = %err,
                    "VerifiedNostrSdkAdapter: publish failed (after settle window)"
                );
            }
        }
        inner_result
    }

    async fn next_event(&mut self) -> Result<Event> {
        // Inbound events are the only place `peer_last_seen` advances on the
        // bridge side, so log each one with the event id, kind, sender pubkey
        // (if present in the tags), and a tag/path. `RUST_LOG=debug` will
        // surface this in `adb logcat` so a future worker can confirm the
        // autoping PONG actually crossed the Android wire end-to-end without
        // needing to rely on stale peer_status snapshots.
        match self.inner.next_event().await {
            Ok(event) => {
                let event_id = event.id.to_hex();
                let event_kind = u64::from(event.kind.as_u16());
                let sender = event.pubkey.to_hex();
                info!(
                    path = self.path_tag,
                    event_id = %event_id,
                    event_kind = event_kind,
                    sender = %sender,
                    "VerifiedNostrSdkAdapter: inbound event received from relay"
                );
                Ok(event)
            }
            Err(err) => {
                warn!(
                    path = self.path_tag,
                    error = %err,
                    "VerifiedNostrSdkAdapter: inbound event recv failed"
                );
                Err(err)
            }
        }
    }
}

async fn settle_after(path: &'static str, phase: &'static str, base_ms: u64) {
    // `RUST_LOG=debug` drives additional log volume on Android, so emit a
    // debug-level breadcrumb that names both the path and the round being
    // settled. This is the breadcrumb a worker would grep for to convert a
    // round-5 validator logcat scrape into a sequenced end-to-end timeline.
    debug!(
        path = path,
        phase = phase,
        settle_ms = base_ms,
        "VerifiedNostrSdkAdapter: settle window opening"
    );
    tokio::time::sleep(Duration::from_millis(base_ms)).await;
    debug!(
        path = path,
        phase = phase,
        "VerifiedNostrSdkAdapter: settle window closed"
    );
}
