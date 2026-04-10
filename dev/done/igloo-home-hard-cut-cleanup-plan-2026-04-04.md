# Hard-Cut Cleanup Plan for `igloo-home`

## Summary
Do a behavior-preserving structural cleanup of `igloo-home` focused on three areas:

- split the Tauri app and signer-session control plane into explicit services
- remove process-global env mutation from runtime startup
- redesign local test strategy so repeated visible desktop popups are no longer the default developer experience

## Why This Matters
- [src-tauri/src/lib.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/lib.rs) mixes Tauri commands, tray/window behavior, startup wiring, autostart, test-mode setup, and app state bootstrap.
- [src-tauri/src/session.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session.rs) mixes signer lifecycle, event emission, logging, close behavior, and resume state.
- [src-tauri/src/test_mode.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/test_mode.rs) is effectively a second command router layered beside the real app commands.
- The desktop harness in [test/desktop/run.mjs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/test/desktop/run.mjs) intentionally launches a real Tauri window, waits for it via `xwininfo`, and screenshots it via `import`, which is why local testing causes visible popups.

## Popup Question: Concrete Direction
Yes, it is possible to get rid of the repeated visible popups during `igloo-home` testing, but not while keeping the current desktop screenshot harness unchanged.

Chosen direction:
- make headless visual testing the default UI-observability path
- keep desktop Tauri smoke as an opt-in or CI-only path
- when desktop smoke is needed, run it in a virtual display such as `xvfb-run` so it does not steal focus on the developer desktop

Do not try to simply hide the Tauri window in test mode while still using the current `xwininfo`/`import` workflow, because that would make the desktop harness invalid.

## Key Changes

### 1. Split Tauri app wiring into explicit modules
Keep `src-tauri/src/lib.rs` as a thin bootstrap file only.

Move implementation into `src-tauri/src/app/`.

Target split:
- `commands.rs`
  - Tauri command registration only
- `window.rs`
  - show/hide/focus logic
  - close-request behavior
- `tray.rs`
  - tray sync and menu handling
- `settings.rs`
  - settings load/save/apply orchestration
- `bootstrap.rs`
  - app startup
  - state construction
  - test-mode startup hook

Rules:
- Tauri invoke handlers should delegate into services, not implement behavior inline
- window/tray logic should stop being entangled with profile/session commands

### 2. Split signer session orchestration
Move the signer/session implementation out of `session.rs` into `src-tauri/src/session/`.

Target split:
- `controller.rs`
  - start/stop/resume lifecycle
  - active signer ownership
- `events.rs`
  - app event emission
  - lifecycle/status/log payload helpers
- `logs.rs`
  - in-memory log buffer
  - persisted session log helpers
- `close.rs`
  - close-to-tray and close-request resolution
- `resume.rs`
  - session resume state and last-session metadata

Rules:
- one controller should own signer lifecycle
- event emission and session logging should not be mixed into all lifecycle methods

### 3. Remove unsafe env-var mutation from runtime startup
Current startup mutates `IGLOO_SHELL_PROFILE_PASSPHRASE` and XDG directories in-process in [session.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session.rs#L125) and [lib.rs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/lib.rs#L489).

Refactor toward:
- explicit unlock/session parameters passed into shell-core/runtime APIs
- explicit test path overrides in app state/bootstrap rather than global env mutation
- env vars only at the outer process boundary if absolutely needed for compatibility

This likely depends on parallel cleanup in `igloo-shell` and `bifrost-rs`.

### 4. Replace duplicated test-control routing with service-backed test hooks
`test_mode.rs` should stop being a second ad hoc router over app behavior.

Refactor toward:
- one thin test transport layer
- test requests delegating to the same services used by real Tauri commands

Benefits:
- less drift between real app behavior and test-only behavior
- easier unit/integration coverage
- lower maintenance cost for new features

### 5. Rebalance the test strategy to remove popup-heavy local runs
Adopt this testing model:

- `test:unit`
  - component and app-local logic tests only
- `test:visual`
  - primary UI observability path
  - headless Chromium against deterministic preview scenarios
- `test:desktop`
  - reduced-scope Tauri smoke only
  - opt-in locally
  - preferred in CI or under virtual display

Concrete harness changes:
- keep [test/visual/run.mjs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/test/visual/run.mjs) as the main visual test path
- reduce [test/desktop/run.mjs](/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/test/desktop/run.mjs) to a minimal real-window smoke
- add support for running desktop smoke under `xvfb-run` on Linux
- update docs so developers do not default to popup-heavy desktop tests

### 6. Optional test-mode hidden-window path
If you still want a non-interruptive Tauri-specific local check, add a separate hidden-window test mode:
- test mode starts the app without calling `window.show()`
- assertions run exclusively through the test TCP API and emitted app state
- no screenshot capture

This should be a separate mode, not a silent change to the existing desktop screenshot harness.

## Public APIs / Interface Changes
- End-user app behavior should remain stable.
- Internal module layout changes substantially.
- Test behavior changes intentionally:
  - desktop smoke becomes opt-in and no longer the recommended default local path
  - visual smoke becomes the default UI-observability path

## Test Plan
- `npm run test:unit`
- `npm run test:visual`
- `IGLOO_HOME_RUN_DESKTOP_TESTS=1 npm run test:desktop` under virtual display or CI
- targeted Rust tests for:
  - session controller start/stop/resume
  - close-request handling
  - test-mode transport delegation

## Acceptance Criteria
- `lib.rs` stops being a mixed command/tray/window/startup monolith
- `session.rs` stops being the single signer lifecycle implementation file
- test-mode requests share service code with real commands
- local default testing no longer produces repeated visible window popups
- desktop smoke remains available when explicitly requested

## Assumptions and Defaults
- Preserve user-facing Tauri behavior.
- Prefer headless visual coverage over always-on desktop-window capture.
- Treat popup elimination as a test-strategy change, not a window-hiding hack.
- Coordinate the env-var cleanup with `igloo-shell` and `bifrost-rs` so `igloo-home` can use explicit runtime inputs instead of global process mutation.
