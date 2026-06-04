# Bucket A — `bifrost-rs` Crypto-Primitive Hardening (Hard-Cut Plan)

Status: approved
Related: precedes every other bucket; ships in R1.

## Context

The 2026-04-22 workspace audit
(`/home/cscott/Repos/frostr/frostr-infra/dev/audit/workspace-audit-synthesis-2026-04-22.md`)
identified the `bifrost-rs` crypto primitives as the highest-leverage place to
start remediation. The findings: one of three NIP-44 decrypt paths uses a
non-constant-time MAC compare (timing oracle), only `SharePackage` zeroizes
(the full reconstructed Nostr key, ECDH shared secrets, nonce-pool seckey, and
file-store key all leak), the bridge envelope has no outer size cap
(authenticated DoS), and the NIP-44 cipher stack is copy-pasted across three
crates.

The user has chosen the hard-cut path: secret newtypes that **do not**
implement `Serialize`/`Deserialize`; every persistence path goes through an
explicit DTO. No feature-flag shortcuts. `DeviceState::VERSION` bumps 5→6
atomically; mixed-version state files are not supported. Subagents will
execute the work; this plan is the hand-off.

Bucket A lives entirely in `repos/bifrost-rs/`. Downstream hosts (`igloo-shell`,
`igloo-home`, `igloo-pwa`, `igloo-shared`) will need a coordinated release at
the end of Bucket A because of the state-version bump and the
`SharePackage` serde removal — flagged in the Cross-Repo section.

## Scope

**In:**
- A.1 — Constant-time MAC compare across three NIP-44 decrypt paths.
- A.2 — `.expect()` removal in `recovery.rs:verifying_key_to_group_pk`.
- A.3 — Envelope size ceiling + per-field string caps in `bifrost-codec`.
- A.4 — Secret newtypes (`ZeroizeOnDrop`, no serde) + `DeviceState` split with explicit persistence DTO.
- A.5 — NIP-44 cipher-stack consolidation into `bifrost-core::nip44`, preceded by KAT freeze.

**Out of scope for Bucket A (deferred to later buckets):**
- `RuntimeSnapshotExport.bootstrap` leaking `share.seckey` hex on every snapshot call (`bifrost-bridge-wasm/src/lib.rs:110-114`) — pre-existing; **flag for Bucket D** (browser host secret hygiene).
- Argon2 params / envelope AAD (Bucket B).
- Doc updates to `docs/CRYPTOGRAPHY.md`, `docs/WIRE.md` (Bucket J, runs alongside).

## Execution Order

4 PRs total. Each PR is a single subagent task with clear acceptance criteria.

| PR | Items | Depends on |
|---|---|---|
| PR1 | A.1, A.2, A.3, A.4.a (add `subtle`, `bifrost-core::secret`), A.4.b (`SharePackage`), A.4.c (`EncryptedFileStore.key`), A.4.d (`RecoveredKeyMaterial`) | none |
| PR2 | A.4.e (hoist `NoncePool.seckey`), A.4.f (split `DeviceState` + DTO + atomic bincode migration + `VERSION` 5→6), A.4.g (`EcdhCacheEntry` newtype + drop from persistence) | PR1 |
| PR3 | A.5.pre (KAT freeze for all three NIP-44 stacks) | PR1 (needs `subtle`) |
| PR4 | A.5.main (consolidate into `bifrost-core::nip44`, migrate callers) | PR3 |

PR1 and PR3 can run in parallel. PR2 and PR4 are serial behind PR1/PR3
respectively. Total ~1,800 lines touched.

---

## A.1 — Constant-time MAC compare

**Problem:** `frostr-utils/src/profile_packages.rs:926` uses `!=` for MAC
comparison while sibling paths use a hand-rolled `ct_eq_32`. Timing oracle on
encrypted-profile-backup decrypts.

