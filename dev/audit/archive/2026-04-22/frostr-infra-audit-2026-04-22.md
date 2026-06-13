# `frostr-infra` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra` (parent-repo surfaces only) — `Makefile`, root `scripts/`, `services/dev-relay` and `services/igloo-demo`, `compose.test.yml`, `.github/workflows/`, `test/` (minus submodule trees and `test/node_modules`), root docs, `docs/`, and `dev/` process material.

The workspace orchestration is generally clean: strict-mode shell scripts, a single Makefile surface, explicit scratch discipline via `lib-scratch.sh`, and a thorough `test:guards` set that actively checks doc/Makefile coherence. The dominant patterns to flag are (1) the demo-harness containers run as root with world-writable mounts shared into the host's source tree, (2) the parent scratch discipline that CLAUDE.md and CONTRIBUTING.md prescribe (`.tmp/` only, never `data/`) is not actually enforced — `data/` is still tracked via `.gitkeep` and `.env.example` still describes a retired stack (`igloo-server`, `igloo-web`, `igloo-cli`), and (3) the `test-prebuild` / `test-affected` / `test:guards` stack has real seams where the guard set can pass while dead surfaces linger.

## Findings

### 1. High: demo containers run as root and share host source trees as `:rw`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/services/dev-relay/dockerfile:1-12`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/dockerfile:1-12`
- `/home/cscott/Repos/frostr/frostr-infra/compose.test.yml:37-42`
- `/home/cscott/Repos/frostr/frostr-infra/compose.test.yml:80-87`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:189-191`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:344-346`

Why this matters:
- Both `services/dev-relay/dockerfile` and `services/igloo-demo/dockerfile` run as the default root user. There is no `USER`, no non-root account, and no dropped capabilities.
- `compose.test.yml` mounts `./repos/igloo-shell` and `./repos/bifrost-rs` as `:rw` into both containers. The entrypoints only need to read source + write to `target/` — they do not need to mutate the entire submodule tree.
- `relax_artifact_permissions()` runs `chmod -R a+rwX` over the full harness artifact dir, and `start_demo_daemon()` does `chmod 0777` on the socket directory. That combination makes every host user able to read/rewrite onboarding packages, passwords, and the daemon control socket while the stack is up.
- The demo harness is marketed as local-only, but any tool invoking `docker compose up` (including CI runners sharing a workspace) inherits a root-writable surface over the checkout.

Smells:
- No `USER` directive, no non-root fallback, no read-only bind where one would suffice.
- World-writable scratch directory holding plaintext onboarding passwords.
- Host bind mounts of the full submodule trees rather than the narrower directories the entrypoints actually touch.

Streamline:
- Add a dedicated non-root user in both Dockerfiles and run the relay / shell under it; bake in a writable `/cargo-target` path owned by that user.
- Drop the `:rw` mode on `./repos/bifrost-rs` (read-only is enough to run the prebuilt binary) and narrow `./repos/igloo-shell` to the paths the shell actually needs.
- Replace `chmod -R a+rwX` and `chmod 0777` with a directory ownership strategy that does not depend on "everyone can touch everything."

Cross-repo note: the container expects prebuilt binaries under `repos/*/target/debug/`. Tightening permissions requires a matching convention inside `bifrost-rs` and `igloo-shell` so binaries produced on the host can be exec'd inside the container without a rebuild.

### 2. High: `.env.example` advertises a retired stack and leaks a plausible-looking "admin secret"

Files:
- `/home/cscott/Repos/frostr/frostr-infra/.env.example:1-30`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-surfaces.sh:27-38`

Why this matters:
- The file prescribes defaults for `IGLOO_SERVER_*`, `IGLOO_WEB_*`, and `IGLOO_CLI_*` — none of those services exist in the current submodule set (`bifrost-rs`, `igloo-shared`, `igloo-shell`, `igloo-home`, `igloo-pwa`, `igloo-chrome`, `igloo-ui`, `igloo-paper`).
- `IGLOO_SERVER_ADMIN_SECRET=change-me` and `IGLOO_SERVER_API_KEY=dev-local-key` read as production-style secrets. A new contributor following the README's `cp .env.example .env` instruction ends up with "admin secret" and "API key" env vars that match nothing.
- The legacy-surface guard at `check-doc-surfaces.sh:27-34` explicitly scans for `igloo-web` in `Makefile`, `scripts`, `.github`, `test`, `README.md`, `CONTRIBUTING.md`, `docs`, and `dev` — but not in `.env.example`, which is the single file that still mentions it.

Smells:
- Example env vars for services this workspace does not own.
- `change-me`-style strings in a file that the README tells users to copy and keep.
- A legacy-surface guard that audits every doc except the one still carrying the retired names.

Streamline:
- Strip `.env.example` down to the demo-harness variables that `compose.test.yml` and `services/igloo-demo/entrypoint.sh` actually consume.
- Add `.env.example` to the `check-doc-surfaces.sh` scan set so future renames cannot leave this file behind again.

### 3. High: parent-repo scratch discipline is documented but not enforced — `data/` is still tracked

Files:
- `/home/cscott/Repos/frostr/frostr-infra/CONTRIBUTING.md:178-181`
- `/home/cscott/Repos/frostr/frostr-infra/CLAUDE.md:160-161`
- `/home/cscott/Repos/frostr/frostr-infra/.gitignore:10-12`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-surfaces.sh:27-38`

