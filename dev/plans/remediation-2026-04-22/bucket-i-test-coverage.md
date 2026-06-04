# Bucket I — Residual Test Coverage (Hard-Cut Plan)

Status: draft, pending user approval
Related: covers the test-coverage gaps **not** already absorbed into
Buckets A–H. Ships in a third coordinated release (R3) along with
Bucket J.

## Context

The 2026-04-22 audit synthesis identified test coverage as one of the
largest cross-cutting gaps: 5 of 11 `bifrost-rs` crates had no `tests/`
directories, no property tests, no FROST KATs; `browser-runtime-core.ts`
had zero unit tests; `igloo-shell` had 32 integration tests all
happy-path; every host test suite ran only happy-path scenarios.

Buckets A–H absorbed a substantial fraction of this debt:
- Bucket A (PR3) added NIP-44 KAT fixtures for the three cipher stacks.
- Bucket B (PR5) added four pinned portable-package KATs at the
  bech32m-string layer.
- Bucket B (PR7) added ten adversarial host-local encryption tests.
- Bucket C (PR8–PR12) added adversarial CLI coverage (wrong passphrase,
  corrupted ciphertext, partial-write, stale daemon.json).
- Bucket D (PR13–PR15) added Secret<T> redaction fuzz tests, request_id
  correlation tests, onboarding rate-limit tests, base64 validation
  tests.
- Bucket E (PR20) added WASM integrity tamper tests. (PR23) added
  HomeError round-trip tests.
- Bucket H (PR38) added jest-axe + full primitive unit test suite for
  `igloo-ui`.

**What Bucket I covers:** the residual crypto-layer + integration-layer
gaps that don't naturally fit any feature bucket.

## Scope

**In:**
- I.1 — FROST-secp256k1-tr signing KAT vectors in `bifrost-core`.
  Independent-implementation cross-check of the threshold-sign
  aggregation against the upstream RFC draft / reference test vectors.
- I.2 — Wire fuzz harness in `bifrost-codec` using `arbitrary`. Every
  `TryFrom<*Wire>` impl gets fuzzed in CI with a small budget; panics
  are treated as failures.
- I.3 — `bifrost-router` integration tests: queue overflow under
  bounded memory, dedupe on replay, phase state-machine transitions
  under adversarial input ordering.
- I.4 — `NoncePool` property tests: single-use invariant, FIFO order,
  `remap_peer_indexes` collision rejection, serialization round-trip.
- I.5 — Post-Bucket-G TS runtime tests: `wasm-bridge-node.test.ts`,
  `runtime-pump.test.ts`, `onboarding-transport.test.ts`. Covers the
  unit-test gap that existed in `browser-runtime-core.ts` before the
  split.
- I.6 — Cross-repo E2E gap analysis: identify flows that cross two or
  more repo boundaries and have zero coverage; add the minimum
  Playwright fixture set to close the top gaps.

**Out of scope for Bucket I:**
- Happy-path smoke coverage — already exercised by the demo harness.
- Load / performance testing — out of hardening scope.
- Mutation testing / coverage-percentage targets — quality ratchets
  belong in a later process bucket, not a remediation bucket.

## Execution Order

Five PRs. Numbering continues from Bucket H (PR34–PR38).

| PR | Items | Submodule |
|---|---|---|
| PR39 | I.1 (FROST KATs) + I.4 (NoncePool property tests) | `bifrost-rs/crates/bifrost-core` |
| PR40 | I.2 (wire fuzz harness) | `bifrost-rs/crates/bifrost-codec` |
| PR41 | I.3 (bifrost-router integration tests) | `bifrost-rs/crates/bifrost-router` |
| PR42 | I.5 (post-G TS runtime tests) | `igloo-shared` |
| PR43 | I.6 (cross-repo E2E gap coverage) | `frostr-infra/test/` |

All five PRs are independent. Can run in parallel. Total touch: ~1,500
lines of test code.

Ships in the third coordinated release (R3) alongside Bucket J. No
runtime behavior change; no version bumps.

---

## I.1 — FROST signing KATs

### Problem

