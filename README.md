# frostr-infra

`frostr-infra` is the coordinating workspace for FROSTR.

It owns the shared system docs, the root command surface, cross-repo demo and
E2E harnesses, compose-based local environments, and the submodule pointers for
the implementation repos under [`repos/`](./repos).

## What Lives Here

- `docs/`
  - shared FROSTR architecture, interfaces, protocol, cryptography, and
    artifact specs
- `dev/`
  - workspace-level release docs, ADRs, policies, and engineering notes
- `repos/`
  - independent project repos such as `bifrost-rs`, `igloo-shell`,
    `igloo-home`, `igloo-pwa`, `igloo-chrome`, `igloo-shared`, and `igloo-ui`
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
- [`docs/INDEX.md`](./docs/INDEX.md)
  - shared FROSTR system manual
- [`test/README.md`](./test/README.md)
  - cross-repo demo and E2E harness guide

## Root Command Surface

`make` is the supported root command interface. Root `scripts/` are private
implementation detail.

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

## Quick Start

```bash
cp .env.example .env
make repo-init
make repo-check
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
