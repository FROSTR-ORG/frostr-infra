# `bifrost-rs` audit

Date: 2026-06-13

Scope: `repos/bifrost-rs` (all 11 workspace crates; no WASM build artifacts audited)

`bifrost-rs` is the Rust signing core for FROSTR: it implements threshold FROST signing, NIP-44 encrypted messaging, host orchestration, and bridge runtimes for both browser WASM and Tokio. Compared with the 2026-04-22 audit, the remediation work has been thorough where it landed — secret newtypes are zeroizing and constant-time, NIP-44 is consolidated, MAC comparisons use `subtle::ct_eq`, file store encryption is in place, and daemon token generation is now random. The remaining debt clusters around three themes: one oversized module that hasn't been decomposed yet, tooling seams (CI yaml, devtools) that haven't kept pace with production remediation, and public surfaces that lack rustdoc.

## Findings

### 1. High: `bifrost-signer/src/lib.rs` is a 4554-line god file

Rule: `ARC-01` (architecture)

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs:1-4554`

Why this matters:
- The file mixes at least five distinct responsibilities: device state types (`DeviceState`, `DeviceSecrets`, `DeviceStatePersisted`), the `SigningDevice` struct lifecycle (`new`, `init`, `apply`), protocol operation initiation (`initiate_sign`, `initiate_ecdh`, `initiate_ping`, `initiate_onboard`), peer selection and readiness computation, and an inline 1700-line test suite — all in one translation unit.
- Navigating or modifying a single responsibility (e.g. peer-selection policy) requires reasoning about the entire file's invariants. The CLAUDE.md comment that "peer/readiness computation should exist in one place" acknowledges the tension but hasn't yet produced a boundary.

Smells:
- Single file exceeds 4 × the ARC-01 threshold (800 LOC) with no module hierarchy.
- Inline `#[cfg(test)] mod tests` block at ~1700 lines — nearly a second file's worth — lives at the bottom of a 4554-line file, making test/production boundaries hard to see.

Streamline:
- Decompose into sub-modules: state types (`state.rs`), operation initiators (`ops.rs`), peer/readiness logic (`readiness.rs`), and a thin `lib.rs` re-exporting the public surface.
- Move the inline test module to a dedicated `tests/` directory or at minimum to a `#[path]`-ed `tests.rs` alongside.

### 2. High: CI workflow references nonexistent crates (`bifrost-node`, `bifrost-transport-ws`, `bifrost-dev`)

Rule: `DOC-02` (documentation — README/CI drift)

Files:
- `repos/bifrost-rs/.github/workflows/ci.yml` (test-node job: `cargo test -p bifrost-node`; test-ws job: `cargo test -p bifrost-transport-ws`; runtime-regressions job: uses `bifrost-dev`)

Why this matters:
- The workspace has 11 crates; none is named `bifrost-node`, `bifrost-transport-ws`, or `bifrost-dev`. The CI jobs that reference these crates will fail silently or be permanently skipped, meaning the test surface described in CI yaml no longer exists.
- A contributor following CI output or adding coverage will mis-target effort toward nonexistent crates.

Smells:
- Job names describe test intent but `cargo test -p <missing-crate>` will error, making the intent invisible in practice.
- No comment in the workflow explaining that these jobs were retired or renamed.

Streamline:
- Remove or replace each job that references a retired crate with the current equivalent (or a `# retired` note with the replacement crate name).
- Add a workspace-level `cargo test --workspace` job as a backstop to catch future crate renames.

### 3. Medium: `Argon2Params` duplicated across `frostr-utils` and `bifrost-profile`

Rule: `ARC-05` (architecture — deliberate duplication without a deprecation/resolution plan)

Files:
- `repos/bifrost-rs/crates/frostr-utils/src/argon2_params.rs:1-end`
- `repos/bifrost-rs/crates/bifrost-profile/src/argon2_params.rs:1-end`

