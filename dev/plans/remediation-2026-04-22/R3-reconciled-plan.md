# R3 — Reconciled Execution Plan (Buckets I + J)

Status: **approved 2026-06-01**, reconciled against current code reality
(verified by three read-only Explore passes on `security-hardening`).
Supersedes the scope assumptions in `bucket-i-test-coverage.md` and
`bucket-j-docs-chrome.md` where they conflict with the findings below.

R3 is the final coordinated release before the L2 cutover
(`security-hardening` → `master`). It is **purely additive** (tests + docs +
one re-audit report + small carried fixes): no runtime behavior change, no
version bumps, no operator migration. Conventions unchanged from R1/R2:
one agent per repo at a time, hard-cut, feature branch off
`security-hardening` → user reviews diff → ff-only submodule merge /
`--no-ff` parent, **local merges only** (subagents never push, never merge),
no `Co-Authored-By`. `master` everywhere stays pristine until the operator
explicitly approves the cutover after R3 closes.

**Posture (user decision 2026-06-01): "close the real gaps only."** Execute
exactly the verified-real gaps; do not re-derive work that already landed in
R1/R2. **I.3 (user decision): thin direct router tests + a gap note**, not the
full draft suite.

---

## Reality corrections that reshaped the drafts (verified)

1. **I.6 e2e is ~90% already covered.** Rotation (pwa `rotation-create` +
   `rotation-update`, chrome `rotation-update`, home `rotation-live` +
   `rotation-update-live`), recovery (pwa + chrome `profile-recovery`), and
   wasm-integrity (pwa `wasm-integrity.spec.ts`, Bucket E PR20) all exist.
   **Only `home-error-surface` is genuinely missing.**
2. **Chrome monoliths are already split.** `background.ts` is **84 lines**
   (logic in `background/{onboarding,permission,runtime}-service.ts`,
   `state-projector.ts`, `router-profiles.ts`); `extension-runtime-host.ts`
   is **62 lines** (facade over `lib/runtime-host/controller.ts`, ~500 lines).
   The `messageText` undefined bug is **fixed** (`onboarding-service.ts:149`).
   Secrets are **not** in `storage.local` (encrypted blobs + session-only
   unlock keys). J.4 therefore collapses to near-zero; J.3 mostly documents
   transitive closure.
3. **Docs lag the code MORE than the drafts assumed.** Bucket B migrated the
   *code* (Argon2id + XChaCha20Poly1305, `ENCRYPTED_PROFILE_VERSION` 1→2,
   `BF_PACKAGE_VERSION` 1→2) but did **not** write the docs. So J.1 is bigger:
   `BACKUP.md` still says PBKDF2 + AES-GCM; `WIRE.md` lacks
   `MAX_BRIDGE_ENVELOPE_BYTES`/field caps; `CRYPTOGRAPHY.md` lacks the v2
   sections; `GLOSSARY.md` lacks `Secret<T>`/`SecretBytes`/`Passphrase`/
   `DaemonToken`/`Argon2Params`.
4. **Rust test-API names in the drafts are wrong** — corrected inline below.
5. **The router is already integration-tested** via `bifrost-bridge-tokio/
   tests/` (`bridge_dedupe_and_failures.rs`, `bridge_queues.rs`,
   `bridge_admin_and_phases.rs`, `bridge_flow.rs`, `bridge_recovery.rs`).
   `bifrost-router` itself has no own `tests/` → thin direct tests + gap note.

---

## Bucket I — residual test coverage (verified-real gaps)

### PR-I1 — bifrost-rs: FROST KATs + NoncePool property tests
Repo `repos/bifrost-rs`, crate `bifrost-core` (has **no** `tests/` dir today).
Add `proptest` as a workspace dev-dep.

- `crates/bifrost-core/tests/frost_kat.rs` — 3+ pinned threshold-sign +
  aggregation vectors (2-of-3, 3-of-5, variable sighash) verified against
  `frost-secp256k1-tr-unofficial` (already a dep, imported as `frost` in
  `nonce.rs:3`); signing in `sign.rs`, nonce gen in `nonce.rs`. Plus one
  `proptest` that `sign`+`aggregate` → `verify` accepts for bounded threshold
  configs. Bucket D redaction guard: assert no test logs a seckey.
