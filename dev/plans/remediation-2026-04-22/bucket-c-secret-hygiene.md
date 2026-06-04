# Bucket C — Host-Local Secret Hygiene (Hard-Cut Plan)

Status: draft, pending user approval
Related: `bucket-a-bifrost-rs-crypto.md` (depends on `bifrost-core::secret`), `bucket-b-kdf-aad.md` (coordinated release)

## Context

The 2026-04-22 audit's highest-signal finding was a chained local-UID
privilege-escalation path in `igloo-shell` + `bifrost-app`:

- Every file created by the shell inherits the default umask (no `0o600`
  anywhere) → ciphertext envelopes, daemon tokens, socket paths, profile
  manifests, nonce-pool state, logs all become world-readable on a
  typical umask=022 system.
- The daemon auth token is the predictable string
  `daemon-<profile_id>-<unix_secs>`, passed via `--token` argv (visible
  in `/proc/*/cmdline`) and stored in `daemon.json` JSON (no chmod).
- Token comparison is non-constant-time (`request.token != expected_token`).
- The Unix socket is created with no `chmod 0600`, parent dir no `chmod 0700`.
- Long socket paths fall back to `/tmp/igloo-shell-<hash>.sock` — world-
  writable.
- The profile passphrase is handed to daemon children via
  `PROFILE_PASSPHRASE_ENV` — readable from `/proc/<pid>/environ` for the
  daemon's entire lifetime.
- Passphrase lives as plain `String` with 10+ `.clone()` sites; no
  zeroization despite `zeroize` being a workspace dep.
- Manifest writes are non-atomic (`fs::write` truncate-then-write). No
  `fsync` anywhere. Partial writes leave profiles unreadable.
- Rotation finalization is a 7-step linear sequence; crash mid-rotation
  leaves ghost profiles, orphaned state dirs, or both.
- `derive_profile_encryption_key` re-runs on every decrypt — with the
  Bucket B defaults (Argon2id m=256 MiB / t=4), that's ~400-600 ms per
  operation, noticeable on rapid UI flows.

The chain is real: an attacker with the same UID can read
`daemon.json` (world-readable), extract the token, connect to the socket
(world-writable fallback), and drive `Sign` / `Ecdh` / `WipeState` without
the passphrase.

Bucket C closes all of the above. It is the largest single-bucket effort in
the remediation track (five PRs across two submodules) and ships in a
separate coordinated release from Bucket A + B — operators get two
migration events total.

## Scope

**In:**
- C.1 — Filesystem permissions: `umask(0o077)` at daemon start, explicit
  `chmod 0o600` on every ciphertext / metadata / log file, `chmod 0o700` on
  every profile directory, centralized helpers.
- C.2 — Atomic manifest writes: `tempfile::persist` behind a helper; route
  every `fs::write(manifest, ...)` through it. Add explicit `fsync` on
  renames.
- C.3 — Secret newtypes: extend `bifrost-core::secret` (Bucket A) with
  `Passphrase` and `DaemonToken`. Thread through all call sites. Eliminate
  unnecessary `.clone()`s; remaining clones use explicit `clone_secret()`.
- C.4 — Daemon authentication hardening: `OsRng`-generated token (32 bytes
  → 64 hex chars), token handoff via `daemon.json` with `0o600` perms
  (no `--token` argv), socket chmod `0o600`, parent dir chmod `0o700`,
  `/run/user/$UID/` fallback replacing `/tmp`, constant-time token compare
  via `subtle`.
- C.5 — Passphrase transport: replace `PROFILE_PASSPHRASE_ENV` with
  stdin-pipe handoff (parent writes passphrase bytes, closes; child reads
  once, drops).
- C.6 — Session-scoped KDF cache: `UnlockSession` holds the derived
  `FileStoreKey` (Bucket A) for daemon lifetime. Unlock once, sign many.
- C.7 — Rotation intent journal: single atomic `rotations/.intent.json`
  (`0o600`) written before each rotation step; scanned on daemon startup.
  First pass logs warnings on incomplete intents; no auto-recovery.

**Out of scope for Bucket C:**
- Multi-user access or a privilege boundary beyond "same-UID = trusted".
  FROSTR-on-a-shared-laptop with multiple non-root users is a separate
  threat model; flag for later.
- Windows support for daemon mode. Remains `#[cfg(unix)]`-only.
- Per-operation re-authentication. UnlockSession lives for the daemon's
  process lifetime.
- Automatic rollback of incomplete rotations — first pass is
  detect-and-log; auto-recovery is explicitly deferred.

## Execution Order

Five PRs across two submodules. Numbering continues from Bucket B (PR5–PR7).

