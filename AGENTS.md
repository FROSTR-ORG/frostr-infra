# Repository Guidelines

## Project Structure & Module Organization

`frostr-infra` is the coordinating workspace for FROSTR. Root ownership is:

- `docs/`: shared FROSTR architecture, protocol, artifact, and wire specs
- `dev/`: release docs, ADRs, policies, reports, and historical workspace notes
- `test/`: cross-repo Playwright, desktop, and demo-harness verification
- `services/`: infra-owned compose services such as `dev-relay` and `igloo-demo`
- `repos/`: git submodules for implementation repos; treat each as an independent project

Use root docs for workspace behavior, then read the owning submodule’s docs for repo-local implementation details.

## Build, Test, and Development Commands

Use `make` as the public root interface. Root `scripts/` are implementation detail.

- `make repo-init`: sync and initialize top-level submodules
- `make repo-check`: verify workspace prerequisites
- `make demo-start` / `make demo-onboard`: start the demo stack and print onboarding artifacts
- `make test-prep`: prebuild shared Rust binaries, browser artifacts, and demo images
- `make test-affected`: run the minimal branch-dependent validation surface
- `make test-release`: run the full coordinated release matrix
- `npm --prefix test run test:guards`: run doc, command-surface, and harness guard checks

## Coding Style & Naming Conventions

Keep changes scoped to the owning layer: shared semantics in `docs/`, workspace process in `dev/`, cross-repo harness logic in `test/`, and product code in the correct submodule. Prefer Markdown with short sections and concrete commands. For shell scripts, follow existing Bash style (`set -euo pipefail`, lowercase helper names). Do not add ad hoc root entrypoints when `Makefile` should own the workflow.

## Testing Guidelines

Cross-repo browser tests use Playwright from `test/`. Name specs `*.spec.ts`; keep helper code under `test/.../fixtures` or `test/shared`. Run the smallest proof first, then escalate to `make test-affected` or `make test-release`. When docs change, run `npm --prefix test run test:guards`.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects, for example `Reorganize workspace docs and cross-repo test harness`. Keep commits focused by layer. Update docs in the same pass as behavior changes. PRs should summarize affected workspace surfaces, note any submodule pointer updates, and include validation commands run.

## Workspace Rules

Use non-recursive submodule commands. Keep generated output under `./.tmp/`, not tracked-looking paths like `data/`. If the workspace scratch tree becomes stale, repair it with `make repo-reset`.
