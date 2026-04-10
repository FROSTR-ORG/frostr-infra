# Hard-Cut Cleanup Plan for `igloo-shell`

## Summary
Do a behavior-preserving structural cleanup of `igloo-shell` focused on the oversized shell core, CLI entrypoint, and test harness.

Goals:
- split the `igloo-shell-core` god module into domain modules
- split the CLI command parsing layer from command execution
- reduce dependence on process-global env var unlock flow
- make CLI integration tests faster, clearer, and less monolithic

## Why This Matters
- [crates/igloo-shell-core/src/shell.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-core/src/shell.rs) is 3755 lines and mixes paths, config, profiles, encrypted profile, relay profiles, onboarding, rotation, policy, backup, daemon control, and test helpers.
- [crates/igloo-shell-cli/src/main.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/src/main.rs) is 2753 lines and mixes Clap schema, interactive prompts, output rendering, and business logic dispatch.
- [crates/igloo-shell-cli/tests/support/mod.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell/crates/igloo-shell-cli/tests/support/mod.rs) is 911 lines and currently acts as a giant mixed harness.

## Key Changes

### 1. Split `igloo-shell-core` by domain
Move the core implementation out of `shell.rs` into `crates/igloo-shell-core/src/shell/`.

Target split:
- `paths.rs`
  - `ShellPaths`
  - path creation and directory layout
- `config.rs`
  - shell config
  - relay profiles
  - keyring preference and fallback unlock settings
- `profiles.rs`
  - profile manifests
  - profile CRUD
  - doctor/load/list/remove
- `encrypted profile.rs`
  - encrypted profile record schema
  - encryption/decryption
  - unlock and passphrase flow
- `relay_profiles.rs`
  - relay profile add/replace/remove/default logic
- `daemon.rs`
  - daemon metadata
  - start/stop/restart/status
  - runtime query helpers
- `onboarding.rs`
  - raw import
  - onboarding package import
  - bfprofile/bfshare recovery
- `rotation.rs`
  - rotation workspace
  - rotate-key/rotate-keyset helpers
- `policy.rs`
  - peer policy override parsing and persistence
- `backup.rs`
  - relay backup publish/export/import helpers

Rules:
- no single file should own both disk layout and relay/network orchestration
- core logic should return typed domain values rather than large generic JSON blobs where avoidable

### 2. Split CLI parsing from execution
Keep `main.rs` as a thin composition layer only.

Move implementation into `crates/igloo-shell-cli/src/commands/`.

Target split:
- `commands/import.rs`
- `commands/export.rs`
- `commands/recover.rs`
- `commands/profile.rs`
- `commands/daemon.rs`
- `commands/runtime.rs`
- `commands/check.rs`
- `commands/peer.rs`
- `commands/policy.rs`
- `commands/relays.rs`
- `commands/rotate.rs`
- `commands/keys.rs`
- `output.rs`
- `interactive.rs`

Rules:
- Clap definitions should be near the command they serve, not piled into one file
- command execution should call typed shell-core APIs, not reconstruct shell behavior locally
- output formatting should be centralized so machine-readable and human-readable output policies are consistent

### 3. Reduce env-var-based encrypted profile/session coupling
The current unlock contract leans heavily on `IGLOO_SHELL_PROFILE_PASSPHRASE`, and that leaks into downstream apps and tests.

Refactor toward:
- explicit unlock parameters for shell-core operations that require encrypted profile access
- a typed session/unlock context object where repeated unlock use is necessary
- env-var fallback only as a CLI convenience boundary, not as the core library contract

This is especially important because the current model forces unsafe env mutation in downstream hosts like `igloo-home`.

### 4. Split and simplify the CLI test harness
Move the current giant support module into focused helpers under `tests/support/`.

Target split:
- `harness.rs`
  - root tempdir and process environment
- `relay.rs`
  - relay lifecycle and availability waiting
- `commands.rs`
  - run/run_with_env/run_expect_failure helpers
- `fixtures.rs`
  - keygen/profile material setup
- `assertions.rs`
  - JSON/output helpers

Rules:
- the test harness should not serialize the whole suite through one giant mixed helper unless truly necessary
- relay lifecycle should be reusable across scenarios without copying shell command boot logic

### 5. Add a clearer library boundary for downstream consumers
`igloo-home` and future hosts should be able to use shell-core domain APIs without depending on CLI-oriented assumptions.

Make sure shell-core exposes:
- typed profile import/export/recovery APIs
- typed daemon/runtime query APIs
- typed rotation/update APIs

without requiring callers to emulate CLI env handling or output formatting.

## Public APIs / Interface Changes
- End-user CLI surface should remain behaviorally stable.
- Internal module layout changes substantially.
- Shell-core APIs may gain more explicit unlock/session parameters.
- CLI may keep env-var fallback at the outer boundary for compatibility.

## Test Plan
- `cargo test -p igloo-shell-core`
- `cargo test -p igloo-shell-cli`
- workspace `cargo test`
- targeted integration verification for:
  - import/export/recover flows
  - daemon start/stop/status
  - runtime sign/ecdh/diagnostics
  - peer policy overrides
  - rotation flows

## Acceptance Criteria
- `shell.rs` is no longer the single implementation file for the entire product
- `main.rs` becomes a thin CLI entrypoint
- shell-core no longer requires env-var mutation as its primary unlock contract
- test support is split into focused modules
- downstream apps can consume shell-core more cleanly

## Assumptions and Defaults
- Preserve CLI behavior and current data layout unless a later migration plan explicitly changes them.
- Prefer typed library contracts over env-var-driven implicit behavior.
- Optimize first for maintainability and downstream host reuse, then for any follow-on feature work.