| PR | Items | Submodule | Depends on |
|---|---|---|---|
| PR8 | C.1 (filesystem perms) + C.2 (atomic writes) | `bifrost-rs` | none |
| PR9 | C.3 (Passphrase + DaemonToken newtypes) | `bifrost-rs` | Bucket A PR1 |
| PR10 | C.4 (daemon auth) + C.5 (passphrase stdin) | `bifrost-rs` | PR9 |
| PR11 | C.6 (UnlockSession) + C.7 (rotation journal) | `bifrost-rs` | PR8 + PR9 + Bucket A PR1 |
| PR12 | Consumer migration (all of C.1–C.7) | `igloo-shell` | PR8 + PR9 + PR10 + PR11 |

PR8 and PR9 can run in parallel. PR10 depends on PR9 (token = `DaemonToken`).
PR11 depends on PR8 (atomic writes) and PR9 (Passphrase). PR12 lands after
all four `bifrost-rs` PRs merge.

Rough touch: ~2,200 lines. Most volume is in PR10 (daemon auth refactor)
and PR12 (igloo-shell migration: ~50 call-site updates for the type
signature changes from `String` → `Passphrase`).

Bucket C ships as a **separate coordinated release** from Bucket A + B.
Operators migrate twice total (A+B first, then C). Rationale below.

---

## C.1 — Filesystem permissions

### Approach

Three layers of defense:

1. **`umask(0o077)` set at the top of daemon process init.** Single syscall
   protects every future file/dir creation. Set in:
   - `bifrost-app::host::daemon::run_resolved_daemon` (daemon process entry)
   - `bifrost-app::host::mod::serve_daemon` (if applicable)
   - `igloo-shell-cli::main` at the top of `main()` (covers non-daemon CLI
     paths that create files — import, rotation, etc.)

2. **Explicit `PermissionsExt::set_mode` on every secret-bearing file write**
   — defense-in-depth in case umask is ever unset (tests, sandboxed
   environments). Modes:
   - `0o600` on `.enc` ciphertext, `daemon.json`, profile manifest JSON,
     relay profile JSON, staged import JSON, daemon log files, rotation
     intent journal.
   - `0o700` on every directory created by `ProfilePaths::ensure`:
     `config_dir`, `data_dir`, `state_dir`, `profiles_dir`, `groups_dir`,
     `encrypted_profiles_dir`, `imports_dir`, `state_profiles_dir`,
     `rotations_dir`.

3. **Centralized helpers** — new module `bifrost-profile::fs_guard`:
   ```rust
   pub fn ensure_dir_restricted(path: &Path, mode: u32) -> Result<()>;
   pub fn write_restricted_bytes(path: &Path, data: &[u8], mode: u32) -> Result<()>;
   pub fn write_restricted_bytes_atomic(path: &Path, data: &[u8], mode: u32) -> Result<()>;
   ```
   Every existing `fs::write` / `fs::create_dir_all` call site in
   `bifrost-profile` and `igloo-shell-core` migrates to these helpers. No
   bare `fs::write` allowed on secret-bearing paths post-refactor.

### Caller audit

PR8 must migrate these sites (exhaustive list from Phase 1 exploration):

| Site | Current call | New call |
|---|---|---|
| `bifrost-profile/src/native.rs:452` (ciphertext write) | `fs::write(&ciphertext_path, envelope)` | `write_restricted_bytes_atomic(..., 0o600)` |
| `bifrost-profile/src/native.rs:550` (`write_json`) | `fs::write(path, raw)` | `write_restricted_bytes_atomic(..., 0o600)` |
| `bifrost-profile/src/paths.rs:60-75` (`ProfilePaths::ensure`) | `fs::create_dir_all(&p)` | `ensure_dir_restricted(&p, 0o700)` |
| `igloo-shell-core/src/shell/io.rs:15-21` (`write_json`) | `fs::write(path, raw)` | `write_restricted_bytes_atomic(..., 0o600)` |
| `igloo-shell-core/src/shell/daemon.rs:124-137` (daemon log + metadata) | `OpenOptions::new().create(true).append(true)` | new helper + explicit chmod after open |
| `igloo-shell-core/src/shell/rotation.rs:223-227` (rotation workspace) | `write_json` | migrated helper |
| `igloo-shell-core/src/shell/onboarding.rs:51-104` (staged imports) | `write_json` | migrated helper |

### Testing

- `fs_guard_creates_dir_with_restricted_mode` — creates a dir via the
  helper, asserts `fs::metadata(path).mode() & 0o777 == 0o700`.
- `fs_guard_writes_file_with_restricted_mode` — writes via the helper,
  asserts `mode & 0o777 == 0o600`.
