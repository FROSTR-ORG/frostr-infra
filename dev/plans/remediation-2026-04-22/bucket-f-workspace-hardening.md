# Bucket F — Workspace Hardening (Hard-Cut Plan)

Status: draft, pending user approval
Related: ships in the same coordinated release as Buckets A + B + C + D + E. All work lives in `frostr-infra` (parent repo); no submodule coordination required.

## Context

The 2026-04-22 `frostr-infra` audit flagged the workspace orchestration as
generally clean (strict-mode shell scripts, single Makefile surface,
thorough `test:guards` set) but with three high-severity pattern issues:

1. **Demo containers run as root** with world-writable onboarding artifacts
   and `:rw` bind mounts of the full `repos/` submodule trees.
2. **`.env.example` advertises a retired stack** (`IGLOO_SERVER_*`,
   `IGLOO_WEB_*`, `IGLOO_CLI_*`) with plausible-looking "admin secret"
   defaults. Legacy-surface guard omits `.env.example` from its scan set.
3. **Tracked `data/` directory** contradicts the scratch-discipline policy
   documented in `CONTRIBUTING.md` and `CLAUDE.md`. `data/.gitkeep` is
   tracked and `data/test-harness/` exists on disk at `0777`.

Plus seven medium-priority findings on GitHub Actions hygiene, demo
entrypoint complexity, script dead-ends, port TOCTOU, and doc drift, and
three low-priority findings on dead directories and helper cleanup.

Bucket F closes the high-severity items and bundles the medium/low items
into a cleanup wave. Alpha; no operator-burden concerns.

**Out of scope for Bucket F:**
- `test-prebuild.sh` stamp/fingerprint engine rewrite (audit finding 5).
  Larger architectural question; defer to a later bucket focused on test
  infrastructure.
- `release-matrix.sh` globals cleanup (audit finding 14). Low-signal;
  defer or fold into a future tooling-polish bucket.
- Docker image size optimization. Minimal base is already fine; no action
  needed.

## Scope

**In:**
- F.1 — Demo-harness hardening: non-root `USER`, `:ro` bind mounts where
  read-only suffices, eliminate `chmod 0777` / `chmod -R a+rwX` from
  entrypoints, narrow socket-directory perms, remove `/tmp` fallback for
  long socket paths from `demo.sh` (dup of Bucket C.C.4 pattern at the
  container level).
- F.2 — `.env.example` rewrite: strip retired `igloo-server` /
  `igloo-web` / `igloo-cli` variables. Leave only the demo-harness
  variables that `compose.test.yml` and `services/igloo-demo/entrypoint.sh`
  actually consume. Add `.env.example` to `test/scripts/check-doc-surfaces.sh`.
- F.3 — `data/` directory removal: delete `data/.gitkeep` and the
  `data/*` / `!data/.gitkeep` / `!data/*/.gitkeep` entries from
  `.gitignore`. Tighten the legacy-surface guard to flag any tracked
  `data/` path as well as any tracked `.gitignore` entry re-introducing
  it.
- F.4 — GitHub Actions hardening: pin every action to its 40-char commit
  SHA (tag kept in a comment for reviewer context); add
  `permissions: contents: read` at workflow level; add a
  `concurrency:` key; switch `workspace-guards.yml` from `npm install`
  to `npm ci`.
- F.5 — Demo entrypoint refactor: install `jq` in the `igloo-demo`
  container image; replace every `awk`/`sed` JSON parser in
  `services/igloo-demo/entrypoint.sh` with a one-liner `jq` pipeline;
  extract shared polling helpers (`wait_for_relay`, `wait_for_socket`,
  `wait_for_onboard_ready`) into a reusable `lib-wait.sh`.
