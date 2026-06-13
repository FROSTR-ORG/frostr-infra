# `dev/audit/`

The FROSTR workspace's technical-debt and code-quality audit system. It defines
a stable set of criteria — organized into eight **domains** — and the machinery
to run a pass against every target, track progress, share notes between the
agents doing the work, and archive each completed run.

This is the living system. Past, frozen runs live in [`archive/`](./archive/).

## Layout

```
dev/audit/
  README.md      ← you are here: the system entry point
  rules/         the criteria, one file per domain (the shared bar for "good")
  TASKS.md       current run's target × domain status matrix + checklist
  NOTES.md       current run's shared, append-only agent scratchpad
  RUNNER.md      how to execute a pass (briefs, lanes, Workflow sketch, close-out)
  templates/     report + synthesis templates a run fills in
  findings/      working area for the current run's reports (drains to archive/)
  archive/       completed runs, one dated folder each (frozen)
```

## Domains

Every pass judges each target against these eight domains. Full criteria in
[`rules/`](./rules/README.md).

| # | Domain | Judges |
|---|---|---|
| 01 | [Legacy & deprecation](./rules/01-legacy-deprecation.md) | shims, dead code, version forks, retired APIs |
| 02 | [Architecture & boundaries](./rules/02-architecture-boundaries.md) | god files, mixed concerns, layering, leaky packages |
| 03 | [Code quality & practices](./rules/03-code-quality-practices.md) | error taxonomy, panics, type escapes, duplication |
| 04 | [Readability & searchability](./rules/04-readability-searchability.md) | naming, function size, grep-ability, entry points |
| 05 | [Aesthetics & formatting](./rules/05-aesthetics-formatting.md) | whitespace, density, alignment, formatter enforcement |
| 06 | [Documentation](./rules/06-documentation.md) | doc comments, README accuracy, doc-vs-code drift |
| 07 | [Testing](./rules/07-testing.md) | core-journey coverage, adversarial paths, KATs |
| 08 | [Security](./rules/08-security.md) | secret lifecycle, crypto, validation, IPC auth |

## Targets

A pass covers the parent workspace and every active submodule:
`frostr-infra`, `bifrost-rs`, `igloo-shared`, `igloo-ui`, `igloo-pwa`,
`igloo-chrome`, `igloo-home`, `igloo-shell`. `igloo-paper` is reference-only and
out of scope.

## How to use it

- **Run a pass:** follow [`RUNNER.md`](./RUNNER.md) — one finder per target across
  all domains, then a synthesis. It includes a ready-to-adapt `Workflow` sketch.
- **Track progress:** [`TASKS.md`](./TASKS.md) holds the `target × domain` matrix
  and per-target checklist for the run in flight.
- **Share notes:** agents append cross-cutting observations to
  [`NOTES.md`](./NOTES.md) so findings in one target inform another.
- **Read past runs:** [`archive/`](./archive/) — each dated folder is frozen;
  its `file:line` references reflect the code at run time.

## What this produces

Findings, not fixes — each one cites a rule ID and a `file:line`, and points a
direction via `Streamline:`. Confirmed, actionable items graduate to
[`../BACKLOG.md`](../BACKLOG.md); decisions and remediation plans live in
[`../plans/`](../plans/). Nothing under `dev/audit/` writes code or takes a
decision.

Related: [`../policies/`](../policies/) is per-change review guidance (the rules
here reuse, not restate, its drift signals); the canonical system behavior the
audit checks against lives in [`../../docs/`](../../docs/).
