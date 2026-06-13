# `igloo-home` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home`

This audit focused on the Tauri boundary (config, capabilities, command handlers), the Rust backend's panic surface and secret handling, the shape of the in-process test server, and the React front-end's control flow and tests. The repo is small and the command layer is clean, but the Tauri shell is configured more loosely than the desktop signer warrants, the embedded test server opens an unauthenticated command channel when enabled, and `App.tsx` has drifted into a single 1,875-line controller that mirrors runtime shape locally.

## Findings

### 1. High: `tauri.conf.json` disables CSP and ships no bundle identifier hardening

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/tauri.conf.json:25-27`

Why this matters:
- `"security": { "csp": null }` explicitly opts out of Tauri's Content Security Policy. For a desktop signer that touches secret share material, passphrases, and onboarding packages, a tight CSP is the main defense against an injected string or renderer-side XSS exfiltrating to `http(s)` or `ws(s)` endpoints.
- There is no `devCsp`, `freezePrototype`, `assetProtocol`, or `dangerousDisableAssetCspModification` override either way, so every policy lever is left at the default-of-"none".
- The config does not pin an updater endpoint or public key, so if an updater is added later without review the default posture will be unsafe.

Smells:
- `csp: null` committed as the long-term shape rather than an explicit development escape.
- No separation between a relaxed dev CSP and a tight release CSP.

Streamline:
- Set a strict `csp` with `default-src 'self'`, narrow `connect-src` only to the relay schemes and the Tauri IPC origin, and explicit `script-src 'self'`.
- If `csp: null` is required in dev, express that via a separate dev-only override rather than the shipped config.

### 2. High: the embedded test-mode TCP server exposes the full command dispatcher with no auth

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/test_mode.rs:10-45`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:40-42`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/test_dispatch.rs:23-293`

Why this matters:
- When `IGLOO_HOME_TEST_MODE` is truthy and `IGLOO_HOME_TEST_PORT` is set, `start_server()` binds `127.0.0.1:<port>` and accepts any JSON line with `{request_id, command, input}`. The dispatcher can import profiles, start sessions, stop the signer, rotate keys, export `bfprofile`/`bfshare`, and publish backups — effectively the entire backend surface.
- There is no request token, no origin check beyond listening on loopback, and no gating that test mode is actually in a disposable environment. Any local process (including a browser tab via a CORS-less socket-adjacent technique, or another user on a shared machine) can drive the signer once the port is up.
- `is_test_mode()` only requires an env var set to `1`/`true`/`yes`; if that env accidentally leaks into a packaged or CI-attached session, the door opens.

Smells:
- Full production command dispatcher reused verbatim in a test transport.
- No shared secret or handshake on the test channel.
- Test-mode gating is a single env string with no safety interlock on bundle identifier or build flavor.

Streamline:
- Require a bootstrap token written to a file with user-only permissions, and have the test harness read the token before connecting.
- Or compile the test server behind a dedicated `#[cfg(feature = "test-server")]` and refuse to build it in release profiles.
- At minimum, refuse to start the listener unless both `IGLOO_HOME_TEST_MODE` and a matching `IGLOO_HOME_TEST_TOKEN` are present.

### 3. High: Tauri capability allowlist is permissive and no fs/shell scope is defined

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/capabilities/default.json:1-7`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/Cargo.toml:25-27`

Why this matters:
- `permissions` includes `core:default`, `dialog:default`, and `autostart:default`. `core:default` pulls in the broad core plugin surface (event, path, window, webview, app, etc.) rather than a scoped subset.
- There is no `fs` plugin, but `dialog:default` exposes file dialogs whose results are then handed to Rust commands that pass `PathBuf::from(input.destination_dir)` straight through to bifrost export code (see Finding 5). Capabilities and Rust handlers both lack path-scope enforcement.
- `autostart:default` grants full launch-on-login control to the renderer without narrowing to the specific argv used at bootstrap (`--from-autostart`).

Smells:
- One capability file with no per-window or per-route narrowing.
- No `fs:allow-*` scope rules even though the backend writes encrypted profile blobs and session logs.

Streamline:
- Replace `core:default` with the specific `core:*` permissions the renderer actually uses.
- Add a `fs` scope that restricts renderer-visible file APIs to the app data directory.
- Narrow `autostart:default` to the specific commands the settings page needs.

