# Spec: bifrost-rs peer telemetry + interactive signing approval

Scoping/spec doc (no Rust written this pass). Drives the two `bifrost-rs` backlog
items in [`../BACKLOG.md`](../BACKLOG.md). Line references are from the state of
the submodules on 2026-06-10 and are pointers, not contracts — re-confirm before
implementing.

## Why

The signer dashboard (`igloo-ui` `OperatorSignerPanel`) and Paper's
`1-signer-dashboard` artboard draw peer telemetry the runtime cannot supply yet
(per-peer latency, "Avg" latency, a nonce sparkline, per-method SIGN/ECDH/PING
capability badges), and a Pending-Approvals card whose interactive behavior is
stubbed. The `dashboard-signer` visual entry stays `needs-work` until the
telemetry lands. This doc scopes both.

## Current state (verified)

### Architecture
Crates under `repos/bifrost-rs/crates/`: `bifrost-core` (crypto types, policy
structs, FROST nonce pool), `bifrost-signer` (`SigningDevice` state machine,
peer/operation tracking), `bifrost-router` (`BridgeCore` command router over
Nostr), `bifrost-codec` (wire), `bifrost-bridge-wasm` (browser surface),
`bifrost-bridge-tokio` (native). Inbound flow: Nostr `Event` →
`BridgeCore::enqueue_inbound_event` → `tick` → `SigningDevice::process_event`
(`bifrost-signer/src/lib.rs:1232+`), dispatched per method.

### Permission / policy control — EXISTS today
Direct answer to "do we have permission control / can we allow-deny protocol
actions?": **yes.**
- `PeerPolicy` / `MethodPolicy` / `PeerPolicyOverride` / `PolicyOverrideValue`
  (`bifrost-core/src/types.rs:310-432`) gate `echo`/`ping`/`onboard`/`sign`/`ecdh`
  per direction (request vs respond).
- `manual_policy_overrides` in `DeviceState` (`bifrost-signer/src/lib.rs:157`);
  resolved via `local_policy_for_peer` (`:872`) + `effective_policy_for_peer`
  (`:912`); enforced at `inbound_allowed(peer, method)` (`:938`), checked on every
  inbound request (PING `:1851`, ONBOARD `:1888`, SIGN `:2019`, ECDH `:2090`),
  rejecting via `reject_request`.
- Mutable through `set_peer_policy_override` (`:1690`) / `clear_peer_policy_overrides`
  (`:1706`), exported to WASM as `set_policy_override`
  (`bifrost-bridge-wasm/src/lib.rs:589`).
- **Gap:** enforcement is immediate auto-allow / auto-deny by stored policy. There
  is **no** pending-approval queue or "wait for the operator to decide" path.

### Telemetry — partial today
- `PeerStatus` (`bifrost-signer/src/lib.rs:398-410`): `idx`, `pubkey`, `known`,
  `last_seen`, `online` (derived via `PEER_ONLINE_GRACE_SECS`), nonce counts,
  `can_sign`, `should_send_nonces`. **No latency, no per-method capability beyond
  `can_sign`, no timing history.**
- `CollectedResponse.seen_at` (`:513-518`) and `PendingOperation.started_at` /
  `timeout_at` (`:474-475`) exist → response RTT is *derivable* but not aggregated.
- `PeerNonceInventoryObservation` (`:269`) holds the latest peer nonce inventory +
  `updated_at`, stored in `DeviceState` (`:159`) — a current snapshot, no history.
- Bridge: `runtime_status()` (`bifrost-bridge-wasm/src/lib.rs:541`) serializes
  `RuntimeStatusSummary` (peers, permission states, pending_operations,
  onboarding_statuses). `igloo-shared`/`igloo-ui` project it via
  `runtime-view-models.ts` (`RuntimePeerStatusInput`, `runtimePeerToReadinessRow`)
  — none of latency / avg / sparkline / per-method badges are carried.

## Work items

| # | Item | Effort | Touches |
|---|------|--------|---------|
| a | Per-peer + avg latency | S–M | `bifrost-signer` (`PeerStatus`, `DeviceState` RTT ring buffer, `peer_status`), `runtime-view-models.ts`, `view-models.ts` |
| b | Nonce sparkline series | M | `bifrost-signer` (per-peer `(ts, held_count)` ring buffer off ping responses), bridge, view-models |
| c | Per-method SIGN/ECDH/PING badges | S | `bifrost-signer` (`can_ecdh`/`can_ping` next to `can_sign`, from `effective_policy_for_peer` + `online`), view-models |
| d | Interactive approval queue | M–L | `bifrost-signer` (queue + new `SignerInput::ApproveRequest` + branch `inbound_allowed`), `bifrost-core` (policy value), `bifrost-bridge-wasm` (`approve_request` export), `igloo-shared`, `igloo-ui` |

### (a) Per-peer + avg latency — S/M
Compute RTT = `CollectedResponse.seen_at − PendingOperation.started_at` on
completion (esp. PING). Add `last_response_latency_ms` + `avg_latency_ms`
(rolling window, e.g. a `VecDeque` of recent PING RTTs per peer in `DeviceState`)
to `PeerStatus`; populate in `peer_status()` (`bifrost-signer/src/lib.rs:950`).
Add the fields through `RuntimePeerStatusInput` + `PeerReadinessRowModel`.

### (b) Nonce sparkline — M
Add a per-peer ring buffer of `(timestamp, held_codes.len())` recorded when a
PING response updates `PeerNonceInventoryObservation` (`match_pending_response`,
`~:2159`). Serialize a bounded series; render as the sparkline.

### (c) Per-method capability badges — S
`can_sign` already exists. Add `can_ecdh` / `can_ping` computed like
`readiness_from_peers` (`:1067-1078`): `online && effective_policy.request.<method>`.
Pure field additions + serialization; smallest of the four.

### (d) Interactive approval queue — M/L
Recommended **simple queue**: a `PendingApprovalRequest` map in `DeviceState`
(+ its persisted mirror); branch `inbound_allowed` so an "ask" disposition queues
the request and defers the response instead of auto-allow/deny; add
`SignerInput::ApproveRequest { request_id, approved }` (`:562`); expose
`approve_request(request_id, approved)` from `bifrost-bridge-wasm`; project a
real `pendingApprovalRows` to the UI (the model field
`SignerDashboardViewModel.pendingApprovalRows` already exists, stubbed empty).
Defer the richer "always allow / timed grants / revocable" model.

## Sequencing

(c) → (a) → (b) are additive telemetry and unblock the `dashboard-signer`
promotion; do them as one telemetry pass. (d) is a separate, larger state-machine
change with its own UI wiring — schedule independently. Each requires matching new
fields end-to-end (bifrost-signer → `runtime_status` → `runtime-view-models.ts` →
`OperatorSignerPanel`).

## Verification (when implemented)

- `bifrost-rs`: `cargo test` for the new latency/capability/queue logic; a serde
  test pinning the new `runtime_status` JSON shape.
- Rebuild browser WASM and re-vendor; `igloo-shared`/`igloo-ui` unit tests for the
  new view-model fields; re-run the PWA visual loop and promote `dashboard-signer`
  to `aligned` once Peers parity is met.
