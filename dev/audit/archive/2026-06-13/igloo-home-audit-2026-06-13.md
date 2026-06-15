# `igloo-home` audit

Date: 2026-06-13

Scope: `repos/igloo-home` (Tauri desktop host: TypeScript frontend in `src/`, Rust backend in `src-tauri/src/`)

`igloo-home` is the Tauri desktop co-signer host for FROSTR. Compared to the browser hosts it carries more ambient code because it owns profile-lifecycle logic (import, export, rotation, key recovery, session orchestration, path scoping) in Rust rather than delegating it all to bifrost crates. The Rust backend is well-structured — responsibilities are separated into focused modules (`profiles.rs`, `session/`, `path_scope.rs`, `error.rs`) and the IPC error story is unusually strong (typed `HomeError`, `scrub_for_display`, `Zeroize` on secrets). The dominant debt pattern is in the TypeScript frontend: `App.tsx` at ~1,945 lines is a god component that holds view state, orchestration, I/O, and all JSX across every workflow. There is also a recurring issue where `GeneratedKeyset` — which carries the plaintext group `nsec` — lacks the `Zeroize`/`ZeroizeOnDrop` protection that `RecoveredGroupKey` already models correctly. Testing is render-first with no adversarial coverage for wrong passphrase, corrupted package, or hostile envelope inputs.

## Findings

### 1. High: `App.tsx` is a ~1,945-line god component holding all view state, orchestration, I/O, and JSX

Rule: `ARC-01` (Architecture & boundaries)

Files:
- `repos/igloo-home/src/App.tsx:1–1945`

Why this matters:
- The file has at least five distinct reasons to change: landing navigation, create/rotate workflow, onboard workflow, key-recovery workflow, and the dashboard signer/permissions/settings tabs. Any change to any of them requires reading the whole file.
- State pollution is high: ~30 `useState` hooks all live in one component, making it impossible to reason about which flows touch which state without scanning the whole tree.

Smells:
- Single 1,945-line default export managing `activeView`, `activeDashboardTab`, `generatedKeyset`, `distributionResults`, `onboardConnectForm`, `recoverSources`, `settingsDraft`, etc. — over 30 independent state concerns.
- All event-listener subscriptions, polling intervals, and multi-step workflow handlers inline in the same component.
- `handleDistributeGeneratedShare` alone is ~90 lines of branching logic for `prepare/mark/revert/cancel/copy/qr/save` states.

Streamline:
- Extract each workflow into its own page component (e.g. `CreatePage.tsx` already exists as a precedent — the same split should apply to `OnboardPage`, `RecoverKeyPage`, `DashboardPage`).
- Move shared state that crosses page boundaries (selected profile, runtime snapshot, passphrase) into a context or top-level container with a narrow interface.

Cross-repo note: The same god-component pattern reportedly exists in `igloo-pwa/src/lib/store.tsx` (~2k lines) and `igloo-ui/.../CreateFlow.tsx` (~1.7k lines).

---

### 2. High: `GeneratedKeyset.nsec` is a plain `String` with no zeroize-on-drop — unlike the already-correct `RecoveredGroupKey`

Rule: `SEC-01` (Security — secret material lifecycle)

Files:
- `repos/igloo-home/src-tauri/src/models.rs:59–68` (`GeneratedKeyset`)
- `repos/igloo-home/src-tauri/src/models.rs:156–172` (`RecoveredGroupKey` — the correct pattern)
- `repos/igloo-home/src-tauri/src/session.rs:317–325` (`generated_keyset_response` — builds the struct)

Why this matters:
- `GeneratedKeyset` carries the plaintext `nsec` (the group secret key) of the freshly generated or rotated keyset. It is returned to the Tauri IPC layer and then drops without scrubbing its heap copy.
- `RecoveredGroupKey` (the output of `recover_group_key_from_shares`) already derives `Zeroize, ZeroizeOnDrop` with a custom redacted `Debug`. The same signal applies here — the comment on `RecoveredGroupKey` (line 154–155) says "fields zeroize on drop … scrubbing the Rust-side heap copy once the IPC layer has serialized the response" — but `GeneratedKeyset` never received the same treatment.
- The `nsec` inside `GeneratedKeyset` lingers in heap memory until the allocator reuses it, which on a desktop host may be a long time.

