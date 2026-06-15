# Mobile Signer Events-Len Dedupe Contract

Notes pinned by `fix(signer): track signer runtime events_len and dedupe per-tick INFO rows`
(commit `04d9486`, `mobile-create-keyset-flow` events_len feature).

## Why this contract exists

`bifrost-bridge-tokio` does not expose a per-event payload stream the way
`bifrost-bridge-wasm` does. The mobile shell bottom path for "Rust emitted a
new runtime event" is therefore just the `events_len` count the
`FfiApp::get_signer_status()` JSON surfaces. Without deduplication the
actor's `SignerStatusUpdate` handler would either:

1. Append an INFO row on every single poll (~1s cadence × every visible
   runtime transition = many duplicates), or
2. Stay silent on transitions because `events_len` stays at the hardcoded
   `0` the polling task used to use.

## Actor contract

`SignerRuntimeState.runtime_observed_events_len: u64` tracks the highest
`events_len` value the actor has ingested from a `SignerStatusUpdate`.
Stored alongside the existing `events: Vec<LogEntry>` field.

`AppAction::SignerStatusUpdate { events_len, .. }` (in `updates.rs`):

- Compare incoming `events_len` against the previous tracked value.
- If new > tracked: prepend a single safe INFO log entry via
  `display_timestamp_rfc3339()` and update the tracked value to new.
  Message format: `Runtime event count advanced to <N> (bridge-supplied)`.
- If new <= tracked: update the tracked value to new (recovery safe — the
  bridge counter may reset on restart) without appending anything.

Insertion uses `events.insert(0, …)` so existing Rust-emitted rows stay
above/after the new row in newest-first order.

## Polling-task contract

`SignerStatusCache.events_len: u64` (in `lib.rs`) is the polling-task side
of the same contract. Before this commit it was hardcoded to `0` on every
poll. The task now:

- Computes a fingerprint of `(readiness_str, relay_connected, peer-online
  map, pending_ops count)` after each bridge observation.
- If the fingerprint differs from the previous poll, advances
  `cache.events_len` by one and stores the new fingerprint in
  `cache.last_obs_fingerprint`.
- Resets `last_obs_fingerprint` to `None` on `stop_signer` (via
  `*cache = SignerStatusCache::default()`) so a fresh `start_signer`
  always counts as at least one event, even if the initial bridge state
  matches the last-observed one.

## Tests pinning the behavior

`apps/igloo-mobile/rust/tests/signer_runtime_recovery.rs` adds five
state-machine tests that exercise the public
`igloo_mobile_core::update` entry point:

1. `signer_status_update_appends_info_row_on_events_len_increase` —
   first poll with `events_len = 5` appends exactly one INFO row whose
   message references the new count.
2. `signer_status_update_does_not_duplicate_on_unchanged_events_len` —
   two consecutive polls with the same `events_len` produce exactly one
   row, never two.
3. `signer_status_update_uses_rfc3339_timestamp_in_info_row` — the row's
   `timestamp` field matches the `YYYY-MM-DDTHH:MM:SSZ` shape from
   `display_timestamp_rfc3339()`.
4. `signer_status_update_preserves_existing_events_after_info_append` —
   pre-existing Rust-emitted rows (e.g. "Signer runtime started") stay
   intact and sit at index ≥ 1 after the new row prepends at index 0.
5. `signer_status_update_recovers_when_events_len_drops_then_advances_again` —
   a lower count (post-bridge-restart baseline) does not append, and the
   next advancement past the recovered baseline appends exactly one row
   referencing the new count.

## UniFFI binding regeneration

Adding `runtime_observed_events_len: u64` to `SignerRuntimeState` changed
the binary layout of app-state snapshots. The Android binding in
`apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/rust/igloo_mobile_core.kt`
must be regenerated via `just gen-kotlin` (or the equivalent
`cargo run -p uniffi-bindgen -- generate ...`) so the Kotlin
`data class SignerRuntimeState` carries the new `runtimeObservedEventsLen:
ULong` field and its `FfiConverterULong` read/write helpers are wired
in. The iOS Swift binding is gitignored and regenerated locally by
`just ios-gen-swift` before every iOS build.
