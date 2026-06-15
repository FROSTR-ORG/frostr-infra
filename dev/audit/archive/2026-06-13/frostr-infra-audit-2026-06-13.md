# `frostr-infra` audit

Date: 2026-06-13

Scope: `/Users/cscott/Repos/frostr/frostr-infra` — Makefile, scripts/, dev/scripts/, test/, services/, docs/, dev/, compose*.yml, .github/workflows/. Submodules under repos/ are excluded.

`frostr-infra` is a well-layered coordination workspace: the Makefile stays thin, scripts are factored into lib files, guard scripts protect key invariants, and the CI workflows are structured and path-scoped. The previous audit pass (2026-04-22) cleared major security debt and the remediation plans are visible in dev/. What remains is a cluster of **security hygiene issues at shell trust boundaries** (passphrases on command-line argv, world-wide chmod, a predictable harness token in compose), one **high-severity CI blind spot** (release-validation targets the wrong default branch and never fires on master pushes), and a set of medium/low findings around script duplication, a large fixture file, and the absence of a formatter gate at the workspace test layer.

## Findings

### 1. High: `release-validation.yml` push trigger targets `main`, not `master`

Rule: `SEC-05` (IPC / daemon authentication) — secondary classification `TST-01` (core journey not covered)

Files:
- `.github/workflows/release-validation.yml:21–24`

Why this matters:
- The repository's default/HEAD branch is `master` (confirmed via `git remote show origin`). `workspace-guards.yml` and `client-scoped-validation.yml` both gate on `push: branches: - master`.
- `release-validation.yml` gates its push trigger on `branches: - main`. No branch named `main` exists in this repo, so the release-validation workflow (the full matrix: demo build, live E2E, igloo-chrome:live) **never fires on any push to master**. It fires only on pull requests.
- PRs can merge and break the demo lane without the post-merge gate ever confirming it. This defeats the purpose of the push-on-master gate.

Smells:
- `push: branches: - main` in a repo whose default branch is `master`.
- Other workflows use `master`; only `release-validation.yml` uses `main`.

Streamline:
- Change `release-validation.yml` push trigger branch from `main` to `master` to match the repo default and the other two workflow files.

---

### 2. High: Passphrase exposed on `igloo-shell` command-line argv in two places

Rule: `SEC-05` (IPC / daemon authentication) — see also `SEC-01`

Files:
- `services/igloo-demo/entrypoint.sh:283` (`igloo-shell import --passphrase "${IGLOO_SHELL_PROFILE_PASSPHRASE}"`)
- `services/igloo-demo/entrypoint.sh:357` (`igloo-shell daemon start --passphrase "${IGLOO_SHELL_PROFILE_PASSPHRASE}"`)
- `test/igloo-chrome/fixtures/live-signer.ts:327–328` (`'--passphrase', 'playwright-live-passphrase'` on the args array for `igloo-shell import`)

Why this matters:
- Passing a passphrase as a positional argument makes it visible in `/proc/<pid>/cmdline` and in `ps` output, readable by any process with the same or higher UID in the container/host.
- The `daemon start` call (entrypoint line 357) is the highest-risk: the daemon runs for the lifetime of the demo, leaving the window open. The `import` call (line 283) is shorter-lived but the same exposure.
- The same codebase already knows the right pattern: `export` uses `--passphrase-env` (line 341), and the `live-signer.ts` daemon-start uses stdin piping (lines 697–709). The `import` call in `live-signer.ts:327–328` is the last direct-argv passphrase remaining in the test fixture.

Smells:
- `--passphrase "${IGLOO_SHELL_PROFILE_PASSPHRASE}"` on two exec calls in `entrypoint.sh`.
- Hard-coded literal `'playwright-live-passphrase'` on the argv array for `import` in `live-signer.ts`.
- Inconsistency: export uses `--passphrase-env`, daemon-start uses stdin, import uses argv.

Streamline:
- For `igloo-shell import`: switch to `--passphrase-file` (write passphrase to a temp file with `umask 077`) or `--passphrase-env` where the CLI supports it.
- For `igloo-shell daemon start` (entrypoint): switch to stdin pipe (matching the live-signer fixture pattern), or `--passphrase-file`.
- For the Playwright `live-signer.ts:327–328`: replace the literal with an env-var read via `--passphrase-env IGLOO_SHELL_TEST_PASSPHRASE`, which is already set in `shellEnv`.

