# Bucket B — Host-Local + Portable-Package Hardening (Hard-Cut Plan)

Status: draft, pending user approval (revised 2026-04-23 for stronger defaults + portable-package migration)
Related: `bucket-a-bifrost-rs-crypto.md` (precedes; coordinated release required)

## Context

The 2026-04-22 workspace audit identified two independent encryption schemes
in `bifrost-rs` that ship with inadequate parameter discipline:

1. **Host-local encryption** (`crates/bifrost-profile/src/native.rs`) uses
   `Argon2::default()` with no parameters recorded anywhere on disk and no
   AAD binding envelope metadata to the ciphertext. Rigid
   `ENCRYPTED_PROFILE_VERSION = 1` reader cannot survive a parameter change.
2. **Portable package encryption** (`crates/frostr-utils/src/profile_packages.rs`)
   uses `SHA-256(password) || PBKDF2-HMAC-SHA256(600k)` → AES-256-GCM with
   a non-standard 24-byte nonce. Cryptographically sound, but: PBKDF2 is
   compute-bound (GPU-cheap to attack), AES-256-GCM-24 is non-NIST (GCM spec
   mandates 12-byte nonces; 24-byte is a RustCrypto extension), and zero
   KAT coverage.

Given FROSTR is in alpha and the threat model includes keys that will secure
cryptocurrency, the user has chosen **strong, secure defaults** with hard-cut
semantics for both schemes. Every existing `.enc` file and every existing
bech32m package becomes unreadable at the release cut. Coordinated release
with Bucket A's `DeviceState::VERSION` 5→6 bump is required so operators
migrate once across all three version bumps.

**What stays NIP-44 byte-compatible** (not touched by Bucket B):
- Peer-to-peer signer messaging (`bifrost-signer::crypto`) — Bucket A A.5 consolidates, preserves bytes.
- Profile-backup encryption bound for relay events (`encrypt_profile_backup_content` → `*_nip44_compatible_payload`) — Bucket A A.5 consolidates.
- Onboarding request/response payloads (`frostr-utils::protocol::encrypt_for_peer` / `decrypt_for_peer`) — Bucket A A.5 consolidates.
- HKDF salt `b"nip44-v2"`, ChaCha20 + HMAC-SHA256, 32-byte random nonce — NIP-44 spec fixed-points.

**What is FROSTR-custom** (migrated in Bucket B):
- Host-local `.enc` profile files — custom ChaCha20Poly1305 + Argon2. (B.1)
- Portable bech32m packages: `bfshare`, `bfprofile`, `bfonboard` — custom AES-256-GCM-24 + PBKDF2. (B.2)

Phase 1 exploration confirmed there is no native JS implementation of either
scheme; every JS host reaches encryption via WASM exports. B.1 and B.2 are
therefore Rust-only changes with no cross-platform coordination on wire
bytes.

## Scope

**In:**
- B.1 — Host-local envelope v2: embedded Argon2id parameters, AAD binding to
  metadata, `ENCRYPTED_PROFILE_VERSION` 1→2, `UnsupportedVersion` /
  `UnsupportedKdf` / `UnsupportedParams` / `Truncated` / `InvalidMetadata`
  error taxonomy, adversarial test coverage.
- B.2 — Portable package v2: migrate KDF from `SHA-256(pw) || PBKDF2-600k`
  to Argon2id; migrate AEAD from non-standard `Aes256Gcm24` to
  XChaCha20Poly1305; embed KDF parameters in envelope; AAD binding to HRP +
  salt + outer-id; `ProtectedPackageEnvelope.version` 1→2; drop `aes-gcm`
  and `pbkdf2` workspace deps; KAT fixtures for the new scheme.
- B.3 — Adversarial test coverage on both boundaries: wrong passphrase,
  tampered ciphertext, tampered metadata AAD, unsupported version, params
  below floor, params above ceiling, short envelope, interior-NUL rejection.

**Out of scope for Bucket B:**
- Session-scoped KDF key cache (each decrypt re-runs Argon2 at ~400–600 ms on
  the new defaults). Legitimate UX concern but belongs with unlock-session
  work. **Flag for Bucket C** (host-local secret hygiene).