- `fs_guard_survives_relaxed_umask` — set umask to `0o000` in-test, write
  via helper, assert file is still `0o600` (proves explicit chmod works).

---

## C.2 — Atomic manifest writes

### Approach

`write_restricted_bytes_atomic(path, data, mode)` implementation:

```rust
use tempfile::NamedTempFile;
use std::os::unix::fs::PermissionsExt;

pub fn write_restricted_bytes_atomic(
    path: &Path,
    data: &[u8],
    mode: u32,
) -> Result<()> {
    let parent = path.parent().ok_or(FsGuardError::NoParent)?;
    let mut tmp = NamedTempFile::new_in(parent)?;

    // Write + fsync while still a temp file so the rename sees complete bytes.
    tmp.as_file_mut().write_all(data)?;
    tmp.as_file().sync_all()?;

    // Set the final mode before persist; avoids a brief window where the
    // final path exists with the default tempfile mode.
    tmp.as_file()
       .set_permissions(Permissions::from_mode(mode))?;

    tmp.persist(path)?;

    // fsync the directory so the rename is durable across a crash.
    let dir = std::fs::File::open(parent)?;
    dir.sync_all()?;

    Ok(())
}
```

Key points:
- `NamedTempFile::new_in(parent)` ensures the temp file is on the same
  filesystem as the target. `persist()` is atomic only on same-device
  renames. On cross-device, persist copies and cleans up, which is NOT
  atomic; document this limitation.
- `sync_all()` on the temp file flushes contents to disk before rename.
- `set_permissions` on the temp file before persist — the final path
  never exists with a broader mode even for a microsecond.
- `sync_all()` on the parent directory makes the rename durable. Without
  this, a crash can leave the old file visible on reboot even though the
  rename "succeeded" from userspace's point of view.

### Workspace dependency

Add to `repos/bifrost-rs/Cargo.toml` `[workspace.dependencies]`:
```toml
tempfile = "3"
```
Consumed by `bifrost-profile`.

### Testing

- `atomic_write_survives_crash_in_middle_of_rename` — simulated with a
  poisoned tempfile persist that panics; verify target file still has the
  old bytes (not partial write).
- `atomic_write_sets_final_mode_before_persist` — verify via `fs::metadata`
  on the persisted path that mode is `0o600` immediately.
- `atomic_write_round_trip` — write, read, assert byte equality.

### Rotation and removal atomicity (related; lands in PR11)

