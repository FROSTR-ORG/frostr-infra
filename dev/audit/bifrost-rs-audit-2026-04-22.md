# `bifrost-rs` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs`

This audit covered all 11 crates of the signer/runtime core, focusing on FROST invariants, unsafe blocks, secret zeroization, constant-time comparisons, wire-boundary strictness, RNG sourcing, and state-machine clarity. The dominant pattern across crates is cryptographic correctness with selective discipline: FROST invariants, threshold checks, nonce single-use, strict recipient routing, and `OsRng` sourcing are uniformly good, but secret hygiene (zeroization) is applied to exactly one type (`SharePackage`) across the entire workspace, constant-time MAC comparison is hand-rolled and inconsistent (one path uses `!=`), and the NIP-44-style encrypt/decrypt stack is copy-pasted across three crates. No production `unsafe` exists (good), and production `unwrap`/`expect`/`panic!` usage is small and localized. The codec boundary is strict on structure but not on outer message size, and dedicated integration tests exist only for `bifrost-app`, `bifrost-signer` (one file), and `bifrost-bridge-tokio` — the pure-crypto crates (`bifrost-core`, `bifrost-codec`, `bifrost-router`, `bifrost-bridge-wasm`, `bifrost-profile`) rely entirely on inline unit tests with no property tests and no KATs.

## Findings

### 1. High: only one type in the workspace zeroizes on drop; reconstructed key, ECDH shared secret, nonce-pool seckey, and derived state keys all leak

