# `igloo-shell` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell`

This audit focused on on-disk secret handling, the CLI attack surface, daemon lifecycle, and the cross-repo contract with the signer runtime in `bifrost-rs`. The primary pattern is that `igloo-shell` has a clean per-command surface but leans on the default process umask for every file it creates, publishes a predictable daemon-auth token alongside a world-permissioned Unix socket, and passes profile passphrases across process boundaries via environment variables. On-disk encryption itself is AEAD with a per-record salt and nonce, but the KDF parameters and the absence of any mode/permission hardening are weaker than the threat model this host implies.

## Findings

### 1. High: encrypted-profile records and all shell state inherit the default umask with no mode hardening

Files:
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:432-467`
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:545-551`
- `repos/bifrost-rs/crates/bifrost-profile/src/paths.rs:60-75`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/io.rs:15-21`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:124-154`

Why this matters:
- `FilesystemEncryptedProfileStore::store_encrypted_profile` writes ciphertext with plain `fs::write`, never chmod'd to `0o600`.
- `ProfilePaths::ensure()` creates `config_dir`, `profiles_dir`, `groups_dir`, `encrypted_profiles_dir`, `state_profiles_dir`, `rotations_dir`, and `imports_dir` with `create_dir_all`; no `PermissionsExt::set_mode(0o700)` anywhere.
- `write_json` used for profile manifests, daemon metadata, relay profiles, and staged onboarding imports also uses default umask.
- The daemon log is opened with `OpenOptions::new().create(true).append(true)`; tracing output from the signer runtime lands in a file whose default mode is `umask`-derived.
- Taken together, any user on the machine with a permissive system umask (022, typical on multi-user servers) sees ciphertext envelopes, daemon tokens, socket paths, profile manifests, and nonce-pool state files as world-readable.

Smells:
- Encryption is the only line of defence for share secrets, but other host-controlled confidentiality (socket auth tokens, nonce-pool snapshots) sits in world-readable files.
- No `#[cfg(unix)]` block attempts mode hardening; the Unix-only code paths already exist elsewhere in the crate.

Streamline:
- Make `ProfilePaths::ensure()` chmod each directory `0o700` on Unix.
- Add a Unix-only post-write step in `store_encrypted_profile` / `write_encrypted_profile` / `write_daemon_metadata` / daemon log creation to set `0o600`.
- Document the assumption in `docs/PROFILE.md` (currently silent on permissions).

