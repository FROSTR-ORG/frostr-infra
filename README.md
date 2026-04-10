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
- `run.sh`
  - curated root command router

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

`./run.sh` is the supported root command interface. Root `scripts/` are private
implementation detail.

Common commands:

```bash
./run.sh repo init
./run.sh repo check
./run.sh repo reset
./run.sh demo start
./run.sh demo onboard
./run.sh demo smoke
./run.sh test smoke
./run.sh test fast
./run.sh test live
./run.sh test prep
./run.sh test affected
./run.sh test release
./run.sh browser igloo-chrome build
```

`./run.sh demo start` stays attached to the terminal by default. Use
`BG=1 ./run.sh demo start` if you want the demo stack to keep running in the
background.

The root workspace manages the demo-harness services (`dev-relay`,
`igloo-demo`), shared docs, cross-repo tests, and submodule coordination.
Those parent-owned services do not correspond one-to-one with a repo under
`repos/`; they are still owned and documented by this workspace.

## Quick Start

```bash
cp .env.example .env
./run.sh repo init
./run.sh repo check
./run.sh demo start
./run.sh demo onboard
```

For the local demo harness:

```bash
./run.sh test prep
./run.sh demo start
./run.sh demo onboard
./run.sh demo logs
./run.sh demo stop
./run.sh test release
```

If the default relay port is occupied, the demo harness auto-picks the next
free port and records it in `./.tmp/test-harness/demo-relay-port.txt`. You can
still choose a specific port yourself:

```bash
./run.sh demo start --port 8394
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
./run.sh repo reset
```

For cross-repo test work:
- `./run.sh test prep`
  - prebuilds shared binaries, browser artifacts, and demo images
- `./run.sh test affected`
  - runs the deterministic minimal test surface for the current branch
- `./run.sh test release`
  - runs the full coordinated release matrix and prints a timing summary

## Submodule Policy

- Use non-recursive submodule commands in this repo.
- Avoid recursive submodule operations from the parent workspace.
- Treat each repo under `repos/` as an independent project with its own root
  manuals and release surface.