---

### 3. High: Broad `chmod 0777` and `chmod -R a+rwX` on secret-bearing harness directories

Rule: `SEC-06` (file / scratch permissions)

Files:
- `services/igloo-demo/entrypoint.sh:380` (`chmod 0777 "$(dirname "${daemon_socket_bind}")" "${daemon_socket_bind}"`)
- `services/igloo-demo/entrypoint.sh:217` (`chmod -R a+rwX "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}"`)

Why this matters:
- `chmod 0777` on the socket and its parent directory gives world-execute (and world-read) permission to the daemon socket and the directory containing the signer profile material. In a multi-UID environment this opens the socket to any local process.
- `chmod -R a+rwX "${IGLOO_SHELL_DEMO_ARTIFACT_DIR}"` is called at line 464 after producing onboarding packages and password files. `a+rwX` makes every file in the artifact dir world-readable, including `onboard-*.password.txt` and `onboard-*.txt` (which contain keying material for the onboarding package).
- These are local demo and CI environments where other processes likely share the user space; world-readable signer artifacts and a world-writable socket are broader than needed.

Smells:
- `chmod 0777` on a daemon socket and the directory it sits in.
- `chmod -R a+rwX` on the artifact directory that holds onboarding password files.
- The path comment (`# The host never connects to this socket`) suggests the socket could stay 0700.

Streamline:
- For the socket: use `chmod 0660` or `0600` (owner and optionally group); Docker UID mapping means the test harness reading the socket file can be in the same GID.
- For artifact relaxation: open only to the specific user/group the host-side test runner operates as (`chmod -R g+rX` with the right GID), rather than world-readable. Or rely on the already-exported bind-mount rather than widening permissions.

---

### 4. Medium: `release-validation.yml` actions are commit-pinned; `client-scoped-validation.yml` uses floating semver tags

Rule: `AES-06` — secondary `SEC-07`

Files:
- `.github/workflows/client-scoped-validation.yml:35, 52, 88, 105, 133, 150` (`actions/checkout@v5`, `dtolnay/rust-toolchain@stable`)
- `.github/workflows/release-validation.yml:54, 59, 75` (commit-SHA pins with date comment)
- `.github/workflows/workspace-guards.yml:40, 56, 61` (commit-SHA pins)

Why this matters:
- `release-validation.yml` and `workspace-guards.yml` correctly pin every action to a commit SHA with a date comment, preventing tag-mutable supply-chain attacks.
- `client-scoped-validation.yml` uses floating `@v5` and `@stable` references for every job's actions. A tag re-point or a `stable` branch force-push can silently change what runs in CI.
- The client-scoped lane runs on every PR touching a submodule — the highest-frequency workflow — with the least supply-chain protection.

Smells:
- Three jobs in `client-scoped-validation.yml` all reference `actions/checkout@v5` (not pinned to SHA).
- `dtolnay/rust-toolchain@stable` (floating branch name) in all three jobs.
- The other two workflow files already follow the correct pattern with SHA + comment.

Streamline:
- Pin all `client-scoped-validation.yml` action references to commit SHA with a date comment, matching the pattern already established in `release-validation.yml` and `workspace-guards.yml`.

---

### 5. Medium: Clang-detection logic duplicated across `check-setup.sh` and `prepare-browser-wasm.sh`

Rule: `CQ-04` (duplicated logic)

Files:
- `scripts/check-setup.sh:27–49` (`clang_supports_wasm`, `find_wasm_clang`)
- `scripts/prepare-browser-wasm.sh:53–88` (`clang_supports_wasm`, `select_wasm_clang`, `ensure_wasm_clang`)

Why this matters:
- Both scripts independently implement the wasm-capable clang detection (same probe: compile a trivial C fragment to `wasm32-unknown-unknown`; same candidate list: `CC_wasm32_unknown_unknown`, `WASM_CC`, `/opt/homebrew/opt/llvm/bin/clang`, `clang`).
- The two copies can drift. They already have different function names (`find_wasm_clang` vs `select_wasm_clang`) and different wrappers around the same selection logic. If the detection priority changes (e.g. adding a new candidate), both files must be updated.
- A similar duplication exists for the `trim()` helper, independently implemented in both `scripts/demo.sh:161–165` and `services/igloo-demo/entrypoint.sh:77–82`.