`bifrost-core::sign` has happy-path roundtrip tests and one
tampered-share rejection test. No pinned test vectors against an
independent FROST implementation.

### Target

New file `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-core/tests/frost_kat.rs`:

For each of 3–5 test scenarios (2-of-3, 3-of-5, variable sighash):
- Fixed group keyset (pinned seed).
- Fixed signing-nonce seed.
- Fixed message.
- Expected aggregated signature as a hex constant.

Source the expected signatures from the upstream
`frost-secp256k1-tr-unofficial` crate's own test vectors where
available, or generate via the reference impl and commit as pinned
fixtures.

Also: one property test asserting that `sign` + `aggregate` produces
signatures that `verify` accepts for arbitrary (but bounded) threshold
configurations. Use `proptest`.

### Acceptance

- `cargo test -p bifrost-core --test frost_kat --offline` passes.
- 3+ pinned vectors covering different threshold shapes.
- Proptest exercises 100+ threshold configurations per CI run.
- Bucket D's redaction assertion: no test accidentally logs a seckey
  value.

---

## I.2 — `bifrost-codec` wire fuzz harness

### Problem

Bucket A PR4 bounded `bifrost-codec` envelope size and added
boundary-case tests. No fuzz coverage on the per-message `TryFrom<*Wire>`
decoders.

### Target

New dev-dependency on `arbitrary` + `proptest`. For each
`TryFrom<*Wire>` impl in `crates/bifrost-codec/src/wire.rs`:

```rust
proptest! {
    #[test]
    fn try_from_sign_package_wire_never_panics(
        wire in arb_sign_package_wire(),
    ) {
        let _ = SignPackage::try_from(wire);
        // Either Ok or Err — never a panic.
    }
}
```

Plus a structure-aware fuzz for the outer envelope via
`arbitrary::Arbitrary`:

```rust
fuzz_target!(|data: &[u8]| {
    let _ = decode_bridge_envelope(std::str::from_utf8(data).unwrap_or(""));
});
```

Integrate with `cargo-fuzz` OR run a time-bounded proptest pass in
CI (easier than standing up full libFuzzer infra for alpha). A panic
or unbounded allocation fails the build.

### Acceptance

- `cargo test -p bifrost-codec --offline` exercises 1,000+ fuzz
  iterations per decoder in the default test run.
- Zero panics under fuzz.
- Allocation under fuzz stays bounded (verified by setting
  `MAX_BRIDGE_ENVELOPE_BYTES` from Bucket A PR4 and asserting decoders
  reject anything larger before allocation).

---

## I.3 — `bifrost-router` integration tests

### Problem

`bifrost-router` has no `tests/` directory. The queue, dedupe, and
phase state machine are exercised only via the full host-level
integration tests in `bifrost-app`.

### Target

New integration tests under `bifrost-rs/crates/bifrost-router/tests/`:

- `queue_overflow.rs` — push commands past the configured queue size;
  assert the router returns a typed `RouterError::QueueFull`, no
  panic, no memory growth beyond the cap.
- `dedupe.rs` — push the same `request_id` twice; assert the router
  dedupes on the second (returns the prior result or
  `RouterError::DuplicateRequest`, whichever is the design).
- `phase_machine.rs` — walk the router through every valid phase
  transition: `Created → AwaitingResponses → Completed` and the three
  failure terminals (`Failed`, `Expired`, `Aborted`). Assert invalid
  transitions error cleanly.
- `adversarial_ordering.rs` — drive inbound responses out of order
  relative to outbound requests; assert the router correlates
  correctly (uses the post-Bucket-D request_id keying).

### Acceptance

- `cargo test -p bifrost-router --offline` passes with the new suite.
- All four phase-transition scenarios covered.
- Queue bound is strict: pushing N+1 commands into a size-N queue
  rejects rather than silently dropping.

---

## I.4 — `NoncePool` property tests

### Problem

Bucket A PR2 moved `NoncePool.seckey` out to `DeviceSecrets`. Core
nonce-pool invariants (single-use, FIFO) are asserted only in
host-level integration tests.

