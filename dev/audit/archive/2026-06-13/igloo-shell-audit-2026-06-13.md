# `igloo-shell` audit

Date: 2026-06-13

Scope: `repos/igloo-shell` (full Rust CLI operator host, both crates)

`igloo-shell` is the CLI-first operator host for FROSTR. It manages local
profiles, encrypted profile storage, per-profile daemons, and the full
operator package-flow surface (onboard, import, rotate-key, rotate-keyset,
keygen, recover-key, export). The codebase is well-structured: a thin
`igloo-shell-cli` crate wires the clap surface, and `igloo-shell-core` owns
the storage, daemon, and rotation logic behind a clean module split. Bucket C
secret-hygiene work is evident throughout — passphrase zeroization, 0o600 file
perms, OsRng daemon tokens, stdin-pipe delivery — and the integration test
coverage is broad and behavioral (not render-only). The remaining debt is
concentrated in three areas: an exported function that has no live callers
(LEG/CQ), a triplicate internal helper (ARC/CQ), and an `unsafe env::set_var`
whose rationale is not documented at the call site (SEC). The testing domain is
clean apart from the absence of adversarial crypto/input tests for the
rotation path.

## Findings

### 1. Medium: `resolve_profile_runtime` exported but never called outside its definition module

Rule: `LEG-04` (Legacy & deprecation)

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:30-63`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell.rs:71`

Why this matters:
- `resolve_profile_runtime` (the passphrase-free overload of
  `resolve_profile_runtime_for_passphrase`) is re-exported from `shell.rs` and
  visible to every crate that depends on `igloo-shell-core`, but a grep across
  all crates finds no call sites outside the definition. The only callers in
  the CLI layer use `resolve_profile_runtime_for_passphrase` exclusively.
- A public export with no callers implies the function is either dead code or
  was kept for a consumer that no longer exists. Future changes to the
  passphrase model may keep it in sync only through the active path, letting the
  dead export quietly diverge.

Smells:
- Two public functions with nearly identical bodies (lines 30–63 and 65–97)
  where one is unused. The body duplication is a maintenance hazard even before
  the dead-code concern.
- `shell.rs:71` re-exports both variants side-by-side with no comment
  distinguishing their contract.

Streamline:
- Verify no external consumer calls `resolve_profile_runtime`. If confirmed
  dead, delete it and the re-export entry. If a consumer is intended (e.g.,
  for unencrypted legacy profiles), document the use-case and the migration
  trigger that would retire the no-passphrase path.

---

### 2. Medium: `profile_domain` helper duplicated in three sibling modules

Rule: `ARC-05` (Architecture & boundaries)

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/onboarding.rs:5-13`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/profiles.rs:19-28`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/shared.rs:5-13`

Why this matters:
- All three modules independently define a private `fn profile_domain(paths:
  &ShellPaths) -> FilesystemProfileDomain` with the same six-argument
  constructor. The body is identical in each.
- If the `FilesystemProfileDomain` constructor signature or the path fields it
  reads ever change, three separate sites must be updated in sync. The Rust
  type system will catch a signature mismatch but not a semantically wrong
  path wiring.

Smells:
- Three `fn profile_domain` definitions within the same Rust module tree, with
  the same body and no doc comment explaining why each copy exists rather than
  calling a shared version.
- `shared.rs` already exists as the module for shared helpers — the function
  belongs there, but `profiles.rs` and `onboarding.rs` each carry their own
  copy rather than calling it.

Streamline:
- Promote one definition to `shared.rs`, expose it `pub(crate)`, and delete
  the two copies in `onboarding.rs` and `profiles.rs`.

---

### 3. Medium: `unsafe env::set_var` in `configure_trace_env` without thread-safety rationale

Rule: `SEC-07` (Defence-in-depth at the shell boundary)

Files:
- `repos/igloo-shell/crates/igloo-shell-cli/src/main.rs:672-680`

Why this matters:
- `std::env::set_var` is marked `unsafe` in Rust 2024 because concurrent
  access to the environment from multiple threads can produce undefined
  behaviour. `configure_trace_env` is called in `main` before the Tokio
  multi-thread runtime is started — but there is no comment at the call site
  documenting that invariant, so a future refactor that moves tracing init
  later (e.g., inside an async block after `#[tokio::main]` runs) would
  silently become unsafe without any compiler or reviewer warning.
- The umask `unsafe` block directly above (line 574) carries an explicit
  SAFETY comment explaining why it is safe; the `set_var` block does not.

Smells:
- `unsafe { std::env::set_var(...) }` with no `// SAFETY:` comment, unlike the
  neighbouring umask block which has one.
- No assertion or documentation that this code runs before any thread is
  spawned.

Streamline:
- Add a `// SAFETY:` comment mirroring the umask pattern: state explicitly that
  this call is in `main` before the Tokio executor spawns any threads.
  Alternatively, switch to `EnvFilter::from_env` / `tracing_subscriber`
  builder rather than mutating `RUST_LOG` directly.

---