- `EncryptedFileStore` (`bifrost-app/src/runtime/store.rs`) — different
  encryption path (encrypts `DeviceState` bincode with a share-derived key).
  Handled by Bucket A. Bucket B does not touch it.
- NIP-44 code paths — preserved byte-for-byte by Bucket A A.5.

## Execution Order

Three PRs. Numbering continues from Bucket A (PR1–PR4).

| PR | Items | Depends on | Merge |
|---|---|---|---|
| PR5 | B.2 portable package v2 migration (new KDF, new AEAD, new envelope, AAD, KATs, adversarial tests) | none | coordinated release with Bucket A PR2 |
| PR6 | B.1 primitives (`Argon2Params`, `build_aad_hostlocal`, new KDF helper, new error variants) — crate-internal, not wired in | none | independent |
| PR7 | B.1 writer/reader cutover + `ENCRYPTED_PROFILE_VERSION` 1→2 + B.3 host-local adversarial tests | PR6 | coordinated release with Bucket A PR2 and PR5 |

PR5 and PR6 can run in parallel. PR7 depends on PR6. All three ship in
one release window alongside Bucket A PR2 — one operator migration covers
the `DeviceState::VERSION`, `ENCRYPTED_PROFILE_VERSION`, and
`ProtectedPackageEnvelope::version` bumps together.

Rough touch: ~1,800 lines across three PRs. Most volume is in PR5 (new
envelope shape, new KDF path, new AEAD wiring, removal of old crate deps).

---

## B.1 — Host-local envelope v2

### Envelope byte layout (v2)

```
offset  len  field
  0      1   envelope_version = 2
  1      1   kdf_id (1 = Argon2id; reserved for future KDF families via version bump)
  2      4   m_cost  (u32 big-endian)  — Argon2id memory cost, KiB
  6      4   t_cost  (u32 big-endian)  — Argon2id time cost / iterations
 10      1   p_cost  (u8)              — Argon2id parallelism
 11     12   ChaCha20Poly1305 nonce
 23    N+16  ciphertext || Poly1305 tag
```

Minimum envelope length is **39 bytes** (1+1+4+4+1+12+16). The reader must
verify `envelope.len() >= 39` before indexing; a corrupted short file must
produce `StateError::Truncated`, never a panic.

Salt remains in the metadata sidecar (`EncryptedProfileRecord.salt_hex`).

### `kdf_id` semantics

`kdf_id = 1` unambiguously means "Argon2id with the `(m_cost, t_cost, p_cost)`
triple in the fixed positions above". A future KDF family **bumps
`envelope_version` to 3** — it does not reinterpret the v2 header.

### AAD construction

```
AAD_hostlocal = b"bfrstprof\x00"           // 10-byte domain separator
              || version:u8                  // 1 byte, equal to envelope_version
              || record_id_len:u16_be        // 2 bytes
              || record_id_utf8              // N bytes
              || kind_len:u16_be             // 2 bytes
              || kind_utf8                   // N bytes
              || source_len:u16_be           // 2 bytes
              || source_utf8                 // N bytes
              || salt:16                     // 16 raw bytes (NOT hex)
              || created_at:u64_be           // 8 bytes
```

- Length-prefixed UTF-8 concatenation — auditable, no JSON canonicalization.
- Raw 16-byte salt — single canonical form.
- Interior-NUL rejection: any of `record_id`, `kind`, `source` containing
  `0x00` returns `StateError::InvalidMetadata`.
- Excluded fields: `updated_at` (mutable), `ciphertext_path` (mutable),
  `key_source` (currently hardcoded, could gain semantics later).

### `Argon2Params` public API

