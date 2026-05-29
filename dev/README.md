# `dev/` Workspace Notes

`dev/` holds workspace-level engineering material for `frostr-infra`.

Use it for release coordination, architecture decisions, contributor guidance,
and historical engineering records that do not belong in the shared system spec
under [`../docs/`](../docs) or the cross-repo test manual under
[`../test/README.md`](../test/README.md).

## Reading Paths

Task-oriented entry sequences. Read top to bottom for the goal you have.

- **First-time onboarding**
  1. [`../README.md`](../README.md) — workspace entrypoint and quick start
  2. [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — ownership and contribution rules
  3. [`../docs/INDEX.md`](../docs/INDEX.md) — shared FROSTR system manual
- **Coding work**
  1. the owning submodule's own docs under [`../repos/`](../repos)
  2. [`docs/STYLES.md`](./docs/STYLES.md) — workspace shell, docs, and commit style
  3. [`policies/`](./policies) — engineering guidance and review prompts
  4. [`docs/GOTCHAS.md`](./docs/GOTCHAS.md) — environment footguns before you build
- **Cross-repo testing**
  1. [`../test/README.md`](../test/README.md) — demo and E2E commands
  2. [`../test/docs/WORKFLOWS.md`](../test/docs/WORKFLOWS.md) — lane selection
- **Releasing**
  1. [`docs/RELEASE.md`](./docs/RELEASE.md) — coordinated release and pointer process
- **Paper / UI design handoff**
  1. [`docs/DESIGN.md`](./docs/DESIGN.md) — the import boundary and handoff rules
  2. [`../.agents/skills/frostr-paper-ui-workflows/SKILL.md`](../.agents/skills/frostr-paper-ui-workflows/SKILL.md) — quick routing card
- **Workspace process**
  1. [`docs/WORKFLOWS.md`](./docs/WORKFLOWS.md) — durable workflow and drift rules

## Directory Map

- [`docs/`](./docs)
  - canonical workspace process docs
  - currently includes the workspace workflow guide in
    [`docs/WORKFLOWS.md`](./docs/WORKFLOWS.md), the parent design handoff manual
    in [`docs/DESIGN.md`](./docs/DESIGN.md), the coordinated parent release
    manual in [`docs/RELEASE.md`](./docs/RELEASE.md), the workspace gotchas
    reference in [`docs/GOTCHAS.md`](./docs/GOTCHAS.md), and the workspace style
    guide in [`docs/STYLES.md`](./docs/STYLES.md)
- [`adrs/`](./adrs)
  - architecture decision records
  - use [`adrs/INDEX.md`](./adrs/INDEX.md) as the entrypoint
  - ADRs are historical decision logs; current behavior still belongs in
    [`../docs/`](../docs) or [`../test/README.md`](../test/README.md)
- [`policies/`](./policies)
  - contributor-facing engineering guidance and review prompts
  - these guide how work should be done in the workspace
- `plans/`
  - active working plans and in-progress engineering notes
  - not a canonical product or process manual
- `reports/`
  - point-in-time audits, investigations, and review outputs
  - historical by default unless another canonical doc links to them
- `done/`
  - completed plans and archived implementation notes
  - retained for history, not as the current source of truth

## Canonical Sources

Use the workspace docs this way:

- [`../README.md`](../README.md)
  - workspace entrypoint and supported top-level commands
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
  - ownership, contribution rules, and validation expectations
- [`../docs/INDEX.md`](../docs/INDEX.md)
  - shared FROSTR architecture, protocol, artifact, and wire specs
- [`docs/RELEASE.md`](./docs/RELEASE.md)
  - coordinated parent release process
- [`docs/DESIGN.md`](./docs/DESIGN.md)
  - design handoff rules between reference design exports and implementation
    packages
- [`docs/WORKFLOWS.md`](./docs/WORKFLOWS.md)
  - workspace workflows, documentation drift control, and follow-up harvests
- [`docs/GOTCHAS.md`](./docs/GOTCHAS.md)
  - workspace gotchas and environment footguns
- [`docs/STYLES.md`](./docs/STYLES.md)
  - workspace shell, documentation, and commit style
- [`../test/README.md`](../test/README.md)
  - cross-repo demo harness and E2E guidance
- [`../test/docs/WORKFLOWS.md`](../test/docs/WORKFLOWS.md)
  - test workflow selection, client-scoped validation, visual loops, and WASM
    test guidance

## Retention And Ownership

- Shared system semantics belong in [`../docs/`](../docs), not in `dev/`.
- Cross-repo validation and manual demo guidance belong in
  [`../test/README.md`](../test/README.md) and
  [`../test/docs/WORKFLOWS.md`](../test/docs/WORKFLOWS.md), not in `dev/`.
- Repo-specific implementation and release detail belong in the owning repo
  under [`../repos/`](../repos).
- `plans/`, `reports/`, and `done/` are workspace records, not canonical
  manuals. They may go stale as the codebase evolves.
- If a `plans/`, `reports/`, or `done/` note captures a lasting rule, move that
  rule into [`../docs/`](../docs), [`./docs/`](./docs), [`./policies/`](./policies),
  [`../test/README.md`](../test/README.md), or
  [`../test/docs/WORKFLOWS.md`](../test/docs/WORKFLOWS.md).
- Remove or archive stale working notes when they no longer help contributors
  understand the current workspace.
