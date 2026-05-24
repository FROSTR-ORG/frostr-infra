# frostr-infra

`frostr-infra` is the coordinating workspace for FROSTR.

It owns the shared system docs, the root command surface, cross-repo demo and
E2E harnesses, compose-based local environments, and the submodule pointers for
the implementation and reference repos under [`repos/`](./repos).

## What Lives Here

- `docs/`
  - shared FROSTR architecture, interfaces, protocol, cryptography, and
    artifact specs
- `dev/`
  - workspace-level release docs, ADRs, policies, and engineering notes
- `repos/`
  - independent project repos such as `bifrost-rs`, `igloo-shell`,
    `igloo-home`, `igloo-pwa`, `igloo-chrome`, `igloo-shared`, and `igloo-ui`
  - reference-only repos such as `igloo-paper`, the static Paper design
    contract export used as design source material
- `test/`
  - cross-repo browser, desktop, and demo-harness verification
- `services/`
  - infra-owned compose images and entrypoints
- `compose.test.yml`
  - local demo-harness stack definition
- `Makefile`
  - curated root command surface

Use the workspace docs this way:
- [`README.md`](./README.md)
  - workspace entrypoint and daily command surface
- [`CONTRIBUTING.md`](./CONTRIBUTING.md)
  - workspace structure, ownership, and contribution rules
- [`dev/README.md`](./dev/README.md)
  - map of workspace engineering docs and historical records under `dev/`
- [`dev/docs/RELEASE.md`](./dev/docs/RELEASE.md)
  - coordinated release process for submodules and the parent repo
- [`dev/docs/DESIGN.md`](./dev/docs/DESIGN.md)
  - parent-owned design handoff between `igloo-paper` and implementation repos
- [`docs/INDEX.md`](./docs/INDEX.md)
  - shared FROSTR system manual
- [`test/README.md`](./test/README.md)
  - cross-repo demo and E2E harness guide

## Root Command Surface

`make` is the supported root command interface. Script directories are private
implementation detail:

- `scripts/` backs root workspace and demo/test-prep workflows.
- `dev/scripts/` holds development-only bridge tooling.
- `test/scripts/` holds harness guards and test-only helpers.

Common commands:

```bash
make repo-init
make repo-check
make repo-reset
make demo-start
make demo-foreground
make demo-onboard
make demo-smoke
make test-smoke
make test-fast
make test-live
make test-demo
make test-prep
make test-affected
make test-release
make browser-wasm-refresh
make browser-wasm-check
make wasm-toolchain-check
make igloo-paper-sync
make igloo-paper-verify
make igloo-ui-paper-token-sync
make igloo-ui-paper-token-check
make igloo-chrome-build
make igloo-pwa-dev
make igloo-home-tauri-dev
```

`make demo-start` launches the demo stack in the background by default. Use
`make demo-foreground` if you want to stay attached to compose output in the
current terminal.

The root workspace manages the demo-harness services (`dev-relay`,
`igloo-demo`), shared docs, cross-repo tests, and submodule coordination.
Those parent-owned services do not correspond one-to-one with a repo under
`repos/`; they are still owned and documented by this workspace.

`make igloo-paper-sync` exports the live Paper canvas and then verifies the
checked-in design contract. `make igloo-paper-verify` runs only the verifier.
Both commands require Paper desktop and Paper MCP, and are not part of the
default runtime, demo, or release validation lanes.

`make igloo-ui-paper-token-sync` copies the approved design-token handoff into
`igloo-ui` as package-local generated files. `make igloo-ui-paper-token-check`
verifies those files are current. This bridge is parent-owned; `igloo-ui` does
not import or run Paper tooling.

## Quick Start

Install Rust through rustup before running browser wasm or release checks. This
workspace does not support Homebrew Rust on `PATH`.

```bash
brew unlink rust # or: brew uninstall rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
export PATH="$HOME/.cargo/bin:$PATH"
rustup target add wasm32-unknown-unknown
cargo install --locked --version 0.14.0 wasm-pack
brew install llvm # required on macOS for wasm-capable clang
```

```bash
cp .env.example .env
make repo-init
make repo-check
make wasm-toolchain-check
make demo-start
make demo-onboard
```

For the local demo harness:

```bash
make test-prep
make demo-start
make demo-onboard
make demo-logs
make demo-stop
make test-release
```

If the default relay port is occupied, the demo harness auto-picks the next
free port and records it in `./.tmp/test-harness/demo-relay-port.txt`. You can
still choose a specific port yourself:

```bash
make demo-start PORT=8394
```

## Reading Paths

For shared FROSTR system semantics:
- start at [`docs/INDEX.md`](./docs/INDEX.md)

For repo-local work:
- read the root docs inside the relevant project under [`repos/`](./repos)

For design-contract reference material:
- read [`repos/igloo-paper/README.md`](./repos/igloo-paper/README.md) and
  [`repos/igloo-paper/AGENTS.md`](./repos/igloo-paper/AGENTS.md)
- read [`dev/docs/DESIGN.md`](./dev/docs/DESIGN.md) for the parent-owned
  handoff boundary between design reference material and implementation repos

For cross-repo validation and demos:
- read [`test/README.md`](./test/README.md)

For release work:
- read [`dev/docs/RELEASE.md`](./dev/docs/RELEASE.md) first, then the affected
  submodule release docs

The default parent scratch location for live demo-harness artifacts is
`./.tmp/test-harness/`. Override it with `FROSTR_TEST_HARNESS_DIR` when a custom
path is required.

The shared prep and timing scratch path is `./.tmp/test-prebuild/`. Override it
with `FROSTR_TEST_PREBUILD_DIR` only when you intentionally want a different
scratch location.

Validation tiers are intentionally layered. Use `make test-prep` when a local
workflow needs prebuilt shared binaries, browser wasm artifacts, or demo images.
Use `make test-affected` for the minimal branch-dependent validation surface,
and reserve `make test-release` for coordinated release checks.

If `./.tmp/` becomes stale or unwritable, repair it with:

```bash
make repo-reset
```

For cross-repo test work:
- `make test-prep`
  - prebuilds shared binaries, browser artifacts, and demo images
- `make test-demo`
  - runs the required Docker-backed Chrome/Home demo validation lane
- `make test-affected`
  - runs the deterministic minimal test surface for the current branch
- `make test-release`
  - runs the full coordinated release matrix and prints a timing summary

GitHub Actions also runs the required `release-validation` workflow on pull
requests and `main` pushes for the release-facing demo lane.

## Submodule Policy

- Use non-recursive submodule commands in this repo.
- Avoid recursive submodule operations from the parent workspace.
- Treat each repo under `repos/` as an independent project with its own root
  manuals and release surface.
- Treat `repos/igloo-paper` as reference-only design material. Do not import it
  into runtime code, product packages, or app builds.