### 2. High: daemon auth token is a predictable format and the Unix socket is created with no permission floor

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:110-116`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:133-164`
- `repos/bifrost-rs/crates/bifrost-app/src/host/daemon.rs:36-42`
- `repos/bifrost-rs/crates/bifrost-app/src/host/daemon.rs:109-115`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/shared.rs:90-102`

Why this matters:
- `build_daemon_transport` sets `token = format!("daemon-{}-{}", profile.id, now_unix_secs())`. The profile id is derivable from a share public key and a stable SHA-256 domain tag, and `now_unix_secs()` is observable from process start time. Token entropy is effectively zero for a local attacker who sees the daemon start.
- The token is handed to the child via `--token` CLI arg, visible to every user via `/proc/*/cmdline` on Linux.
- The control socket is bound with `UnixListener::bind(&transport.socket_path)?` in `bifrost-app` with no `set_permissions(0o600)` and no parent directory chmod.
- `shorten_unix_socket_path` falls back to `std::env::temp_dir().join(format!("igloo-shell-{short}.sock"))` when the state-dir path exceeds 96 bytes; that is the world-writable `/tmp` in typical Linux installs.
- Combined with finding 1, a local attacker can read the daemon metadata JSON (token included), connect to the socket, and drive `Sign`, `Ecdh`, `WipeState`, and `SetPolicyOverride` without the passphrase.
- Token comparison is `request.token != expected_token` (non-constant time). That is a secondary concern given the other weaknesses.

Smells:
- Treating `token` as a secret but emitting it as a CLI argument and as a plaintext JSON file.
- No `chmod(0o600)` on the socket file.
- Silent fallback to `/tmp` for long socket paths.

Cross-repo note: `bifrost-app::host::daemon::run_resolved_daemon` is the place to gate socket permissions; `bifrost-app::host::daemon.rs:109` is where the token comparison lives. Both are shared by every host that embeds the native runtime.

Streamline:
- Generate `token` from `rand::rngs::OsRng` (e.g. 32 random bytes, hex).
- Pass the token out-of-band via an inherited pipe or an env var, not `--token`.
- On Unix, `std::os::unix::fs::PermissionsExt::set_mode(0o600)` on the socket file and `0o700` on its parent.
- Use a constant-time comparison for `token`.

### 3. High: profile passphrase is propagated to the daemon child via an inherited environment variable

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:140-154`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell.rs:42-43`
- `repos/igloo-shell/crates/igloo-shell-cli/src/main.rs:555-598`

Why this matters:
- When a CLI flow passes a passphrase (e.g. `profile load --daemon`), `start_profile_daemon_with_passphrase` does `command.env(PROFILE_PASSPHRASE_ENV, passphrase)` and spawns the child process.
- On Linux, `/proc/<pid>/environ` is readable by the owning user. Any parallel process in the same UID (a compromised auxiliary tool, a sibling shell plugin, a rogue extension) can recover the passphrase at any point while the daemon is alive.
- The comment in `shell.rs:41-43` marks this as a "temporary shell-side convenience contract" — the debt is acknowledged, but the attack surface remains.
- `IGLOO_SHELL_ONBOARDING_PASSWORD` has the same shape for `onboard` flows, though it is only in the parent process lifetime.

Smells:
- Env vars carrying long-lived secrets for the lifetime of a daemon process.
- A retained `Temporary shell-side convenience contract` comment that has not been migrated.

Streamline:
- Write the passphrase to a private pipe the child reads once from stdin/FD, then close.
- Or, unlock the share in the parent, hand the derived material (already limited to this run) to the child, and never transport the passphrase.
- Once migrated, remove the `PROFILE_PASSPHRASE_ENV` shim entirely.

### 4. High: profile passphrase, onboarding secret, and ciphertext plaintext are held in plain `String`/`Vec<u8>` with no zeroization

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/encrypted_profile.rs:36-92`
- `repos/igloo-shell/crates/igloo-shell-cli/src/commands/prompts.rs:3-34`
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:432-491`
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:532-538`

Why this matters:
- `prompt_hidden_secret` builds the passphrase into `let mut password = String::new();` and returns it by value. Every subsequent `.clone()` (there are many — see `commands/imports.rs:30`, `commands/imports.rs:45`, `commands/imports.rs:56`, `commands/rotation.rs:24`, `commands/rotation.rs:36`, etc.) spreads copies across the heap with no drop-time erase.
- The decrypted share payload comes back as `String::from_utf8(plaintext)` (`native.rs:490`) and is passed around as `share_raw` before being re-serialized and, in some paths, written back to disk.
- The derived 32-byte Argon2id key (`derive_profile_encryption_key`) is a stack `[u8; 32]` with no `Zeroizing` wrapper.
- The `zeroize` crate is in `Cargo.lock` as a transitive dep only; neither `igloo-shell-core` nor `bifrost-profile` declares it or uses it.

Smells:
- No `ZeroizeOnDrop` on secret carrier types.
- No `Zeroizing<String>` for passphrase buffers.
- Clones of passphrase strings are freely used because the type system does not discourage them.

Streamline:
- Introduce a shared `SecretString` / `SecretBytes` wrapper (or adopt `secrecy`) in `bifrost-profile` and `igloo-shell-core` at the boundary and propagate it through CLI plumbing.
- Apply `Zeroizing<[u8; 32]>` to `derive_profile_encryption_key` output.

### 5. High: on-disk KDF uses `Argon2::default()` which resolves to a spec-minimum parameter set, and the derivation is undocumented

Files:
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:532-538`
- `repos/bifrost-rs/Cargo.lock:106` (argon2 `0.5`)
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:425-467`

Why this matters:
- `Argon2::default()` on argon2 `0.5` picks `Argon2id` with `Params::DEFAULT` (m=19456 KiB, t=2, p=1). Those are the crate defaults, which match OWASP's minimum recommendation but are much weaker than the portable package KDF documented in `docs/BACKUP.md` (PBKDF2-SHA256, 600 000 iterations) and weaker than most current host-side recommendations (m=64 MiB, t=3, or m=19 MiB with t>=3, depending on OWASP row).
- There is no version byte or parameter record carried inside `EncryptedProfileRecord`; the parameter choice is implicit in whatever `Argon2::default()` happens to resolve to at build time, which couples future upgrades to a silent breaking change.
- The ciphertext envelope header is a single `ENCRYPTED_PROFILE_VERSION` byte, with nothing covering the KDF parameters.

Smells:
- Implicit, undocumented KDF parameters on the on-disk secret.
- No AEAD AD binding the envelope to its `EncryptedProfileRecord` metadata (id, kind, salt_hex), so an attacker with write access to the metadata JSON can swap salt/ciphertext between records without detection before decryption.

Cross-repo note: parameters and envelope shape belong to `bifrost-profile`. Raising parameters and adding AD needs a coordinated migration (version bump, backfill).

Streamline:
- Pick an explicit `argon2::Params::new(...)`, store `m_cost`, `t_cost`, `p_cost` next to the salt in `EncryptedProfileRecord`.
- Add AAD: either the record id or a canonical serialization of `EncryptedProfileRecord` minus `ciphertext_path`.
- Document KDF choice in `docs/PROFILE.md` or `docs/CRYPTOGRAPHY.md`.

### 6. Medium: staged onboarding imports mix encrypted and plaintext metadata in a world-readable directory

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/onboarding.rs:51-104`

Why this matters:
- `stage_onboarding_import` encrypts the onboarding package text through `store_encrypted_profile`, then writes a sibling `StagedOnboardingImport` JSON at `imports_dir/<id>.json` containing `peer_pubkey`, `relays`, `label`, and the `encrypted_profile_id`.
- `paths.imports_dir` is created in `ProfilePaths::ensure()` with no mode hardening (see finding 1), so the metadata (peer pubkey + relays linked to a share-holder) leaks to any local user even though the encrypted blob is protected.
- The flow never cleans up this directory on successful `finalize_connected_onboarding_import`, so stale staged entries linger indefinitely.

Smells:
- Two files per staged import — one encrypted, one plaintext — written in lockstep but with divergent confidentiality.
- No lifecycle for staged entries (no TTL, no success-path cleanup, no GC command).

Streamline:
- Hoist the identifying metadata into the encrypted blob instead of the JSON sibling, or chmod the JSON `0o600`.
- Add explicit cleanup when the staged import transitions into a real profile.

### 7. Medium: the daemon startup readiness loop silently discards the child when it never answers

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs:166-186`

Why this matters:
- The parent polls `client.runtime_metadata()` 50 times with 100 ms sleeps (5 s budget). On timeout it `child.kill()` + `child.wait()` and returns an error.
- If the child crashed before setting up the socket (common source: bad profile unlock in the child), `last_error` is a connect-refused line; the daemon log stderr line that actually explains the failure is only available through `daemon logs`. For a CLI user running `profile load --start`, that secondary lookup is not automatic.
- `try_wait` is only consulted in the timeout path; if the child exits successfully-but-silently (e.g. signer panics post-init), the parent hangs for the full 5 s before noticing.
- The removed `daemon_metadata` path on failure (`daemon.rs:180`) is best-effort; a partial failure can leave stale `daemon.json` pointing at a dead socket, which then fools `ensure_profile_daemon` (`runtime_support.rs:10-15`) into thinking the daemon is "recorded but not responsive".

Smells:
- Polling readiness instead of reading a readiness signal from the child.
- Separate code paths for "not answering" and "exited" that are both coerced into a single error string.
- `ensure_profile_daemon` re-reads `read_daemon_metadata` to decide existence, which is true until the stale file is removed.

Streamline:
- Have the child write a small "ready" marker (or close a pipe inherited from the parent) when the socket is up, and block the parent on that.
- Include a tail of the daemon log in the parent's error when readiness fails.
- Atomically remove `daemon.json` whenever the child exits.

### 8. Medium: rotation finalization commits the new profile before removing the old, with non-atomic multi-file side effects on failure

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/rotation.rs:4-72`
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/profiles.rs:49-79`

Why this matters:
- `finalize_rotation_update_import` writes a new group package, stores a new encrypted profile, writes the migrated profile manifest, then calls `remove_profile(target)`.
- `remove_profile` performs four separate filesystem operations — manifest delete, state-dir recursive delete, group-ref delete, encrypted-profile record delete — and updates the shell config.
- If a crash or permission error hits between any two steps (say, after state-dir delete but before encrypted-profile delete), the workspace ends up with ghost records and no atomic rollback. The on-disk flow does not use fsync+rename semantics for manifest writes (`io::write_json` is plain `fs::write`).
- Rotation specifically is the path where a partial failure leaves both "old" and "new" share material referenced on disk, which is the opposite of what a rotation is meant to guarantee.

Smells:
- Multi-step manifest mutation with no write-ahead log.
- `fs::write` used for manifests whose partial write would yield a JSON parse error on next load.

Cross-repo note: the file-level atomic-write primitive (create temp + fsync + rename) belongs in `bifrost-profile`; `igloo-shell-core` should use it everywhere a manifest is replaced.

Streamline:
- Introduce an atomic JSON writer (`tempfile::persist`) and route all manifest writers through it.
- Mark the rotation intention with a small journal entry and replay or roll back on next invocation.

### 9. Medium: `shell.rs` is a 1062-line god module that mixes public API re-exports, private helpers, and 800 lines of tests

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell.rs:1-1062`

Why this matters:
- The top of the file is a tangled `pub use`/`pub(crate) use` surface across nine sibling modules plus hand-written `SetupRequest`, `SetupResult`, `GeneratedKeysetDraft`, `RotationWorkspaceDocument`, etc.
- The bottom half (lines 261-1062) is a single `#[cfg(test)] mod tests` block containing daemon fixture, policy tests, onboarding import tests, and bfprofile round-trip tests — each of which belongs next to the module whose behavior it verifies.
- The module boundary is therefore "everything the CLI imports from core", which is why the file is also where the runtime/bootstrap `_` secondary `run_setup` dispatcher lives (`onboarding.rs:244-294`) while the types for that dispatcher live in `shell.rs`.

Smells:
- One module doubling as a re-export hub, a type-definition file, and the test suite for five other modules.
- Changes to any rotation/policy/onboarding type bump churn in `shell.rs`.

Streamline:
- Split the test block into `crates/igloo-shell-core/tests/*.rs` integration tests (or into `#[cfg(test)]` blocks inside each sibling module).
- Move public types (`SetupRequest`, `RotationWorkspaceDocument`, etc.) into the module whose flows use them.
- Leave `shell.rs` as a thin façade.

### 10. Medium: `main.rs` owns 533 lines of clap definitions and 320 lines of tests — command plumbing has no module boundary

Files:
- `repos/igloo-shell/crates/igloo-shell-cli/src/main.rs:49-553`
- `repos/igloo-shell/crates/igloo-shell-cli/src/main.rs:650-969`

Why this matters:
- Every `Args` and `Subcommand` lives in `main.rs`, alongside the dispatch match and an `unsafe { std::env::set_var("RUST_LOG", ...) }` block (`main.rs:617-624`) that is reachable at parse time.
- The tests at the bottom of `main.rs` verify clap parsing but cannot verify command handling without a harness; they also keep the file over 900 lines.
- `configure_trace_env` uses `unsafe` to `set_var` because Rust 2024 requires it, but the call runs before `init_tracing` and does so unconditionally, which is fine today but obscures the invariant.

Smells:
- CLI grammar and CLI runtime code sharing one file.
- `unsafe` used purely to satisfy the 2024-edition env-var API; no safety commentary near the block.

Streamline:
- Move `Args`/`Subcommand`/`Cli` definitions into `commands/cli.rs`.
- Move clap parser tests into that module.
- Keep `main.rs` as a slim dispatcher.

### 11. Medium: integration-test coverage exercises happy paths but not adversarial inputs against the encryption boundary

Files:
- `repos/igloo-shell/crates/igloo-shell-cli/tests/managed_integration.rs`
- `repos/igloo-shell/crates/igloo-shell-cli/tests/utility_integration.rs`
- `repos/igloo-shell/crates/igloo-shell-cli/tests/policy_integration.rs`

Why this matters:
- There are 32 test functions across the three integration files. None cover:
  - wrong passphrase on `profile load` (ensure decrypt failure is a clean error, not a panic or partial state write).
  - corrupted ciphertext file (truncated, mutated `ENCRYPTED_PROFILE_VERSION`, mutated nonce — the version check in `native.rs:480-482` is plausible but unverified).
  - partial-write recovery during `remove_profile` or `finalize_rotation_update_import`.
  - stale `daemon.json` pointing at a gone socket (`ensure_profile_daemon` path).
  - `/tmp` socket fallback from `shorten_unix_socket_path` (`shared.rs:95-100`).
- `bifrost-profile::native::tests` has one small round-trip test (`native.rs:575-588`) that does not exercise malformed envelopes either.

Smells:
- Coverage is concentrated on successful flows.
- The encryption/IPC boundary is not treated as a test-worthy surface.

Streamline:
- Add adversarial cases for the four categories above.
- Add a property-test or seeded fuzz pass over `decrypt_encrypted_profile` with truncation/flip mutations.

### 12. Low: `read_package_or_inline` quietly swallows CLI/path ambiguity, and TTY-dependent resolution makes that invisible

Files:
- `repos/igloo-shell/crates/igloo-shell-cli/src/commands/resolve.rs:210-219`
- `repos/igloo-shell/crates/igloo-shell-cli/src/commands/resolve.rs:146-184`

Why this matters:
- `read_package_or_inline` treats the positional `package_or_path` as a path if it exists on disk, otherwise as literal text. A user who points `onboard` at `./alice.bfonboard` from a working directory that contains an empty file of that name gets the empty file as the "package". The error surfaces later as a decode failure with no hint about the path-vs-inline decision.
- `resolve_secret_source_with` has an `unreachable!("clap enforces secret source conflicts")` branch (`resolve.rs:182`) that depends on clap's `conflicts_with` annotation staying in sync. If a future refactor adds a new secret source without updating the enum, the panic is reachable.

Smells:
- Positional argument doing heuristic type dispatch.
- Invariant between clap grammar and resolver encoded as `unreachable!`.

Streamline:
- Introduce `--package` and `--package-file` or at least log the chosen branch at debug.
- Replace `unreachable!` with a real error that carries the label.

### 13. Low: doc drift around on-disk encryption and profile storage

Files:
- `/home/cscott/Repos/frostr/frostr-infra/docs/PROFILE.md:1-120`
- `/home/cscott/Repos/frostr/frostr-infra/docs/BACKUP.md:50-71`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/README.md:1-149`

Why this matters:
- `docs/BACKUP.md` documents the portable-package KDF (PBKDF2-SHA256, 600k iterations) in detail, but the host-local `EncryptedProfileRecord` format (Argon2id defaults, ChaCha20Poly1305, 16-byte salt, 12-byte nonce, v1 envelope) is not documented anywhere visible to operators.
- `docs/PROFILE.md` talks about "durable portable profile state" but does not distinguish the share secret carrier for the host from the carrier for portable packages; operators cannot tell from the docs whether their on-disk copy is weaker, stronger, or different from what the `bfprofile` package guarantees.
- `igloo-shell/README.md` points to `./TESTING.md` and `./CONTRIBUTING.md` but does not mention any security considerations (permissions, secret lifetime, daemon exposure) at all.

Smells:
- Two encryption schemes in production (portable and host-local) with asymmetric documentation.
- README is feature-focused, not threat-model aware.

Streamline:
- Add a "Host-local Encryption" section to `docs/PROFILE.md` or a short `docs/HOST-STORAGE.md` with envelope byte layout, KDF parameters, and a commitment to AD bindings.
- Cross-link from `igloo-shell/README.md` under a new "Security Model" heading.

### 14. Low: relay profile validation and onboarding relay ensuring can silently overwrite an existing profile id

Files:
- `repos/igloo-shell/crates/igloo-shell-core/src/shell/relay.rs:81-88`
- `repos/bifrost-rs/crates/bifrost-profile/src/native.rs:111-146`
- `repos/igloo-shell/crates/igloo-shell-cli/src/commands/runtime_support.rs:47-76`

Why this matters:
- `replace_relay_profile` uses `retain(|entry| entry.id != next.id)` then `push(next)`. There is no "exists, differs" branch; a user-triggered overwrite of someone else's relay config is silent.
- `ensure_relay_profile` in `runtime_support.rs` falls back to generating `relay-<unix_secs>` when the caller has not supplied an id, which can collide on fast repeated runs (nanosecond precision is not used here).
- `FilesystemProfileDomain::ensure_onboarding_relay_profile` replaces an existing id blindly if the provided id is known.

Smells:
- Collision-prone id generation combined with silent overwrite.

Streamline:
- Prefer `relay-<unix_secs>-<random>` for fallback ids.
- Warn (or refuse unless `--force`) when `replace_relay_profile` is replacing a distinct existing entry.

## Cross-Repo Summary

Most of the highest-severity items actually live one level down, in `bifrost-profile` and `bifrost-app`:

- `bifrost-profile::native` owns the encryption envelope (findings 1, 5) and the filesystem layout (findings 1, 6, 8).
- `bifrost-app::host::daemon` owns the control socket and the token compare (finding 2).
- `bifrost-app::native_runtime` shares the passphrase-via-env contract (finding 3).

`igloo-shell` itself is in the uncomfortable position of being the operator face for those invariants without owning them. Any hardening work needs a paired change in `bifrost-rs`.

## Bottom Line

`igloo-shell` is well-factored at the command-dispatch level but leaves its host-local secret material defended only by the user passphrase plus whatever the system umask happens to be. The highest-signal cleanup is not in the CLI itself — it is in `bifrost-profile` (envelope + KDF + file mode) and `bifrost-app` (daemon token, socket permissions, passphrase handoff). After that, the shell's own big wins are atomic manifest writes, adversarial test coverage at the encryption boundary, and splitting the two god-files (`shell.rs`, `main.rs`) into focused modules.