### 4. High: the Rust entrypoint uses `expect`/`unwrap` liberally, and any poisoned mutex kills the backend

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:18-26`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:47`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:101-102`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:32`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:106`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:174`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:193`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:206`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:231-237`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:308-313`

Why this matters:
- `run()` panics on any failure to resolve paths, load settings, or build the Tauri app. Those panics kill the desktop app with no user-visible diagnostic path, and the daemon branch does `result.expect("run igloo-home profile daemon")`, which means a daemon IPC failure bubbles as a process crash.
- Every `state.signer.lock().unwrap()`, `state.settings.lock().unwrap()`, `state.close.lock().unwrap()`, and `state.pending_onboarding.lock().unwrap()` assumes the mutex is never poisoned. If a thread panics while holding any of these (for example the monitor thread's log-push code), the next command panics, taking the backend down.
- `refresh_runtime_peers` at `commands.rs:231-237` locks the signer mutex inside a Tauri command with `.unwrap()` on the guard — a poisoned mutex converts a recoverable condition into a crash.

Smells:
- No shared `fn lock_signer(&self) -> Result<MutexGuard<_>>` helper; every call site unwraps.
- Entrypoint treats config/dependency errors as unrecoverable even though they often reflect first-run conditions.

Streamline:
- Centralize mutex acquisition behind a helper that maps poison errors to `anyhow::Error`.
- In `run()`, surface setup failures via a visible error dialog before exiting, not via `.expect` at process root.

### 5. Medium: `export_profile_command` accepts a raw `destination_dir` string with no path validation

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:134-144`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/models.rs:123-128`

Why this matters:
- `ExportProfileInput.destination_dir` is a `String` that the handler converts with `PathBuf::from(input.destination_dir)` and passes to `bifrost_profile::export_profile` without canonicalization, symlink checks, or a scope guard.
- A renderer-side bug or injected string can pass `/etc` or a path containing `..` and get a file written there by the backend. Desktop Tauri file dialogs are the intended source, but the command itself has no policy that says so, and the dispatch layer happily accepts whatever the frontend sends.
- The same shape appears in `ListSessionLogsInput.runtime_dir` at `commands.rs:301-314`, which is then read and parsed as JSON lines — a hostile path could still cause unexpected reads.

Smells:
- `PathBuf::from(String)` in a command handler with no scope or canonicalization.
- Assumption that inputs only come from native file dialogs.

Streamline:
- Canonicalize the path and verify it is inside the desktop profiles/export root before proceeding.
- Treat the file-dialog path as hint, not as trust boundary: always re-validate in the command.

### 6. Medium: passphrases and onboarding passwords live on `String` with no zeroization

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/models.rs:60-136`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/models.rs:160-164`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:34-128`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/Cargo.toml:13-31`

Why this matters:
- Every input struct that carries a secret (`passphrase`, `onboarding_password`, `package_password`) uses `String` with `Deserialize`. These `String`s are cloned through `Some(input.passphrase)` and propagated into `bifrost_profile` and `native_runtime` calls, then dropped silently when the command returns.
- The crate has `argon2`, `chacha20poly1305`, and k256 in `Cargo.toml` but does not depend on `zeroize`. There is no `ZeroizeOnDrop` wrapper for passphrases at this layer, so secret bytes linger in heap pages until reuse.
- Runtime-triggered errors serialize the full `anyhow::Error` chain into a `String` returned to the renderer; any underlying error that includes passphrase-adjacent context is forwarded to the frontend verbatim.

Smells:
- Secrets modeled as plain `String` across a public IPC surface.
- No project-wide wrapper type (e.g. `PassphraseInput`) to centralize secret handling.

Streamline:
- Introduce a thin `SecretString` (or reuse `secrecy`/`zeroize`) and change every command input that carries a password to that type.
- Scrub error strings before returning them to the renderer.

### 7. Medium: the monitor task polls `bridge.status()` on a 2s loop and blocks shutdown on its join

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session.rs:194-224`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session/controller.rs:150-163`

Why this matters:
- `spawn_monitor` hard-codes a 2-second poll over `bridge.status()` and emits on changes. That duplicates live status events the bridge already emits and keeps waking the runtime while idle.
- `stop_signer()` does `active.monitor_handle.await` before snapshotting state. If the monitor task is mid-`bridge.status().await` against a wedged relay, stop is delayed by up to the poll interval, and a status-poll failure inside the loop writes a log entry (with a lock acquisition) that can itself contend with other writers.
- The monitor path is the most likely to panic while holding the signer mutex (see Finding 4), because it fires on every tick and the guard is held while pushing to `VecDeque` and calling `trim_logs`.

Smells:
- Polling used as primary status feed instead of a bridge subscription.
- Shutdown serializes behind a polling task's current iteration.

Streamline:
- Replace the poll with a subscription/channel from `bifrost-bridge-tokio` that the bridge already publishes status on.
- Add an explicit cancellation that breaks out of the current `await` rather than relying on the 2s loop to exit.

Cross-repo note: depends on whether `bifrost-bridge-tokio::Bridge` exposes a status stream; if not, the subscription shape should live in `bifrost-rs` and this monitor should switch when available.

### 8. Medium: `App.tsx` is a 1,875-line controller that re-models bifrost runtime types locally and polls the runtime

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:156-184`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:298-432`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:435-526`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:186`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:770-806`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx:820-881`

Why this matters:
- `App.tsx` inlines types that mirror runtime shape (`HomeRuntimeStatus`, `RuntimeOnboardingStatus`) and two large extractor functions (`extractPeerPermissionStates`, `extractRuntimePeers`) that unfold `runtime_status` four levels deep with repeated `as Record<string, unknown>` casts. This is a local copy of the runtime contract that will drift from whatever `bifrost-rs`/`igloo-shared` exports today.
- Alongside the event-driven refresh on lifecycle/status/log events, there is also a 2-second wall-clock poll (`ACTIVE_RUNTIME_POLL_INTERVAL_MS`) firing `profile_runtime_snapshot` against the backend. Events and polls trigger the same snapshot fetch — one transport should be enough.
- The component owns onboarding draft state, rotation state, distribution state, passphrase state, landing state, settings state, and runtime state in ~40 `useState` hooks, plus a confirm-dialog close handshake.

Smells:
- Single page component acting as data layer, controller, and renderer.
- Locally re-expressed runtime types instead of shared ones.
- Event subscriptions plus interval polls doing the same work.

Streamline:
- Lift typed runtime projections (peers, permissions, pending ops) into `igloo-shared` and consume them here.
- Extract a `useRuntimeSnapshot(profileId)` hook that owns the subscription and collapses the interval into a debounced refresh on event.
- Split the giant page into focused views (Landing, Create, Load, Onboard, Dashboard) with their own drafts.

Cross-repo note: if `igloo-shared` already exposes runtime-status projections used by `igloo-pwa`, this file should reuse those. If not, the shape belongs in `igloo-shared`, not in the desktop app.

### 9. Medium: Tauri commands are stringly named and return `Result<T, String>` without structured error taxonomy

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:338-554`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/lib/api.ts:17-23`

Why this matters:
- Every command returns `Result<T, String>` via `map_err(|error| error.to_string())`. The frontend then uses regex on that string (`/already exists/i.test(message)`) to decide whether to swap in a user-facing message. That is a string-match control path: any change to the underlying `anyhow!` message breaks the UX.
- `#[tauri::command]` handlers all end in `_command`. The suffix is redundant (the attribute already marks them as commands) and every frontend call includes the suffix in its `invoke()` argument. It's boilerplate without payoff.
- There is no shared error enum (`thiserror`-style) carrying variants like `ProfileAlreadyExists`, `InvalidPassphrase`, `OnboardingPending`. All callers pay for the classification gap.

Smells:
- Error classification implemented in TypeScript regexes.
- Command naming convention duplicates the `#[tauri::command]` attribute.

Streamline:
- Define a `HomeError` enum with `serde`-stable variants and return `Result<T, HomeError>` from commands.
- Drop `_command` suffixes and collapse the thin wrappers once a real error type exists.

### 10. Medium: duplicate test dispatcher keeps drifting from the Tauri command layer

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/test_dispatch.rs:23-293`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:72-100`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs:338-554`

Why this matters:
- `test_dispatch::dispatch_request` hand-rolls a `match` over command names that parallels the `invoke_handler![...]` list in `bootstrap.rs`. They already disagree: the dispatcher accepts a legacy `refresh_all_peers` alias (`test_dispatch.rs:278-283`) that is not registered as a Tauri command, and it does not expose `recover_profile_from_bfshare`, `export_profile_package`, `update_profile_operator_settings`, or `resolve_close_request`.
- Every new command means two registrations (Tauri handler + test dispatcher). New work silently lacks test coverage, and legacy aliases silently outlive their Tauri counterparts.
- `tauri::async_runtime::block_on` is called inside the test dispatcher for async commands, which means the test server thread blocks the shared Tauri async runtime.

Smells:
- Two parallel command tables.
- Legacy aliases only reachable via test mode.
- `block_on` inside spawned OS threads of the main app process.

Streamline:
- Generate the dispatcher from the same source of truth as the Tauri handler list (macro or build-time registry).
- Remove the `refresh_all_peers` alias once the harness no longer calls it.
- Replace `block_on` in the spawned thread with a dedicated tokio runtime or channel into the main runtime.

### 11. Low: `append_session_log` reads, appends, and rewrites the whole log file on every event

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/session_log.rs:21-36`

Why this matters:
- Each log entry triggers a full-file read, append in memory, then `fs::write` of the whole buffer. For a long-running signer with frequent events, this is O(n²) work and one power-off moment from a corrupted log file.
- The right primitive is `OpenOptions::new().append(true)` with a single write call.

Smells:
- File rewrite instead of append.
- No rotation policy and no size cap.

Streamline:
- Switch to append-mode writes.
- Add a simple rotation or byte cap to keep the log file bounded.

### 12. Low: autostart plugin is wired on every desktop platform via `MacosLauncher::LaunchAgent`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs:28-36`

Why this matters:
- The `cfg(not(target_os = "macos"))` branch passes `tauri_plugin_autostart::MacosLauncher::LaunchAgent` — a macOS-specific selector — on Linux and Windows. That is probably harmless because the plugin ignores the selector off-macOS, but the intent is unclear and the argument looks like a bug.
- The `--from-autostart` flag is passed to autostart but no command surface treats it differently from a normal launch. If the product decides not to show the main window on autostart, the hook is already plumbed; if not, the arg is noise.

Smells:
- macOS-only type used in non-macOS branch of a `cfg` split.
- Argv that is never consumed.

Streamline:
- Use the platform-appropriate autostart config for each target.
- Either implement `--from-autostart` handling (e.g. auto-hide the window) or drop the argument.

### 13. Low: README and TESTING documentation reference scripts and behaviors that no longer match the root command surface

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/README.md:25-47`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/TESTING.md:28-58`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/package.json:6-22`

Why this matters:
- README steers to `make igloo-home-build` / `make igloo-home-dev` / `make igloo-home-test-e2e`, but the parent workspace command surface is `./run.sh`, not `make`. A new contributor following the repo-local README will run targets that the parent repo no longer documents.
- TESTING.md lists `npm run test:desktop` and `npm run test:visual`, which exist in `package.json`, alongside unit/typecheck scripts; all of those are fine. But it implies `make igloo-home-test-e2e` is the canonical end-to-end path, which conflicts with `run.sh test e2e` at the parent level.
- No rustdoc is present on any `#[tauri::command]`. Those functions are the backend's public API and should carry a docstring explaining arguments, side effects, and failure modes.

Smells:
- Repo-local docs drifting from workspace docs.
- Zero doc comments on the IPC surface.

Streamline:
- Update README/TESTING to point at `./run.sh` entry points for anything workspace-owned.
- Add one-line rustdoc above each `#[tauri::command]` describing the call and its failure modes.

## Bottom Line

`igloo-home` has a clean Rust layout and a reasonable session/controller split, but the desktop shell is not as hardened as a threshold signer warrants. The Tauri config opts out of CSP, the capabilities list is broad, the test server exposes the full command surface on loopback without auth, and passphrases flow through plain `String`s end-to-end. On the quality side, `App.tsx` has become a single-file controller that duplicates runtime types and drives both event subscriptions and a polling loop, and the parallel test dispatcher is already drifting from the real command handler list. The highest-leverage fixes are tightening `tauri.conf.json` and `capabilities/default.json`, gating the test server behind a build flag or token, and introducing a shared secret/error type so both sides of the IPC can stop doing string matching on sensitive flows.