- F.6 — Script + doc hygiene bundle:
  - Delete the dead `test/igloo-web/specs` and `test/igloo-web/support`
    directories.
  - Remove the `test:run-sh` `package.json` alias; rename the guard
    script from `test-run-sh.sh` to `test-makefile-surface.sh`.
  - Narrow `test/igloo-pwa/global-setup.ts` prebuild to `['pwa']` only.
    Narrow `test/igloo-chrome/global-setup.ts` to `['chrome']` for the
    fast tier; keep `['chrome', 'home', 'demo']` only for live/demo tiers.
  - Fix `scripts/reset.sh`: remove the unreachable interactive prompt
    branch; wipe all of `build/` atomically (both `igloo-shell-target` and
    `bifrost-target`); replace bare `docker compose ... down` with a call
    to `demo.sh stop_projects`.
  - Fix `scripts/demo.sh` port-resolution TOCTOU: drop the `port_in_use`
    probe; let `docker compose up` fail loud on conflict; persist the
    resolved port only after compose reports healthy.
  - Expand `scripts/check-setup.sh` to verify `cargo`, `npm`, `wasm-pack`
    (matching the `release-validation.yml` pinned version), and `xvfb-run`.
    Fail on missing tools rather than warn.
  - Align `AGENTS.md` with the full `make` surface enforced by
    `check-doc-command-surfaces.sh`.

## Execution Order

Four PRs. Numbering continues from Bucket E (PR18–PR24).

| PR | Items | Notes |
|---|---|---|
| PR25 | F.1 (container hardening) + F.5 (entrypoint refactor) | Both touch demo-harness containers; co-landing avoids a fragile intermediate state |
| PR26 | F.2 (.env.example) + F.3 (data/ removal) | Related workspace-scratch hygiene |
| PR27 | F.4 (GitHub Actions hardening) | Self-contained; no runtime impact |
| PR28 | F.6 (script + doc hygiene bundle) | Many small independent fixes; one PR keeps review load low |

All four PRs are independent and can run in parallel. Rough touch: ~800
lines across scripts, Dockerfiles, workflows, compose file, and docs.

Ships in the coordinated alpha release with A+B+C+D+E. No version bumps
specific to F.

---

## F.1 — Demo-harness container hardening

### Non-root `USER`

Both Dockerfiles (`services/dev-relay/dockerfile` and
`services/igloo-demo/dockerfile`) become:

```dockerfile
FROM ubuntu:24.04

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       bash ca-certificates libssl3 jq \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --system --gid 1500 igloo \
  && useradd --system --uid 1500 --gid 1500 --no-create-home --shell /usr/sbin/nologin igloo

WORKDIR /workspace
COPY services/<name>/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER igloo:igloo

ENTRYPOINT ["/entrypoint.sh"]
```

Changes:
- Add `jq` to the package list (needed by F.5).
- Create `igloo` user + group with stable UID/GID `1500`. Stable UID lets
  the parent-side scratch dir (`.tmp/test-harness/`) be `chown`'d or
  written with compatible perms if needed.
- `USER igloo:igloo` — container runs as non-root by default.

### Narrow `:rw` → `:ro` mounts

`compose.test.yml` mounts that become `:ro`:
```yaml
- ./repos/igloo-shell:/workspace/repos/igloo-shell:ro
- ./repos/bifrost-rs:/workspace/repos/bifrost-rs:ro
- ./services:/workspace/services:ro  # already :ro
```

Rationale: the entrypoints only read pre-built binaries from those paths
(binaries are built on the host via `scripts/test-prebuild.sh`, which
writes to host `target/`). The container never writes back.

Kept `:rw`:
```yaml
- ${FROSTR_TEST_HARNESS_DIR:-./.tmp/test-harness}:${FROSTR_TEST_HARNESS_CONTAINER_DIR:-/workspace/.tmp/test-harness}:rw
- cargo-target:/cargo-target
- cargo-registry:/usr/local/cargo/registry
- cargo-git:/usr/local/cargo/git
```

- The harness scratch dir is where the entrypoint writes onboard packages,
  passwords, and daemon state. `:rw` is required.
- Cargo-target volume is anonymous, `:rw` is required.

### UID-compatible scratch dir