Why this matters:
- Both files implement identical `Argon2Params` types with matching defaults, floor, and ceiling. The source comment in `frostr-utils` says the duplication is deliberate due to a dependency cycle (`bifrost-profile` depends on `frostr-utils`) and that changes must be kept in lockstep.
- "Must be kept in lockstep" is a manual process that audits cannot verify. A divergence in KDF parameters between WASM (uses `frostr-utils`) and native (uses `bifrost-profile`) would be a silent crypto inconsistency across platforms.

Smells:
- Comment explicitly names the lockstep requirement — meaning the coupling is known and unresolved.
- Two modules with identical constants, validation logic, and doc comments maintained by convention alone.

Streamline:
- Investigate whether the cycle can be broken by extracting `Argon2Params` into a third, zero-dependency crate (e.g. `bifrost-types` or a thin `bifrost-kdf-params` crate) that both `frostr-utils` and `bifrost-profile` can depend on.
- Until resolved, add a `#[cfg(test)]` assertion in at least one crate that deserialization of the other's serialized defaults produces equal values.

### 4. Medium: `bifrost-router` and `bifrost-bridge-tokio` have zero rustdoc on their public surfaces

Rule: `DOC-01` (documentation — undocumented public surface)

Files:
- `repos/bifrost-rs/crates/bifrost-router/src/lib.rs:1-1020` (1020 lines, 0 `///` lines)
- `repos/bifrost-rs/crates/bifrost-bridge-tokio/src/lib.rs:1-867` (867 lines, 0 `///` lines)

Why this matters:
- `bifrost-router` exports `BridgeCore`, `BridgeCommand`, `RouterPort`, `BridgeConfig`, and the top-level `run` / command dispatch surface — the integration boundary that hosts wire into.
- `bifrost-bridge-tokio` exports `Bridge`, `BridgeConfig`, `RelayAdapter`, `BridgeError`, `SignResult`, `EcdhResult` — the Tokio runtime entry points for all hosted signers.
- A caller must read hundreds of lines of implementation to understand how to use either crate correctly. Neither documents its failure modes, expected call ordering, or secret-handling obligations.

Smells:
- `grep -c "///" crates/bifrost-router/src/lib.rs` returns 0.
- `grep -c "///" crates/bifrost-bridge-tokio/src/lib.rs` returns 0.

Streamline:
- Add `///` doc comments on every public struct, trait, and `pub fn` in both crates, at minimum covering purpose, key invariants, and failure modes.
- Enable `#![warn(missing_docs)]` in each crate's `lib.rs` so future additions are caught by the compiler.

Cross-repo note: the pattern of zero rustdoc on bridge/router integration surfaces likely appears in `igloo-shared` TypeScript as well. Mirror into NOTES.md.

### 5. Medium: KDF return value (`derive_profile_encryption_key_v2`) is a plain `[u8; 32]` with caller-zeroize contract

Rule: `SEC-01` (security — secret material lifecycle)

Files:
- `repos/bifrost-rs/crates/bifrost-profile/src/kdf.rs` (function signature and doc comment)
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:599-601` (call site)

Why this matters:
- `derive_profile_encryption_key_v2` returns a bare `[u8; 32]`. The doc comment says "The returned key must be zeroized by the caller," but at the call site in `native.rs` the array is passed directly into `ChaCha20Poly1305::new((&key).into())` without wrapping it in a `ZeroizeOnDrop` type first. If the compiler inlines or reorders the intermediate, the 32 key bytes may remain on the stack after the cipher is constructed.
- The fix applied to other secrets in this codebase (newtype + `ZeroizeOnDrop`) was not extended to the KDF output, leaving an inconsistency in the secret lifecycle model.

Smells:
- A "caller must zeroize" comment on a security-critical return value is a memory-safety contract enforced only by convention.
- The rest of the codebase uses newtypes for this purpose; this function stands out.

Streamline:
- Return a newtype (e.g. `DerivedKey([u8; 32])`) that is `ZeroizeOnDrop`, eliminating the caller contract and making the drop implicit.
- Alternatively, accept a `&mut [u8; 32]` output buffer owned by a `Zeroizing<[u8; 32]>` at the call site.

### 6. Medium: Encrypted device state file written without mode hardening

Rule: `SEC-06` (security — file/scratch permissions)

Files:
- `repos/bifrost-rs/crates/bifrost-app/src/runtime/store.rs:183` (`write_bytes_atomic` using `File::create`)
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs` (comparison: uses `write_restricted_bytes_atomic(..., 0o600)`)

