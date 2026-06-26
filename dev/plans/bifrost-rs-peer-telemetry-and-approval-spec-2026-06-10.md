# Spec: bifrost-rs peer telemetry + interactive signing approval

Scoping/spec doc for the peer telemetry and approval track. Drives the
`bifrost-rs` / dashboard backlog items in [`../BACKLOG.md`](../BACKLOG.md). Line
references from the original 2026-06-10 read are pointers, not contracts —
re-confirm before implementing new slices.

## Why

The signer dashboard (`igloo-ui` `OperatorSignerPanel`) and Paper's
`1-signer-dashboard` artboard draw peer telemetry plus a Pending-Approvals card.
Per-method SIGN/ECDH/PING/ONBOARD capability badges, latest response latency,
and bounded nonce inventory history landed on 2026-06-22. This doc now tracks
the larger interactive approval queue. Peer telemetry visual parity is complete
for the current dashboard scope.

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

### Telemetry — complete for current dashboard scope

2026-06-22 update: `PeerStatus` now carries live request-side method
capabilities (`can_sign`, `can_ecdh`, `can_ping`, `can_onboard`) and the
`igloo-shared` / `igloo-ui` / `igloo-pwa` projection path renders those as
method badges when no richer peer policy state is present.

2026-06-22 follow-up: `PeerStatus.latency_ms` now carries the latest accepted
peer response latency. The dashboard row latency and "Avg" pill are computed
from this live runtime field.

2026-06-22 follow-up: `PeerStatus.nonce_inventory_history` now carries a bounded
series of peer-held nonce inventory samples recorded from normalized ping
inventory observations. `igloo-shared`, `igloo-ui`, and `igloo-pwa` project that
series to the shared peer row, where it renders as mini history bars in the nonce
meter.

- `PeerStatus` (`bifrost-signer/src/lib.rs:398-410`): `idx`, `pubkey`, `known`,
  `last_seen`, `online` (derived via `PEER_ONLINE_GRACE_SECS`), nonce counts,
  latest response `latency_ms`, bounded `nonce_inventory_history`, method
  capability booleans, `should_send_nonces`. **No rolling timing history.**
- `CollectedResponse.seen_at` (`:513-518`) and `PendingOperation.started_at` /
  `timeout_at` (`:474-475`) exist → response RTT is *derivable* but not aggregated.
- `PeerNonceInventoryObservation` (`:269`) holds the latest peer nonce inventory +
  `updated_at`, stored in `DeviceState` (`:159`). A runtime-only bounded history
  now records the normalized held-count samples used by the dashboard sparkline.
- Bridge: `runtime_status()` (`bifrost-bridge-wasm/src/lib.rs:541`) serializes
  `RuntimeStatusSummary` (peers, permission states, pending_operations,
  onboarding_statuses). `igloo-shared`/`igloo-ui` project it via
  `runtime-view-models.ts` (`RuntimePeerStatusInput`, `runtimePeerToReadinessRow`)
  — method capability badges, latest latency, and nonce inventory history are
  carried.

## Work items

| # | Item | Effort | Touches |
|---|------|--------|---------|
| a | Latest per-peer + UI avg latency | Done 2026-06-22 | `bifrost-signer` (`PeerStatus.latency_ms`, runtime-only pending start ms map), `RuntimePeerStatus`, PWA projection |
| b | Nonce sparkline series | Done 2026-06-22 | `bifrost-signer` (per-peer `(ts, held_count)` ring buffer off ping responses), bridge, view-models |
| c | Per-method SIGN/ECDH/PING badges | Done 2026-06-22 | `bifrost-signer` (`can_ecdh`/`can_ping`/`can_onboard` next to `can_sign`, from `effective_policy_for_peer` + `online`), view-models, PWA projection |
| d | Interactive approval queue | M–L | `bifrost-signer` (queue + new `SignerInput::ApproveRequest` + branch `inbound_allowed`), `bifrost-core` (policy value), `bifrost-bridge-wasm` (`approve_request` export), `igloo-shared`, `igloo-ui` |

### (a) Per-peer + avg latency — S/M
Landed 2026-06-22 as latest response latency. Runtime-created pending operations
store a millisecond start timestamp in memory; restored/manual pending operations
fall back to the existing second-resolution `PendingOperation.started_at`. On a
valid accepted response, `PeerStatus.latency_ms` records the latest latency for
that peer and flows through `RuntimePeerStatus` to the shared/PWA dashboard. The
visible "Avg" chip is derived in `OperatorSignerPanel` from peer rows that carry
latency. Rolling latency history remains out of scope for this landed slice.

### (b) Nonce sparkline — Done 2026-06-22
Landed 2026-06-22. `bifrost-signer` records a bounded runtime-only
`nonce_inventory_history` series from normalized peer-held nonce observations
when ping responses update `PeerNonceInventoryObservation`. `igloo-shared`,
`igloo-ui`, and `igloo-pwa` carry the series as dashboard peer-row view-model
data, and `OperatorSignerPanel` renders it as mini history bars inside the nonce
meter.

### (c) Per-method capability badges — S
Landed 2026-06-22. `can_sign` is now policy-gated, and `can_ecdh` / `can_ping`
/ `can_onboard` are computed from `online && effective_policy.request.<method>`.
The fields flow through `RuntimePeerStatus`, `runtimeStatusToSignerDashboardView`,
and the PWA dashboard peer projection.

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

(a), (b), and (c) have landed and the `dashboard-signer` visual manifest entry
is promoted to `aligned`. Rolling latency history remains intentionally out of
scope unless product asks for more than latest response latency. (d) is a
separate, larger state-machine change with its own UI wiring — schedule
independently.

## Verification (when implemented)

- `bifrost-rs`: `cargo test` for the new latency/capability/queue logic; a serde
  test pinning the new `runtime_status` JSON shape.
- Rebuild browser WASM and re-vendor; `igloo-shared`/`igloo-ui` unit tests for the
  new view-model fields; re-run the PWA visual loop when changing peer telemetry
  visuals.