**Change:**
1. Add `subtle = "2.5"` to `repos/bifrost-rs/Cargo.toml` under `[workspace.dependencies]`. Edition is 2024.
2. Replace `expected_mac != mac` at `crates/frostr-utils/src/profile_packages.rs:926` with `subtle::ConstantTimeEq::ct_eq(&expected_mac[..], &mac[..]).unwrap_u8() == 0` (or the `bool` conversion via `.into()`).
3. Replace the hand-rolled `ct_eq_32` at `crates/bifrost-signer/src/crypto.rs:226-232` and `crates/frostr-utils/src/protocol.rs:394-400` with the `subtle` equivalent. Keep the function names if callers are extensive; otherwise inline.
4. Add a regression test in each of the three crates: four mismatch positions (first byte, middle byte, last byte, single-bit flip) asserting the expected error variant. These tests complement the KATs added in A.5.pre.

**Acceptance:**
- `rg 'ct_eq_32|!= ?mac|!= ?expected_mac'` in `crates/` returns no production matches.
- `cargo test --workspace` passes.
- New 4-position mismatch tests pass in all three crates.

---

## A.2 — Remove `.expect()` from `verifying_key_to_group_pk`

**Problem:** `crates/frostr-utils/src/recovery.rs:83` aborts the process if the
upstream `frost-secp256k1-tr-unofficial` crate ever fails to serialize a
verifying key. Reachable via public `recover_key`.

**Change:**
1. Change `fn verifying_key_to_group_pk(...) -> Bytes32` to return `FrostUtilsResult<Bytes32>`.
2. Replace `.expect("secp256k1-tr verifying key serialization should succeed")` with `.map_err(|e| FrostUtilsError::Crypto(e.to_string()))?`.
3. Update the single caller (`recover_key` at `recovery.rs:68`) to propagate via `?`.

**Acceptance:**
- `recover_key`'s public signature unchanged (it already returns `FrostUtilsResult`).
- New test: malformed verifying-key input returns `FrostUtilsError::Crypto`, not a panic.

---

## A.3 — Envelope size ceiling + per-field caps in `bifrost-codec`

**Problem:** `decode_bridge_envelope(raw: &str)` at
`crates/bifrost-codec/src/bridge.rs:34` calls `serde_json::from_str(raw)` with
no bound on `raw.len()`; per-field string caps are also absent. Authenticated
DoS from any group peer who shares a conversation key.

**Change:**
1. Add a module-level constant in `crates/bifrost-codec/src/bridge.rs`:
   ```rust
   pub const MAX_BRIDGE_ENVELOPE_BYTES: usize = 65_536; // 64 KiB
   ```
2. At the top of `decode_bridge_envelope`, reject inputs where `raw.len() > MAX_BRIDGE_ENVELOPE_BYTES` with a specific `CodecError::EnvelopeTooLarge` variant (add the variant).
3. Per-field string caps in the wire types (`crates/bifrost-codec/src/wire.rs`):
   - `kind`, `group_name`, `code`, `message` (identifiers / labels) → 1 KiB each
   - `content` (hex payload) → 32 KiB
   Enforce in each `TryFrom<*Wire>` impl; add `CodecError::FieldTooLarge { field: &'static str, limit: usize }`.
4. Tests in `crates/bifrost-codec/tests/envelope_bounds.rs` (new):
   - `decode_rejects_oversized_envelope_before_parse`: 128 KiB input, asserts `EnvelopeTooLarge` and that no allocation beyond the input buffer occurs (measured via a `tracking-allocator` or just by noting the early return site).
   - `decode_rejects_oversized_field_in_valid_envelope`
   - `decode_accepts_maximum_sized_valid_input`
   - `decode_rejects_oversized_content_hex`

**Acceptance:**
- Existing codec tests pass.
- New bound tests pass.
- `MAX_BRIDGE_ENVELOPE_BYTES = 65_536` is hardcoded (not configurable). Design decision: keeps wire contract predictable.

