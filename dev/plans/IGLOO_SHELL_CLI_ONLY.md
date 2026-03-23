# `igloo-shell` CLI-Only Hard-Cut Plan

## Summary

Remove the `igloo-shell` TUI and make `igloo-shell` a CLI-only tool for now.

This is a hard cut:

- no embedded full-screen session shell remains
- no automatic CLI-to-TUI handoff remains
- no TUI-specific tests, scripts, docs, or dependencies remain
- the supported shell UX becomes:
  - explicit CLI commands
  - interactive CLI prompts where needed
  - human-readable command output by default
  - `--json` for machine use

The CLI already owns the important product flows:

- `profile load`
- `import`
- `recover`
- `onboard`
- `keygen`
- `daemon`
- `runtime`
- `peer`
- `policy`
- `relays`

The work is to complete that transition and remove the TUI session shell as a second product surface.

## Goals

- simplify `igloo-shell` to one primary interface
- remove `ratatui` / terminal UI maintenance cost
- keep all core shell/runtime capabilities available through the CLI
- preserve interactive prompts for secrets and guided inputs where they still help
- replace TUI handoff behavior with clear CLI next steps

## Non-Goals

- no replacement curses-style UI
- no compatibility shim for the old logged-in shell
- no attempt to preserve the old `Dashboard / Permissions / Settings` interaction model

## Phase 1: Stop Launching the TUI

### Objective

Break the CLI’s runtime dependency on the TUI before deleting code.

### Changes

- Remove the `launch_dashboard(...)` handoff from:
  - `profile load`
  - `import`
  - `recover`
  - `onboard`
  - `keygen`
- Replace each success path with:
  - a concise human-readable success summary
  - clear next commands
  - unchanged `--json` output for machine workflows

### Required behavior changes

- `profile load`
  - validate the profile and vault secret
  - do not open a session shell
  - instead:
    - unlock validation succeeds
    - optionally start the daemon if that becomes the new contract
    - print recommended next commands such as:
      - `igloo-shell daemon start --profile <id>`
      - `igloo-shell runtime status --profile <id>`
- `import`, `recover`, `onboard`, `keygen`
  - continue to perform the operation
  - continue to publish backups where applicable
  - stop auto-entering the logged-in shell
  - print next actions instead

### Decision to lock during this phase

Adopt one explicit CLI convention for “what to do after profile creation”:

- Recommended default:
  - profile creation/import/recovery/onboarding/keygen end with success output plus suggested commands
  - daemon start remains explicit

This is simpler than replacing the TUI handoff with hidden daemon auto-start.

### Exit criteria

- no user-facing command automatically launches the TUI
- all success paths end cleanly in the terminal
- `--json` output contracts remain intact

## Phase 2: Replace TUI-Only Capabilities with CLI Commands

### Objective

Ensure nothing important is lost when the TUI is removed.

### Gaps to close

The TUI currently provides convenient access to:

- dashboard-style runtime status
- policy editing
- peer actions like ping/onboard
- daemon start/stop and log detail toggles
- logout semantics

Most of these already exist in the CLI, but the plan should tighten them so the CLI is sufficient and coherent.

### Changes

- Audit and tighten the CLI output and affordances for:
  - `runtime status`
  - `runtime diagnostics`
  - `peer list`
  - `peer ping`
  - `peer onboard`
  - `policy show`
  - `policy set-default-override`
  - `policy set-peer-override`
  - `policy clear-peer`
  - `daemon start|stop|restart|status|logs`
- If needed, add one or two missing convenience commands, but only if they express real state transitions and are not “mini-TUI” replacements.

### Logout replacement

The TUI currently models “logout” as leaving the logged-in shell and stopping the daemon for the active session.

Hard-cut replacement:

- there is no shell session to log out from
- use explicit daemon lifecycle commands instead
- if any “session unlock” state remains in shell internals, expose explicit CLI behavior for clearing it or remove it if it is TUI-only

### Exit criteria

- every TUI-only operational action has a CLI equivalent or is intentionally removed
- docs can explain shell usage without referring to dashboard tabs or session-shell concepts

## Phase 3: Delete TUI Code and Dependencies

### Objective

Remove the TUI implementation from the codebase.

### Changes

- Delete:
  - `repos/igloo-shell/crates/igloo-shell-core/src/tui.rs`
- Remove:
  - `pub mod tui;` from `igloo-shell-core`
  - `use igloo_shell_core::tui;` from the CLI crate
  - `launch_dashboard(...)` helper and any TUI launch options/types that become unused
- Remove TUI-specific dependencies from shell crates:
  - `ratatui`
  - `crossterm` usage that only exists for the TUI