Why this matters:
- CONTRIBUTING and CLAUDE both say "parent live scratch belongs under `./.tmp/`, not tracked-looking paths such as `./data/`."
- `.gitignore` still preserves `data/*` with `!data/.gitkeep` carve-outs, and `data/.gitkeep` is the one file in this tree `git ls-files` reports under `data/`.
- On disk the working tree still contains `data/test-harness/` (with `0777` perms). No script creates `data/` today, but nothing prevents a contributor from writing there — and the `.gitkeep` telegraphs that it is a valid destination.
- The legacy-surface guard scans for `data/test-harness` in docs but excludes `.gitignore` and `data/.gitkeep`, so the policy can never trip its own check.

Smells:
- Doc-level policy that contradicts tracked tree state.
- A `.gitkeep` that keeps alive the directory the docs explicitly call out as wrong.
- A guard whose allow-list silently whitelists the surface it claims to forbid.

Streamline:
- Decide whether `data/` still has a role. If not, remove `data/.gitkeep` and the `data/*` carve-outs from `.gitignore`; extend the legacy-surface guard to reject any tracked `data/` paths.
- If `data/` does still have a role, document it in the scratch section and stop warning against it in CONTRIBUTING/CLAUDE.

### 4. High: `services/igloo-demo/entrypoint.sh` is a 450-line single-file orchestrator with hand-rolled JSON parsing

Files:
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:42-65`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:101-134`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:217-240`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:278-313`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh:389-450`

Why this matters:
- A single shell script owns demo material generation, relay waiting, socket waiting, readiness polling, onboard package export, daemon start, symlinking, ownership relaxation, logging, and cleanup.
- `json_string_field`, `json_number_field`, and `imported_profile_id` parse JSON with `awk` / `sed` heuristics against `igloo-shell`'s real output format. Any change to the CLI JSON emission will break this script silently at runtime inside the container, not at guard time in CI.
- Polling loops (`wait_for_relay`, `wait_for_socket`, `wait_for_onboard_ready`) each use their own sleep/attempt logic with hardcoded 60s timeouts. The stanzas are nearly identical but cannot share a helper because this file stands alone in the container.
- The password-file path forces `chmod 0644` after generating material with `umask 077`, deliberately walking a secret back to world-readable so the host user can read it.

Smells:
- JSON parsing in `awk` for a contract that is explicitly marked as a shell CLI.
- Fixed polling intervals, copy-pasted across helpers.
- A script that mixes validation, orchestration, and cleanup paths with only a single `trap cleanup EXIT INT TERM` set very late (line 443, long after the work that most needs cleanup).

Streamline:
- Move structured JSON consumption into `igloo-shell` itself (emit a `--json-script-friendly` record or rely on a stable key order documented in that repo), so the demo script can use a single one-liner.
- Extract the polling helpers into a small `lib-wait.sh` sourced by both entrypoints.
- Register `trap cleanup EXIT INT TERM` right after the daemon is started, not after the onboarding export.

Cross-repo note: the JSON parsers assume specific field names from `igloo-shell import --json` and `daemon start`. That output format is an informal contract and should be pinned in `repos/igloo-shell`'s docs.

### 5. Medium: `test-prebuild.sh` is a 363-line stamp/fingerprint engine with its own mini-language

Files:
- `/home/cscott/Repos/frostr/frostr-infra/scripts/test-prebuild.sh:34-68`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/test-prebuild.sh:80-207`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/test-prebuild.sh:264-323`

Why this matters:
- `select_target` implements a target/dep DAG by recursion in shell; `SELECTED` is the associative-array output.
- `render_input_fingerprint` hashes every file under `repos/*/src` and `repos/*/public` with `sha256sum` per file — fine when green, but a slow and inscrutable failure surface when a sub-tree drifts.
- `render_output_state` hashes build outputs (including compiled Tauri binaries) and stores the result under `.tmp/test-prebuild/stamps/<selected_key>.state`. A missing image (`bifrost-infra-dev-relay:dev`) turns into a cryptic `missing_image` line rather than a targeted "demo images not built" diagnostic.
- Failures from `render_state_stamp` or `cmp -s` are reported as "prebuild outputs are stale for <key>" without telling the user which file changed. `check_stamp` deletes the current stamp before it is shown to the user.

Smells:
- A hand-rolled build cache that duplicates what `cargo`, `npm`, and `docker build` already do.
- Fingerprint inputs drift silently because there is no allow-list of what's hashed.
- Target recursion and key serialization combined into a single file with no unit coverage.

Streamline:
- Consider replacing the stamp/fingerprint machinery with `mtime`-only freshness and leaning on `cargo`/`npm`/`docker` cache layers; keep fingerprints only for the two phases where they actually catch cross-repo drift (browser-wasm sync, demo images).
- When `check_stamp` fails, print the first mismatching line from the stamp diff rather than only reporting "stale".

### 6. Medium: `test-run-sh.sh` / `test:run-sh` leaves dead ends and CI disparity

Files:
- `/home/cscott/Repos/frostr/frostr-infra/test/package.json:7,21`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/test-run-sh.sh:104-116`
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/workspace-guards.yml:65-73`
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/release-validation.yml:92-99`

