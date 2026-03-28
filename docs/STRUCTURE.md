# Repository Structure

This document defines ownership boundaries for the `frostr-infra` workspace and its release documentation.

## Workspace Shape

- `docs/`
  - shared FROSTR system manual
- `repos/`
  - independent submodule projects
- `test/`
  - cross-repo browser and demo-harness verification
- `services/`
  - infra-owned container images and entrypoints
- `scripts/`
  - parent-repo helper scripts
- `compose*.yml`
  - infra and test stack definitions
- `run.sh`
  - curated top-level command router

## Documentation Ownership

### Parent `docs/` owns shared-system truth

The top-level docs are the canonical source for:
- FROSTR architecture
- cross-host interface contracts
- peer protocol semantics
- cryptographic model
- profile, backup, onboarding, rotation, and wire formats
- shared terminology and identity rules

These docs describe FROSTR as a system, not any one implementation.

### Repo-local docs own project-specific truth

Each submodule should document only:
- what that project owns
- how to build and test it
- project-specific contributor and release process
- implementation details specific to that repo

Repo-local docs should not redefine:
- the FROSTR protocol
- the shared cryptographic model
- the shared glossary
- the cross-host package model

## Submodule Ownership

### `repos/bifrost-rs`

Owns:
- cryptographic/session primitives
- strict wire and package validation
- signer state machine and readiness model
- runtime router and bridge layers
- reusable host/runtime glue
- keyset, onboarding, recovery, and backup utilities

This repo is the canonical implementation owner for the runtime and cryptographic stack, but not the canonical documentation owner for shared-system behavior.

### `repos/igloo-shared`

Owns:
- shared browser/runtime adapter contracts
- shared browser package/runtime helpers
- browser-facing bridge consumption patterns

### `repos/igloo-shell`

Owns:
- CLI/operator workflows
- explicit operator rotation tooling
- shell-local profile, vault, and runtime management
- shell-owned smoke and node E2E harnesses

`igloo-shell` is the strongest operator host and the primary enterprise/business surface.

### `repos/igloo-home`

Owns:
- desktop/browser-shell host behavior
- multi-profile desktop workflows
- local profile-management UX

### `repos/igloo-pwa`

Owns:
- browser-first onboarding, recovery, and profile-management UX
- PWA host behavior

### `repos/igloo-chrome`

Owns:
- extension host behavior
- provider/runtime control plane
- extension-specific settings and provider surfaces

### `repos/igloo-ui`

Owns:
- shared presentational UI package consumed by browser-facing hosts

## Testing Ownership

### Parent repo

The parent repo owns:
- cross-repo browser E2E under `test/`
- demo-harness orchestration
- release-level matrix entrypoints

### Submodules

Submodules own:
- local unit and integration tests
- project-specific smoke and workflow checks
- project-specific release/process evidence

## Release Rule

For a beta or production release:
- read top-level `docs/` for the FROSTR system contract
- read each submodule’s root docs for project-specific operation and maintenance
- do not rely on one submodule’s docs to explain another submodule or the shared protocol