---

## A.4 — Secret newtypes + `DeviceState` split

### A.4.a — Add `subtle`, introduce `bifrost-core::secret`

New module `crates/bifrost-core/src/secret.rs`. Types:

```rust
// Sketch — final signatures finalized in PR1

pub struct SharePrivateKey([u8; 32]);
pub struct NoncePoolSecret([u8; 32]);
pub struct EcdhSharedSecret([u8; 32]);
pub struct RecoveredSigningKey([u8; 32]);
pub struct FileStoreKey([u8; 32]);
```

For each:
- Derive `ZeroizeOnDrop` via `zeroize_derive`.
- Implement `PartialEq` + `Eq` via `subtle::ConstantTimeEq` — total equality over 32 bytes.
- Implement `Debug` manually: prints `"SharePrivateKey(<redacted>)"` — no byte content.
- Do **not** derive `Serialize` or `Deserialize`.
- Explicit constructor: `pub fn new(bytes: [u8; 32]) -> Self`.
- Explicit accessor: `pub fn expose_bytes(&self) -> &[u8; 32]` — intentionally named to make call sites searchable.
- **No `Clone` derived by default.** Add `Clone` only on types where migration requires it (likely: `SharePrivateKey` for `EncryptedFileStore::new`, and `NoncePoolSecret` for `DeviceState::clone` path). Every `Clone` leaves a documented trail in the module header.

Workspace `Cargo.toml` changes:
- Add `subtle = "2.5"` to `[workspace.dependencies]`.
- Add `subtle.workspace = true` to `crates/bifrost-core/Cargo.toml` (consumed by A.4 and A.5).

Public re-export: `crates/bifrost-core/src/lib.rs` adds `pub mod secret;` and an explicit re-export set.

### A.4.b — Migrate `SharePackage.seckey` → `SharePrivateKey`

File: `crates/bifrost-core/src/types.rs`.

- Replace field: `seckey: Bytes32` → `seckey: SharePrivateKey`.
- Drop `#[serde(with = "serde_fixed_array::bytes32")]` on `seckey`.
- **Remove `Serialize` and `Deserialize` from `SharePackage`.** All wire-crossing and persistence already goes through `SharePackageWire` (`crates/bifrost-codec/src/wire.rs:250`); verify and fix any direct users.
- Keep `ZeroizeOnDrop`, `Clone`, `PartialEq`, `Eq`.
- Update the existing `From<SharePackage> for SharePackageWire` and `TryFrom<SharePackageWire> for SharePackage` to go through `SharePrivateKey::new` and `.expose_bytes()`.
- Update `EncryptedFileStore::new` at `crates/bifrost-app/src/runtime/store.rs:24` — `hasher.update(share.seckey.expose_bytes())`.
- Rewrite tests at `crates/bifrost-core/src/types.rs` (around lines 552-591) that round-trip `SharePackage` through serde. They must now round-trip through `SharePackageWire`.
- Audit and fix remaining `share.seckey` call sites (expected ~30 across the workspace; `rg 'share\.seckey' crates/` is the canonical list).

**Existing DTO to reuse:** `SharePackageWire` at `crates/bifrost-codec/src/wire.rs:250`. Do not invent a new one.

### A.4.c — `EncryptedFileStore.key` → `FileStoreKey`

File: `crates/bifrost-app/src/runtime/store.rs`.

- Field change: `key: [u8; 32]` → `key: FileStoreKey`.
- Trivial: ~10 lines across the file.

### A.4.d — `RecoveredKeyMaterial.signing_key32` → `RecoveredSigningKey`

File: `crates/frostr-utils/src/types.rs:45-47`.

