# Releasing frostr-infra

This document describes how to prepare and publish a coordinated release across
the submodules under [`repos/`](./repos) and the parent `frostr-infra`
workspace.

Use this document as the workspace-level coordinator. When a submodule has its
own release manual, follow that repo-local manual for package- or artifact-
specific steps.

## Release Order

Release in this order:

1. prepare and validate changed submodules
2. update submodule versions and changelogs
3. cut submodule commits and tags
4. update parent submodule pointers and parent changelog
5. cut the parent workspace release commit and tag

Do not tag the parent repo before the submodule release commits and tags exist.

## Decide What Is Releasing

For each release cycle:
- identify which repos under [`repos/`](./repos) changed
- decide which repos need a version bump
- update the repo-local changelog and release notes surface for each changed
  repo

Current repos with dedicated release docs:
- [`repos/bifrost-rs/RELEASE.md`](./repos/bifrost-rs/RELEASE.md)
- [`repos/igloo-chrome/RELEASE.md`](./repos/igloo-chrome/RELEASE.md)

For the remaining repos, use their root `README.md`, `TESTING.md`, and
`CONTRIBUTING.md` plus the validation matrix below.

## Prepare the Changed Submodules

Inside each changed submodule:
- update versions
- update `CHANGELOG.md` if the repo carries one
- update repo-local docs if release-facing behavior changed
- run the repo’s required checks
- commit the release-prep state

Typical release-facing repos and checks:
- `repos/bifrost-rs`
  - follow repo-local `RELEASE.md`
- `repos/igloo-chrome`
  - follow repo-local `RELEASE.md`
- `repos/igloo-shell`
  - run its root testing/manual flows
- `repos/igloo-home`, `repos/igloo-pwa`, `repos/igloo-shared`, `repos/igloo-ui`
  - run the checks documented in their root docs

## Workspace Validation Matrix

Run the release matrix against the candidate state.

Canonical root entrypoint:

```bash
./run.sh test prep
./run.sh test release
```

That command is the supported parent release gate. It prebuilds shared
artifacts, runs the core/runtime and shell checks, then runs the host E2E
slices. It also prints a compact phase timing summary at the end.

Core runtime:

```bash
cargo test --manifest-path repos/bifrost-rs/Cargo.toml --workspace --offline
```

Shell/operator host:

```bash
cargo test --manifest-path repos/igloo-shell/Cargo.toml -p igloo-shell-cli --offline
(cd repos/igloo-shell && bash scripts/devnet.sh smoke)
(cd repos/igloo-shell && bash scripts/test-node-e2e.sh)
```

Shared/browser layer:

```bash
npm --prefix repos/igloo-shared run test:typecheck
```

Cross-repo E2E:

```bash
npm --prefix test run test:e2e:igloo-home
npm --prefix test run test:e2e:igloo-pwa
npm --prefix test run test:e2e:igloo-chrome
```

Optional narrower root wrappers:

```bash
./run.sh test smoke
./run.sh test fast
./run.sh test live
./run.sh test demo
./run.sh test e2e
```

If a release changes only a narrow surface, you may run a narrower matrix first,
but the full matrix should be green before cutting the coordinated parent
release.

`./run.sh test prep` is optional but useful when you want the shared build and
Docker work separated from the full release gate. It uses the parent `./.tmp/`
scratch tree by default; repair that tree with `./run.sh repo reset` if it
becomes stale.

## Cut Submodule Releases

For each changed repo:
- ensure `git status --short` is clean
- create the release commit
- create the annotated tag
- push the branch and tag

After the pushes succeed, update the parent repo to the new submodule pointers.

## Cut the Parent Workspace Release

In the parent repo:
- update [`CHANGELOG.md`](./CHANGELOG.md) with the coordinated checkpoint
- verify submodule pointers reference the intended release commits
- verify the parent repo is clean aside from the intended release changes
- create the parent release commit
- create the annotated parent release tag
- push the parent branch and tag

The parent repo is the coordinating release record for the workspace, not the
replacement for individual submodule tags.

## Final Checks

Before closing the release:
- confirm the parent repo and released submodules are clean
- confirm pushed tags exist remotely
- confirm any renamed remotes or repo transfers are reflected in local git
  config
- keep a short release summary in the parent changelog so the workspace
  checkpoint is understandable without reading every submodule changelog
