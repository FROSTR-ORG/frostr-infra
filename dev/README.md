# `dev/` Workspace Notes

`dev/` holds workspace-level engineering material for `frostr-infra`.

Use it for release coordination, architecture decisions, contributor guidance,
and historical engineering records that do not belong in the shared system spec
under [`../docs/`](../docs) or the cross-repo test manual under
[`../test/README.md`](../test/README.md).

## Directory Map

- [`docs/`](./docs)
  - canonical workspace process docs
  - currently includes the coordinated parent release manual in
    [`docs/RELEASE.md`](./docs/RELEASE.md)
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
- [`../test/README.md`](../test/README.md)
  - cross-repo demo harness and E2E guidance

## Retention And Ownership

- Shared system semantics belong in [`../docs/`](../docs), not in `dev/`.
- Cross-repo validation and manual demo guidance belong in
  [`../test/README.md`](../test/README.md), not in `dev/`.
- Repo-specific implementation and release detail belong in the owning repo
  under [`../repos/`](../repos).
- `plans/`, `reports/`, and `done/` are workspace records, not canonical
  manuals. They may go stale as the codebase evolves.
- If a `plans/`, `reports/`, or `done/` note captures a lasting rule, move that
  rule into [`../docs/`](../docs), [`./docs/`](./docs), [`./policies/`](./policies),
  or [`../test/README.md`](../test/README.md).
- Remove or archive stale working notes when they no longer help contributors
  understand the current workspace.