- Field change: `signing_key32: Bytes32` → `signing_key32: RecoveredSigningKey`.
- Remove `Serialize` and `Deserialize` from `RecoveredKeyMaterial`. **No DTO needed** — the type does not cross any serialization boundary; it's a short-lived return value from `frostr-utils::recovery::recover_key` consumed inside `frostr-utils::keyset`.
- Keep `Clone` (recovery flows need it), `ZeroizeOnDrop` (via field), `PartialEq`, `Eq`, redacted `Debug`.
- Call-site audit: `rg -l RecoveredKeyMaterial crates/` — expected results limited to `frostr-utils::recovery`, `frostr-utils::keyset`. `bifrost-profile-wasm` does **not** import it; earlier claims otherwise were incorrect.

### A.4.e — Hoist `NoncePool.seckey` into `DeviceSecrets`

File: `crates/bifrost-core/src/nonce.rs`.

- **Remove `seckey: Bytes32` from `NoncePool`.** `NoncePool` becomes purely public state.
- Keep `Debug, Clone, Serialize, Deserialize` on `NoncePool` (all fields are now public state).
- Change `generate_for_peer(&mut self, peer_idx, count)` → `generate_for_peer(&mut self, peer_idx, count, seckey: &NoncePoolSecret)` at `nonce.rs:134`.
- Update three production callers (find via `rg '\.generate_for_peer\('`):
  - `crates/bifrost-signer/src/lib.rs:175` (`generate_onboarding_bootstrap_seed`)
  - `crates/bifrost-signer/src/lib.rs:1188` (`initiate_sign`)
  - `crates/bifrost-signer/src/lib.rs` onboarding `handle_inbound_request` path (grep locates it)

Each caller pulls the secret from `state.secrets.nonce_pool_secret`.

Test callers update to build `NoncePool` without a seckey, and pass a `NoncePoolSecret` at call time.

### A.4.f — Split `DeviceState`; introduce `DeviceStatePersisted` DTO; atomic bincode migration; `VERSION` 5 → 6

File: `crates/bifrost-signer/src/lib.rs` (struct definition around lines 93-112).

**New shape:**

```rust
// In-memory only — NOT Serialize/Deserialize
pub struct DeviceSecrets {
    pub nonce_pool_secret: NoncePoolSecret,
    // ecdh_cache_secrets intentionally NOT here — dropped from persistence (see A.4.g)
    pub ecdh_cache: HashMap<String, EcdhCacheEntryLive>,
}

// Live runtime state — flat fields, one secrets substruct
// NOT Serialize/Deserialize on the whole thing.
pub struct DeviceState {
    pub secrets: DeviceSecrets,
    pub nonce_pool: NoncePool,                      // now purely public state
    pub sig_cache: HashMap<String, SigCacheEntry>,  // already public signatures
    pub pending_operations: HashMap<String, PendingOperation>,
    pub replay_cache: ReplayCache,
    pub manual_policy_overrides: ManualPolicyOverrides,
    pub remote_scoped_policies: RemoteScopedPolicies,
    // ... remaining fields verbatim
}

// Serialization-only DTO — this is the bincode boundary.
#[derive(Serialize, Deserialize)]
pub struct DeviceStatePersisted {
    pub version: u32,                               // 6
    pub nonce_pool: NoncePool,
    pub sig_cache: HashMap<String, SigCacheEntry>,
    pub pending_operations: HashMap<String, PendingOperation>,
    pub replay_cache: ReplayCache,
    pub manual_policy_overrides: ManualPolicyOverrides,
    pub remote_scoped_policies: RemoteScopedPolicies,
    // ... all non-secret fields; explicitly NOT ecdh_cache
}

impl From<&DeviceState> for DeviceStatePersisted { /* ... */ }
impl DeviceState {
    pub fn from_persisted(secrets: DeviceSecrets, persisted: DeviceStatePersisted) -> Self { /* ... */ }
}
```