`remove_profile` at `igloo-shell-core/src/shell/profiles.rs:49-79` currently
does 5 separate `fs::remove_*` operations with no rollback. Bucket C does
NOT make `remove_profile` atomic (that requires transactional filesystem
semantics we can't provide). Instead, the rotation intent journal (C.7)
records intent before each step so a crash can be detected on restart.

---

## C.3 — Secret newtypes: `Passphrase` and `DaemonToken`

### Approach

Extend Bucket A's `bifrost-core::secret` module with:

```rust
// In crates/bifrost-core/src/secret.rs

/// UTF-8 passphrase entered by the operator. Zeroized on drop; redacted Debug.
/// Does NOT impl Serialize/Deserialize — must not be persisted.
pub struct Passphrase(String);

impl Passphrase {
    pub fn new(s: String) -> Self;
    pub fn expose_secret(&self) -> &str;
    pub fn expose_bytes(&self) -> &[u8];
    pub fn clone_secret(&self) -> Self;  // explicit; no Clone derive
}
// + ZeroizeOnDrop, redacted Debug ("Passphrase(<redacted>)"), no PartialEq

/// Random daemon authentication token — 32 bytes rendered as 64 hex chars.
/// Zeroized on drop; redacted Debug; PartialEq is constant-time via subtle.
pub struct DaemonToken {
    bytes: [u8; 32],
}

impl DaemonToken {
    pub fn new_random<R: rand_core::CryptoRngCore>(rng: &mut R) -> Self;
    pub fn from_hex(s: &str) -> Result<Self, TokenError>;
    pub fn to_hex(&self) -> String;  // returns owned String for daemon.json
    pub fn expose_bytes(&self) -> &[u8; 32];
    pub fn clone_secret(&self) -> Self;
}
// + ZeroizeOnDrop, redacted Debug ("DaemonToken(<redacted>)"),
// + PartialEq via subtle::ConstantTimeEq
```

### Thread-through migration (PR9 in bifrost-rs; PR12 in igloo-shell)

Every call site that currently takes `String` / `&str` passphrase migrates:

- `derive_profile_encryption_key_v2(passphrase: &Passphrase, salt: &[u8], params: Argon2Params)` — takes `&Passphrase`, internally calls `passphrase.expose_bytes()`.
- `store_encrypted_profile(..., passphrase: &Passphrase, ...)`.
- `decrypt_encrypted_profile(..., passphrase: &Passphrase, ...)`.
- `UnlockSession::new(passphrase: Passphrase, ...)` — takes ownership.
- CLI prompt layer: `prompt_hidden_secret` returns `Passphrase`, not `String`.

### Eliminate `.clone()` sites

The 10+ audit-cited `.clone()` sites in `igloo-shell-cli/src/commands/`
migrate as follows:
- Where a function only reads the passphrase: pass `&Passphrase` (no clone).
- Where a function takes ownership (spawns a daemon, then uses it again):
  use explicit `clone_secret()` with a rustdoc comment explaining why.
- The 10+ clone sites should reduce to 2-3 legitimate ones.

Target call-site audit after migration: `rg 'passphrase\.clone\(\)|password\.clone\(\)' repos/igloo-shell/` returns only sites that have an explicit justification comment immediately above.

### Testing

- `passphrase_debug_is_redacted` — `format!("{:?}", passphrase)` contains `<redacted>`, not the actual string.
- `passphrase_drop_zeroizes` — use unsafe `ptr::read_volatile` pattern to observe zeroization (or rely on the `zeroize` crate's tests; our test asserts the type implements `ZeroizeOnDrop` via trait bound).
- `daemon_token_partialeq_is_constant_time` — benchmark-style test that compares equal and nearly-equal tokens and asserts no observable timing difference beyond noise floor.
- `daemon_token_generation_uses_osrng` — verify two tokens differ with overwhelming probability.

---

## C.4 — Daemon authentication hardening

### Token generation

At daemon spawn time in `igloo-shell-core::shell::daemon::start_profile_daemon_with_passphrase`:

```rust
let mut rng = rand::rngs::OsRng;
let token = DaemonToken::new_random(&mut rng);
```

Token is 32 random bytes rendered as 64 lowercase hex characters for
storage in `daemon.json`. Entropy: 256 bits, unguessable.

### Token handoff: via `daemon.json` with `0o600`, NOT argv

**Removed:** `--token` argv flag on the child process.

**Replaced with:** The parent writes the token to `daemon.json` via
`write_restricted_bytes_atomic(..., 0o600)` **before spawning the child**.
The child reads `daemon.json` on startup to learn its own token (instead
of being told via argv). Subsequent CLI clients read `daemon.json` the
same way to auth.

Advantages over argv:
- No exposure via `/proc/<pid>/cmdline`.
- Existing metadata file already needed for socket-path discovery; token
  piggybacks on the same channel.
- Same channel for parent-to-child and CLI-to-daemon; one source of truth.

Disadvantage:
- Token lives on disk for the daemon's lifetime. Mitigated by `0o600` perms
  and the fact that a same-UID attacker who can read the file could also
  read `/proc/<pid>/environ` historically — so this isn't a regression.

### Constant-time token compare

In `bifrost-app::host::daemon` request-handling path, replace:
```rust
if request.token != expected_token {
```
with:
```rust
if request.token.ct_eq(&expected_token).unwrap_u8() == 0 {
```
using `subtle::ConstantTimeEq` (already added in Bucket A PR1).

### Socket permissions

After `UnixListener::bind(&transport.socket_path)?` at
`bifrost-app/src/host/daemon.rs:42`:

```rust
let listener = UnixListener::bind(&transport.socket_path)?;
std::fs::set_permissions(
    &transport.socket_path,
    Permissions::from_mode(0o600),
)?;
```

Parent directory is already `0o700` via `ensure_dir_restricted`.

### `/tmp` fallback replaced with `/run/user/$UID/`

`shorten_unix_socket_path` at `igloo-shell-core/src/shell/shared.rs:90-102`:

1. First try: `state_profiles_dir/<profile_id>/daemon.sock` (original path).
2. If path length ≥ 100 bytes: try `/run/user/$UID/igloo-shell-<hash>.sock`.
   `/run/user/$UID/` is tmpfs, user-owned, `0700` by default on systemd
   systems.
3. If `/run/user/$UID/` does not exist (macOS, some BSDs): return typed
   `TransportError::SocketPathTooLong { path, limit }`. No `/tmp` fallback.
4. Detect macOS / BSD via `std::env::var("XDG_RUNTIME_DIR")` — honor the
   override first if set, else `/run/user/$UID/`, else typed error.

Document in `igloo-shell/README.md`: "Long home directory paths may require
overriding `XDG_STATE_HOME` to a shorter directory. See `SECURITY.md`."

### Testing

- `daemon_token_rejected_if_wrong` — existing test preserved; adapt to new
  `DaemonToken` type.
- `daemon_socket_file_has_mode_0600` — spawn daemon, stat socket file,
  assert mode.
- `daemon_metadata_has_mode_0600` — assert `daemon.json` mode.
- `daemon_spawn_without_argv_token_still_works` — verify child reads token
  from `daemon.json`; `/proc/<pid>/cmdline` does not contain the token.
- `socket_path_too_long_returns_typed_error` — mock a very long path and
  `/run/user/$UID/` absent; assert `TransportError::SocketPathTooLong`.

---

## C.5 — Passphrase transport: stdin pipe, not env var

### Approach

Remove `PROFILE_PASSPHRASE_ENV` end-to-end. Replace with stdin pipe.

Parent spawn sequence (in
`igloo-shell-core/src/shell/daemon.rs:start_profile_daemon_with_passphrase`):

```rust
use std::io::Write;
use std::process::Stdio;

let mut command = Command::new(exe);
command
    .arg("__daemon-run")
    .arg("--profile").arg(profile_id)
    .arg("--socket-path").arg(&transport.socket_path)
    // Note: no --token arg anymore (read from daemon.json)
    .stdin(Stdio::piped())
    .stdout(Stdio::from(stdout))
    .stderr(Stdio::from(stderr))
    .env_remove(PROFILE_PASSPHRASE_ENV);  // belt-and-braces

let mut child = command.spawn()?;

// Write passphrase to child stdin, then close it.
{
    let mut stdin = child.stdin.take().expect("stdin piped");
    stdin.write_all(passphrase.expose_bytes())?;
    stdin.write_all(b"\n")?;  // terminator
    // stdin is dropped here → closed → child gets EOF after reading.
}

// Passphrase goes out of scope here and is zeroized on drop.
```

Child read path (in `bifrost-app::host::daemon` or `igloo-shell-cli`
depending on where the daemon entry point lives):

```rust
use std::io::BufRead;

let stdin = std::io::stdin();
let mut line = String::new();
stdin.lock().read_line(&mut line)?;
// Strip trailing newline.
if line.ends_with('\n') { line.pop(); }

let passphrase = Passphrase::new(line);
// `line` moved into Passphrase; original buffer zeroized when
// Passphrase drops.
```

### Environment variable removal

- Delete `PROFILE_PASSPHRASE_ENV` constant from `igloo-shell-core/src/shell.rs:42`.
- Delete env-reader at `igloo-shell-core/src/shell/encrypted_profile.rs:66`.
- Grep-audit: `rg 'PROFILE_PASSPHRASE_ENV|IGLOO_SHELL_PROFILE_PASSPHRASE' repos/` returns no matches post-refactor.
- Also migrate `IGLOO_SHELL_ONBOARDING_PASSWORD` to stdin-pipe handoff using the same mechanism. One-shot password for onboarding flows; same hygiene as profile passphrase. Grep-audit: `rg 'IGLOO_SHELL_ONBOARDING_PASSWORD|ONBOARDING_PASSWORD_ENV' repos/` returns no matches post-refactor. Any CLI caller that currently reads from env var now reads from stdin.

### Breaking change: CLI scripting

Anyone currently scripting `IGLOO_SHELL_PROFILE_PASSPHRASE=... igloo-shell profile load` must update to:
```
echo "$PASSPHRASE" | igloo-shell profile load ...
```

Document in release notes. Alpha allows this break.

### Testing

- `daemon_reads_passphrase_from_stdin` — spawn daemon, write passphrase
  to stdin, assert unlock succeeds.
- `daemon_rejects_missing_stdin_passphrase` — spawn without writing to
  stdin; expect clean error (not panic or hang).
- `daemon_passphrase_not_in_environ` — spawn daemon; read
  `/proc/<pid>/environ`; assert passphrase not present.
- `daemon_passphrase_zeroized_after_read` — direct-memory test of
  `Passphrase` type; covered by C.3 tests.

---

## C.6 — Session-scoped KDF cache (`UnlockSession`)

### Approach

New type in `bifrost-app::host`:

```rust
pub struct UnlockSession {
    profile_id: ProfileId,
    file_store_key: FileStoreKey,  // Bucket A newtype, ZeroizeOnDrop
    // Passphrase NOT held — already consumed by Argon2 during KDF.
}

impl UnlockSession {
    pub fn new(
        passphrase: Passphrase,
        salt: &[u8; 16],
        params: &Argon2Params,
        profile_id: ProfileId,
    ) -> Result<Self, UnlockError> {
        let key = derive_file_store_key(&passphrase, salt, params)?;
        // `passphrase` is dropped here, zeroizing its buffer.
        Ok(Self { profile_id, file_store_key: FileStoreKey::new(key) })
    }

    pub fn decrypt_profile(&self, record: &EncryptedProfileRecord)
        -> Result<Vec<u8>, DecryptError>;
}
// ZeroizeOnDrop via FileStoreKey.
```

### Lifetime

One `UnlockSession` per daemon process, created at daemon startup after
reading the passphrase from stdin. Lives for the daemon's entire process
lifetime. Dropped (and zeroized) at process exit.

Not shared across processes. CLI commands that spawn a child daemon
create their own session in the child; CLI commands that communicate with
an existing daemon go through the socket IPC (already authenticated via
`DaemonToken`).

### Cache hit path

Every `decrypt_encrypted_profile` call in daemon context uses the cached
`FileStoreKey` instead of re-running Argon2. Encrypt/decrypt AEAD
operations still run per-op (correct — the AEAD is fast).

With Bucket B's m=256 MiB / t=4 defaults, this turns ~400-600 ms per
operation into ~1 ms per operation. Daemon response latency for Sign/Ecdh
operations becomes network-bound rather than KDF-bound.

### Explicit invalidation

`UnlockSession` does NOT invalidate automatically. If the operator rotates
their passphrase, the daemon must be restarted (hard-cut). Flag for future
if the UX gets painful. Rotation of the SHARE is different — handled by
the rotation flow, not the unlock session.

### Testing

- `unlock_session_reuses_key_across_decrypts` — unlock once, decrypt two
  records, observe (via mock or timing) that Argon2 runs once.
- `unlock_session_zeroizes_on_drop` — covered by `FileStoreKey` tests.
- `unlock_session_wrong_passphrase_fails_at_create` — constructor
  validates by decrypting a known fixture; returns `UnlockError::Decrypt`
  on wrong passphrase.

---

## C.7 — Rotation intent journal

### Approach

Minimal first pass: detect and log incomplete rotations; do not auto-recover.

Single file per rotation workspace:
`rotations_dir/<workspace_id>/.intent.json` (`0o600`, written via
`write_restricted_bytes_atomic`).

Shape:

```rust
#[derive(Serialize, Deserialize)]
pub struct RotationIntent {
    pub workspace_id: String,
    pub kind: RotationKind,       // RotateShare | RotateKeyset
    pub profile_id: String,
    pub started_at: u64,          // unix seconds
    pub step: RotationStep,       // see below
    pub updated_at: u64,
}

#[derive(Serialize, Deserialize)]
pub enum RotationStep {
    PreCreate,                // intent written; nothing changed yet
    PostCreateNewProfile,     // new profile created; old still exists
    PostWriteNewManifest,     // new manifest committed
    PreRemoveOldProfile,      // about to delete old
    Completed,                // all operations successful
}
```

### Write sites

In `igloo-shell-core/src/shell/rotation.rs::finalize_rotation_update_import`
(the 7-step sequence audit-flagged), write the intent BEFORE each
step-transition:

```rust
let mut intent = RotationIntent::new(workspace_id, kind, profile_id);
write_intent(&paths, &intent)?;  // step = PreCreate

create_new_profile(...)?;
intent.advance(RotationStep::PostCreateNewProfile)?;
write_intent(&paths, &intent)?;

write_new_manifest(...)?;
intent.advance(RotationStep::PostWriteNewManifest)?;
write_intent(&paths, &intent)?;

remove_old_profile(...)?;
intent.advance(RotationStep::Completed)?;
write_intent(&paths, &intent)?;

delete_intent(&paths)?;  // cleanup; Completed is fleeting
```

If a crash occurs between `advance` and `delete_intent`, the `.intent.json`
file remains on disk.

### Startup scan

At daemon start (in `bifrost-app::host::daemon::run_resolved_daemon`):

```rust
let incomplete = scan_rotation_intents(&paths)?;
for intent in incomplete {
    warn!(
        workspace_id = %intent.workspace_id,
        step = ?intent.step,
        started_at = intent.started_at,
        "incomplete rotation detected; manual inspection required"
    );
}
```

No auto-recovery in first pass. Operator runs `igloo-shell rotation
inspect` (new subcommand, optional stretch goal for PR12) to see what's
stuck. Auto-recovery is explicitly deferred to a future bucket.

### Testing

- `rotation_intent_written_before_each_step` — instrument the rotation
  flow; assert intent file exists between steps with correct step value.
- `rotation_intent_cleaned_up_on_success` — full rotation; assert
  `.intent.json` absent at end.
- `incomplete_rotation_detected_on_startup` — leave a `PostCreateNewProfile`
  intent in place; start daemon; assert warn log.
- `intent_scan_ignores_completed` — an intent with `step = Completed` that
  wasn't cleaned up (edge case) should not trigger a warning.

---

## Critical Files

Modify (`bifrost-rs`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/Cargo.toml` (add `tempfile = "3"` to `[workspace.dependencies]`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-core/Cargo.toml` (if `subtle` / `rand_core` need adding there for `DaemonToken`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-core/src/secret.rs` (add `Passphrase`, `DaemonToken`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/Cargo.toml` (add `tempfile.workspace = true`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/fs_guard.rs` (NEW — helpers)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/paths.rs` (migrate to `ensure_dir_restricted`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-profile/src/native.rs` (migrate `fs::write` sites; take `&Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/host/daemon.rs` (token CT compare; socket chmod; umask; stdin read for passphrase)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/host/client.rs` (pass `DaemonToken` explicitly in requests)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/host/protocol.rs` (`ControlRequest.token: DaemonToken`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs/crates/bifrost-app/src/host/unlock.rs` (NEW — `UnlockSession`)

Modify (`igloo-shell`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell.rs` (remove `PROFILE_PASSPHRASE_ENV`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell/io.rs` (migrate `write_json` to `write_restricted_bytes_atomic`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell/daemon.rs` (token generation; remove `--token` argv; stdin write passphrase)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell/shared.rs` (`/run/user/$UID/` fallback; typed error for too-long)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell/encrypted_profile.rs` (remove env-var reader)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell/rotation.rs` (intent journal writes; `Passphrase` parameter)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/commands/prompts.rs` (return `Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/commands/rotation.rs` (thread `Passphrase`; remove `.clone()`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/commands/imports.rs` (7 `.clone()` sites; thread `Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/commands/profile.rs` (thread `Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/main.rs` (top of `main()`: `umask(0o077)`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/README.md` (add `SECURITY.md` link)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/SECURITY.md` (NEW — document the hardening contract)

Documentation:
- `/home/cscott/Repos/frostr/frostr-infra/docs/PROFILE.md` (new "Host-Local Security Model" section)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/SECURITY.md` (per-repo security model)

Reuse (do not re-invent):
- `zeroize` + `zeroize_derive` (already in workspace deps via Bucket A).
- `subtle::ConstantTimeEq` (added in Bucket A PR1).
- `rand_core::CryptoRngCore` (already used by bifrost-rs).
- `tempfile` (new workspace dep in this bucket).
- `Argon2Params`, `FileStoreKey` (from Bucket A/B).

## Verification

Per PR:

**PR8 (C.1 + C.2 — filesystem perms + atomic writes):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/bifrost-rs
cargo test -p bifrost-profile --offline
cargo clippy -p bifrost-profile --all-targets --offline --no-deps -- -D warnings
cargo fmt --all -- --check
```
Plus:
- `rg 'fs::write\(|fs::create_dir_all\(' crates/bifrost-profile/` returns no production matches (all via helpers).
- New fs_guard tests pass.
- Existing encryption tests still pass (migration is transparent to callers
  taking `&Passphrase` in PR9).

**PR9 (C.3 — secret newtypes):**
```bash
cargo test -p bifrost-core --offline
cargo clippy -p bifrost-core --all-targets --offline --no-deps -- -D warnings
```
Plus:
- `format!("{:?}", passphrase)` redaction test.
- `format!("{:?}", token)` redaction test.
- `DaemonToken::new_random` produces distinct values across two calls.
- `DaemonToken` `PartialEq` is via `subtle`.

**PR10 (C.4 + C.5 — daemon auth + stdin passphrase):**
```bash
cargo test -p bifrost-app --offline
cargo clippy -p bifrost-app --all-targets --offline --no-deps -- -D warnings
```
Plus:
- Socket file mode `0o600` verified in integration test.
- `daemon.json` mode `0o600` verified.
- Spawn daemon; `grep` its `/proc/<pid>/cmdline` for "token" → should not appear.
- Spawn daemon; `grep` its `/proc/<pid>/environ` for `IGLOO_SHELL_PROFILE_PASSPHRASE` → should not appear.
- `rg 'PROFILE_PASSPHRASE_ENV' crates/` returns no matches.

**PR11 (C.6 + C.7 — UnlockSession + rotation journal):**
```bash
cargo test -p bifrost-app -p bifrost-profile --offline
cargo clippy -p bifrost-app -p bifrost-profile --all-targets --offline --no-deps -- -D warnings
```
Plus:
- `UnlockSession` reuse test passes.
- Rotation intent write / scan / cleanup tests pass.

**PR12 (igloo-shell consumer migration):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell
cargo test --workspace --offline
cargo clippy --workspace --all-targets --offline --no-deps -- -D warnings
cargo fmt --all -- --check
```
Plus:
- `rg 'passphrase\.clone\(\)|password\.clone\(\)' repos/igloo-shell/` returns only sites with a justification comment.
- `rg 'PROFILE_PASSPHRASE_ENV|IGLOO_SHELL_PROFILE_PASSPHRASE' repos/igloo-shell/` returns no matches.
- Manual smoke from the parent workspace:
  ```bash
  cd /home/cscott/Repos/frostr/frostr-infra
  make demo-start
  make demo-onboard
  make demo-smoke
  make demo-stop
  ```
  Confirm passphrase prompts work, daemon starts, onboarding and sign flows complete on the new auth path.

**Full-bucket verification (after PR12):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```

## Cross-Repo Coordination

Bucket C ships in the **same coordinated release** as Buckets A + B.
Alpha; one operator migration event covers all three buckets.

Contents of that single release:
- **Bucket A:** `DeviceState::VERSION` 5→6, secret newtypes, NIP-44 consolidation.
- **Bucket B:** `ENCRYPTED_PROFILE_VERSION` 1→2, `ProtectedPackageEnvelope::version` 1→2, Argon2id+XChaCha20Poly1305 unification.
- **Bucket C:** daemon auth hardening, passphrase transport, file perms, UnlockSession.

Operator impact:
- Re-onboard all profiles (driven by A+B version bumps).
- Rebuild any script or service using `IGLOO_SHELL_PROFILE_PASSPHRASE=...` or `IGLOO_SHELL_ONBOARDING_PASSWORD=...` — switch to `echo "$PASSPHRASE" | igloo-shell ...`.
- Any tooling scraping `/proc/*/cmdline` for the daemon token will break — the token is no longer there.
- Existing world-readable `.enc` files from old installs become unreadable anyway due to A+B, so the perms tightening in Bucket C is invisible to operators.

No additional DeviceState / envelope / package version bumps in Bucket C
beyond what A+B introduce. Bucket C changes the daemon-client protocol
(token no longer in argv; passphrase via stdin) but not any on-disk
persisted format.

Per `/home/cscott/Repos/frostr/frostr-infra/dev/docs/RELEASE.md` coordinated
release process.

## Out-of-Bucket Flags

- **Auto-recovery of incomplete rotations** — first pass detects and logs;
  auto-rollback is a future enhancement. Flag as "Bucket C follow-up."
- **UnlockSession idle timeout / re-auth** — session lives for daemon
  lifetime with no idle timeout. A real idle-TTL with passphrase re-prompt
  would reduce memory-extraction window, but only if the derived key is
  dropped and re-derived — a meaningful UX and engineering addition.
  Deferred; reconsider if attacker-with-memory-access becomes an explicit
  part of the threat model.
- **Multi-user privilege model** — Bucket C assumes "same UID = trusted."
  Hardening against a hostile same-UID process is explicitly out of scope.
- **Typed-error transport across Tauri IPC** — Bucket E owns that (raised
  in Bucket B's plan as well).
- **Windows support** — Daemon remains `#[cfg(unix)]`-only.

## Summary

Five PRs across two submodules, ~2,200 lines touched. Closes the local-UID
privilege-escalation chain the audit flagged. Key moves:

- **Filesystem perms:** `umask(0o077)` + explicit `0o600`/`0o700` via
  centralized helpers; atomic manifest writes via `tempfile::persist`
  with `fsync`.
- **Secret newtypes:** `Passphrase` + `DaemonToken` extend Bucket A's
  `bifrost-core::secret`. Zeroized on drop, redacted Debug, constant-time
  comparison. Eliminates 10+ `.clone()` sites; remaining clones explicit
  and documented.
- **Daemon auth:** 256-bit `OsRng` token; handoff via `daemon.json`
  (`0o600`), not argv; no env-var passphrase; socket `0o600`; parent dir
  `0o700`; constant-time compare; `/run/user/$UID/` replaces `/tmp`
  fallback.
- **Passphrase transport:** stdin pipe from parent to child; both
  `IGLOO_SHELL_PROFILE_PASSPHRASE` and `IGLOO_SHELL_ONBOARDING_PASSWORD`
  env vars removed end-to-end.
- **Perf:** `UnlockSession` caches the derived `FileStoreKey` for daemon
  lifetime, turning Bucket B's ~400-600 ms Argon2 cost into a one-time
  startup cost. Sign/Ecdh operations become network-bound, not KDF-bound.
- **Crash safety:** rotation intent journal detects incomplete rotations on
  startup; auto-recovery deferred.
- **Ships in the same coordinated release** as Buckets A + B. One
  migration event covers three buckets. CLI scripting users must switch
  from env var to stdin pipe for both profile passphrase and onboarding
  password.