Why this matters:
- `test/package.json` still exposes a standalone `"test:run-sh": "bash ./scripts/test-run-sh.sh"` script. Nothing else invokes it (the aggregate `test:guards` already runs the script directly as `bash ./scripts/test-run-sh.sh`). It is a one-hop alias with no remaining caller.
- The guard named `test-run-sh.sh` no longer reflects what it tests — it now exercises the Makefile surface (`make -s ... help`, `make ... demo-start`, etc.). The file name is a fossil from the `run.sh` era.
- `workspace-guards.yml:66` uses `npm install`; `release-validation.yml:93-99` uses `npm ci`. The guard workflow can therefore pass against a drifted lockfile that the release workflow would reject.

Smells:
- A package.json script kept only as historical alias.
- A guard whose filename lies about its scope.
- Two workflows with divergent install semantics over the same `test/package.json`.

Streamline:
- Delete the `test:run-sh` script entry; keep the guard script and rename it to `test-makefile-surface.sh` (or fold it into `check-doc-command-surfaces.sh`).
- Use `npm ci` in both workflows so the lockfile is the single source of truth.

### 7. Medium: third-party GitHub Actions are tag-pinned, not SHA-pinned, and the workflows omit `permissions:` blocks

Files:
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/release-validation.yml:1-70`
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/workspace-guards.yml:1-51`

Why this matters:
- Both workflows pin external actions by floating version tags: `actions/checkout@v4`, `actions/setup-node@v4`, `dtolnay/rust-toolchain@stable`, `Swatinem/rust-cache@v2`. A tag can be moved; a commit SHA cannot.
- Neither workflow declares a `permissions:` block. Both therefore inherit the repository's default `GITHUB_TOKEN` permissions, which is more surface than they need. Release validation writes no artifacts back and does not comment on PRs; `contents: read` would be sufficient.
- Both trigger on `pull_request` (not `pull_request_target`), so untrusted-input concerns are smaller, but the lack of a `permissions:` block still weakens defense-in-depth.

Smells:
- Tag pinning for build-critical actions.
- Default `GITHUB_TOKEN` scope taken implicitly.
- No concurrency group — two rapid pushes to `main` can fight for cache locks.

Streamline:
- Pin each action to a specific commit SHA and keep the tag in a comment for human readability.
- Add `permissions: contents: read` at the workflow level (with job-level escalations if anything ever needs them).
- Add a `concurrency:` key keyed by ref so stacked CI runs cancel correctly.

### 8. Medium: `demo.sh` port selection is TOCTOU and the resolve/stop interaction is subtle