- `crates/bifrost-core/tests/nonce_pool_props.rs` — **corrected API**:
  - construct `NoncePool::new(our_idx: u16, config: NoncePoolConfig)`
    (`nonce.rs:53`), **not** `new_empty(0)`.
  - `generate_for_peer(&mut self, peer_idx: u16, count: usize,
    seckey: &NoncePoolSecret) -> CoreResult<Vec<DerivedPublicNonce>>`
    (`nonce.rs:131`). `NoncePoolSecret::new([u8;32])` (`secret.rs:76`).
  - single-use invariant: track emitted public nonces in a `HashSet`; note
    `DerivedPublicNonce` has **no `.commitment()`** — it's a struct with
    `binder_pn`/`hidden_pn`/`code` fields (`types.rs:195`); key the set on
    those bytes.
  - `remap_peer_indexes(&mut self, new_our_idx: u16,
    index_map: &HashMap<u16,u16>)` (`nonce.rs:76`) — **two args**; collision
    case asserts `is_err()`.
  - serialize round-trip (bincode) preserves state.

### PR-I2 — bifrost-rs: bifrost-codec wire-decoder fuzz
Repo `repos/bifrost-rs`, crate `bifrost-codec` (has `tests/envelope_bounds.rs`).
- `crates/bifrost-codec/tests/wire_fuzz.rs` — a `proptest` per `TryFrom<*Wire>`
  decoder (17 of them, `wire.rs:187`–`782`: Member/Group/Share package,
  nonce/commitment sets, sign-session, partial-sig, ecdh, ping, policy,
  onboard request/response). Each: arbitrary wire input → `try_from` is
  `Ok`/`Err`, never panics. Outer-envelope structure fuzz via
  `decode_bridge_envelope` asserting anything over
  `MAX_BRIDGE_ENVELOPE_BYTES = 65_536` (`bridge.rs:17`) is rejected before
  allocation. Time-bounded `proptest` (not full libFuzzer) per the draft.

### PR-I3 — bifrost-rs: thin bifrost-router direct tests + gap note
Repo `repos/bifrost-rs`, crate `bifrost-router` (no own `tests/`).
- `crates/bifrost-router/tests/router_core.rs` — direct unit/integration tests
  for cases not already exercised by `bifrost-bridge-tokio`: `BridgeCoreError`
  (**not** `RouterError`) `QueueFull` on overflow (`lib.rs:40`); `RequestPhase`
  transitions Created → AwaitingResponses → Completed / Failed / Expired
  (**no `Aborted`**, `lib.rs:21`); inbound-id dedupe via the internal
  `seen_inbound_ids` set. Header comment documenting that
  `bifrost-bridge-tokio/tests/` is the existing integration layer and what
  this file adds beyond it (the gap note).

### PR-I4 — igloo-shared: post-G runtime-module tests
Repo `repos/igloo-shared`. The five split modules exist but have **zero**
tests: `wasm-bridge-node.ts` (**1521 lines**), `runtime-api.ts` (323),
`runtime-pump.ts` (190), `onboarding-transport.ts` (212),
`relay-transport.ts` (33-line stub). vitest runner; **no WASM mock harness
exists yet** — build a hand-rolled `WasmBridgeRuntimeApi` stub + `SimplePool`
fake so tests need no real WASM build.
- `wasm-bridge-node.test.ts` — init→ready, command lifecycle (issue `sign` →
  pending map populated → completion resolves), `stop()` cancels pending with
  typed errors, emitted events match the Bucket D `EVENT_SCHEMAS` allow-list.