Files:
- `repos/bifrost-rs/crates/bifrost-core/src/types.rs:181-187`
- `repos/bifrost-rs/crates/bifrost-core/src/nonce.rs:29-39`
- `repos/bifrost-rs/crates/frostr-utils/src/types.rs:44-47`
- `repos/bifrost-rs/crates/bifrost-app/src/runtime/store.rs:15-32`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:93-112`

Why this matters:
- `SharePackage` derives `Zeroize`/`#[zeroize(drop)]` at `types.rs:181`. A grep for `Zeroize` or `ZeroizeOnDrop` across the workspace returns exactly those two lines and no other use.
- `NoncePool` stores the device's `seckey: Bytes32` in a plain field and is itself `Serialize`/`Deserialize` with no zeroize, so stale FROST signing-share bytes remain in the heap after drop and show up in any `Debug` printing of `DeviceState`.
- `RecoveredKeyMaterial.signing_key32` is the full threshold-reconstructed Nostr secret key — the single most sensitive value in the system — returned as a plain `Bytes32` with `Debug` and `Serialize` derived.
- `EncryptedFileStore.key` at `store.rs:17` is SHA256(share.seckey || "bifrost-device-state"). It is held for the lifetime of the process and never wiped.
- `DeviceState.ecdh_cache` holds every successful ECDH result keyed by target as `shared_secret: [u8; 32]`. These sit in memory and on disk (encrypted, see #4) with no in-memory zeroize on drop.

Smells:
- Zeroize discipline treated as one-off on the input container, not as a policy across the secret lifecycle.
- `Debug` derived on structs that contain key material (`DeviceState`, `NoncePool`, `RecoveredKeyMaterial`) — easy to log by accident.
- `Serialize` derived on the in-memory secret-bearing types for persistence, which also exposes them to tracing or snapshot dumps.

Streamline:
- Introduce secret newtypes (`SharePrivateKey`, `NoncePoolSecret`, `RecoveredSigningKey`, `EcdhSharedSecret`) with `ZeroizeOnDrop` and a manual `Debug` that redacts.
- Wrap `EncryptedFileStore.key` and derived conversation keys in `Zeroizing<[u8; 32]>`.
- Remove default `Debug` from `DeviceState`, `NoncePool`, `EcdhCacheEntry`, `RecoveredKeyMaterial`; implement redacted `Debug` manually.

### 2. High: `decrypt_nip44_compatible_payload` in the profile-backup path uses non-constant-time MAC comparison

Files:
- `repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs:909-933`

Why this matters:
- At `profile_packages.rs:926` the MAC check is `if expected_mac != mac`, a byte-array equality that short-circuits on first mismatch. This is the decrypt path for encrypted profile backups (`kind: 10000`), so an attacker that can observe decrypt timing (co-tenant, browser side-channel, cross-origin timing oracles in WASM) can extract tag bytes byte-by-byte.
- The two sibling payload decrypt paths get this right and use a hand-rolled `ct_eq_32` (`repos/bifrost-rs/crates/bifrost-signer/src/crypto.rs:81`, `repos/bifrost-rs/crates/frostr-utils/src/protocol.rs:249`), which confirms the author knows the rule. The backup path is the exception.
- `ct_eq_32` is hand-rolled in two places (`crypto.rs:226`, `protocol.rs:394`) rather than using `subtle::ConstantTimeEq`; the code is small enough to be correct, but any future edit that replaces `|=` with `&&` would silently reintroduce a timing oracle.

Smells:
- Three parallel implementations of the same NIP-44-style crypto with different MAC-check primitives.
- No dependency on the `subtle` crate, which is the de-facto Rust standard for this.

Streamline:
- Replace the `!=` at `profile_packages.rs:926` with the local `ct_eq_32` pattern immediately.
- Add `subtle = "2"` to workspace dependencies and swap both hand-rolled implementations for `ConstantTimeEq::ct_eq(...).into()`.
- Collapse the three NIP-44-style codec stacks into one crate (`bifrost-core::cipher` or equivalent) and have `bifrost-signer`, `frostr-utils::protocol`, and `frostr-utils::profile_packages` all consume it.

### 3. High: `bifrost-core`, `bifrost-codec`, `bifrost-router`, `bifrost-bridge-wasm`, and `bifrost-profile` have no integration tests and no KATs

Files:
- `repos/bifrost-rs/crates/bifrost-core/` (no `tests/` directory)
- `repos/bifrost-rs/crates/bifrost-codec/` (no `tests/` directory)
- `repos/bifrost-rs/crates/bifrost-router/` (no `tests/` directory)
- `repos/bifrost-rs/crates/bifrost-bridge-wasm/` (no `tests/` directory)
- `repos/bifrost-rs/crates/bifrost-profile/` (no `tests/` directory)
- `repos/bifrost-rs/crates/bifrost-core/src/sign.rs:332-683`
- `repos/bifrost-rs/crates/bifrost-core/src/nonce.rs:337-437`

Why this matters:
- The only integration tests in the workspace are `bifrost-app/tests/*` (seven files), `bifrost-bridge-tokio/tests/*` (five files), and `bifrost-signer/tests/runtime_roundtrip.rs` (one file, 141 lines). Everything else lives in inline `#[cfg(test)] mod tests`.
- Coverage of adversarial inputs is thin: `sign.rs` tests happy-path roundtrip and one tampered-share rejection, but there are no tests for duplicate `hash_index` entries reaching aggregation, mixed-sighash partials from the same signer, or cross-session replay of partial signatures. There are no property tests and no FROST Known-Answer-Test vectors cross-checked against an independent implementation.
- `bifrost-codec` wire parsing has unit tests for empty/oversized arrays but no fuzz harness and no tests for the bridge envelope size bound (see #9).
- `bifrost-router` has only inline tests; the queue overflow, dedupe, and phase state machine have no integration-level coverage.

Smells:
- Crypto crate without KAT vectors.
- Adversarial coverage concentrated in host-level tests that exercise the whole stack, not the primitives.

Streamline:
- Add `bifrost-core/tests/sign_kat.rs` with FROST-secp256k1-tr test vectors from the upstream crate or RFC draft, compared byte-for-byte.
- Add `bifrost-codec/tests/wire_fuzz.rs` using `arbitrary` and a small fuzz budget in CI for each `TryFrom<*Wire>` impl.
- Add property tests for `NoncePool` single-use and FIFO invariants (`proptest` on `generate_for_peer` / `take_outgoing_signing_nonces` sequences).

### 4. High: `decode_bridge_envelope` has no outer input-size limit

Files:
- `repos/bifrost-rs/crates/bifrost-codec/src/bridge.rs:30-48`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:1644-1648`
- `repos/bifrost-rs/crates/frostr-utils/src/protocol.rs:139-142`

Why this matters:
- `decode_bridge_envelope(raw: &str)` at `bridge.rs:34` calls `serde_json::from_str(raw)` unconditionally and then only validates `request_id` bounds. Every inner `Vec` has a cap (MAX_GROUP_MEMBERS=1000, MAX_NONCE_PACKAGE=1000, etc.), but there is no ceiling on `raw.len()` itself.
- The signer reaches this path from `decrypt_event` (`lib.rs:1647`) after NIP-44 decryption of a relay event. A malicious peer who holds a valid shared-x with the signer can send arbitrarily large JSON blobs; each must be decrypted, allocated, and parsed before any bound applies.
- Strings inside the wire types (`kind`, `group_name`, hex `content`) are also unbounded. A `SignSessionPackageWire.content` could be a multi-megabyte hex string and pass validation.
- This is a denial-of-service / memory-exhaustion vector against a long-running signer that cannot simply drop the peer (the peer is an authenticated group member).

Smells:
- Defense-in-depth missing at the outermost boundary.
- Bounds expressed in counts of structured items, not in bytes.

Streamline:
- Add a configurable `MAX_BRIDGE_ENVELOPE_BYTES` (default 64 KiB or so) checked before `serde_json::from_str` in `decode_bridge_envelope`.
- Add per-field string limits in the wire types (`kind`, `group_name`, `code`/`message` on `PeerError`, `content` hex).
- Consider switching to `serde_json::from_reader` with a bounded reader so allocation is bounded by the limit rather than by the input.

### 5. High: `recovery.rs:verifying_key_to_group_pk` panics in production code

Files:
- `repos/bifrost-rs/crates/frostr-utils/src/recovery.rs:78-86`

Why this matters:
- `.expect("secp256k1-tr verifying key serialization should succeed")` at `recovery.rs:83` runs after `frost::keys::reconstruct` produces the recovered signing key. If the upstream `frost-secp256k1-tr-unofficial` crate changes behavior (a version bump, a compressed-form edge case) this panic aborts the process instead of returning `FrostUtilsError::Crypto`.
- `recover_key` is exposed as a public API in `frostr-utils` and is callable from hosted runtimes that must not abort on malformed input. Even if the invariant holds today for well-formed shares, the input path is reachable with attacker-influenced `group.group_pk` bytes.
- The function also returns the full reconstructed secret key (see #1) so a stable error path is doubly important.

Smells:
- Production panic whose comment is aspirational ("should succeed") rather than a proof.

Streamline:
- Replace `.expect(...)` with `.map_err(|e| FrostUtilsError::Crypto(e.to_string()))?` and adjust the function signature to return `FrostUtilsResult<Bytes32>`.
- Cross-repo note: consuming hosts treat recovery as a recoverable operator action; a panic here would crash the host runtime instead of surfacing a dialog.

### 6. Medium: `derive_package_encryption_key` SHA-256 pre-digests the password before PBKDF2, deviating from NIST SP 800-132

Files:
- `repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs:714-717`
- `repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs:29-34`

Why this matters:
- `derive_package_encryption_key(password, salt)` hashes `password` with `Sha256` first, then feeds the 32-byte digest into `pbkdf2_hmac_array::<Sha256, 32>(&password_digest, salt, 600_000)`. This is not RFC 8018 / NIST SP 800-132 compliant PBKDF2 and gives an attacker a fixed-size 32-byte "effective password" input regardless of length.
- The envelope records `password_encoding: "sha256"` (`profile_packages.rs:604`), which suggests the deviation is intentional for cross-implementation compatibility (browser JS using `crypto.subtle.digest` before PBKDF2). That is a valid design choice, but it is not what an auditor reviewing crypto conventions will expect.
- 600_000 iterations is good (matches current OWASP guidance for PBKDF2-HMAC-SHA256), and `BF_PACKAGE_SALT_BYTES=16` is fine. The SHA-256 pre-digest does not directly weaken the scheme against brute-force (HMAC-SHA256 with a 32-byte key is secure), but it does lose the standard's length-extension resistance argument, and it means porting to a different-endian or different-encoding implementation silently changes keys.

Smells:
- Non-standard password preprocessing with no inline justification.
- The `"sha256"` marker implies this is a format decision, but `SECURITY.md` / `CRYPTOGRAPHY.md` do not currently document it (see #13).

Streamline:
- Add a rustdoc block on `derive_package_encryption_key` explaining the cross-platform requirement.
- Add a KAT test in `profile_packages.rs` with a known password, salt, and resulting key, plus the matching browser output, pinned as the canonical vector.
- Document the scheme in `docs/CRYPTOGRAPHY.md` explicitly.

### 7. Medium: NIP-44-style cipher stack is copy-pasted across three crates with drift

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/crypto.rs:91-232`
- `repos/bifrost-rs/crates/frostr-utils/src/protocol.rs:200-400`
- `repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs:891-1000`

Why this matters:
- Three near-identical implementations of ECDH → HKDF-extract/expand → ChaCha20 → HMAC-SHA256 → base64 padding live in three files. The `event_shared_x`, `hkdf_extract_sha256`, `hkdf_expand_sha256`, `get_message_keys`, `pad_message`, `unpad_message`, and `hmac_aad` helpers are duplicated in both `bifrost-signer/src/crypto.rs` and `frostr-utils/src/protocol.rs`.
- The MAC comparison drifted in `profile_packages.rs` (see #2). Any future bugfix to one copy (for example, a length-confusion or unpad bug) must be ported manually to the other two. Each copy has its own error enum (`SignerError::DecryptFailed(String)` vs `FrostUtilsError::DecryptionFailed` vs `FrostUtilsError::Codec(String)`) with subtly different leak-surface in the error message.

Smells:
- Duplicated low-level crypto primitives.
- Inconsistent error taxonomy for the same failure modes.

Streamline:
- Extract a single `bifrost-cipher` or `bifrost-core::nip44` module that exposes `encrypt_for_peer`, `decrypt_from_peer`, and `encrypt_under_conversation_key` primitives, with one canonical `CipherError` type.
- Collapse `ct_eq_32` to one implementation in that module and swap in `subtle::ConstantTimeEq`.

### 8. Medium: `build_signed_event` uses zero aux-rand for BIP-340 Schnorr signatures

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/event_io.rs:21-53`
- `repos/bifrost-rs/crates/frostr-utils/src/protocol.rs:170-198`

Why this matters:
- Both implementations sign the Nostr event envelope with `let aux = [0u8; 32]; signing_key.sign_raw(digest.as_slice(), &aux)`. BIP-340 recommends using 32 random bytes for `aux_rand` to provide fault-attack resistance; using a constant is allowed but explicitly noted as less safe.
- These signatures are outer transport signatures on relay events, not FROST group signatures, so the impact is limited to the signer's own per-device key. The Nostr ecosystem broadly accepts deterministic Schnorr signatures, so this is not wrong — just below the recommended defense.

Smells:
- Duplicated signing helper (see #7) with the same weakened parameter.
- No comment indicating the deterministic choice is intentional.

Streamline:
- Source `aux` from `OsRng.fill_bytes`, or add an explicit comment documenting the deterministic-signature choice if that is a protocol decision.

### 9. Medium: `CoreError::Frost(String)` and `SignerError::*(String)` embed upstream error messages into the error taxonomy

Files:
- `repos/bifrost-rs/crates/bifrost-core/src/error.rs:47-48`
- `repos/bifrost-rs/crates/bifrost-signer/src/error.rs:5-23`
- `repos/bifrost-rs/crates/frostr-utils/src/errors.rs:3-21`

Why this matters:
- `CoreError::Frost(String)` carries the formatted error from the `frost-secp256k1-tr-unofficial` crate into every call site. These messages are not part of the bifrost contract and can leak internal validator state (identifier values, share indices, or inner library wording) to whichever layer ultimately serializes the error.
- `SignerError::DecryptFailed(String)` is similar: decrypt failure reasons are distinguished by free-form strings ("invalid MAC", "unknown encryption version marker", "invalid base64: ..."), which a client or peer can use to fingerprint the local version.
- Converting between the three error enums uses `.to_string()` repeatedly, so the final error seen by a host is a stack of concatenated strings that is hard to match on programmatically.

Smells:
- Wide string-typed error variants with no discriminated subtype.
- Loss of error programmatic typing across crate boundaries.

Streamline:
- Tighten `CoreError::Frost` to a small set of discriminated variants (`FrostInvalidShare`, `FrostAggregationFailed`, `FrostIdentifier`), with the upstream message kept only in a `source: Box<dyn Error>` for diagnostics, not for display by hosts.
- Distinguish `DecryptFailed { reason: DecryptReason }` with a small enum (BadMac, BadVersion, BadBase64, BadUtf8, BadLength); log detailed strings locally via `tracing`, not in the error.

### 10. Medium: `bifrost-signer/src/lib.rs` is 3,770 lines and mixes state machine, I/O encoding, policy, readiness, and pending-op lifecycle

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:1-3770`

Why this matters:
- The signer's canonical runtime type (`SigningDevice`) lives in one file with its state machine, config, peer-permission logic, readiness computation, onboarding status, ECDH cache, sig cache, and replay cache all implemented as methods on the same struct.
- State transitions are scattered across match arms in `handle_inbound_request`, `handle_inbound_response`, `fail_pending_operation`, `expire_pending_operations`, etc., with no single module that diagrams or guards the lifecycle `Created → AwaitingResponses → Completed | Failed | Expired` (the enum exists in `bifrost-router` but no enforcement inside the signer).
- This file contains the most security-sensitive code in the repo. The grouped tests (`#[cfg(test)] mod tests` beginning around `lib.rs:2440`) make up roughly a third of the file, pushing the already-dense production code further down.

Smells:
- Single-file signer with no internal crate-level modules for policy, readiness, caching, pending-ops, inbound/outbound.
- Test code co-located with production in a file already too large to navigate comfortably.

Streamline:
- Split `bifrost-signer/src/lib.rs` into focused modules: `signer/state.rs`, `signer/policy.rs`, `signer/readiness.rs`, `signer/pending.rs`, `signer/inbound.rs`, `signer/outbound.rs`, with `lib.rs` re-exporting only the public surface.
- Move tests to `bifrost-signer/tests/` alongside `runtime_roundtrip.rs`, split by concern.

### 11. Medium: Bridge command surface in `bifrost-bridge-tokio` is mechanically repeated 13+ times

Files:
- `repos/bifrost-rs/crates/bifrost-bridge-tokio/src/lib.rs:380-636`

Why this matters:
- Every public method on `Bridge` (`sign`, `ecdh`, `ping`, `onboard`, `snapshot_state`, `status`, `peer_permission_states`, `read_config`, `update_config`, `peer_status`, `readiness`, `runtime_status`, `runtime_metadata`, `set_policy_override`, `clear_policy_overrides`, `wipe_state`, `take_persistence_hint`, `request_phase`) follows the identical oneshot-channel pattern and is nearly character-for-character identical.
- This is not a bug, but every new command must be added in at least four places: the `BridgeCommand` enum, the select-branch handler, the async public method, and any WASM mirror. Drift between these is a meaningful correctness risk — the WASM bridge in `bifrost-bridge-wasm/src/lib.rs` is 2,177 lines of the same pattern.

Smells:
- Hand-rolled command routing that could be expressed once.

Streamline:
- Define a `trait BridgeCall { type Response; fn into_command(self, reply: oneshot::Sender<...>) -> BridgeCommand; }` and generate the async methods via one generic `async fn call<C: BridgeCall>(&self, call: C) -> Result<C::Response, BridgeError>` helper.
- Cross-repo note: the WASM bridge exposes the same surface to JS via `wasm_bindgen`; shrinking the Rust side also shrinks the generated JS bindings.

### 12. Low: `contrib/example/Cargo.toml` references three crates that do not exist in the workspace

Files:
- `repos/bifrost-rs/contrib/example/Cargo.toml:11-14`

Why this matters:
- The example declares dependencies on `bifrost-node`, `bifrost-transport`, and `bifrost-transport-ws` at `../../crates/bifrost-node`, `../../crates/bifrost-transport`, and `../../crates/bifrost-transport-ws`. None of those paths exist under `crates/` — the current workspace has `bifrost-signer`, `bifrost-router`, `bifrost-bridge-tokio`, and `bifrost-bridge-wasm`.
- The example is not a workspace member, so `cargo check --workspace` does not notice. Anyone who tries to run it will get a missing-crate error. This looks like a legacy contrib artifact from before the signer/router/bridge rename.
- The root README says "No legacy compatibility layer is maintained in this repository" (`README.md:20`) — verified as true for the runtime code; this contrib example is the one exception.

Smells:
- Stale example pointing at removed crates.
- Confusing onboarding experience for external contributors.

Streamline:
- Either port `contrib/example` to the current `bifrost-bridge-tokio` + `RelayAdapter` APIs, or delete the directory.

### 13. Low: shared docs drift from the code in two concrete places

Files:
- `repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs:714-717`
- `repos/bifrost-rs/crates/bifrost-codec/src/bridge.rs:30-48`
- `/home/cscott/Repos/frostr/frostr-infra/docs/CRYPTOGRAPHY.md`
- `/home/cscott/Repos/frostr/frostr-infra/docs/WIRE.md`

Why this matters:
- `docs/CRYPTOGRAPHY.md` is the canonical system-level description of the crypto. It does not document the SHA-256 pre-digest in `derive_package_encryption_key` (#6), the PBKDF2 iteration count (600_000), or the `"sha256"` `password_encoding` marker in the envelope. An implementer building a compatible JS/WASM peer from the doc alone would produce incompatible ciphertexts.
- `docs/WIRE.md` documents the bridge envelope structure. It does not specify a maximum envelope size (see #4), nor the per-field string ceilings that the Rust code does or does not enforce. An implementer cannot tell what the Rust side will accept.
- The inline rustdoc on the public API of `bifrost-core`, `bifrost-codec`, and `bifrost-signer` is thin; most public items (`SigningDevice`, `NoncePool`, `BridgeEnvelope`, `create_session_package`, `combine_signatures`) have no `///` comments.

Smells:
- Shared docs describe intent; code encodes facts; nothing keeps them aligned.
- Public crypto surface with no rustdoc comments.

Streamline:
- When the password-encoding scheme or envelope size caps change, update `docs/CRYPTOGRAPHY.md` / `docs/WIRE.md` in the same pass. Add a test in `bifrost-codec` that fails CI if the docs-declared caps and the in-code constants disagree (parse the doc for the constant name and compare).
- Add rustdoc on every `pub` item in `bifrost-core/src/sign.rs`, `bifrost-core/src/nonce.rs`, `bifrost-codec/src/bridge.rs`, and `bifrost-signer/src/lib.rs`.

### 14. Low: `NoncePool.remap_peer_indexes` silently merges on key collision

Files:
- `repos/bifrost-rs/crates/bifrost-core/src/nonce.rs:74-127`

Why this matters:
- `remap_peer_indexes` is called during onboarding finalization (`bifrost-signer/src/lib.rs:183-201`) to translate the bootstrap `(LOCAL=0, PEER=1)` indices to real group member indices. Its helpers use `.entry(new_key).or_insert_with(...).extend(values)`, which means if two old indices map to the same new index (or if a bootstrap index collides with an already-existing real index), all nonces, spent codes, and incoming queues are silently merged into a single bucket.
- In practice, index collisions require an attacker-controlled index map, which the signer does not accept — but the helper is `pub` and the invariant "keys of `index_map` are pairwise distinct after remap" is not enforced locally.

Smells:
- Implicit merge semantics on a data structure that is supposed to be per-peer-scoped.
- Public helper without a safety comment.

Streamline:
- Validate in `remap_peer_indexes` that the remapped key set has no collisions; return a `CoreError::InvalidConfig` if it does, or make the function internal to `bifrost-signer`.

### 15. Low: test-only `panic!` calls in `bifrost-signer/src/lib.rs` would be better as `assert!(matches!(...))` or explicit `unreachable!`

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:2628`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:2834`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:2901`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:2930`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:2988`
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:3309`

Why this matters:
- Six `panic!("expected X context")` calls sit inside the inline tests module. They do exactly what `unreachable!()` is for, but they also swallow the surrounding pattern and make the test output less informative than a `assert!(matches!(ctx, PendingOpContext::SignSession { .. }))` would be. This is purely stylistic, but the pattern recurs and will be copied.
- None of these are reachable from production code (verified: `panic!` only appears inside `#[cfg(test)]` or inside doc-example strings).

Smells:
- Idiomatic Rust testing would use `assert!(matches!(...))` or `let-else { unreachable!() }` consistently.

Streamline:
- Replace with `assert!(matches!(...))` for existence checks, or `let ... = ... else { unreachable!("..."); };` for destructuring where the compiler cannot otherwise prove the shape.