### Target

New proptest file `bifrost-rs/crates/bifrost-core/tests/nonce_pool_props.rs`:

```rust
proptest! {
    #[test]
    fn generated_nonces_are_single_use(
        seckey in arb_bytes32(),
        requests in prop::collection::vec(arb_gen_for_peer_request(), 1..50),
    ) {
        let mut pool = NoncePool::new_empty(0);
        let secret = NoncePoolSecret::new(seckey);
        let mut all_outgoing = HashSet::new();
        for (peer_idx, count) in requests {
            let nonces = pool.generate_for_peer(peer_idx, count, &secret);
            for n in nonces {
                assert!(all_outgoing.insert(n.commitment()), "nonce reused");
            }
        }
    }

    #[test]
    fn remap_peer_indexes_rejects_collision(
        input in arb_nonce_pool_with_remap(/* forces collision */)
    ) {
        let result = input.pool.remap_peer_indexes(&input.colliding_map);
        prop_assert!(result.is_err());
    }

    #[test]
    fn serialize_roundtrip_preserves_state(
        pool in arb_nonce_pool(),
    ) {
        let bytes = bincode::serialize(&pool).unwrap();
        let decoded: NoncePool = bincode::deserialize(&bytes).unwrap();
        prop_assert_eq!(pool, decoded);
    }
}
```

### Acceptance

- `cargo test -p bifrost-core --test nonce_pool_props --offline` passes
  with 256+ random cases per property.
- Single-use invariant holds across 50-request sequences.
- Collision rejection test from Bucket A's audit finding 14 passes.

---

## I.5 — Post-Bucket-G TS runtime tests

### Problem

Bucket G PR30 split `browser-runtime-core.ts` (2,189 lines, zero unit
tests) into five focused modules. Each new module needs a test file.
Bucket D PR14 added request_id correlation tests that now live in
`runtime-pump.test.ts`; Bucket D PR15 added onboarding defenses that
live in `onboarding-transport.test.ts`. Bucket I fills the rest.

### Target

New test files in `igloo-shared/src/`:

**`wasm-bridge-node.test.ts`** — class-level integration:
- WASM bridge init → ready state.
- Command lifecycle: issue `sign`, observe pending map population,
  receive completion, observe resolution.
- Graceful shutdown: `stop()` cancels pending ops with typed errors.
- Observability: every emitted event matches the Bucket D allow-list
  schema (uses the redaction fuzz test from D PR13).

**`relay-transport.test.ts`** — pool lifecycle:
- Probe with timeout (loopback reachable vs. unreachable).
- Subscribe + close cleans up WebSocket.
- Reconnect behavior on drop.

**`runtime-api.test.ts`** — public function surface:
- `createSignerNode` → typed `BrowserBridgeNode` (post-G.3).
- `getRuntimeStatus` vs. `getRuntimeSnapshot` distinction (ensure
  hot-path callers use `getRuntimeStatus` per Bucket D PR16).

Test harness: mock `WasmBridgeRuntimeApi` via a hand-rolled stub so
tests don't require a real WASM build. `SimplePool` is mocked via a
lightweight fake that mimics the subscribe/publish API.

### Acceptance

- `npm --prefix repos/igloo-shared test` runs all five new test files
  plus the existing tests.
- Coverage report shows every `.ts` source file under `src/` has at
  least one test file importing it.
- Redaction fuzz from Bucket D PR13 still passes on the new code paths.

---

## I.6 — Cross-repo E2E gap coverage

### Problem

The parent-workspace `test/` directory already covers the major demo
flows (onboard → sign → ecdh on PWA + Chrome + Home). Gaps identified
in the audit:

- Rotation end-to-end: PWA + Chrome + Home rotating a share with Bucket
  B's new package envelope v2.
- Recovery end-to-end: PWA + Chrome + Home recovering from `bfshare`
  with the new masked-by-default UI (Bucket H).
- Typed-error surface: exercise every `HomeError` variant (Bucket E
  PR23) through a Playwright scenario.
- WASM integrity: tamper test (Bucket E PR20) runs as a Playwright
  spec, not just a unit test.

