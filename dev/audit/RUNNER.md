# Running an audit pass

How to execute an audit against [`rules/`](./rules/README.md), where output goes,
and how a finished run is closed out. The pass produces **findings only** —
fixes are never written under `dev/audit/`.

## Shape of a pass

- **Unit of work:** one **finder** agent per audit target, evaluating all eight
  domains against `rules/` and writing `findings/<target>-audit-<date>.md` from
  [`templates/repo-report.md`](./templates/repo-report.md).
- **Targets (8):** `frostr-infra`, `bifrost-rs`, `igloo-shared`, `igloo-ui`,
  `igloo-pwa`, `igloo-chrome`, `igloo-home`, `igloo-shell`. (`igloo-paper` is
  reference-only — skip it.)
- **Sharding:** the big targets (`bifrost-rs`, `igloo-pwa`, `igloo-ui`,
  `igloo-home`) may split into two finders by domain group —
  *structure* (`LEG ARC CQ RS AES`) and *substance* (`DOC TST SEC`) — that merge
  into one report.
- **Shared memory:** every finder appends cross-target observations to
  [`NOTES.md`](./NOTES.md) and ticks its row in [`TASKS.md`](./TASKS.md).
- **Synthesis:** a final agent reads all `findings/` + `NOTES.md` and writes
  `findings/workspace-audit-synthesis-<date>.md` from
  [`templates/synthesis.md`](./templates/synthesis.md).

## Each finder's brief

Give every finder the same instructions, varying only the target:

1. Read [`rules/README.md`](./rules/README.md) and all eight domain files.
2. Audit `<target>` against every domain. Cite `repo/path:line` and the rule ID
   (e.g. `ARC-01`) for each finding. Findings are **directions, not fixes** —
   fill the `Streamline:` field, don't write patches.
3. Ground claims where cheap: run the relevant lane (below) rather than guessing.
4. Write `findings/<target>-audit-<date>.md` from the report template.
5. Append anything cross-cutting to `NOTES.md`; update your row in `TASKS.md`.

## Grounding lanes

Finders should verify rather than assume. Useful `make` / repo lanes:

- `make test-affected` — minimal branch-dependent test surface.
- `cargo clippy` / `cargo fmt --check` (in `bifrost-rs`, `igloo-shell`,
  `igloo-home/src-tauri`) — lint/format signal for Rust findings.
- `tsc --noEmit` (per TS repo) — type-truth for `CQ-03` type-escape findings.
- `npm --prefix test run test:guards` — workspace doc/contract guards.
- Note: `make test-fast` is **render-only** — green there does not prove behavior
  (see `TST-05`).

## Orchestration: `Workflow` sketch

A ready-to-adapt pipeline the maintainer can launch later (finders run, each
writes its report; synthesis runs after). This is a sketch — review before
running; it spawns ~8 agents plus synthesis.

```js
export const meta = {
  name: 'frostr-audit',
  description: 'Audit every target against dev/audit/rules across 8 domains',
  phases: [{ title: 'Find' }, { title: 'Synthesize' }],
}

const DATE = args?.date          // pass the YYYY-MM-DD stamp in via args
const TARGETS = [
  'frostr-infra', 'bifrost-rs', 'igloo-shared', 'igloo-ui',
  'igloo-pwa', 'igloo-chrome', 'igloo-home', 'igloo-shell',
]

const brief = (t) => `
Audit the FROSTR target "${t}" against dev/audit/rules/ (all 8 domains).
Read rules/README.md and every rules/0N-*.md first. For each finding cite
repo/path:line and the rule ID; fill Streamline with a direction, not a fix.
Ground claims with the lanes in dev/audit/RUNNER.md. Write the report to
dev/audit/findings/${t}-audit-${DATE}.md using templates/repo-report.md, tick
your row in dev/audit/TASKS.md, and append cross-target notes to
dev/audit/NOTES.md. Return a one-line H/M/L tally.`

phase('Find')
const tallies = await parallel(TARGETS.map((t) => () =>
  agent(brief(t), { label: `audit:${t}`, phase: 'Find' })))

phase('Synthesize')
await agent(`
Read every dev/audit/findings/*-audit-${DATE}.md and dev/audit/NOTES.md.
Write dev/audit/findings/workspace-audit-synthesis-${DATE}.md using
templates/synthesis.md: executive summary, highest-signal items, theme map,
severity rollup, prioritized buckets, suggested sequence. Per-target tallies:
${tallies.join(' | ')}`, { label: 'synthesis', phase: 'Synthesize' })
```

Pass the date in via `args` (scripts can't call `Date.now()`):
`Workflow({ script, args: { date: '2026-06-13' } })`.

## Manual fallback

Without a workflow, launch finders with the `Agent` tool (one per target, the
brief above), then run the synthesis agent once all reports land. Sequential is
fine; it's just slower.

## Close-out

When the synthesis is written and reviewed:

1. `git mv dev/audit/findings/* dev/audit/archive/<date>/` (create the folder).
2. Copy `TASKS.md` and `NOTES.md` into `archive/<date>/` as the run's frozen
   record.
3. Update [`archive/README.md`](./archive/README.md) with the run's row (date,
   scope, H/M/L totals, entry-point link).
4. Reset `TASKS.md` (matrix back to `—`, run fields blank) and `NOTES.md` (back
   to "no entries yet") for the next pass.
5. Graduate confirmed, actionable findings into [`../BACKLOG.md`](../BACKLOG.md).