```rust
#[non_exhaustive]
pub struct Argon2Params {
    // private fields
}

impl Argon2Params {
    pub fn new(m_cost: u32, t_cost: u32, p_cost: u8) -> Result<Self, ParamsError>;

    /// m = 256 MiB, t = 4, p = 1 — strong default for keys protecting crypto assets.
    /// ~400-600 ms unlock on modern desktop hardware.
    pub fn default() -> Self;

    /// m = 64 MiB, t = 3, p = 1 — rejection floor. Envelopes with weaker
    /// parameters are refused on decrypt to defend against an attacker
    /// substituting a weak-KDF envelope on disk before offline cracking.
    pub fn minimum_secure() -> Self;

    /// m = 512 MiB, t = 4, p = 1 — for operators who accept ~1-2s unlock
    /// latency in exchange for roughly 3x attack cost.
    pub fn high_security() -> Self;

    pub fn m_cost(&self) -> u32;
    pub fn t_cost(&self) -> u32;
    pub fn p_cost(&self) -> u8;
}
```

### Param floor and ceiling (decrypt-time validation)

Reject on decrypt if:
- `m_cost < 65_536` (64 MiB — the new floor; was 19 MiB in the earlier plan)
- `t_cost < 3`
- `p_cost < 1`
- `m_cost > 1_048_576` (1 GiB — cap against malformed reads)

Return `StateError::UnsupportedParams { m_cost, t_cost, p_cost }`.

### Default parameters for new writes

`Argon2Params::default()` = **m=262_144 (256 MiB), t=4, p=1**.

Rationale: threat model includes crypto-key protection. GPU-based offline
attack on an 8-character password at these parameters costs roughly
$0.002/guess in 2026 cloud pricing — multi-year break time even for a
well-funded attacker. Sub-second unlock on 2020-era desktop hardware.

### Writer / reader changes

Writer (`store_encrypted_profile` in `crates/bifrost-profile/src/native.rs`):
- Accept `Argon2Params` parameter (defaulted by callers if unspecified).
- Derive key via `derive_profile_encryption_key_v2(passphrase, salt, params)`.
- Build AAD via `build_aad_hostlocal(record)` and pass to AEAD.
- Emit v2 envelope per the byte layout above.

Reader (`decrypt_encrypted_profile`):
- Enforce `envelope.len() >= 39` → `StateError::Truncated`.
- Parse version byte → require `2` → `UnsupportedVersion(u8)`.
- Parse `kdf_id` → require `1` → `UnsupportedKdf(u8)`.
- Parse `m_cost, t_cost, p_cost` → validate against floor/ceiling →
  `UnsupportedParams`.
- Build AAD from the sidecar metadata (caller provides record).
- Derive key and AEAD decrypt with AAD; propagate MAC failure as
  `StateError::Decrypt`.

---

## B.2 — Portable package v2

### New envelope shape

Existing `ProtectedPackageEnvelope` replaced. Bech32m wrapping and HRPs
(`bfshare`, `bfprofile`, `bfonboard`) unchanged.

```json
{
  "version": 2,
  "kdf": "argon2id",
  "kdf_m_cost": 262144,
  "kdf_t_cost": 4,
  "kdf_p_cost": 1,
  "aead": "xchacha20poly1305",
  "salt_hex": "...",
  "nonce_hex": "...",
  "ciphertext": "..."
}
```

Fields:
- `version: 2` — hard-cut from v1. Reader treats `version != 2` as error.
- `kdf: "argon2id"` — string marker for forward-compat. Reader rejects
  other values. Future KDF migrations bump `version`.
- `kdf_m_cost`, `kdf_t_cost`, `kdf_p_cost` — Argon2id parameters, validated
  against the same floor and ceiling as B.1.
- `aead: "xchacha20poly1305"` — string marker. Reader rejects other values.
- `salt_hex` — 16 raw bytes hex-encoded.
- `nonce_hex` — 24 raw bytes hex-encoded (XChaCha20 native nonce size).
- `ciphertext` — base64-url-no-pad encoded AEAD output (ciphertext ||
  Poly1305 tag).

### AEAD: XChaCha20Poly1305