**Atomic migration** — update all four bincode call sites in one PR:
1. `crates/bifrost-app/src/runtime/store.rs:96-99` — save: `bincode::serialize(&DeviceStatePersisted::from(state))`.
2. `crates/bifrost-app/src/runtime/store.rs:85-88` — load: `bincode::deserialize::<DeviceStatePersisted>(&plaintext)`, then `DeviceState::from_persisted(secrets, persisted)` where `secrets` is rebuilt from the share.
3. `crates/bifrost-bridge-wasm/src/lib.rs:1075` — snapshot: serialize `DeviceStatePersisted::from(state)` only.
4. `crates/bifrost-bridge-wasm/src/lib.rs:1082` — restore: deserialize to `DeviceStatePersisted`, rebuild via `DeviceState::from_persisted` using the share that's already in the `RuntimeBootstrapInput.share` of the surrounding snapshot.
5. **Fourth site (not in original audit):** `crates/bifrost-app/src/onboarding.rs:244-250` — its own `encode_device_state_hex`/`decode_device_state_hex`. Must migrate in lock-step.

**Version bump:** `DeviceStatePersisted.version = 6`. The old version-5 loader returns `Err(StateError::UnsupportedVersion)`. No back-compat shim. This is the hard-cut boundary: any state file written before PR2 lands is abandoned.

**Clone discipline:** production `DeviceState.clone()` happens in 3 sites — `InMemoryStore` (`runtime/store.rs:84`), `BridgeCore::snapshot_state` (`bifrost-router/src/lib.rs:327`), and the WASM snapshot thread. All three are in-memory pre-persistence and can keep the `Clone` semantics. `DeviceSecrets::clone` must be implemented (not derived) to preserve the `ZeroizeOnDrop` contract on both the original and the clone.

### A.4.g — `EcdhCacheEntry`: wrap secret, drop from persistence

Files: `crates/bifrost-signer/src/lib.rs:501-506` + persistence sites.

- Rename existing type to `EcdhCacheEntryLive` (runtime shape).
- `shared_secret: [u8; 32]` → `shared_secret: EcdhSharedSecret`.
- Remove `Serialize`/`Deserialize` from `EcdhCacheEntryLive`.
- The cache itself (`DeviceSecrets.ecdh_cache`) does not persist through `DeviceStatePersisted`. On restart, it starts empty. TTL is already 300s (`config.ecdh_cache_ttl_secs`); restart-from-cold is semantically identical to "user restarted after 5 min". Cost is a single `k256::diffie_hellman` + FROST `ecdh_finalize` on first re-use — cheap.

**Acceptance for A.4 as a whole:**
- `rg 'derive\(.*Serialize' crates/bifrost-core/src/secret.rs` returns nothing.
- `rg 'derive\(.*Serialize' crates/bifrost-core/src/types.rs` shows no `Serialize` on `SharePackage`.
- `rg 'signing_key32|seckey|shared_secret' crates/` call-site audit: every remaining match is either (a) inside the `secret` newtype module, (b) inside the existing wire DTOs, (c) a hex field on a `*Wire` type. No raw `[u8; 32]` or `Bytes32` direct field on a persistent struct.
- `grep -r 'DeviceState::VERSION' crates/` shows the new value 6.
- Test: `DeviceState` round-trip through `DeviceStatePersisted` preserves all non-cache fields; the ECDH cache starts empty on reload.
- Test: a v5 bincode blob returns `StateError::UnsupportedVersion`.
- Test: `format!("{:?}", share_private_key)` contains `<redacted>` and no hex digits.

---

## A.5 — NIP-44 cipher-stack consolidation

The three current stacks are **wire-byte identical** (Plan agent confirmed:
identical HKDF salt `b"nip44-v2"`, identical `STANDARD_NO_PAD` base64,
identical padding scheme, identical MAC construction). Only Stack 1 has a
pinned KAT today. Safe to consolidate, but the KAT freeze is non-negotiable.

### A.5.pre — Freeze KATs before touching cipher code (PR3)

New test file: `crates/bifrost-core/tests/nip44_kats.rs`.