Why this matters:
- The encrypted device state file is written with `File::create`, which inherits the process umask. On a system with a permissive umask (e.g. 0o022 → 0o644 result), the encrypted state file is world-readable.
- `bifrost-profile` already has `write_restricted_bytes_atomic` that enforces 0o600 on ciphertext files. The same discipline is absent from the app-layer state store.

Smells:
- `File::create` used for a secret-bearing ciphertext file in a crate that has access to the restricted-write helper.
- Inconsistency between `bifrost-profile` (hardened) and `bifrost-app` (umask-dependent) for the same security property.

Streamline:
- Replace `File::create` in `write_bytes_atomic` with the same `write_restricted_bytes_atomic(..., 0o600)` pattern used in `bifrost-profile/src/native.rs`.
- Add a test or comment confirming that the state store directory is also created with `ensure_dir_restricted(..., 0o700)`.

### 7. Medium: Devtools passes vault passphrase via inheritable environment variable

Rule: `SEC-05` (security — IPC/daemon authentication)

Files:
- `repos/bifrost-rs/crates/bifrost-devtools/src/e2e.rs:197` (`command.env("IGLOO_SHELL_TEST_PASSPHRASE", &self.passphrase)`)

Why this matters:
- `IGLOO_SHELL_TEST_PASSPHRASE` is set on a `Command` and therefore appears in `/proc/<pid>/environ` on Linux, is visible to any process sharing the UID, and is inherited by any child of the test binary.
- The production code remediated this in the C.5 pass: `native_runtime.rs` comments (lines 556–561) explicitly document that the env-var passphrase path was removed from production. Devtools retained it, creating a split where the hardening was applied to production but not to the orchestration layer that exercises it in CI.

Smells:
- `command.env("IGLOO_SHELL_TEST_PASSPHRASE", ...)` passes a plaintext secret through an inheritable environment slot.
- Production and devtools use different passphrase-delivery mechanisms for the same subsystem, so devtools does not validate the hardened path.

Streamline:
- Deliver the test passphrase through the same out-of-band channel used by the production path (e.g. a temporary file with restricted permissions, or a control-socket message), so devtools tests exercise the remediated channel.
- Document why the env-var path is acceptable in the devtools context if it is retained (e.g. test-only, ephemeral credential), and gate it with a `#[cfg(test)]` or `#[cfg(feature = "devtools")]` guard.

### 8. Medium: FROST signing tests are verify-roundtrips only — no pinned KAT vectors

Rule: `TST-03` (testing — missing KAT/property tests at the crypto layer)

Files:
- `repos/bifrost-rs/crates/bifrost-core/tests/frost_sign_roundtrip.rs` (comment: "These are *verify-roundtrip* tests, not pinned known-answer vectors")

Why this matters:
- The FROST signing core has tests that generate keys, sign, and verify within the same process. They confirm internal consistency but will pass for any self-consistent implementation — including a subtly wrong one that deviates from the BIP-340/FROST spec.
- The comment in the test file explicitly acknowledges the gap: keygen and nonce generation use `OsRng` with no deterministic seam, so cross-implementation agreement cannot be checked.
- FROST is the core security guarantee of FROSTR; a deviation that passes roundtrip but fails against a reference implementation would be caught only in production.

Smells:
- Comment in the test file explicitly names the limitation ("not pinned known-answer vectors").
- `OsRng` used with no option to inject a deterministic seed, making KAT addition architecturally blocked until a seam is added.