### 4. Medium: `resolve_profile_runtime` body duplicates `resolve_profile_runtime_for_passphrase`

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:30-97`

Why this matters:
- The two functions share six of seven logical steps (read profile → read relay
  profile → read group → load share → parse group + share → resolve peers +
  options → return `ResolvedAppConfig`). The only difference is whether
  `load_share_payload` or `load_share_payload_with_passphrase` is called.
- Any logic change to the resolution path (e.g., new AppOptions parsing, new
  peer-override resolution) must be applied to both copies. The duplication is
  already live: the `resolve_profile_runtime` variant lacks the `Ok(())` blank
  line between the `let options:` block and the final `Ok((profile.clone(), ...))`
  that `_for_passphrase` has.

Smells:
- Near-identical 30-line function bodies, differing only in one method call at
  line 39 vs 74.
- No factoring or comment explaining why two paths exist instead of one with an
  `Option<&Passphrase>` parameter (which `resolve_profile_runtime_for_passphrase`
  already accepts, accepting `None`).

Streamline:
- Delete `resolve_profile_runtime` and replace the one expected caller (if it
  exists) with `resolve_profile_runtime_for_passphrase(paths, id, None)`. The
  `_for_passphrase` variant already handles the `None` case via
  `load_share_payload_with_passphrase`.

---

### 5. Low: No `rustfmt.toml` to gate formatting in CI

Rule: `AES-06` (Aesthetics & formatting — no enforced formatter)

Files:
- `repos/igloo-shell/` (repo root; no `.github/` CI directory present)
- `repos/igloo-shell/TESTING.md:10` (mentions `cargo fmt --all -- --check`)

Why this matters:
- `TESTING.md` tells contributors to run `cargo fmt --check` before pushing, but
  there is no CI workflow file to enforce it automatically. Without a gate, the
  manual step is easy to skip, and formatting debates live in code review instead
  of tooling.
- There is also no `rustfmt.toml`; any per-repo style preferences (e.g.,
  import grouping, max width) must be re-communicated in reviews.

Smells:
- No `.github/workflows/` or equivalent CI directory in the repo.
- `cargo fmt` is documented as a manual step only.

Streamline:
- Add a CI workflow (or confirm the workspace-level CI covers this repo) that
  runs `cargo fmt --all -- --check` and `cargo clippy` as a blocking gate.

---

### 6. Low: Adversarial paths for `rotate-keyset generate` are not unit-tested

Rule: `TST-02` (Testing — happy-path-only coverage)

Files:
- `repos/igloo-shell/crates/igloo-shell-cli/tests/utility_integration.rs:393-451`
  (covers `rotate-key` negative paths)
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/rotation.rs:365-568`

Why this matters:
- `rotate-keyset generate` is the highest-value operator flow: it derives a
  fresh keyset from threshold shares, emits encrypted `bfonboard` packages, and
  atomically replaces the local profile. Its adversarial paths (wrong source
  passwords, mismatched group, duplicate member index, threshold not met) are
  validated only via guard clauses and `bail!` in the core, but there are no
  integration tests that feed them wrong input and assert the correct error
  message and clean rollback (e.g., that no new profile is written on failure).
- `utility_integration.rs` has a `rotate_key_rejects_wrong_secret_…` test for
  the simpler `rotate-key` command, but the more complex `rotate-keyset generate`
  path has no corresponding negative-path counterpart.

Smells:
- The integration test for `rotate-keyset init` + `generate` in
  `managed_integration.rs:117-287` only exercises the golden path; the test
  comment on line 188 moves straight to "generate" without any wrong-password
  or mismatched-group case.
- `rotation.rs:380-389` validates workspace readiness and source password count
  but these guards are exercised only implicitly.

Streamline:
- Add a `rotate_keyset_generate_rejects_wrong_source_password` test (wrong
  password on one source bfshare) and a `rotate_keyset_generate_rejects_mismatched_group`
  test that confirms the invariant check at `rotation.rs:403-408` fires and
  leaves the local profile unchanged.

---

### 7. Low: Public exports from `igloo-shell-core` lack doc comments

Rule: `DOC-01` (Documentation — undocumented public surface)

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:30-97` (two
  exported `resolve_profile_runtime*` functions, no `///`)
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/checks.rs:58-251`
  (`test_relay_connectivity`, `check_profile_runtime`, no `///`)
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/rotation.rs:82-121`
  (`apply_rotation_update_from_bfonboard_value`, no `///`)

Why this matters:
- `igloo-shell-core` re-exports a large public surface (the `pub use` block in
  `shell.rs` runs to ~40 entries). A consumer reading `cargo doc` sees function
  names but no description of caller contract, failure modes, or passphrase
  expectations. `build_daemon_transport` is the only function in `daemon.rs`
  with a doc comment.
- The functions that deal with secret material are the most important ones to
  document: what the caller must supply, whether `None` passphrase implies
  plaintext profile, and what errors to expect.

Smells:
- Majority of exported `pub fn` and `pub async fn` entries in `daemon.rs`,
  `checks.rs`, and `rotation.rs` have no `///` comment.
- Contrast with the in-line `// Bucket C C.x` prose annotations (useful for
  auditors but not surfaced as `cargo doc`).

Streamline:
- Add `///` doc comments to at minimum the exported functions that accept a
  `passphrase: Option<&Passphrase>` parameter, documenting whether `None`
  implies a plaintext fall-through, and the failure modes callers should match
  on.

## Summary

| Severity | Count |
|---|---|
| High | 0 |
| Medium | 4 |
| Low | 3 |
| **Total** | **7** |