1. **Migrate Stack 1's existing JS-ciphertext KAT** (`crates/bifrost-signer/src/crypto.rs:241-254`) into the new shared location. This test currently pins an externally-generated ciphertext to its plaintext — it is the one load-bearing cross-implementation anchor in the repo.
2. **Capture new KATs for Stacks 2 and 3.** For each:
   - Stack 2 (`frostr-utils::protocol` peer messaging): fix a plaintext, peer seckey, peer pubkey, and nonce. Run `encrypt_for_peer` in the current code. Record the resulting ciphertext bytes as a hex constant. Add a test that asserts `encrypt_for_peer(plaintext, keys, nonce) == ciphertext` and that `decrypt_from_peer(ciphertext, keys) == plaintext`.
   - Stack 3 (`frostr-utils::profile_packages`): fix a plaintext, conversation key (bypass `derive_profile_backup_conversation_key`), and nonce. Record the ciphertext. Same shape of test.
3. **Run the new KATs and commit their captured ciphertexts.** These become the regression net for A.5.main. Any byte drift during consolidation fails these tests.

**Acceptance:**
- 3 KAT tests committed with hex constants.
- All 3 pass against the pre-consolidation code.
- Stack 3's KAT still uses the current (non-CT) MAC compare because A.1 may or may not have landed; the KAT is about ciphertext bytes, not timing.

### A.5.main — Consolidate into `bifrost-core::nip44` (PR4)

New module: `crates/bifrost-core/src/nip44/mod.rs`.

Public surface:
```rust
pub fn encrypt_for_peer(...) -> Result<String, CipherError>;
pub fn decrypt_from_peer(...) -> Result<String, CipherError>;
pub fn encrypt_under_conversation_key(...) -> Result<String, CipherError>;
pub fn decrypt_under_conversation_key(...) -> Result<String, CipherError>;

#[derive(Debug, thiserror::Error)]
pub enum CipherError {
    InvalidVersion,
    PayloadTooShort,
    MacMismatch,
    BadBase64,
    BadUtf8,
    BadLength,
    Crypto(String),  // upstream k256 / hkdf / chacha errors
}
```

Internal helpers (not public): `event_shared_x`, `hkdf_extract_sha256`,
`hkdf_expand_sha256`, `get_message_keys`, `calc_padded_len`, `pad_message`,
`unpad_message`, `hmac_aad`, `ct_eq` (uses `subtle::ConstantTimeEq`).

Stack 1 is the canonical implementation — it has the JS-interop KAT and the
best-structured error taxonomy.

**Caller migration:**

1. `crates/bifrost-signer/src/crypto.rs`
   - Delete helpers (lines 91-232).
   - Rewrite `encrypt_content_for_peer` / `decrypt_content_from_peer` to call the new module.
   - Map `bifrost_core::nip44::CipherError` → `SignerError::DecryptFailed(String)` at the crate boundary.

2. `crates/frostr-utils/src/protocol.rs`
   - Delete helpers (lines 259-400).
   - Rewrite `build_onboard_request_event` / `decode_onboard_response_event` payload paths to call the new module.
   - Map to `FrostUtilsError::DecryptionFailed`.

3. `crates/frostr-utils/src/profile_packages.rs`
   - Delete helpers (lines 871-1015).
   - Rewrite `encrypt_nip44_compatible_payload` / `decrypt_nip44_compatible_payload` to call the new module.
   - Map to `FrostUtilsError::DecryptionFailed`.

**Acceptance:**
- `rg 'hkdf_expand_sha256|calc_padded_len|pad_message|unpad_message|hmac_aad|ct_eq_32' crates/` shows matches only inside `crates/bifrost-core/src/nip44/`.
- All three KATs from A.5.pre still pass byte-for-byte.
- `cargo test --workspace` passes.
- `cargo clippy --workspace -- -D warnings` clean.
- Net line count: ~600 lines deleted across the three caller crates, ~400 added in `bifrost-core::nip44`.