- `runtime-pump.test.ts` — `request_id`-keyed pending map, stale-completion
  tombstone (note: existing `bridge-dispatch.test.ts` /
  `onboarding-defenses.test.ts` already cover parts — extend, don't duplicate).
- `onboarding-transport.test.ts` — rate-limit / base64 / bundle defenses not
  already in `onboarding-defenses.test.ts`.
- `runtime-api.test.ts` — `createSignerNode` → typed `BrowserBridgeNode`
  (`runtime-api.ts:164`); `getRuntimeStatus` (`:321`) vs `getRuntimeSnapshot`
  (`:317`) hot-path distinction.
- `relay-transport.test.ts` — light (33-line stub); probe/subscribe/close if
  meaningful, else fold a note.

### PR-I5 — parent test/: home-error-surface e2e (the one real e2e gap)
Repo `frostr-infra/test`. Add `test/igloo-home/specs/home-error-surface.spec.ts`
(or chrome-side per the draft) driving each `HomeError` variant (Bucket E
PR23) through the shared demo harness (`fixtures/helpers/demo-harness.ts`,
`ensureDemoHarness()`). Document in `test/README.md` that rotation / recovery /
wasm-integrity are already covered (no new specs) so the coverage decision is
explicit, not silent.

---

## Bucket J — docs + chrome re-audit (verified-real gaps)

### PR-J1 — parent docs catch-up + CI constant assertions
Repo `frostr-infra`. Docs must catch up to the R1 code migration:
- `docs/BACKUP.md` — retire PBKDF2 + AES-GCM language; document Argon2id +
  XChaCha20Poly1305, raw 16-byte salt, length-prefixed AAD; cross-link
  `CRYPTOGRAPHY.md`.
- `docs/CRYPTOGRAPHY.md` — add "Host-Local Encryption v2" and "Portable
  Package Encryption v2" sections (the code shipped them; the doc never did).
- `docs/WIRE.md` — add `MAX_BRIDGE_ENVELOPE_BYTES = 65_536` + per-field caps
  (sourced from `bifrost-codec/src/`); `request_id` already documented.
- `docs/GLOSSARY.md` — add `Secret<T>`, `SecretBytes`, `Passphrase`,
  `DaemonToken`, `Argon2Params`, plus `wire/` module organization.
- `docs/PROFILE.md` — Host-Local Security Model section, cross-link.
- `docs/INDEX.md` — ratify reading order against post-remediation state.
- `test/scripts/check-doc-surfaces.sh` — **extend** with doc-vs-code constant
  assertions: `MAX_BRIDGE_ENVELOPE_BYTES` matches `bifrost-codec`; Argon2
  params match `Argon2Params::default()`; bech32m HRPs match
  `frostr-utils/src/profile_packages.rs`. CI fails on drift.

### PR-J2 — igloo-shared public-API docs
Repo `repos/igloo-shared`. JSDoc every exported symbol in `index.ts`
(runtime-api functions: params, returns, thrown typed errors, required caller
order, cross-repo contract; `wire/` types: canonical shape, owning bifrost-rs
crate, secret-field flags for the allow-list redactor). New "Runtime
Integration" section in `README.md` (lifecycle + onboarding/import/recovery/
rotation/signing samples). Cross-link from `docs/INTERFACES.md`.

### PR-J3 — igloo-chrome re-audit report
Repo `frostr-infra/dev/reports`. New `igloo-chrome-audit-2026-06-DD.md` (same
format as `igloo-chrome-audit-2026-04-02.md`). Verify each 2026-04-02 finding
against current reality: the three High findings appear **transitively closed**
(monoliths split, `messageText` fixed, secrets not in `storage.local`) —
document closure with new file:line evidence; audit `lib/runtime-host/
controller.ts` (the ~500-line extraction) for residual monolith smell; flag
any net-new issues from the refactor. Drives PR-J4 scope.

### PR-J4 — igloo-chrome cleanup (contingent on J3)
Repo `repos/igloo-chrome`. Expected minimal. Folds in the two carried items:
- **`observability.test.ts`** ("redacts sensitive fields"): the chrome
  `observability.ts` is `export * from 'igloo-shared'`; the test expects
  `[redacted:password:len=15]`. **Run it first** to confirm stale-assertion
  (igloo-shared now *drops* the field → `undefined`) vs. real redaction bug,
  then fix the side that's wrong (per the R2 note, the field is dropped not
  leaked → no security hole → update the stale expectation).
- **Deep-import hygiene**: 3 test deep-imports of `igloo-shared/src/*`
  (`browser-runtime-core.test.ts:32,222` — file now mis-named post-G.2 split;
  `router-profiles.test.ts:19`). Repoint to the package entry / rename the
  stale test file.

### PR-J5 — igloo-home carried fix
Repo `repos/igloo-home`. `test/frontend/api.test.ts` failures (2,
error-message-normalization per the R2 note). **Run + diagnose** the actual
assertion-vs-behavior delta post-R2, then fix.

---

## Execution sequence (per-repo, one agent per repo at a time)

Independent repos run concurrently; within a repo, PRs are serial. Each
branch: user reviews diff → ff-only submodule merge.

1. **bifrost-rs** — PR-I1 → PR-I2 → PR-I3 (one agent, serial; pure additive).
2. **igloo-shared** — PR-I4 then PR-J2 (one agent, serial).
3. **igloo-chrome** — PR-J3 (re-audit) → PR-J4 (cleanup + carried fixes).
4. **igloo-home** — PR-J5 (small, standalone).
5. **parent** — PR-I5 + PR-J1 (on `frostr-infra` `security-hardening`).

Pre-flight before fixes: run the two carried failing tests to capture the
real delta (informs PR-J4 + PR-J5).

## R3-closed definition
- All verified-real gaps landed on each repo's `security-hardening`; carried
  failures green; deep-imports cleaned.
- `make test-guards` (real `rg` on PATH), `make test-smoke`, pwa/chrome e2e,
  bifrost-rs `cargo test`, igloo-shared vitest — all green.
- Parent submodule-pointer bump committed on `security-hardening`
  (local-only); `master` still pristine; HANDOFF updated to R3-complete.
- Then surface the L2 cutover decision to the operator (not before).