Smells:
- Near-identical `clang_supports_wasm()` bodies in both files.
- Identical candidate list in different order/wrapper.
- `trim()` duplicated between a script and an entrypoint that aren't sourced together.

Streamline:
- Extract clang detection into a shared sourced library (e.g. `scripts/lib-wasm-clang.sh`) and source it from both scripts; `check-setup.sh` can call `select_wasm_clang` from there.
- The `trim()` duplication is harder to consolidate because the entrypoint and the demo script don't share a source, but could be noted for the next services/scripts factoring pass.

---

### 6. Medium: `port_in_use` in `demo.sh` uses `ss` (Linux-only), silently giving false negatives on macOS

Rule: `CQ-04` (duplicated logic); also `RS-01` (inconsistent approach)

Files:
- `scripts/demo.sh:76–79` (`port_in_use` using `ss -ltn`)
- `scripts/igloo-pwa-dev.sh:16–29` (`find_port_pids` using `lsof` first, falling back to `ss`)

Why this matters:
- `demo.sh`'s `port_in_use` calls `ss -ltn "( sport = :${port} )"` with `2>/dev/null`. On macOS, `ss` is not installed; the command fails silently, `tail` and `grep` get empty input, and the function returns "not in use" for every port — even one that is bound.
- The practical effect: `resolve_free_port` always returns the first candidate port on macOS, and if that port is taken by a prior demo, `docker compose up` hard-fails with a port-conflict error rather than the shell gracefully stepping past it. The `resolve_free_port` path becomes inert on macOS.
- `igloo-pwa-dev.sh` already solves this correctly with a `lsof`-first, `ss`-fallback strategy. The two scripts handle the same need with different portability.

Smells:
- `ss -ltn` with no `command -v ss` guard, no `lsof` fallback.
- Contrast with `igloo-pwa-dev.sh`'s defensive pattern just two files away.

Streamline:
- Replace `port_in_use` in `demo.sh` with the same lsof→ss probe pattern used in `igloo-pwa-dev.sh`, or extract it into `lib-demo-services.sh`.

---

### 7. Medium: `test/igloo-chrome/fixtures/live-signer.ts` is a 799-line multi-concern file

Rule: `ARC-01` (god file) — below the 800-LOC threshold but holding multiple responsibilities

Files:
- `test/igloo-chrome/fixtures/live-signer.ts:1–799`

Why this matters:
- The file bundles: type definitions for the live-signer profile shape, a `ManagedRelayProcess` class (relay process lifecycle), relay-port scanning (`waitForRelayPort`, `randomPort`), igloo-shell binary management (`ensureIglooShellBinary`, `managedShellEnv`, `runIglooShellJson`), NIP-44 encryption logic for manually sending onboard-nonce requests (`hexToBytes`, `normalizeNip44PayloadForJs`, `requestOnboardNonceCount`), and the `SharedLiveSignerController` orchestration class.
- Changing the relay probe interval, the shell binary path, the NIP-44 nonce request format, or the fixture lifecycle all require reading the same 799-line file.
- The file is just below the 800-LOC threshold at 799 lines and is still growing (the `requestOnboardNonceCount` path spans ~100 lines of WASM and pool wiring).

Smells:
- Six distinct concerns interleaved in one file.
- `requestOnboardNonceCount` embeds full NIP-44 crypto and relay pool wiring inline (lines 440–555) with no extraction.
- The `ManagedRelayProcess` class (lines 203–276) is fully self-contained and has no dependency on the rest of the file.

Streamline:
- Extract `ManagedRelayProcess` and `waitForRelayPort`/`randomPort` into `test/igloo-chrome/fixtures/helpers/relay.ts`.
- Extract the NIP-44 nonce-request logic into `test/igloo-chrome/fixtures/helpers/seed-crypto.ts` (a file that already exists for crypto helpers).
- The remaining orchestration in `live-signer.ts` drops to ~400 lines and has one job.