### Target

New Playwright specs under
`/home/cscott/Repos/frostr/frostr-infra/test/`:

- `test/igloo-pwa/specs/rotation.spec.ts` — full share rotation flow.
- `test/igloo-chrome/specs/rotation.spec.ts` — same on the extension.
- `test/igloo-home/specs/rotation.spec.ts` — same on the desktop.
- `test/igloo-pwa/specs/recovery.spec.ts` — bfshare recovery with
  masked-by-default rendering.
- `test/igloo-chrome/specs/home-error-surface.spec.ts` — drive each
  `HomeError` variant (handled by the Tauri host) from the Chrome side
  via the shared demo harness.
- `test/igloo-pwa/specs/wasm-integrity.spec.ts` — tamper a byte in the
  bundled `.wasm`; load PWA; assert `wasm_integrity_check_failed`
  surfaces.

### Acceptance

- `make test-e2e` runs the expanded suite and passes.
- Each new spec adds ≤10 minutes to the release-validation lane.
- `test-release` completes within the existing 90-minute timeout.

---

## Critical Files

Add (all NEW):
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-core/tests/frost_kat.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-core/tests/nonce_pool_props.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-codec/tests/wire_fuzz.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-router/tests/queue_overflow.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-router/tests/dedupe.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-router/tests/phase_machine.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-router/tests/adversarial_ordering.rs`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm-bridge-node.test.ts`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/relay-transport.test.ts`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/runtime-api.test.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-pwa/specs/rotation.spec.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-pwa/specs/recovery.spec.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-pwa/specs/wasm-integrity.spec.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-chrome/specs/rotation.spec.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-chrome/specs/home-error-surface.spec.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-home/specs/rotation.spec.ts`

Modify:
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/Cargo.toml` (add `arbitrary`, `proptest` to workspace dev-deps)
- Each affected crate's `Cargo.toml` to pull dev-deps where consumed.

Reuse:
- Bucket A's secret newtypes in `bifrost-core::secret` — tests use them
  directly.
- Bucket D's redaction fuzz corpus — extended to cover the post-G
  module split.
- Bucket H's jest-axe setup — tests extend coverage, don't re-setup.

## Verification

Per PR: `cargo test -p <crate> --offline` (Rust) or `npm --prefix <repo> test` (TS); all new test files run and pass.

Full-bucket verification:
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```
`test-release` timing summary stays within budget (absolute cap: +15
minutes relative to pre-Bucket-I baseline; flag for investigation if
exceeded).

## Cross-Repo Coordination

Ships in release R3 alongside Bucket J. Zero runtime changes, zero
version bumps. Purely additive test code. No operator impact.

Dependencies:
- PR39/PR40/PR41 depend on Bucket A (secret newtypes, `subtle`,
  envelope bounds).
- PR42 depends on Bucket G (post-split module layout) and Bucket D
  (request_id dispatch, allow-list redactor).
- PR43 depends on Buckets B (v2 envelopes for rotation/recovery), E
  (typed errors for HomeError surface, WASM integrity for tamper
  test), H (masked-by-default UI).

## Summary

Five PRs, ~1,500 lines, split across `bifrost-rs` (3 PRs),
`igloo-shared` (1 PR), parent `test/` (1 PR). Closes the residual test
coverage gap after A–H.

- **FROST KATs** pin threshold-sign + aggregation against
  independent-implementation vectors.
- **Wire fuzz** exercises every `TryFrom<*Wire>` decoder with 1,000+
  random inputs per CI run; zero panics allowed.
- **`bifrost-router` integration** covers queue overflow, dedupe,
  phase state machine, and adversarial ordering.
- **`NoncePool` property tests** lock single-use, FIFO, collision
  rejection, serialize round-trip.
- **Post-G TS runtime tests** close the unit-test gap on the five
  modules that replaced `browser-runtime-core.ts`.
- **Cross-repo E2E gap coverage** adds rotation, recovery, typed-error
  surface, and WASM integrity as Playwright scenarios.

Ships in R3 with Bucket J.
