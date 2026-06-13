# Repository Guidelines

`frostr-infra` is the coordinating workspace for FROSTR: a Rust signing core
(`bifrost-rs`, compiled to native and browser WebAssembly) wrapped by a family
of TypeScript `igloo-*` clients. This repo owns the shared system docs, the root
command surface, cross-repo demo and E2E harnesses, and the submodule pointers
for the implementation and reference repos under `repos/`.

Use this file as the always-loaded routing layer, not as the full manual. It
points you at the canonical deep docs; read those for anything beyond the
summaries here.

## Workspace Layout

Root ownership:

- `docs/` — shared FROSTR architecture, protocol, cryptography, artifact, and
  wire specs (the canonical system manual)
- `dev/` — workspace process docs, ADRs, policies, release coordination, and
  historical engineering notes
- `test/` — cross-repo Playwright, desktop, and demo-harness verification
- `services/` — infra-owned compose services (`dev-relay`, `igloo-demo`)
- `repos/` — git submodules; treat each as an independent project
- `Makefile` — the curated, supported root command surface
- `compose.test.yml` — local demo-harness stack definition

Keep changes scoped to the owning layer: shared semantics in `docs/`, workspace
process in `dev/`, cross-repo harness logic in `test/`, product code in the
correct submodule, and design references in `repos/igloo-paper`.

## Repos / Submodule Map

Each repo under `repos/` is an independent project with its own
`CLAUDE.md` / `AGENTS.md` / `README`. Read the owning submodule's docs for
repo-local implementation detail.

| Repo | Role |
|------|------|
| `repos/bifrost-rs` | Rust signing core: threshold signer, router, Nostr messaging, Tokio + WASM bridges |
| `repos/igloo-shared` | Shared TypeScript runtime: signer contracts, package handling, bridge-WASM boundary, browser-host observability |
| `repos/igloo-ui` | React UI package: reusable primitives, shell/layout, FROSTR workflow components, design-token consumption |
| `repos/igloo-pwa` | Progressive Web App signing client |
| `repos/igloo-chrome` | Chrome MV3 extension: thin host over the bifrost WASM runtime |
| `repos/igloo-home` | Tauri desktop co-signer host |
| `repos/igloo-shell` | Shell / operator host runtime |
| `repos/igloo-paper` | **Reference-only** Paper design export. Never import into runtime code, packages, or app builds |

## Languages & Toolchain

- **Rust** drives `bifrost-rs` and the browser WASM artifacts. Install via
  **rustup, not Homebrew** — Homebrew Rust on `PATH` is unsupported.
  `rust-toolchain.toml` pins stable with the `wasm32-unknown-unknown` target and
  `rustfmt` + `clippy`.
- **Browser WASM** is built with `wasm-pack 0.14.0` (install `--locked`); macOS
  also needs `llvm`/`clang`. Run `make wasm-toolchain-check` to verify the setup.
- **JavaScript / TypeScript** uses **npm** (not Bun). Cross-repo E2E runs on
  Playwright from `test/`.

## Doc Map

Use this file for routing; follow these for depth.

| Doc | Scope |
|-----|-------|
| `README.md` | Workspace entrypoint, quick start, and daily command surface |
| `CONTRIBUTING.md` | Ownership boundaries, change-routing decisions, validation expectations |
| `docs/INDEX.md` | Shared FROSTR system manual (architecture, protocol, cryptography, wire, artifacts) |
| `dev/README.md` | Map of workspace engineering docs and historical records under `dev/` |
| `dev/docs/WORKFLOWS.md` | Workspace workflows, documentation-drift control, follow-up harvests |
| `dev/docs/DESIGN.md` | Paper → `igloo-paper` → `igloo-ui` design handoff and import boundary |
| `dev/docs/RELEASE.md` | Coordinated release, tagging, and submodule-pointer process |
| `dev/docs/GOTCHAS.md` | Full list of workspace gotchas and environment footguns |
| `dev/docs/STYLES.md` | Workspace shell, documentation, and commit style (per-language naming is submodule-owned) |
| `dev/adrs/INDEX.md` | Architecture decision records (historical; current behavior lives in `docs/`) |
| `dev/BACKLOG.md` | Curated open follow-up work (the follow-up-harvest sink) |
| `dev/HISTORY.md` | Completed-work log + archived historical follow-up log |
| `dev/policies/` | Contributor-facing engineering guidance and review prompts |
| `test/README.md` | Cross-repo demo and E2E harness commands |
| `test/docs/WORKFLOWS.md` | Test-lane selection, client-scoped validation, visual loops, WASM test guidance |
| `.agents/skills/frostr-paper-ui-workflows/SKILL.md` | Routing for Paper source sync and Paper-to-UI alignment |

