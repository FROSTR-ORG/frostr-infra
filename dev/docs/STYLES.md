# Workspace Styles

Style expectations for work that lives in the **parent workspace** — shell
scripts under `scripts/`, `dev/scripts/`, and `test/scripts/`, the Markdown docs,
and commits.

This doc is intentionally narrow. `frostr-infra` is polyglot (Rust `bifrost-rs`
plus several independent `igloo-*` TypeScript repos), so **per-language naming
and code style are owned by each submodule**, not by this workspace. When you
write product code, follow the owning submodule's own conventions. Use this page
only for the cross-cutting surface the workspace itself owns.

## Shell

Match the existing scripts (`scripts/demo.sh`, `scripts/check-setup.sh`, the
`test/scripts/check-*.sh` guards).

- Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Derive paths from the script location, not the current working directory:
  `ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`.
- Quote variable expansions unless word splitting is intentional.
- Provide defaults with `${VAR:-default}` for tunable inputs.
- Prefer small lowercase helper functions (`print_check`, `usage`,
  `resolve_free_port`) over long flat scripts; factor shared logic into sourced
  `lib-*.sh` helpers.
- Keep these scripts private implementation detail behind the `Makefile`; do not
  add ad hoc root entrypoints.

## Markdown & Docs

- Keep command examples executable exactly as written.
- Prefer short sections and compact bullet lists over long prose.
- Use relative links within a knowledge base (e.g. inside `dev/`).
- Do not duplicate a source of truth that already lives in another canonical doc
  — link to it instead. Canonical homes are listed in
  [`../README.md`](../README.md) and [`WORKFLOWS.md`](./WORKFLOWS.md).
- Update docs in the same pass as the behavior they describe, and run
  `npm --prefix test run test:guards:docs` before finishing doc-affecting work.

## Commits & PRs

- Use short, imperative, sentence-case subjects — match recent history
  (`Add igloo-pwa dev port guard`, `Bump submodule pointers for the threshold
  key-recovery flow`). The workspace does **not** use Conventional Commit
  prefixes.
- Keep commits focused by layer (`docs/`, `dev/`, `test/`, a single submodule).
- For submodule changes, commit inside the submodule first, then commit the
  bumped pointer here; note the submodule, commit hash, and why in the PR.
- PRs should summarize the affected workspace surfaces, call out any submodule
  pointer updates, and list the validation commands run.

## Scope

Keep repo-specific style — Rust formatting in `bifrost-rs`, React/TS conventions
in the `igloo-*` clients — in those submodules' own docs. Promote a rule here
only when it genuinely applies across the workspace.
