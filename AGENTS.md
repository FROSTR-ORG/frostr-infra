# Repository Guidelines

## Project Structure & Module Organization

`frostr-infra` is the coordinating workspace for FROSTR. Root ownership is:

- `docs/`: shared FROSTR architecture, protocol, artifact, and wire specs
- `dev/`: release docs, ADRs, policies, reports, and historical workspace notes
- `test/`: cross-repo Playwright, desktop, and demo-harness verification
- `services/`: infra-owned compose services such as `dev-relay` and `igloo-demo`
- `repos/`: git submodules for implementation and reference repos; treat each as an independent project

Use root docs for workspace behavior, then read the owning submodule's docs for repo-local implementation details.

## Build, Test, and Development Commands

The `Makefile` is the single public root command surface. Root `scripts/`
are private implementation detail; do not invoke them directly and do not
add new root entrypoints outside the Makefile. Run `make help` to see the
canonical list.

### Workspace lifecycle

- `make repo-init`: sync and initialize top-level submodules and install
  workspace dependencies
- `make repo-check`: verify workspace prerequisites (docker, docker compose,
  cargo, npm, wasm-pack, jq, xvfb-run on Linux)
- `make repo-reset`: wipe `.tmp/` scratch and `build/` artifacts after
  stopping any running demo stack; required non-interactively via
  `--force`

### Demo harness

- `make demo-start [PORT=<port>]`: start the dev-relay + igloo-demo
  compose stack in the background
- `make demo-foreground [PORT=<port>]`: same as above but attached to the
  terminal
- `make demo-onboard`: print onboarding packages and relay URLs for the
  running stack
- `make demo-logs` / `make demo-stop`: tail logs / tear the stack down
- `make demo-smoke [PORT=<port>]`: quick onboard-path smoke test

### Testing

- `make test-prep`: prebuild shared Rust binaries, browser-wasm artifacts,
  and demo images
- `make test-smoke`: Docker-backed demo harness + onboarding path
- `make test-fast`: non-live browser tests
- `make test-live`: local relay + live signer browser tests
- `make test-demo`: Docker-backed browser onboard + sign-through
- `make test-e2e`: aggregate browser matrix (fast + live)
- `make test-affected`: minimal test surface for the current branch
- `make test-release`: full coordinated release matrix with timing summary
- `npm --prefix test run test:guards`: doc, command-surface, and harness
  guard checks

### Browser and desktop app commands

Per-submodule targets live on the Makefile too. Common ones:

- `make igloo-pwa-dev` / `make igloo-pwa-build`
- `make igloo-chrome-dev` / `make igloo-chrome-build`
- `make igloo-home-tauri-dev` / `make igloo-home-build`
- `make igloo-paper-verify [STRICT=1]`

### Compose passthrough

- `make compose-start SERVICES="<service> [service...]"`
- `make compose-stop SERVICES="<service> [service...]"`
- `make compose-restart SERVICES="<service> [service...]"`
- `make compose-logs SERVICES="<service> [service...]"`

## Coding Style & Naming Conventions

Keep changes scoped to the owning layer: shared semantics in `docs/`,
workspace process in `dev/`, cross-repo harness logic in `test/`, product
code in the correct implementation submodule, and Paper design references
in `repos/igloo-paper`. Prefer Markdown with short sections and concrete
commands. For shell scripts, follow existing Bash style (`set -euo
pipefail`, lowercase helper names). Do not add ad hoc root entrypoints
when the `Makefile` should own the workflow. Do not import `igloo-paper`
into runtime code, package code, or app builds.

## Testing Guidelines

Cross-repo browser tests use Playwright from `test/`. Name specs
`*.spec.ts`; keep helper code under `test/.../fixtures` or `test/shared`.
Run the smallest proof first, then escalate to `make test-affected` or
`make test-release`. When docs change, run `npm --prefix test run
test:guards` — it enforces the command surfaces documented here and in
`README.md`, `test/README.md`, and `dev/docs/RELEASE.md` stay in sync.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects, for example `Reorganize
workspace docs and cross-repo test harness`. Keep commits focused by
layer. Update docs in the same pass as behavior changes. PRs should
summarize affected workspace surfaces, note any submodule pointer
updates, and include validation commands run.

## Workspace Rules

Use non-recursive submodule commands. Keep generated output under
`./.tmp/`, not tracked-looking paths like `data/`. If the workspace
scratch tree becomes stale, repair it with `make repo-reset`.