## Build, Test, and Development Commands

Use `make` as the public root interface. `make help` lists the full surface.
`scripts/`, `dev/scripts/`, and `test/scripts/` are private implementation
detail behind it — do not add ad hoc root entrypoints.

```bash
make repo-init       # sync and initialize top-level submodules (non-recursive)
make repo-check      # verify workspace prerequisites
make repo-reset      # repair a stale or unwritable scratch tree
make demo-start      # start the demo stack (backgrounds by default)
make demo-foreground # start the demo stack attached to the terminal
make demo-onboard    # print onboarding artifacts for the running demo
```

`make demo-start` auto-picks the next free relay port if the default is taken;
override with `make demo-start PORT=<port>`. Per-client dev/build/test targets
exist too (e.g. `make igloo-pwa-dev`, `make igloo-chrome-build`,
`make igloo-home-tauri-dev`).

## Testing

Choose the smallest check that proves the change, then escalate. When docs
change, run `npm --prefix test run test:guards`.

| Tier | Command | Use when |
|------|---------|----------|
| Smoke | `make test-smoke` | Quick demo-harness onboard sanity check |
| Fast | `make test-fast` | PWA + Chrome suites excluding `@live`; **render-only** pre-push gate (no live signer/relay, so green can still hide a broken demo — use Live/Demo for behavior) |
| Live | `make test-live` | `@live` integration flows |
| Demo | `make test-demo` | Docker-backed Chrome/Home demo lane (CI release gate) |
| Affected | `make test-affected` | Minimal branch-dependent surface for the current change |
| Release | `make test-release` | Full coordinated release matrix |

Use `make test-prep` to prebuild shared Rust binaries, browser WASM artifacts,
and demo images before a local lane that needs them. GitHub Actions runs the
required `release-validation` workflow on PRs and `main` pushes.

## Coding Style & Naming

- Prefer Markdown with short sections and concrete commands.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, lowercase helper
  names, derive paths from the script location.
- Let the `Makefile` own workflows; root script directories stay private.
- Do not import `igloo-paper` into runtime code, package code, or app builds.
- For repo-local code style, follow the owning submodule's own conventions.

Full workspace shell/doc/commit style lives in `dev/docs/STYLES.md`.

## Submodule Workflow

- Use **non-recursive** submodule commands; avoid recursive operations from the
  parent.
- Commit **inside the submodule first**, then commit the bumped pointer in this
  repo.
- In PRs, note the submodule, commit hash, and why the pointer moved.

## Commit & Pull Request Guidelines

Use short imperative subjects (e.g. `Reorganize workspace docs and cross-repo
test harness`). Keep commits focused by layer and update docs in the same pass
as behavior changes. PRs should summarize affected workspace surfaces, note any
submodule pointer updates, and list the validation commands run.

## Key Gotchas

The few that bite most often; the full list lives in `dev/docs/GOTCHAS.md`.

- Install Rust via **rustup, not Homebrew** — Homebrew Rust on `PATH` breaks the
  WASM build.
- `repos/igloo-paper` is **reference-only** design material; never import it into
  runtime, packages, or builds. Tokens flow one way via the parent sync script.
- Keep generated output under `./.tmp/`, not tracked-looking paths like `data/`.
  Repair a stale scratch tree with `make repo-reset`.
- Use non-recursive submodule commands, and commit inside the submodule before
  bumping its pointer here.
