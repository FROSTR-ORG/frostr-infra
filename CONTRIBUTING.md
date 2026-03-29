# Contributing to frostr-infra

This repository is the coordinating workspace for FROSTR. Contributing here is
different from contributing inside a single submodule: parent-repo changes
should improve shared docs, workspace workflows, release coordination, demo
harnesses, or cross-repo verification.

## What This Repo Owns

The parent repo owns:
- shared system docs under [`docs/`](./docs)
- cross-repo browser and demo-harness tests under [`test/`](./test)
- demo compose definitions, demo services, and root orchestration under
  [`compose.test.yml`](./compose.test.yml) and [`run.sh`](./run.sh)
- submodule pointers and coordinated release checkpoints

The parent repo does not own implementation details that belong inside a
specific project repo.

## Workspace Shape

- `docs/`
  - canonical shared-system manual for FROSTR
- `repos/`
  - independent project repos
- `test/`
  - cross-repo browser, desktop, and demo-harness verification
- `services/`
  - infra-owned container images and entrypoints
- `scripts/`
  - root helper scripts used by `run.sh` and release workflows
- `compose*.yml`
  - demo stack definitions
- `run.sh`
  - curated top-level command router

## Documentation Ownership

### Root docs

Root docs in this repo should explain:
- how the workspace is organized
- how contributors should work across repos
- how to run root-level commands and validation
- how coordinated releases are prepared and cut

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

- Use [`./run.sh`](./run.sh) for supported root workflows.
- Treat root `scripts/` as implementation detail unless you are maintaining the
  root orchestration itself.
- Keep the workspace and submodules clean; do not leave generated artifacts in
  tracked locations.
- Parent live scratch output belongs under `./.tmp/`, not tracked-looking paths
  such as `./data/`.
- When changing shared contracts, update the shared docs in [`docs/`](./docs)
  in the same pass.
- When changing cross-repo demos or E2E behavior, update
  [`test/README.md`](./test/README.md) in the same pass.

## Validation Expectations

Choose the smallest validation that proves the change:
- root doc changes: link/reference sweep and manual doc review
- test harness changes: relevant `./run.sh test ...` or `npm --prefix test run ...`
- demo stack changes: `./run.sh demo ...` and the affected smoke flow
- release workflow changes: follow [`RELEASE.md`](./RELEASE.md) and the affected
  repo-local release docs

For coordinated checkpoints, validate both the changed submodule(s) and the
parent workspace before updating submodule pointers.
