# Contributing to frostr-infra

This repository is the coordinating workspace for FROSTR. Contributing here is
different from contributing inside a single submodule: parent-repo changes
should improve shared docs, workspace workflows, release coordination, demo
harnesses, or cross-repo verification.

## What This Repo Owns

The parent repo owns:
- shared system docs under [`docs/`](./docs)
- workspace-level release docs, ADRs, and engineering guidance under
  [`dev/`](./dev)
- cross-repo browser and demo-harness tests under [`test/`](./test)
- demo compose definitions, demo services, and root orchestration under
  [`compose.test.yml`](./compose.test.yml) and [`Makefile`](./Makefile)
- submodule pointers and coordinated release checkpoints

The parent repo does not own implementation details that belong inside a
specific project repo.

## Workspace Shape

- `docs/`
  - canonical shared-system manual for FROSTR
- `dev/`
  - workspace release docs, ADRs, policies, and planning artifacts
- `repos/`
  - independent project repos
- `test/`
  - cross-repo browser, desktop, and demo-harness verification
- `services/`
  - infra-owned container images and entrypoints
- `scripts/`
  - root helper scripts used by `Makefile` and release workflows
- `compose.test.yml`
  - demo stack definition
- `Makefile`
  - curated top-level command surface

## Documentation Ownership

### Workspace docs

Workspace docs in this repo should explain:
- how the workspace is organized
- how contributors should work across repos
- how to run root-level commands and validation
- how coordinated releases are prepared and cut

Workspace-level engineering docs under [`dev/`](./dev) should capture:
- coordinated release instructions
- architecture decision records
- contributor-facing policies and guidance

### Canonical docs map

Use these surfaces as the source of truth:
- [`README.md`](./README.md)
  - supported top-level workspace commands and day-to-day entrypoints
- [`CONTRIBUTING.md`](./CONTRIBUTING.md)
  - ownership, contribution rules, and validation expectations
- [`docs/`](./docs)
  - shared FROSTR system spec
- [`dev/`](./dev)
  - workspace engineering process, ADRs, and historical records
- [`test/README.md`](./test/README.md)
  - cross-repo demo harness and E2E guidance

### Shared system docs

Top-level docs under [`docs/`](./docs) are the canonical source for:
- FROSTR architecture
- cross-host interfaces
- peer protocol semantics
- cryptographic model
- profile, backup, onboarding, rotation, and wire contracts
- shared terminology

These docs describe FROSTR as a system, not any one implementation.

### Repo-local docs

Each repo under [`repos/`](./repos) should document only:
- what that project owns
- how to build and test it
- project-specific contributor and release process
- implementation details specific to that project

Repo-local docs should not redefine the shared FROSTR protocol, cryptography,
or package model.

### Cross-repo test docs

[`test/README.md`](./test/README.md) owns:
- demo-harness guidance
- cross-repo browser and desktop E2E tiers
- shared Playwright and fixture expectations

## Repo Ownership Guide

### `repos/bifrost-rs`

Owns the runtime and cryptographic stack:
- signer/session primitives
- wire and package validation
- router/runtime state machine
- bridge and utility layers

### `repos/igloo-shared`

Owns shared browser/runtime adapter contracts and browser-facing package/runtime
helpers.

### `repos/igloo-shell`

Owns the CLI/operator host, shell-local profile and vault management, and
shell-owned smoke and node E2E workflows.

### `repos/igloo-home`

Owns the desktop host and local multi-profile UX.

### `repos/igloo-pwa`

Owns the browser-first PWA host UX.

### `repos/igloo-chrome`

Owns the extension host, provider surface, and extension-specific control plane.

### `repos/igloo-ui`

Owns the shared presentational UI package.

## How to Decide Where a Change Belongs

Put the change in the parent repo when it affects:
- shared system docs
- root release coordination
- cross-repo E2E harnesses
- demo stack orchestration
- compose/service wiring
- submodule pointers

Put the change in a submodule when it affects:
- product behavior
- repo-local docs
- repo-local tests
- crate/package/app implementation details

If a change touches both, update the owning submodule first and then update the
parent repo to reflect the new shared behavior, release state, or submodule
pointer.

## Workflow Expectations

- Use [`Makefile`](./Makefile) for supported root workflows.
- Prefer `make test-prep`, `make test-affected`, and `make test-release` over
  ad hoc root test orchestration.
- Treat the release-matrix timing summary as the first place to look when a
  root test phase regresses.
- Treat root `scripts/` as implementation detail unless you are maintaining the
  root orchestration itself.
- Keep the workspace and submodules clean; do not leave generated artifacts in
  tracked locations.
- Parent live scratch output belongs under `./.tmp/`, not tracked-looking paths
  such as `./data/`.
- Shared test prep timing output belongs under `./.tmp/test-prebuild/`.
- Use `FROSTR_TEST_PREBUILD_DIR` only when you intentionally need a custom
  scratch location.
- If the parent `./.tmp/` tree becomes stale or unwritable, repair it with
  `make repo-reset`.
- When changing shared contracts, update the shared docs in [`docs/`](./docs)
  in the same pass.
- When changing cross-repo demos or E2E behavior, update
  [`test/README.md`](./test/README.md) in the same pass.

## Validation Expectations

Choose the smallest validation that proves the change:
- root doc changes: link/reference sweep and manual doc review
- test harness changes: relevant `make test-...` or `npm --prefix test run ...`
- demo stack changes: `make demo-...` and the affected smoke flow
- release workflow changes: follow [`dev/docs/RELEASE.md`](./dev/docs/RELEASE.md)
  and the affected repo-local release docs

For coordinated checkpoints, validate both the changed submodule(s) and the
parent workspace before updating submodule pointers.