Files:
- `/home/cscott/Repos/frostr/frostr-infra/scripts/demo.sh:61-104`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/demo.sh:198-219`

Why this matters:
- `port_in_use` uses `ss -ltn` to scan, `resolve_free_port` picks the first free candidate, then the caller writes `demo-relay-port.txt` and runs `docker compose up`. Another process can bind the chosen port between the probe and the `up`. In that case `docker compose up` fails and the port file already records the wrong number.
- `stop_projects` matches compose projects by both `working_dir` and `config_files` labels, but only from `docker ps` — a *stopped* project that still holds the port publication is not found, so `resolve_port` may silently pick a different port even when the intended project can be restarted. That turns a simple "relaunch" into a "drift into a new port on every run."
- The `resolve_port` branch at lines 86-93 returns the requested port unchanged whenever *any* `dev-relay` project is detected, regardless of state. Combined with `stop_projects` at line 202 the order is safe today, but an intermediate invocation would not find a running project and would return the requested port even when it is already bound by something else.

Smells:
- Parallel notions of "the port": the arg, `${DEFAULT_PORT}`, the file, and `docker ps`.
- Port probing instead of "just try to bind" inside compose.
- Compose project discovery keyed off `working_dir`, which is brittle across symlinked checkouts.

Streamline:
- Drop the `resolve_free_port` probe and let `docker compose up` fail loud on port conflict; have `make demo-start` surface that failure with a "retry with `PORT=<port>`" hint.
- Persist the resolved port only after the compose command returns healthy.

### 9. Medium: `reset.sh` is the one script without a `set -euo pipefail`-level guarantee plus has a surprise `rm -rf` on `build/igloo-shell-target`

Files:
- `/home/cscott/Repos/frostr/frostr-infra/scripts/reset.sh:1-36`
- `/home/cscott/Repos/frostr/frostr-infra/Makefile:85-86`

Why this matters:
- `reset.sh:3` does enable `set -euo pipefail`, so strict-mode behavior is there, but the interactive confirmation path at `reset.sh:14-21` interactively prompts the user — even though `Makefile:86` always passes `--force`. The prompt code is unreachable from the supported surface; it exists only for direct invocation, which docs say is not supported.
- `reset.sh:33` unconditionally removes `build/igloo-shell-target` but leaves `build/bifrost-target` alone. The `build/` directory is half-managed: some subtrees are wiped, others survive.
- `reset.sh:23-24` runs `docker compose -f compose.test.yml down` without a project filter, so if the user is in the middle of a `demo-smoke` run (which uses its own `-p` name) those projects are not actually torn down by `repo-reset`.

Smells:
- An interactive prompt branch that no supported path reaches.
- Asymmetric cleanup of `build/` subdirs.
- `compose down` without matching the project names the demo harness actually uses.

Streamline:
- Delete the interactive branch or make it the default and require `make repo-reset FORCE=1` for the Makefile path — do not carry both.
- Either wipe all of `build/` or none of it, and add a note explaining which phase writes to each.
- Call `stop_projects` from `demo.sh` (already authored) rather than a bare `docker compose -f compose.test.yml down`.

### 10. Medium: `igloo-pwa` global-setup builds `home` artifacts, coupling pure-PWA runs to the Tauri toolchain

Files:
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-pwa/global-setup.ts:1-6`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-chrome/global-setup.ts:1-6`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/test-prebuild.sh:52-55`

Why this matters:
- `igloo-pwa/global-setup.ts` calls `runTestPrebuild(['pwa', 'home'])`. That expansion drags in the `home` target, which in `test-prebuild.sh` requires the Tauri toolchain and a Rust debug build of the desktop binary.
- A contributor running only PWA tests on a machine without `libwebkit2gtk` will see the Tauri build fail during global setup, even though no PWA test exercises Home.
- `igloo-chrome/global-setup.ts` similarly asks for `['chrome', 'home', 'demo']`, so the demo image build happens even for fast-tier Chrome tests.

Smells:
- Cross-host prep dependencies carried into fast-tier setups.
- "Because we might as well" prebuild of targets with heavy system deps.

Streamline:
- Narrow the PWA global-setup to `['pwa']` and let the chrome-home-pairing spec declare its own prep when it needs `home`.
- Split the Chrome setup: fast tier gets `['chrome']`, live/demo tiers get `['chrome', 'home', 'demo']`.

### 11. Medium: `AGENTS.md` under-describes the command surface that `check-doc-command-surfaces.sh` enforces