`scripts/demo.sh` and `scripts/test-prebuild.sh` create
`.tmp/test-harness/` on the host (operator's UID, typically 1000). The
container now runs as UID 1500 and needs to write into that bind.

Fix: Docker bind mounts preserve the host owner. If host UID 1000 creates
the dir and the container runs as UID 1500, writes fail. Two options:

**Option A (chosen): `--userns-remap` via compose `user:` directive that
matches host.** Compose service adds:
```yaml
user: "${HOST_UID:-1000}:${HOST_GID:-1000}"
```
and `scripts/demo.sh` sets `HOST_UID="$(id -u)"` and `HOST_GID="$(id -g)"`
before `docker compose up`.

This overrides the `USER igloo` from the Dockerfile at runtime with the
host user's UID, so file writes land with the operator's ownership.
Simple, avoids `userns-remap` complexity, and the container is still
non-root (on the host, it's UID 1000, which is the operator — still
unprivileged).

**Option B (not chosen): chown harness dir to 1500 on the host.**
Awkward, breaks when multiple operators share a checkout, loses file
ownership for the operator.

### Eliminate `chmod 0777` / `chmod -R a+rwX`

`services/igloo-demo/entrypoint.sh`:
- `relax_artifact_permissions()` (around lines 189-191 per audit) — the
  `chmod -R a+rwX` over the harness dir. Delete. With UID matching
  (Option A above), the operator already owns everything the container
  writes.
- `start_demo_daemon()` `chmod 0777` on socket directory (around line
  344-346). Delete. Create the dir with `install -m 0700` instead.
- Password file `chmod 0644` (mentioned in audit finding 4). Change to
  `chmod 0600`.

### Socket path inside container

The daemon control socket lives at
`/workspace/.tmp/test-harness/igloo-shell-<member>.sock`. That path is
~55 characters — well under the 108-byte `UNIX_PATH_MAX`. No `/tmp`
fallback needed for the container. Remove any fallback logic.

### Testing

- `cargo build` shell on host → demo container reads binary via `:ro`
  mount → works.
- Host operator UID 1000: start container, observe
  `.tmp/test-harness/` files are owned by 1000 (not root).
- Security regression test: `docker exec <container> id` returns
  `uid=1000(...)`, not `uid=0(root)`.
- Security regression test: `docker exec <container> touch /workspace/repos/igloo-shell/probe`
  fails with `Read-only file system`.
- Full flow: `make demo-start && make demo-onboard && make demo-smoke`
  continues to work.

---

## F.2 — `.env.example` cleanup

### Target file

New `.env.example`:

```bash
# Docker platform override (set to linux/arm64 on Apple Silicon).
DOCKER_PLATFORM=linux/x86_64
# Project-name prefix for compose networks and containers.
COMPOSE_PROJECT_NAME=bifrost-infra

# Demo harness — consumed by compose.test.yml and services/igloo-demo.
DEV_RELAY_PORT=8194
DEV_RELAY_EXTERNAL_HOST=127.0.0.1
IGLOO_SHELL_DEMO_MEMBER=alice
IGLOO_SHELL_DEMO_INVITE_MEMBERS=bob,carol
IGLOO_SHELL_DEMO_THRESHOLD=2
IGLOO_SHELL_DEMO_COUNT=3
# NOTE: IGLOO_SHELL_DEMO_CONTROL_TOKEN is generated per-run by the harness
# starting in Bucket C; set it here only if pinning for repro.
```

Removed (retired stack, never referenced):
- `IGLOO_SERVER_PORT`, `IGLOO_SERVER_MODE`, `IGLOO_SERVER_HEADLESS`,
  `IGLOO_SERVER_AUTH_ENABLED`, `IGLOO_SERVER_RATE_LIMIT_ENABLED`,
  `IGLOO_SERVER_ADMIN_SECRET`, `IGLOO_SERVER_API_KEY`
- `IGLOO_WEB_MODE`, `IGLOO_WEB_PORT`, `VITE_IGLOO_SERVER_URL`
- `IGLOO_CLI_MODE`

Removes the two plausible-looking "admin secret" values (`change-me`,
`dev-local-key`) from the repo entirely.

### Legacy-surface guard

`test/scripts/check-doc-surfaces.sh`: add `.env.example` to the file-path
list that is scanned for retired terms (`igloo-server`, `igloo-web`,
`igloo-cli`, etc.).

After this change, `rg 'igloo-server|igloo-web|igloo-cli' ./` across the
full repo should return no matches (except possibly historical `dev/done/`
notes, which are explicitly excluded by the guard).

### Testing

- `make repo-init && make demo-start` from a fresh `.env` copied from
  `.env.example` — full flow works.
- `npm --prefix test run test:guards` — passes.
- Regression: `rg 'IGLOO_SERVER|IGLOO_WEB|IGLOO_CLI' .env.example` returns
  no matches.

---

## F.3 — `data/` directory removal

### Changes

1. Delete `data/.gitkeep` from the tree.
2. Remove these three lines from `.gitignore`:
   ```
   data/*
   !data/.gitkeep
   !data/*/.gitkeep
   ```
3. If `data/` exists in the working tree on disk (not tracked), it stays
   ignored by default (any `data/` would need to be explicitly `git add`ed).
4. Remove any residual runtime behavior that writes to `data/`. Grep
   confirms no script writes there today.
5. Extend `test/scripts/check-doc-surfaces.sh`:
   - Reject any tracked path under `data/`.
   - Reject any re-introduction of `data/*` patterns in `.gitignore`.
   - Reject any script / Makefile target that writes to `data/`.

### Testing

- `git ls-files data/` returns empty.
- `rg '^data/' .gitignore` returns empty.
- `rg 'data/test-harness|data/\.gitkeep' .` returns empty outside `dev/`
  archived history and the guard script itself.
- `npm --prefix test run test:guards` passes.

---

## F.4 — GitHub Actions hardening

### SHA pinning

Every third-party action is pinned to a 40-char commit SHA. Current
bindings in `.github/workflows/release-validation.yml`:

| Action | Current | Target |
|---|---|---|
| `actions/checkout@v4` | tag | `actions/checkout@<SHA>  # v4.X.Y` |
| `actions/setup-node@v4` | tag | `actions/setup-node@<SHA>  # v4.X.Y` |
| `dtolnay/rust-toolchain@stable` | floating | `dtolnay/rust-toolchain@<SHA>  # stable @ YYYY-MM-DD` |
| `Swatinem/rust-cache@v2` | tag | `Swatinem/rust-cache@<SHA>  # v2.X.Y` |

Same set in `workspace-guards.yml`.

Implementation: run `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`
for each pinned tag at PR-author time. Encode the SHA with a trailing
`# tag` comment for reviewer readability.

`dtolnay/rust-toolchain@stable` has no stable tag (it's a branch); pin to
the current HEAD SHA and document that updating requires a dependabot-style
bump.

### Permissions block

Add to both workflow files at workflow level (before `jobs:`):

```yaml
permissions:
  contents: read
```

Neither workflow writes back to the repository (no PR comments, no
deployments, no issue updates, no release publication). `contents: read`
is sufficient.

### Concurrency

Add to both workflow files:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

- On pull requests, new pushes cancel previous runs (common pattern).
- On `push` to `main` / `master`, runs queue serially (don't cancel;
  finalize the push-to-main gate even if a later push arrives).

### `npm ci` consistency

`/.github/workflows/workspace-guards.yml` line 66:
```yaml
- name: Install test dependencies
  working-directory: test
  run: npm install
```
→
```yaml
- name: Install test dependencies
  working-directory: test
  run: npm ci
```

All other `npm ci` sites in `release-validation.yml` are correct.

### Testing

- Open a PR touching both workflows; verify both complete green.
- Rebase and push a new commit on the PR; verify the previous run is
  cancelled (concurrency).
- Attempt to `write` something via `GITHUB_TOKEN` (inject a test step
  posting a comment); verify it fails (permissions block working).

---

## F.5 — `igloo-demo` entrypoint refactor

### Scope

`services/igloo-demo/entrypoint.sh` is 450 lines. The audit called out
three smells:
1. Hand-rolled `awk`/`sed` JSON parsing of `igloo-shell` CLI output.
2. Copy-pasted polling loops with hardcoded 60s timeouts.
3. Late `trap cleanup EXIT INT TERM` registration (line 443 per audit).

### Changes

**Install `jq` in the container** (F.1 already does this).

**Replace JSON parsers with `jq`:**
- `json_string_field <json> <field>` → `jq -r ".<field>"`.
- `json_number_field <json> <field>` → `jq -r ".<field>"`.
- `imported_profile_id` helper → inline `jq` on the `igloo-shell import --json` output.

`igloo-shell`'s JSON output is already valid JSON; we were just using
`awk` because `jq` wasn't available. Install + use.

**Extract polling helpers to `services/igloo-demo/lib-wait.sh`:**

```bash
#!/usr/bin/env bash
# Sourced by services/igloo-demo/entrypoint.sh.
# Polling helpers with consistent timeout / interval semantics.

wait_for_condition() {
  local description="$1"
  local timeout_secs="$2"
  local interval_secs="$3"
  shift 3
  local attempt=0
  local max_attempts=$(( (timeout_secs * 1000) / (interval_secs * 1000) ))

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    if "$@"; then
      return 0
    fi
    sleep "${interval_secs}"
    attempt=$((attempt + 1))
  done

  echo "timed out after ${timeout_secs}s waiting for: ${description}" >&2
  return 1
}

wait_for_relay() {
  wait_for_condition "relay to be reachable" 60 0.2 \
    bash -c 'exec 3<>/dev/tcp/${DEV_RELAY_HOST}/${DEV_RELAY_PORT} && exec 3>&-'
}

wait_for_socket() {
  local path="$1"
  wait_for_condition "socket at ${path}" 60 0.2 \
    test -S "${path}"
}

wait_for_onboard_ready() {
  local member="$1"
  wait_for_condition "onboard package for ${member}" 60 0.2 \
    bash -c "test -s \"\${IGLOO_SHELL_DEMO_ARTIFACT_DIR}/onboard-${member}.txt\""
}
```

Entrypoint sources `lib-wait.sh` and uses the helpers. Same polling
semantics, one definition.

**Trap registration early:**

```bash
cleanup() { ... }
trap cleanup EXIT INT TERM
```

Moved to the top of the script, before any side effects (file writes,
daemon spawns). Was previously registered on line 443 per audit.

### `services/igloo-demo/dockerfile` Dockerfile changes

Per F.1, `jq` is added to the `apt-get install` list.

### Testing

- `make demo-start` / `make demo-onboard` / `make demo-smoke` continues to work.
- `docker exec <igloo-demo> jq --version` returns a valid version.
- Fault injection: `docker kill -9 <igloo-demo>`; verify `cleanup`
  trap runs (check logs for cleanup-complete marker).
- Line count: original ~450 lines → target ≤280 lines after dedup.

---

## F.6 — Script + doc hygiene bundle

Single PR, multiple independent fixes. Each listed with its audit-finding
reference.

### F.6.1 — Delete dead `test/igloo-web/` (audit finding 13)

`rm -rf test/igloo-web/`. No files, no specs, no `package.json` entry.
Extend the legacy-surface guard to flag any re-introduction of
`test/igloo-web/` as a tracked path.

### F.6.2 — Remove `test:run-sh` alias + rename guard (audit finding 6)

- `test/package.json`: delete the `"test:run-sh": "bash ./scripts/test-run-sh.sh"` line.
- Rename `test/scripts/test-run-sh.sh` → `test/scripts/check-makefile-surface.sh`.
- Update `test/scripts/...` references inside `test:guards` composite script.
- Update the guard's internal comments to reflect its real purpose
  (verifying the `make` surface, not the now-gone `run.sh`).

### F.6.3 — Narrow `test/igloo-pwa/global-setup.ts` (audit finding 10)

```typescript
// Before:
await runTestPrebuild(['pwa', 'home']);
// After:
await runTestPrebuild(['pwa']);
```

Split `test/igloo-chrome/global-setup.ts` by grep tier:
- Fast tier (`--grep-invert @live`): `['chrome']` only.
- Live tier (`--grep @live`): `['chrome', 'home']`.
- Demo tier: `['chrome', 'home', 'demo']`.

Tier is determined by the Playwright project config; pass it as an arg
to `runTestPrebuild`.

### F.6.4 — Fix `scripts/reset.sh` (audit finding 9)

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${ROOT_DIR}/.tmp"
BUILD_ROOT="${ROOT_DIR}/build"

if [ "${1:-}" != "--force" ] && [ "${1:-}" != "-f" ]; then
  echo "reset.sh requires --force (invoked via 'make repo-reset')" >&2
  exit 1
fi

echo "Stopping demo compose services..."
bash "${ROOT_DIR}/scripts/demo.sh" stop || true

echo "Resetting root scratch directories..."
if [[ -e "${TMP_ROOT}" && ! -w "${TMP_ROOT}" ]]; then
  stale_root="${ROOT_DIR}/.tmp.stale.$(date +%s)"
  echo "Workspace scratch root is not writable; moving it to ${stale_root}"
  mv "${TMP_ROOT}" "${stale_root}"
fi
rm -rf "${TMP_ROOT}"
rm -rf "${BUILD_ROOT}"
mkdir -p "${TMP_ROOT}"
mkdir -p "${BUILD_ROOT}"

echo "Reset complete."
```

Changes:
- Remove the interactive prompt branch (unreachable via `make repo-reset`
  which always passes `--force`).
- Wipe all of `build/` (not just `build/igloo-shell-target`) — symmetric
  cleanup.
- Replace bare `docker compose ... down` with a call to `demo.sh stop`,
  which uses the `stop_projects` helper that correctly matches compose
  project labels.

### F.6.5 — Fix `scripts/demo.sh` TOCTOU port selection (audit finding 8)

Change `start_stack` to:

```bash
start_stack() {
  local action="$1"
  local requested_port="${2:-$DEFAULT_PORT}"

  stop_projects "${requested_port}"
  echo "==> Using demo relay port ${requested_port}"
  mkdir -p "${HOST_HARNESS_DIR}"
  build_binaries

  # Let docker compose fail loud on port conflict instead of probing.
  # If the port is actually bound by another process, docker will exit
  # with a clear error; the operator can re-run with PORT=<alt>.

  if [[ "${action}" == "foreground" ]]; then
    if ! run_compose_attached "${requested_port}"; then
      echo "compose failed (port ${requested_port} may be in use); retry with PORT=<alternative>" >&2
      return 1
    fi
  else
    FROSTR_TEST_HARNESS_DIR="${HOST_HARNESS_DIR}" \
    FROSTR_TEST_HARNESS_CONTAINER_DIR="${CONTAINER_HARNESS_DIR}" \
    DEV_RELAY_PORT="${requested_port}" DEV_RELAY_EXTERNAL_HOST=localhost \
    HOST_UID="$(id -u)" HOST_GID="$(id -g)" \
      docker compose -f "${ROOT_DIR}/compose.test.yml" up -d --build --remove-orphans \
        "${DEMO_HARNESS_SERVICES[@]}" \
      || { echo "compose failed (port ${requested_port} may be in use); retry with PORT=<alternative>" >&2; return 1; }
  fi

  # Only persist the port file after compose succeeds.
  printf '%s\n' "${requested_port}" > "${RELAY_PORT_FILE}"
  print_onboard "${requested_port}"
}
```

Changes:
- Drop `resolve_free_port` + `port_in_use` probing.
- Don't pre-write the port file — only persist after compose is healthy.
- Include the F.1 `HOST_UID` / `HOST_GID` env vars for UID-matched
  bind-mount writes.

Keep the `resolve-port` subcommand as-is (used by `make demo-smoke` for
informational purposes).

### F.6.6 — Expand `scripts/check-setup.sh` (audit finding 12)

Verify every tool the workflow actually uses. Turn warnings into errors:

```bash
require_cmd() {
  local name="$1"
  local install_hint="$2"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "missing required tool: ${name}" >&2
    echo "install hint: ${install_hint}" >&2
    exit 1
  fi
}

require_cmd docker "https://docs.docker.com/get-docker/"
require_cmd cargo "https://rustup.rs/"
require_cmd npm "https://nodejs.org/"
require_cmd wasm-pack "cargo install --locked --version 0.14.0 wasm-pack"
require_cmd xvfb-run "apt-get install xvfb (Linux only)"
require_cmd jq "apt-get install jq"
```

Plus the existing checks for `.gitmodules`, `.env`, `.tmp` writability.

### F.6.7 — Align `AGENTS.md` with the full `make` surface (audit finding 11)

`AGENTS.md` currently lists only a subset. Expand to the full surface
that `test/scripts/check-doc-command-surfaces.sh` enforces. Keep
alignment by running the guard locally as part of the PR checklist.

### Testing

- `npm --prefix test run test:guards` passes.
- `make repo-check` fails cleanly if any tool is missing (new behavior).
- `make repo-reset` runs non-interactively and wipes all scratch.
- `make demo-start PORT=8194` fails loudly if 8194 is taken (previously
  silently drifted to 8195).
- `make test-fast` completes without building home/demo artifacts.

---

## Critical Files

Modify:

**F.1 + F.5 (container hardening + entrypoint refactor):**
- `/home/cscott/Repos/frostr/frostr-infra/services/dev-relay/dockerfile`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/dockerfile`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/entrypoint.sh`
- `/home/cscott/Repos/frostr/frostr-infra/services/igloo-demo/lib-wait.sh` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/compose.test.yml`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/demo.sh` (HOST_UID/HOST_GID env)

**F.2 + F.3 (scratch hygiene):**
- `/home/cscott/Repos/frostr/frostr-infra/.env.example`
- `/home/cscott/Repos/frostr/frostr-infra/.gitignore`
- `/home/cscott/Repos/frostr/frostr-infra/data/.gitkeep` (DELETE)
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-surfaces.sh` (extend scan set)

**F.4 (GitHub Actions):**
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/release-validation.yml`
- `/home/cscott/Repos/frostr/frostr-infra/.github/workflows/workspace-guards.yml`

**F.6 (hygiene bundle):**
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-web/` (DELETE)
- `/home/cscott/Repos/frostr/frostr-infra/test/package.json`
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/test-run-sh.sh` → `check-makefile-surface.sh`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-pwa/global-setup.ts`
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-chrome/global-setup.ts`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/reset.sh`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/demo.sh`
- `/home/cscott/Repos/frostr/frostr-infra/scripts/check-setup.sh`
- `/home/cscott/Repos/frostr/frostr-infra/AGENTS.md`

## Verification

Per PR:

**PR25 (F.1 + F.5):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make repo-reset
make test-prep
make demo-start
make demo-onboard
make demo-smoke
make demo-stop
# Security regressions:
make demo-start
docker exec $(docker ps -qf name=dev-relay) id  # expects non-root uid
docker exec $(docker ps -qf name=dev-relay) touch /workspace/repos/bifrost-rs/probe 2>&1 | grep -q 'Read-only'
make demo-stop
```
Plus: `wc -l services/igloo-demo/entrypoint.sh` ≤ 280.

**PR26 (F.2 + F.3):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
git ls-files data/ | wc -l  # expects 0
rg '^data/' .gitignore  # expects 0 matches
rg 'IGLOO_SERVER|IGLOO_WEB|IGLOO_CLI' .env.example  # expects 0
rg 'igloo-server|igloo-web|igloo-cli' . --glob '!dev/done/**' --glob '!dev/reports/**' --glob '!dev/audit/**' --glob '!dev/plans/**'  # expects 0
npm --prefix test run test:guards
```

**PR27 (F.4):**
```bash
# Manual: push a branch with trivial change, observe workflow runs;
# rebase, observe previous run cancelled (concurrency);
# inject a test step that tries to use GITHUB_TOKEN for write (e.g.,
#   create a label), observe permissions denial.
rg '@v[0-9]+|@stable' .github/workflows/  # expects 0 raw tag pins (all in comments after SHA)
grep -r 'npm install' .github/workflows/  # expects 0 production uses (only inside `# FIXME` or comments if any)
grep -r 'permissions:' .github/workflows/  # expects 2 matches (one per workflow)
grep -r 'concurrency:' .github/workflows/  # expects 2 matches
```

**PR28 (F.6):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
git ls-files test/igloo-web/ | wc -l  # expects 0
rg 'test:run-sh' test/package.json  # expects 0
npm --prefix test run test:guards
# Interactive reset test:
bash scripts/reset.sh  # expects exit 1 with clear message about --force
make repo-reset
# Check-setup with missing tool:
PATH="/usr/bin" scripts/check-setup.sh  # expects failures for cargo/npm/wasm-pack
# demo.sh port TOCTOU fix:
make demo-start PORT=8194
# In another terminal, occupy 8195; then:
make demo-start PORT=8195  # expects loud failure, not silent drift
```

**Full-bucket verification:**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```

## Cross-Repo Coordination

No cross-repo impact. All Bucket F work is in `frostr-infra`. No
submodule pointer updates. No on-disk format version bumps. Ships in
the coordinated alpha release alongside A+B+C+D+E as a no-friction
addition.

Release notes:
- Demo harness now runs containers as a non-root user. Operators who
  mounted custom scratch paths with root ownership will need to re-`chown`
  them to their UID (or let `make demo-start` create fresh ones).
- `IGLOO_SHELL_PROFILE_PASSPHRASE` scripting is already called out for
  Bucket C. `.env.example` no longer documents the retired `igloo-server`
  / `igloo-web` / `igloo-cli` variables; operators relying on those should
  remove them from their local `.env`.
- GitHub workflows now pin actions to SHAs; dependabot (or manual refresh)
  required to pick up upstream action updates.

## Out-of-Bucket Flags

- **`test-prebuild.sh` stamp/fingerprint rewrite** (audit finding 5) —
  meaningful refactor. Defer to a later tooling-polish bucket.
- **`release-matrix.sh` globals cleanup** (audit finding 14) — low-signal;
  fold into the same future tooling bucket.
- **Docker image size optimization** — base images are already minimal;
  no action needed.
- **`userns-remap` full Docker daemon configuration** — more secure than
  the compose-level `user:` directive chosen in F.1 but requires
  operator-side Docker daemon changes. Defer; compose-level `user:`
  matching the host UID is the pragmatic alpha choice.

## Summary

Four PRs, ~800 lines, all in `frostr-infra`. Closes the three
high-severity workspace findings (root containers + `.env.example` leak
+ tracked `data/`) plus the seven medium and three low findings in one
cleanup wave.

- **Containers** run as a non-root user; submodule binds are `:ro` where
  read-only suffices; `chmod 0777` and `chmod -R a+rwX` disappear from
  entrypoints; UID is matched to the host operator so bind-mount writes
  land with correct ownership.
- **`.env.example`** describes only the variables the current compose
  stack actually consumes. The retired `igloo-server` / `igloo-web` /
  `igloo-cli` leak — including the `change-me` admin-secret default — is
  gone. Legacy-surface guard scans `.env.example` so future drift fails
  CI.
- **`data/` directory** removed. `.gitignore` carve-outs deleted. Guard
  flags any re-introduction.
- **GitHub Actions** pin third-party actions to SHAs (with readable tag
  comments), declare `permissions: contents: read`, carry a `concurrency:`
  key, and use `npm ci` consistently.
- **`igloo-demo` entrypoint** replaces `awk`/`sed` JSON parsing with `jq`,
  extracts polling helpers into `lib-wait.sh`, and registers its cleanup
  trap before any side effects.
- **Script and doc hygiene bundle** removes dead directories, renames the
  fossil-named guard, narrows fast-tier prep to one host each, fixes
  `reset.sh` interactive-branch + asymmetric build/ wipe, fixes `demo.sh`
  port TOCTOU, expands `check-setup.sh` to the full toolchain surface,
  and aligns `AGENTS.md` with the enforced `make` surface.

Ships in the coordinated alpha release with Buckets A + B + C + D + E.