Smells:
- `#[derive(Debug, Clone, Serialize, Deserialize)]` on `GeneratedKeyset` — plain `Debug` will print the `nsec` if the struct is logged.
- No `Zeroize` / `ZeroizeOnDrop` derive, no custom redacted `Debug` impl.
- `RecoveredGroupKey` at line 156 shows the correct pattern (`#[derive(Serialize, Zeroize, ZeroizeOnDrop)]` + manual `Debug`) applied to the same kind of material.

Streamline:
- Apply the `RecoveredGroupKey` template to `GeneratedKeyset`: add `Zeroize, ZeroizeOnDrop` derives (drop `Clone` if it is not required by callers), add a custom `Debug` that redacts the `nsec` field, and remove `Deserialize` (the struct is outbound-only).

---

### 3. High: All core journeys have no adversarial test coverage

Rule: `TST-02` (Testing — happy-path-only coverage)

Files:
- `repos/igloo-home/test/frontend/App.test.tsx` (render tests only)
- `repos/igloo-home/test/frontend/RecoverKey.test.tsx` (single happy-path render)
- `repos/igloo-home/test/frontend/api.test.ts` (IPC call-shape checks)
- `repos/igloo-home/src-tauri/src/session.rs:511–629` (recovery/rotation unit tests)

Why this matters:
- The Rust unit tests in `session.rs` cover adversarial paths well (wrong passphrase, non-member share, insufficient shares, duplicate member). But the frontend has zero tests for wrong passphrase → error message, corrupted package → typed error render, hostile `bfonboard` with invalid structure, or passphrase mismatch on save.
- The `home-error-surface.test.ts` verifies the error type taxonomy in isolation, but no test exercises the full chain: wrong input → Rust rejects → typed `HomeError` → `rethrowHomeError` → App renders error message.

Smells:
- `App.test.tsx` asserts visible text and button existence; every mock returns `undefined` or a happy-path value.
- No test for `startProfileSession` rejecting a bad passphrase, `importProfileFromBfprofile` rejecting a corrupted package, or `connectOnboardingPackage` rejecting a bad password.

Streamline:
- Add adversarial render tests: mock API functions to reject with `{ kind: 'invalid_passphrase', detail: null }` and assert the rendered error message; similarly for `invalid_package`, `session_not_active`.
- The existing Rust-level adversarial unit tests are a good model — mirror them at the frontend boundary.

---

### 4. Medium: `lock().unwrap()` on `Mutex` fields throughout the session layer — a poisoned mutex will crash the signer

Rule: `CQ-02` (Code quality — panic/unwrap discipline)

Files:
- `repos/igloo-home/src-tauri/src/session/controller.rs:33,107,175,194,224,246`
- `repos/igloo-home/src-tauri/src/session/close.rs:37,45,49`
- `repos/igloo-home/src-tauri/src/session/lifecycle.rs:11`
- `repos/igloo-home/src-tauri/src/app/commands.rs:232,309`
- `repos/igloo-home/src-tauri/src/profiles.rs:244,258,271`
- `repos/igloo-home/src-tauri/src/app/settings.rs:12,26`
- `repos/igloo-home/src-tauri/src/app/bootstrap.rs:54`
- `repos/igloo-home/src-tauri/src/app/tray.rs:22`

Why this matters:
- Every `state.signer.lock().unwrap()` call will panic if a previous lock-holder panicked while holding the guard. In a desktop signing daemon any such panic poisons the mutex and takes down the entire Tauri process — the user's session is lost.
- The pattern is widespread: 15+ call sites across the session layer.

Smells:
- `state.signer.lock().unwrap()` called in `start_profile_session`, `stop_signer`, `profile_session_snapshot`, `take_active_signer`, `emit_lifecycle`, `sync_tray`, and more.
- No mutex-recovery strategy anywhere; a single panic in a lock-holder makes the signer unusable until restart.

Streamline:
- Replace `lock().unwrap()` with `lock().unwrap_or_else(|poisoned| poisoned.into_inner())` at each call site (standard recover-from-poison idiom), or use `tokio::sync::Mutex` in the async layer to avoid poisoning entirely.
- Alternatively, document in a comment at `AppState` definition that all three `Mutex` fields use the "panic = unwind" safety assumption — though a concrete fix is preferable for production code.