Files:
- `/home/cscott/Repos/frostr/frostr-infra/AGENTS.md:17-26`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-command-surfaces.sh:88-97`

Why this matters:
- The guard at `check-doc-command-surfaces.sh:88-97` requires `AGENTS.md` to contain `make repo-init`, `make repo-check`, `make repo-reset`, `make demo-start`, `make demo-onboard`, `make demo-smoke`, `make test-smoke`, `make test-fast`, `make test-live`, `make test-demo`, `make test-prep`, `make test-affected`, `make test-release`, `make igloo-paper-verify`, `make igloo-chrome-build`. Only a subset is in `AGENTS.md` today (`repo-init`, `repo-check`, `demo-start`, `demo-onboard`, `test-prep`, `test-affected`, `test-release`, `repo-reset`). The guard's `AGENTS.md` loop currently only verifies seven of those entries, so the current doc passes even though it is incomplete relative to the README/CLAUDE surface.
- `demo-stop`, `demo-logs`, `demo-foreground`, `demo-smoke`, `test-smoke`, `test-fast`, `test-live`, `test-demo`, `test-e2e` never appear in `AGENTS.md`. If an agent reads only that file it will not know those commands exist.

Smells:
- Guard tolerates a subset of the real surface.
- Two docs (CLAUDE.md, README.md) that list the full command set; a third (AGENTS.md) that silently lags.

Streamline:
- Expand `AGENTS.md` to the full `make ...` surface, or reduce the guard to reflect the minimal surface the doc is actually promising to describe. Pick one direction and keep all three docs aligned with the same list.

### 12. Low: `scripts/check-setup.sh` is a shallow "Docker is installed" gate and does not cover the prep state it is adjacent to

Files:
- `/home/cscott/Repos/frostr/frostr-infra/scripts/check-setup.sh:1-46`

Why this matters:
- The check verifies `docker`, `docker compose`, `.gitmodules`, `.env`, and `.tmp` writability. It does not verify `cargo`, `npm`, `wasm-pack`, `xvfb-run`, or `playwright` — all of which the rest of the workflow assumes.
- `repo-check` is the only Makefile entry for "am I set up to run this?" A user running `make repo-check` and seeing "OK" can still fail on `make test-prep` because `wasm-pack` is absent.
- The script only warns on missing submodule initialization; `repo-init` must be run separately, and there is no path where `repo-check` can repair that.

Smells:
- `repo-check` scope not aligned with what `make test-prep` actually requires.
- Warnings instead of actionable errors.

Streamline:
- Either expand the check to cover the tools `test-prep` invokes, or rename `repo-check` to `repo-check-docker` so the limited scope is explicit.

### 13. Low: `test/igloo-web/` is an empty shell that outlived the retired host

Files:
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-web/specs`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-web/support`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-surfaces.sh:27-34`

Why this matters:
- `test/igloo-web/specs/` and `test/igloo-web/support/` exist on disk but are empty. There is no `playwright.config.ts`, no package script, no README, and the legacy-surface guard explicitly flags `igloo-web` as retired in `Makefile`, `scripts`, `.github`, `test`, `README.md`, `CONTRIBUTING.md`, `docs`, `dev`.
- The guard scans `test` but the directory itself contains no files to match — so the check "passes" while the dead directory persists.

Smells:
- Empty directories preserved long after the feature left.
- A guard that matches content but not structure.

Streamline:
- Delete `test/igloo-web/`. If the guard should catch this class of drift, extend it to flag empty host-scoped directories under `test/` that are not wired into `test/package.json`.

### 14. Low: `release-matrix.sh` parallel step accounting shares globals and drops timing on error paths

Files:
- `/home/cscott/Repos/frostr/frostr-infra/scripts/release-matrix.sh:49-57`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/release-matrix.sh:110-143`

Why this matters:
- `run_parallel_step` writes to module-level globals `LAST_PID`, `LAST_LABEL`, `LAST_STARTED_AT`; the caller immediately copies them into associative arrays keyed by label. This is workable but brittle — any future call between `run_parallel_step` and the assignment clobbers the globals silently.
- `record_timing` is only called after `wait` in the parallel loop, so if one of the foreground `run_step` calls earlier in the file fails with `exit 1`, the preceding step is recorded but the remaining parallel steps never start and never record "not_run" rows.
- The printed "slowest_phases" sort uses `printf '%b\n' "${TIMING_ROWS[@]}"` with tab-delimited fields; the row ordering then depends on `sort -rn` behavior over that composite key. This works in practice but is easy to break when any label grows to include spaces.

Smells:
- Global variables as return values from helpers.
- Parallel accounting that silently forgets steps that never ran.
- Output formatting that relies on label hygiene rather than escaping.

Streamline:
- Return values explicitly (pipe-delimited output assigned via command substitution) instead of globals.
- Pre-populate the timing file with all planned phases as `pending`; rewrite rows as they complete so the final summary always has every phase.