---

## Critical Files

See the full Bucket A plan at
`/home/cscott/.claude/plans/typed-hatching-pixel.md` for the exhaustive
file-by-file modify/add/reuse lists. Summary:

- Workspace + per-crate `Cargo.toml` updates (add `subtle`).
- `bifrost-core`: new `secret.rs` and `nip44/mod.rs` modules; `types.rs`, `nonce.rs` migrations.
- `bifrost-codec`: `bridge.rs` bounds, `wire.rs` field caps, new `tests/envelope_bounds.rs`.
- `bifrost-signer`: `DeviceState` split (PR2), `crypto.rs` helper deletion (PR4).
- `frostr-utils`: `types.rs` (RecoveredKeyMaterial), `recovery.rs` (.expect removal), `protocol.rs` + `profile_packages.rs` (consolidation).
- `bifrost-app`: `runtime/store.rs` (FileStoreKey + bincode DTO migration), `onboarding.rs` (4th bincode site).
- `bifrost-bridge-wasm`: `lib.rs` persistence DTO migration.
- New `bifrost-core/tests/nip44_kats.rs`.

## Verification (per PR)

**PR1:**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs
cargo test --workspace --offline
cargo clippy --workspace --all-targets -- -D warnings
```
Plus: `rg 'ct_eq_32|!= ?expected_mac' crates/` empty; `rg 'derive\(.*Serialize' crates/bifrost-core/src/types.rs` shows `SharePackage` without `Serialize`; `rg 'share\.seckey[^.]' crates/` returns 0.

**PR2:** `cargo test --workspace --offline` + new `device_state_v5_rejected_with_unsupported_version_error`, `device_state_round_trip_through_persisted_dto_preserves_non_cache_fields`, `device_state_restore_starts_ecdh_cache_empty`, debug-redaction assertions. Manual: `make demo-start && make demo-onboard && make demo-smoke`.

**PR3:** `cargo test -p bifrost-core --test nip44_kats --offline` — 3 KATs pass against pre-consolidation code.

**PR4:** `cargo test --workspace --offline` + `cargo clippy` + `rg 'hkdf_expand_sha256|pad_message|unpad_message|hmac_aad' crates/` only in `bifrost-core/src/nip44/`. KATs pass byte-for-byte. Manual demo-harness re-run.

**Full-bucket:** `make test-prep && make test-release`.

## Cross-Repo Coordination

Bucket A introduces two breaking changes downstream hosts must absorb:

1. **`DeviceState::VERSION` 5 → 6** — state files from before PR2 are unreadable. Hosts persisting `DeviceState` bincode blobs must update simultaneously. Coordinated release across `bifrost-rs`, `igloo-shell`, `igloo-home`, `igloo-pwa`, `igloo-chrome`.
2. **`SharePackage` loses `Serialize`/`Deserialize`.** Any downstream crate directly serializing `SharePackage` (not `SharePackageWire`) will stop compiling.

## Out-of-Bucket Flags

- **`RuntimeSnapshotExport.bootstrap` leaks `share.seckey` hex on every `snapshot_state()` call.** Flagged for Bucket D.
- **Argon2 params and envelope AAD** — Bucket B.
- **`docs/CRYPTOGRAPHY.md` / `docs/WIRE.md` updates** — Bucket J.

## Summary

Four PRs, ~1,800 lines, all inside `bifrost-rs`. Hard-cut on state version.
Secret newtypes in one new module; `DeviceState` gets `secrets: DeviceSecrets`
substruct and a serialization-only `DeviceStatePersisted` DTO; ECDH cache
drops out of persistence. NIP-44 stacks consolidate into `bifrost-core::nip44`
after KATs are frozen. `subtle` replaces hand-rolled `ct_eq_32`. Envelope cap
64 KiB hardcoded. Downstream hosts need coordinated release for
state-version bump + `SharePackage` serde removal.