---

### 5. Medium: `ShellPaths` struct literal is copy-pasted verbatim across four test modules with identical field sets

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-home/src-tauri/src/profiles.rs:469–494` (`test_shell_paths`)
- `repos/igloo-home/src-tauri/src/session.rs:435–460` (`test_paths`)
- `repos/igloo-home/src-tauri/src/session/controller.rs:295–320` (`test_shell_paths`)
- `repos/igloo-home/src-tauri/src/app/commands.rs:601–627` (`test_shell_paths`)

Why this matters:
- Each copy is 25+ lines of identical field derivations (`root.join("config").join("igloo-shell")`, etc.). When `ShellPaths` grows a new field (as has happened with `rotations_dir`, `imports_dir`) all four copies must be updated together.
- The previous add of `rotations_dir` appears in all four, suggesting they were all manually updated — a field added to `ShellPaths` in the future will require the same four-site edit.

Smells:
- Four nearly identical `fn test_shell_paths(label: &str) -> ShellPaths { ... }` functions across separate test modules.
- `imports_dir`, `rotations_dir`, `config_dir`, `data_dir`, `state_dir`, `profiles_dir`, `groups_dir`, `encrypted_profiles_dir`, `state_profiles_dir`, `config_path`, `relay_profiles_path` — 11 fields copied four times.

Streamline:
- Extract a `test_shell_paths(root: &Path) -> ShellPaths` helper into a shared test helper module (e.g. `src-tauri/src/test_helpers.rs` or a `#[cfg(test)]` module in `lib.rs`) and have each test call it with its own temp root.

---

### 6. Medium: `test_dispatch` routes `list_session_logs` without the path-scope guard that the real command enforces

Rule: `SEC-05` (Security — IPC / test surface auth bypass)

Files:
- `repos/igloo-home/src-tauri/src/app/test_dispatch.rs:213–219` (`"list_session_logs"` arm)
- `repos/igloo-home/src-tauri/src/app/commands.rs:537–543` (`list_session_logs_command` — has `canonicalize_session_log_input`)

Why this matters:
- The real Tauri command `list_session_logs_command` canonicalizes the caller-supplied `runtime_dir` under the app's `AppData` root and rejects traversals. The test dispatcher calls `app::commands::list_session_logs` directly, which skips that canonicalization step (`canonicalize_session_log_input` is applied only in the `_command` wrapper).
- Any test that supplies a manipulated `runtime_dir` via the test TCP server can read files outside the allowed scope under test conditions. While the `test-server` feature is compile-gated, the gap means test flows can exercise a weaker surface than users get.

Smells:
- `test_dispatch.rs:215–216`: calls `app::commands::list_session_logs(state.inner(), input)` — the inner helper, not the outer command wrapper that adds scoping.
- The contrast with `export_profile_command` is instructive: that command does its own path scoping inside the `_command` layer, and the test dispatcher calls `app::commands::export_profile` (also inner, also skipping scope). Two commands with the same gap.

Streamline:
- In the test dispatcher, canonicalize the `runtime_dir` under the test app's data root (or call the inner helper only after applying the same scope check inline) so the surface under test matches the real command.
- Alternatively, restructure commands so path scoping lives inside the inner helper rather than the outer `_command` wrapper — one call site enforces it.

---

### 7. Medium: No enforced TypeScript formatter

Rule: `AES-06` (Aesthetics — no enforced formatter)

Files:
- `repos/igloo-home/package.json` (no `prettier` or `eslint` scripts or devDependencies)
- `repos/igloo-home/vite.config.ts` (no formatter config)

Why this matters:
- Formatting is inconsistent across the TS files (mixed trailing-comma, indentation quirks at line 1229–1231 of `App.tsx` where the `confirm` call argument is indented inconsistently). Without a formatter, every PR re-argues style.
- The workspace `dev/docs/STYLES.md` calls out this pattern as needing enforcement.

Smells:
- No `prettier`, `eslint`, or `biome` in `devDependencies` and no formatting check in the `test` or `build` script chain.
- Small inconsistencies visible in `App.tsx` (e.g. lines 1229–1231: `confirm(...)` argument indentation differs from surrounding code).

Streamline:
- Add Prettier (or Biome) with a checked-in config and a `format:check` step that runs in CI alongside `typecheck` and `test:unit`.