Streamline:
- Introduce a deterministic seed path in the FROST keygen/nonce layer (feature-gated or test-only) so that known-answer vectors from the FROST reference implementation (or BIP-340 test vectors) can be pinned.
- Add at least one KAT sourced from an independent implementation for each of: key generation, round-1 nonce commitment, and signature aggregation.

Cross-repo note: the absence of crypto KAT vectors may extend to NIP-44 test vectors in `bifrost-core::nip44`; verify separately. Mirror into NOTES.md.

### 9. Low: Version-suffixed test file names without a documented removal trigger

Rule: `LEG-02` (legacy — version-suffixed parallel implementations)

Files:
- `repos/bifrost-rs/crates/bifrost-app/tests/run_marker_v2.rs`
- `repos/bifrost-rs/crates/bifrost-profile/tests/encryption_v2.rs`
- `repos/bifrost-rs/crates/frostr-utils/tests/package_v2.rs`

Why this matters:
- Filenames with `_v2` suffixes imply a `_v1` predecessor. Without a comment naming what `v1` was and confirming it was removed, a future reader cannot tell whether the suffix is a living parallel or a legacy artifact that can be renamed.
- The production code does not use version-suffix naming (e.g. `health.rs` uses `RUN_MARKER_VERSION = 2` as an internal constant without suffixing the module name).

Smells:
- `_v2` in a test filename with no `_v1` counterpart visible and no comment explaining the suffix.
- Inconsistency between module naming convention (no suffix) and test file naming (suffixed).

Streamline:
- If `v1` is gone, rename the test files to drop the suffix (e.g. `run_marker_v2.rs` → `run_marker.rs`) and update the test function names to match.
- If the suffix is meaningful (e.g. testing format version 2 alongside format version 1 interop), add a comment explaining that.

### 10. Low: `CHANGELOG.md` has a perpetual `[Unreleased]` block with no content

Rule: `DOC-06` (documentation — changelog/version hygiene)

Files:
- `repos/bifrost-rs/CHANGELOG.md`

Why this matters:
- The changelog has `## [Unreleased]` as its only non-boilerplate entry with no items under it. A downstream consumer (e.g. an `igloo-*` submodule bump) cannot determine what changed between workspace versions.
- Coordinated releases across the `igloo-*` family require a changelog that a human reviewer can follow.

Smells:
- First entry in the changelog is `[Unreleased]` with no content.
- No versioned entries recording the substantial changes made since the previous audit (secret newtypes, NIP-44 consolidation, KDF hardening, daemon token remediation).

Streamline:
- Populate `[Unreleased]` with the changes in flight, and backfill at least one prior versioned entry capturing the 2026-Q1/Q2 security hardening pass so the history is traceable.

### 11. Low: Inconsistent vocabulary for FROST co-signers ("peer" / "member" / "node")

Rule: `RS-01` (readability — naming and vocabulary)

Files:
- `repos/bifrost-rs/crates/bifrost-signer/src/lib.rs` (`peer_status`, `PeerStatus`, `select_peers`)
- `repos/bifrost-rs/crates/bifrost-core/` (uses "member" in some type/comment contexts)
- `repos/bifrost-rs/crates/bifrost-router/src/lib.rs` (uses "node" in command names)

Why this matters:
- The same concept — another FROST co-signer participating in a threshold group — is called "peer", "member", and "node" in different parts of the codebase. A new contributor cannot immediately know whether these refer to the same entity or distinct roles.
- Vocabulary inconsistency increases the cognitive load when reading cross-crate code and makes grep-based navigation unreliable.

Smells:
- `peer_status` / `PeerStatus` / `select_peers` in `bifrost-signer` vs. "member" in `bifrost-core` type comments vs. "node" in router command names.
- No glossary or doc comment establishing the canonical term.

Streamline:
- Pick one term for the concept of a remote FROST co-signer and use it consistently across type names, function names, and doc comments throughout the workspace.
- Document the chosen term in `CLAUDE.md` or `README.md` so it is enforced by convention.

## Summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 6 |
| Low | 3 |
| **Total** | **11** |
