# Workspace Workflows

This document is the workspace-level workflow guide for agents and contributors
working in `frostr-infra`. Keep command matrices in the owning manuals; use
this page for durable process rules and routing.

## Ownership Boundaries

- Shared FROSTR semantics belong in [`../../docs/`](../../docs).
- Workspace process, release coordination, ADRs, policies, plans, and reports
  belong in [`../`](../).
- Cross-repo browser, desktop, and demo-harness validation belongs in
  [`../../test/`](../../test).
- Runtime or package implementation belongs in the owning submodule under
  [`../../repos/`](../../repos).
- Paper design references belong in `repos/igloo-paper`; do not import them into
  runtime code, package code, or app builds.

Treat each submodule as an independent project. Use non-recursive submodule
commands and read the owning submodule docs before changing repo-local
implementation behavior.

## Scratch And Generated Output

Keep generated output under `./.tmp/` unless an owning tool documents a
different ignored scratch path. Do not introduce tracked-looking scratch
locations such as `data/`.

Use `make repo-reset` when the root scratch tree becomes stale or unwritable.
Do not use reset commands to discard unrelated user changes.

## Plans, Reports, And Canonical Docs

- Use `dev/plans/` for active implementation plans and in-progress engineering
  notes.
- Use `dev/reports/` for point-in-time audits, investigations, and review
  outputs.
- Use `dev/done/` for completed plans and archived implementation notes.
- Move lasting rules out of plans, reports, or archived notes before closing a
  work stream.

Canonical homes for durable rules:
- workspace workflows and documentation drift: this file
- test workflow selection: [`../../test/docs/WORKFLOWS.md`](../../test/docs/WORKFLOWS.md)
- test commands and demo harness reference: [`../../test/README.md`](../../test/README.md)
- design handoff: [`DESIGN.md`](./DESIGN.md)
- release coordination: [`RELEASE.md`](RELEASE.md)
- shared protocol and artifact specs: [`../../docs/INDEX.md`](../../docs/INDEX.md)

## Documentation Drift

Update docs in the same pass as behavior changes:

- Public root command changes: update `README.md`, `AGENTS.md` when relevant,
  and command-surface guards.
- Test lane, CI, visual harness, or WASM validation changes: update
  `test/README.md`, `test/docs/WORKFLOWS.md`, and guard scripts.
- Paper design handoff changes: update `dev/docs/DESIGN.md`.
- Release sequencing, tagging, or submodule pointer process changes: update
  `dev/docs/RELEASE.md`.
- New durable agent workflow: update this file and route to it from `AGENTS.md`
  if agents need to discover it.

Before finishing documentation-affecting work, run the doc guards:

```bash
npm --prefix test run test:guards:docs
```

## Paper/UI Workflows

Use these routes for the Paper Desktop, `igloo-paper`, `igloo-ui`, and
`igloo-pwa` design handoff. The repo-local agent skill
`.agents/skills/frostr-paper-ui-workflows/SKILL.md` is the quick routing card;
this section is the durable workspace workflow.

### Paper Source To `igloo-paper`

Use this when the source of truth is the live Paper Desktop canvas and the goal
is to refresh checked-in design references.

1. Open Paper Desktop to the `igloo-ui-shared` file and the `core` page.
2. For chat-driven MCP edits, follow
   [`../../repos/igloo-paper/docs/mcp-edit-workflow.md`](../../repos/igloo-paper/docs/mcp-edit-workflow.md).
3. Export and verify from the parent workspace:

```bash
make igloo-paper-sync
make igloo-paper-verify STRICT=1
```

Do not hand-edit generated `igloo-paper` screenshots, HTML, manifests, or
contract output. Fix Paper source or export metadata, then sync again. Use
`make igloo-paper-usage-coverage-sync` when a Paper change introduces or
removes token usage that strict verification tracks.

### `igloo-paper` To `igloo-ui`

Use this when the Paper references are already exported and the implementation
needs to visually align with them.

1. Identify the target Paper screen or pattern under `repos/igloo-paper`.
2. Update `repos/igloo-ui` components and package-local tests.
3. Validate the PWA rendering path that consumes those components.
4. Capture the visual comparison set and write a Markdown review report:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

The report is written to `.tmp/visual/igloo-pwa/comparison-report.md` by
default. Override with `FROSTR_PWA_VISUAL_REPORT_PATH` only when archiving a
point-in-time review under `dev/reports/`.

### Paper Source Plus `igloo-ui`

Use this when the product decision changes both the Paper source and the
functional React implementation.

1. Make the live Paper MCP edit first and review the canvas screenshot.
2. Run `make igloo-paper-sync` and inspect the generated export.
3. When screens are renamed, split, deleted, or replaced, update
   `test/igloo-pwa/visual-manifest.json` in the same pass.
4. Apply the matching implementation change in `repos/igloo-ui`.
5. Validate the consuming client, usually `repos/igloo-pwa`.
6. Run the visual capture and report commands above.

Commit in dependency order: `igloo-paper`, then `igloo-ui` and consuming app
repos, then the parent workspace pointer and workflow docs.

## Follow-Up Harvest

Use this workflow when a substantial work stream ends and the user asks for
follow-up tasks, next steps, or a follow-up hard-cut plan.

Inspect current context before suggesting work:
- current diffs and dirty submodules
- validation gaps, skipped tests, or sandbox-only failures
- documentation drift risks
- test harness or CI friction discovered during implementation
- Paper design mismatches or visual-harness gaps
- deferred correctness, release, or commitability risks

Return a short ranked list:
- `Finish now`: issues that threaten correctness, validation, or commitability
- `Next hard-cut`: bounded, high-value follow-up work
- `Backlog`: useful work that is not urgent

Record `Backlog` (and any deferred `Next hard-cut`) items in
[`../BACKLOG.md`](../BACKLOG.md) — the canonical follow-up sink. When work is
finished, move a one-line summary to [`../HISTORY.md`](../HISTORY.md) and delete
the backlog entry.

If the user asks for a plan, save it under
`dev/plans/*follow-up-hard-cut-plan-YYYY-MM-DD.md`.

## Validation Escalation

Run the smallest meaningful proof first, then widen only as risk or ownership
requires. Prefer focused repo-local tests for product changes, scoped test
lanes for client-specific changes, and release checks for coordinated
workspace changes.

Use [`../../test/docs/WORKFLOWS.md`](../../test/docs/WORKFLOWS.md) for
test-lane selection and [`RELEASE.md`](RELEASE.md) for release validation.