---

### 8. Low: `GeneratedKeyset.nsec` is included in the IPC response and retained in React state with no scrub-on-leave

Rule: `SEC-01` (Security — secret material lifecycle, frontend side)

Files:
- `repos/igloo-home/src/App.tsx:505` (`useState<GeneratedKeyset | null>`)
- `repos/igloo-home/src/App.tsx:874–908` (`handleGenerate` — stores keyset in state)
- `repos/igloo-home/src/App.tsx:1407–1517` (create view renders while keyset is in state)

Why this matters:
- The group `nsec` lives in `generatedKeyset` React state for the entire duration of the create/distribute workflow. There is no mechanism that clears it when the operator navigates away from the create view.
- In contrast, `recoveredKey` is explicitly cleared on leaving the `recover-key` view (lines 700–707).

Smells:
- `useState<GeneratedKeyset | null>` initialized at line 505 and only cleared by completing the distribution flow (`handleFinishDistribution` → `setActiveView('dashboard')`), but not cleared if the user navigates back via the Back button.
- No `useEffect` guard analogous to the `recover-key` clear that zeroes `generatedKeyset` and `saveForms` on view exit.

Streamline:
- Add a `useEffect` that clears `generatedKeyset` (and `saveForms`, `distributionResults`, `distributionForms`) when `activeView` leaves `'create'`, analogous to the `recover-key` clear at lines 700–707.
- On the Rust side, consider whether the `nsec` field needs to be returned to the frontend at all during the distribution phase; the host only needs it for the save step, after which shares can be encrypted without re-exposing it.

---

### 9. Low: `toLogEntries` in `App.tsx` uses `new Date().toLocaleTimeString()` at parse time — log timestamps diverge from `SignerLogEntry.at`

Rule: `CQ-06` (Code quality — magic values / silent assumption)

Files:
- `repos/igloo-home/src/App.tsx:434–442` (`toLogEntries`)

Why this matters:
- `toLogEntries` is called on `runtimeSnapshot.daemon_log_lines` which is a `string[]` of pre-formatted lines already carrying a Unix-second timestamp prefix (`[at] level message` format per `controller.rs:239`). The function discards that timestamp and replaces it with the wall-clock time at render — so log entries will show "when the app rendered them" rather than "when the signer emitted them."

Smells:
- `time: new Date().toLocaleTimeString()` — the actual `at` field from the log entry is stripped by `line.replace(/^\[[^\]]+\]\s*/, '')` on the same line (line 439) and then the current clock is substituted.
- The `dashboard-view.ts` equivalent `toEventRows` (line 75–86) doesn't re-introduce a timestamp at all, suggesting the two code paths produce different-shaped log rows despite running on the same data.

Streamline:
- Parse the `at` unix-second timestamp out of each log line (which is already in the `[at] level message` prefix) and use it to populate the `time` field, or switch `daemon_log_lines` to a typed `SignerLogEntry[]` so the timestamp is always available without re-parsing.

---

### 10. Low: `CHANGELOG.md` is perpetually `[Unreleased]` with no tagged-version entry for the current `0.2.0` work

Rule: `DOC-06` (Documentation — changelog / version hygiene)

Files:
- `repos/igloo-home/CHANGELOG.md:1–8`
- `repos/igloo-home/package.json:3` (version `"0.2.0"`)
- `repos/igloo-home/src-tauri/Cargo.toml:3` (version `"0.2.0"`)

Why this matters:
- Changes that belong to `0.2.0` are sitting in an `[Unreleased]` block even though `package.json` and `Cargo.toml` both declare `0.2.0`. A consumer checking the changelog cannot tell what shipped.

Smells:
- `## [Unreleased]` at the top of `CHANGELOG.md` listing staged onboarding, shared landing shell, and distribution flow changes that are clearly part of the current build.
- The sole version entry is `## [0.2.0] - 2026-03-27` which describes an earlier state.

Streamline:
- Stamp the `[Unreleased]` entries into a new `## [0.2.x] - <date>` section when the current work is released, keeping `[Unreleased]` for genuinely future changes.

## Summary

| Severity | Count |
|---|---|
| High | 3 |
| Medium | 4 |
| Low | 3 |
| **Total** | **10** |