- Keep simple terminal prompt behavior if still needed for hidden-secret prompts.
  - If `crossterm` is only used for secret prompts after TUI removal, consider either:
    - keeping it narrowly for prompt masking
    - or replacing it with a smaller prompt approach

### Exit criteria

- no TUI module remains in `igloo-shell`
- no CLI code references TUI launch helpers
- terminal UI dependencies are removed or reduced to prompt-only use

## Phase 4: Remove TUI Tests, Scripts, and Fixtures

### Objective

Delete the TUI maintenance surface and replace it with CLI-focused validation.

### Changes

- Delete or retire:
  - `repos/igloo-shell/scripts/test-tui-e2e.sh`
  - TUI-specific dev data under `dev/data/tui-e2e`
- Remove TUI-specific assertions from:
  - shell docs
  - CI/test scripts
  - any root repo wrappers that still mention TUI checks
- Replace TUI coverage with CLI-focused checks where needed:
  - `profile load` interactive prompt coverage
  - daemon start/stop/status coverage
  - policy mutation coverage
  - onboarding/import/recovery/keygen happy-path coverage

### Test replacements

- Prefer:
  - Rust integration tests in `igloo-shell-cli/tests`
  - existing `scripts/test-node-e2e.sh`
  - `scripts/devnet.sh smoke`
- Add new integration tests if removing the TUI leaves any behavioral gap in:
  - prompt resolution
  - post-import next-step output
  - daemon lifecycle flows

### Exit criteria

- no TUI-specific script remains in the active test workflow
- shell test coverage is CLI-only

## Phase 5: Rewrite Shell Docs and Product Positioning

### Objective

Make the documentation fully consistent with a CLI-only shell.

### Changes

- Update:
  - `repos/igloo-shell/docs/V2-SHELL-SPEC.md`
  - `repos/igloo-shell/docs/GUIDE.md`
  - `repos/igloo-shell/docs/OPERATIONS.md`
  - `repos/igloo-shell/docs/TESTING.md`
  - `repos/igloo-shell/docs/INDEX.md`
- Remove concepts like:
  - logged-in shell
  - logged-out shell
  - `Dashboard / Permissions / Settings` tabs
  - TUI entry behavior
  - logout from the session shell
- Replace with CLI-native guidance:
  - profile management
  - daemon lifecycle
  - runtime inspection
  - policy management
  - package onboarding/import/recovery
  - key generation and rotation

### Root-repo updates

- Audit root docs and scripts for references to:
  - `igloo-shell profile load` launching a shell UI
  - TUI coverage or `tmux` testing expectations
  - standalone TUI wording

### Exit criteria

- no active docs describe the shell as having a TUI session shell
- the CLI-only model is documented consistently

## Phase 6: Validation and Cleanup

### Objective

Prove the CLI-only shell works and delete leftover dead code.

### Required verification

- Rust:
  - `cargo check --workspace --offline`
  - `cargo test --workspace --offline`
- Shell-specific:
  - `cargo test -p igloo-shell-cli --test managed_integration --offline`
  - `cargo test -p igloo-shell-cli --test policy_integration --offline`
  - `scripts/devnet.sh smoke`
  - `scripts/test-node-e2e.sh`
- Repo-wide:
  - update any root test/docs references that still mention TUI

### Cleanup audit

- grep for:
  - `tui`
  - `ratatui`
  - `Dashboard`
  - `Permissions`
  - `Settings`
  - `test-tui-e2e`
- confirm only historical notes or intentionally archived references remain

### Exit criteria

- `igloo-shell` builds and tests without the TUI
- no active docs or scripts depend on the TUI
- the supported shell surface is clearly CLI-only

## Risks

- `profile load` semantics will change most visibly
  - users currently expect a logged-in shell after unlock
  - the replacement must be explicit and easy to understand
- some policy/runtime inspection flows may feel less discoverable without the TUI
  - CLI output needs to be readable enough to compensate
- removing TUI scripts may expose missing CLI integration coverage
  - plan includes replacing that coverage where necessary

## Recommended Implementation Order

1. Phase 1: stop launching the TUI
2. Phase 2: tighten CLI equivalents
3. Phase 3: delete TUI code/deps
4. Phase 4: remove TUI tests/scripts/fixtures
5. Phase 5: rewrite docs
6. Phase 6: validate and cleanup

## Acceptance Target

At completion:

- `igloo-shell` is a CLI-only tool
- all setup, import, recovery, onboarding, daemon, runtime, peer, policy, relay, and key operations are done through commands and prompts
- no full-screen terminal UI remains in the supported interface