---

### 8. Medium: Dead/misleading `IGLOO_SHELL_DEMO_CONTROL_TOKEN` env var in `compose.test.yml`

Rule: `LEG-04` (dead or unreachable code)

Files:
- `compose.test.yml:75` (`IGLOO_SHELL_DEMO_CONTROL_TOKEN: ${IGLOO_SHELL_DEMO_CONTROL_TOKEN:-dev-harness-token}`)
- `services/igloo-demo/entrypoint.sh:349–379` (daemon token is always generated at runtime, never read from env)

Why this matters:
- The compose environment injects `IGLOO_SHELL_DEMO_CONTROL_TOKEN=dev-harness-token` into the `igloo-demo` container. The entrypoint never reads this variable: it runs `igloo-shell daemon start`, extracts the generated `token` from the JSON response (`json_string_field "token"`), and writes that daemon-generated token to `IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE`.
- The env var `IGLOO_SHELL_DEMO_CONTROL_TOKEN` has no consumer in the entrypoint and no consumer in any test fixture (confirmed by grep: the `_FILE` variant is used everywhere, not the bare `TOKEN` var).
- The comment in `.env.example:13` ("IGLOO_SHELL_DEMO_CONTROL_TOKEN is generated per-run by the harness") correctly documents the intent but the compose env injection (with a default of `dev-harness-token`) contradicts it and could mislead an operator into thinking the token can be configured this way.

Smells:
- `IGLOO_SHELL_DEMO_CONTROL_TOKEN` set in compose but never read by the entrypoint that consumes the compose service.
- Default value `dev-harness-token` looks like a predictable credential when it has no effect.

Streamline:
- Remove the `IGLOO_SHELL_DEMO_CONTROL_TOKEN` line from `compose.test.yml`. Keep only `IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE` which is actually consumed by the entrypoint and by test fixtures.

---

### 9. Low: No formatter enforced for the `test/` TypeScript layer

Rule: `AES-06` (no enforced formatter)

Files:
- `test/package.json` (no `prettier` or `eslint` script or dev dependency)
- `test/tsconfig.json` (only typechecks; no style gate)

Why this matters:
- The `test/` workspace is a non-trivial TypeScript codebase (~30 files, ~3000 LOC) with its own `tsconfig*.json`, CI typecheck targets, and code review surface.
- There is no prettier/eslint config or CI step enforcing consistent style. Style is currently maintained by hand, making reviews partially argue formatting and making drift invisible across contributors.
- This is lower severity than in product code since it's test infrastructure, but it's a non-trivial body of TypeScript that grows with every new E2E spec.

Smells:
- No `prettier` or `eslint` in `test/package.json` devDependencies.
- No `npm run lint` or `npm run format:check` script.
- The AGENTS.md rules note notes that no TS repo here configures eslint/prettier; consistent with cross-cutting pattern across targets.

Streamline:
- Add `prettier` to `test/` dev dependencies and a `format:check` script gated in CI alongside `test:typecheck`. The guards workflow (`workspace-guards.yml`) is the natural home.

---

### 10. Low: Magic numeric `+100` in `resolve_free_port` with no documented basis

Rule: `CQ-06` (magic values)

Files:
- `scripts/demo.sh:84` (`local upper_bound=$((requested_port + 100))`)

Why this matters:
- The `resolve_free_port` function scans from the requested port up to `requested_port + 100` looking for a free port. The window of 100 is unexplained: is it large enough to survive 100 concurrent demo stacks? Is it small enough to avoid colliding with other well-known service port ranges?
- A reader can't recover the intent from the code, and a future change to the default port (currently 8194) might choose a value where `+100` runs into a reserved range without anyone noticing.

Smells:
- Bare `+100` with no constant name and no comment.
- The default port (8194) and the scan window (100) together define a policy that isn't documented.

Streamline:
- Name the constant (`PORT_SCAN_WINDOW=100`) and add a short comment explaining the intent ("space for 100 parallel demo stacks on the same machine").

## Summary

| Severity | Count |
|---|---|
| High | 3 |
| Medium | 5 |
| Low | 2 |
| **Total** | **10** |