Migrated from `Aes256Gcm24` (non-standard NIST; AES-GCM nonce extension via
RustCrypto's `AesGcm<Aes256, U24>` generic) to XChaCha20Poly1305
(standardized extended-nonce AEAD via the `chacha20poly1305` crate — already
a workspace dependency).

Benefits:
- 24-byte nonce is native, not a GHASH-based extension.
- Same AEAD family as host-local — one fewer primitive to reason about.
- Removes `aes-gcm` and `pbkdf2` workspace deps entirely (smaller
  supply-chain surface).

### KDF: Argon2id via unified `Argon2Params`

Replaces `derive_package_encryption_key` (SHA-256 pre-digest + PBKDF2-600k).
New helper `derive_package_encryption_key_v2(passphrase, salt, params)`
uses the same `Argon2Params` type as B.1 — single KDF contract across the
codebase.

Defaults match B.1: `Argon2Params::default()` = m=256 MiB, t=4, p=1.

### AAD construction

```
AAD_package = b"bfrstpkg\x00"                // 10-byte domain separator
            || envelope_version:u8            // 1 byte
            || hrp_len:u8                     // 1 byte
            || hrp_utf8                       // "bfshare" | "bfprofile" | "bfonboard"
            || salt:16                        // 16 raw bytes
            || outer_id_len:u16_be            // 2 bytes; 0 if no outer id
            || outer_id_utf8                  // N bytes; empty for bfshare/bfonboard
```

- **HRP binding** defends against an attacker unwrapping a package's bech32m,
  stripping it, re-wrapping with a different HRP, and re-encoding. Without
  HRP in AAD, the MAC would still verify — the attacker could convince a
  client that a `bfshare` is a `bfprofile`.
- **Outer-id binding** (bfprofile only): `bfprofile` carries an outer hex
  prefix identifying the profile before the encrypted payload. Binding it
  to AAD prevents re-associating a ciphertext with a different profile id.
- **Salt binding** is defense-in-depth; the salt already feeds the KDF but
  binding it to AAD closes any hypothetical encode-swap attack.

### Writer / reader changes

Writer (one per package kind — `encode_bfshare_package`,
`encode_bfprofile_package`, `encode_bfonboard_package`):
- Accept `Argon2Params`; default is used if unspecified.
- Derive key via `derive_package_encryption_key_v2`.
- AEAD-encrypt with XChaCha20Poly1305, fresh random 24-byte nonce, AAD per
  the construction above.
- Emit v2 JSON envelope; bech32m-encode.

Reader (one per package kind — `decode_bfshare_package` etc.):
- Bech32m-decode to JSON.
- Parse `version` — require `2` else `PackageError::UnsupportedVersion`.
- Parse `kdf` — require `"argon2id"` else `UnsupportedKdf`.
- Parse `aead` — require `"xchacha20poly1305"` else `UnsupportedAead`.
- Parse and validate `kdf_m_cost`, `kdf_t_cost`, `kdf_p_cost` → floor/ceiling.
- Build AAD from HRP + salt + optional outer-id.
- Derive key; AEAD decrypt; propagate MAC failure.

### Hard-cut migration

- `ProtectedPackageEnvelope::version = 2` in `profile_packages.rs`.
- **No v1 reader kept.** Existing `bfprofile` / `bfshare` / `bfonboard`
  artifacts in the wild become undecodable.
- Alpha + user directive explicitly accepts this: "don't worry about
  breaking older packages."

### Removed workspace dependencies

After PR5 lands:
- `aes-gcm = "0.10"` — removed from `crates/frostr-utils/Cargo.toml`.
- `pbkdf2 = "0.12"` — removed from `crates/frostr-utils/Cargo.toml`.
- Workspace `Cargo.toml` stays clean (these weren't in `[workspace.dependencies]`).

---

## B.3 — Adversarial test coverage

### Host-local tests (in PR7, added to `crates/bifrost-profile/tests/`)

1. `decrypt_rejects_wrong_passphrase` — `StateError::Decrypt`.
2. `decrypt_rejects_corrupted_ciphertext_byte_flip` — MAC failure.
3. `decrypt_rejects_unsupported_version` — fabricate v1 envelope;
   `UnsupportedVersion(1)`.
4. `decrypt_rejects_tampered_metadata_aad` — mutate `kind` after encrypt;
   expect MAC failure (proves AAD binding is effective).
5. `decrypt_rejects_params_below_floor` — fabricate envelope with
   `m_cost=32_768`; `UnsupportedParams`.
6. `decrypt_rejects_params_above_ceiling` — `m_cost=u32::MAX`;
   `UnsupportedParams`.
7. `decrypt_rejects_short_envelope` — 20-byte blob; `Truncated`, no panic.
8. `argon2_params_round_trip` — write with `high_security()`, read back,
   confirm decrypt succeeds.
9. `aad_bytes_are_deterministic` — `build_aad_hostlocal` twice on same
   record yields identical bytes; differs when `kind` changes.
10. `aad_rejects_interior_nul` — record with `kind = "a\x00b"` →
    `InvalidMetadata`.

### Portable package tests (in PR5, added to `crates/frostr-utils/tests/`)

Same shape, adapted to the package envelope:

1. `decode_rejects_wrong_password` — `PackageError::Decrypt`.
2. `decode_rejects_corrupted_ciphertext_byte_flip`.
3. `decode_rejects_unsupported_version` — fabricate v1 JSON; `UnsupportedVersion`.
4. `decode_rejects_unsupported_kdf` — `"kdf": "pbkdf2"`; `UnsupportedKdf`.
5. `decode_rejects_unsupported_aead` — `"aead": "aes-256-gcm-24"`;
   `UnsupportedAead`.
6. `decode_rejects_hrp_swap` — encode `bfshare`, mutate the bech32m HRP to
   `bfprofile`; expect MAC failure on decrypt (proves HRP binding).
7. `decode_rejects_params_below_floor`.
8. `decode_rejects_params_above_ceiling`.
9. `argon2_params_round_trip` — encode with `high_security()`, decode.
10. `aad_rejects_interior_nul_in_outer_id` — bfprofile with
    `outer_id = "a\x00b"`; `InvalidMetadata`.

### KATs (pinned fixtures in PR5)

Three pinned vectors at the **bech32m-string layer**:

1. **bfshare KAT** — fixed password, salt, nonce, plaintext. Asserts
   `encode_bfshare_package` produces the exact bech32m string and
   `decode_bfshare_package` round-trips.
2. **bfprofile KAT** — same shape, covers the outer hex prefix path.
3. **bfonboard KAT** — same shape, onboarding package path.

KATs pinned after PR5's migration — they capture the new Argon2id +
XChaCha20Poly1305 scheme, not the old PBKDF2 + AES-GCM one. Old-scheme
KATs are not needed since the old scheme is being retired.

---

## Documentation updates (land alongside PR5 and PR7)

### `/home/cscott/Repos/frostr/frostr-infra/docs/CRYPTOGRAPHY.md`

Two new sections:

**"Host-Local Encrypted Profile Envelope v2"**
- Byte layout diagram
- `kdf_id` semantics
- Argon2id parameters (defaults, floor, ceiling)
- AAD construction
- Error taxonomy
- Reference to `crates/bifrost-profile/tests/` for KATs

**"Portable Package Encryption v2"**
- Outer format (bech32m + JSON)
- KDF (Argon2id, same `Argon2Params` as host-local)
- AEAD (XChaCha20Poly1305)
- AAD construction (including HRP binding)
- Error taxonomy
- Reference to `crates/frostr-utils/tests/package_kats.rs`

### `/home/cscott/Repos/frostr/frostr-infra/docs/BACKUP.md`

Expand the existing envelope section. Cross-link both new `CRYPTOGRAPHY.md`
sections. Remove language that refers to PBKDF2 / AES-GCM for portable
packages — that scheme is retired.

### `/home/cscott/Repos/frostr/frostr-infra/docs/ONBOARD.md`

If it currently mentions the `bfonboard` envelope format, update to the v2
description.

---

## Critical Files

Modify:
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/lib.rs` (`ENCRYPTED_PROFILE_VERSION` bump, export new types)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/native.rs` (new envelope, new error variants, `Argon2Params`, `build_aad_hostlocal`, `derive_profile_encryption_key_v2`, migrated writer/reader)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/Cargo.toml` (no new deps)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/frostr-utils/Cargo.toml` (remove `aes-gcm = "0.10"` and `pbkdf2 = "0.12"`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/frostr-utils/src/profile_packages.rs` (replace KDF, replace AEAD, new envelope shape, new AAD, migrated encode/decode for all three package kinds, bump `ProtectedPackageEnvelope::version`, remove old helpers `derive_package_encryption_key` + `Aes256Gcm24` type + PBKDF2 imports)
- `/home/cscott/Repos/frostr/frostr-infra/docs/CRYPTOGRAPHY.md` (two new sections)
- `/home/cscott/Repos/frostr/frostr-infra/docs/BACKUP.md` (update; retire PBKDF2/AES-GCM language)
- `/home/cscott/Repos/frostr/frostr-infra/docs/ONBOARD.md` (if affected)

Add:
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/tests/encryption_v2.rs` (B.3 host-local tests)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/frostr-utils/tests/package_v2.rs` (B.3 portable adversarial tests)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/frostr-utils/tests/package_kats.rs` (three bech32m-string-layer KATs)

Reuse (do not re-invent):
- `chacha20poly1305` crate (already a workspace dep) — used by both schemes.
- `argon2` crate (already present at version 0.5) — used by both schemes.
- Existing `EncryptedProfileRecord` struct and metadata JSON layout — field
  names unchanged; only the `.enc` binary layout changes.
- Existing bech32m wrapping + HRP routing — only the inner JSON envelope
  shape changes.

Callers that need no change but must be re-tested:
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/native.rs` — `import_profile_from_files`, `import_profile_from_payload`, `finalize_onboarding_import` (all call `store_encrypted_profile` with default params).
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/native_runtime.rs` — decrypt path on profile load (will receive new error variants).
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile-wasm/src/lib.rs` — WASM exports for `encode_*_package` / `decode_*_package`; re-exports the new Rust implementation, no direct code changes but must re-test.
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/` — any caller that pattern-matches on old stringly-typed decrypt errors. Audit with
  `rg 'unsupported encrypted profile version|unsupported package' repos/igloo-shell/`.

## Verification

Per PR:

**PR5 (B.2 portable package migration):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs
cargo check --workspace --offline
cargo test -p frostr-utils --offline
cargo test -p bifrost-profile-wasm --offline  # WASM re-exports still compile
cargo clippy -p frostr-utils --all-targets --offline --no-deps -- -D warnings
cargo fmt --all -- --check
```
Plus:
- All 10 adversarial tests from B.3 portable-package pass.
- Three KATs pin the new bech32m strings.
- `rg 'aes-gcm|Aes256Gcm|pbkdf2|derive_package_encryption_key[^_]' repos/bifrost-rs/crates/` returns no production matches (test fixtures may keep the names for v1 reject-tests).
- `grep -E 'aes-gcm|pbkdf2' repos/bifrost-rs/crates/frostr-utils/Cargo.toml` empty.

**PR6 (B.1 primitives, crate-internal):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs
cargo test -p bifrost-profile --offline
cargo clippy -p bifrost-profile --all-targets --offline --no-deps -- -D warnings
cargo fmt --all -- --check
```
Internal unit tests for `Argon2Params`, `build_aad_hostlocal`, and param
floor/ceiling validation pass.

**PR7 (B.1 cutover + B.3 host-local tests):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs
cargo test --workspace --offline
cargo clippy --workspace --all-targets --offline --no-deps -- -D warnings
cargo fmt --all -- --check
```
Plus:
- All 10 adversarial tests from B.3 host-local pass.
- `rg 'ENCRYPTED_PROFILE_VERSION' repos/bifrost-rs/crates/` shows value 2 only.
- `rg 'Argon2::default\(\)' repos/bifrost-rs/crates/` returns no production matches.
- Manual smoke against the demo harness:
  ```bash
  cd /home/cscott/Repos/frostr/frostr-infra
  make demo-start
  make demo-onboard
  make demo-smoke
  make demo-stop
  ```
  Confirms onboard → import → persist → restart → decrypt works on the new envelope.

**Full-bucket verification (after PR5 + PR7, alongside Bucket A PR2):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```

## Cross-Repo Coordination

All three PRs ship in the **same release window** as Bucket A PR2.
Rationale: three independent version bumps, one operator migration.

| Version | Previous | New |
|---|---|---|
| `DeviceState::VERSION` (Bucket A) | 5 | 6 |
| `ENCRYPTED_PROFILE_VERSION` (B.1) | 1 | 2 |
| `ProtectedPackageEnvelope::version` (B.2) | 1 | 2 |

Operational requirements:
- Release notes must call out: "Upgrading requires re-onboarding all
  profiles. Existing `.enc` files, `signer-state.bin` files, and bech32m
  packages are not readable by this version."
- No in-place migration tool for any of the three. Hard-cut by design.
- Document the new crypto defaults in the release notes: Argon2id m=256 MiB
  / t=4 / p=1, XChaCha20Poly1305, AAD binding.

Downstream submodules affected:
- `igloo-shell` — pattern-matches on decrypt errors; must handle new typed
  variants. Also calls `encode_bfshare_package` / `encode_bfprofile_package`
  during onboarding — must re-test end-to-end.
- `igloo-home` — same error-taxonomy concern (see `dev/audit/igloo-home-audit-2026-04-22.md` finding 9 — stringly-typed errors regex-matched on the TS side; this is an on-ramp to proper typed error transport in Bucket E).
- `igloo-pwa` / `igloo-chrome` — call `encode_*_package` / `decode_*_package`
  via WASM exports. Behavior is byte-different (new v2 envelope); must
  re-test demo harness end-to-end.
- `igloo-shared` — WASM-adjacent wiring; no direct code change but must
  re-test through the browser demo lane.

Per `/home/cscott/Repos/frostr/frostr-infra/dev/docs/RELEASE.md` coordinated
release process.

## Out-of-Bucket Flags

- **Session-scoped KDF cache** — each decrypt re-runs Argon2 at ~400–600 ms
  on the new defaults. Legitimate UX concern. Flag for **Bucket C**
  (host-local secret hygiene + unlock-session lifecycle).
- **Typed error transport across Tauri IPC** — `igloo-home` frontend
  regex-matches on error strings (audit finding 9). New typed error
  variants from B.1/B.2 are a natural on-ramp for proper typed-error
  transport; **Bucket E** owns that work.
- **WASM-side native JS mirror of either encryption scheme** — not needed
  today, all JS calls go through WASM re-exports. Out of scope; no flag
  needed.

## Summary

Three PRs, ~1,800 lines, all in `bifrost-rs`. Strong, secure defaults
unified across both encryption schemes:

- **Argon2id**, m=256 MiB / t=4 / p=1 default, m=64 MiB / t=3 / p=1 floor,
  1 GiB ceiling. Same `Argon2Params` struct serves both schemes.
- **ChaCha20Poly1305** for host-local `.enc` files (unchanged).
- **XChaCha20Poly1305** for portable bech32m packages (migrated from
  non-standard `Aes256Gcm24`).
- **AAD binding** for both: domain-separated, length-prefixed,
  interior-NUL-rejected. Binds the envelope to metadata that shouldn't be
  swapped.
- **Hard-cut** version bumps on both schemes. Alpha + user directive.
  Coordinated release with Bucket A's `DeviceState::VERSION` 5→6.
- **NIP-44 paths untouched** — peer messaging, profile-backup relay events,
  and onboarding request/response all preserve their wire bytes via Bucket
  A's A.5 consolidation.
- **Crate surface shrinks**: `aes-gcm` and `pbkdf2` removed from
  `frostr-utils`. One AEAD family across the codebase.
- **Test coverage**: 20 new adversarial tests (10 per scheme) plus 3 KAT
  fixtures for portable packages. Host-local tests cover wrong passphrase,
  byte-flip, version mismatch, AAD tampering, params floor/ceiling, short
  envelope, params round-trip, deterministic AAD, interior-NUL. Portable
  tests add HRP-swap detection and KDF/AEAD marker rejection.
- **Docs**: `docs/CRYPTOGRAPHY.md` gets two new canonical sections
  (host-local v2, portable v2). `docs/BACKUP.md` updated to retire old
  language.
