# Audit tasks — current run

Tracks the current audit pass: which `target × domain` cells are done, and the
per-target checklist. One run lives here at a time; see **Lifecycle** below for
how a finished run is archived and reset. For how cells get filled, see
[`RUNNER.md`](./RUNNER.md); for what each domain judges, see
[`rules/`](./rules/README.md).

**Run:** 2026-06-13 full pass · **Started:** 2026-06-13 · **Date stamp:** 2026-06-13

## Status matrix

Rows = audit targets, columns = domains. Cell legend: `—` not started · `WIP` in
progress · `n` finding count when done (e.g. `3` = done, 3 findings; `0` = done,
clean).

| Target | LEG | ARC | CQ | RS | AES | DOC | TST | SEC |
|---|---|---|---|---|---|---|---|---|
| `frostr-infra` (parent) | 1 | 1 | 2 | 0 | 1 | 0 | 0 | 5 |
| `bifrost-rs` | 1 | 2 | 0 | 1 | 0 | 3 | 1 | 3 |
| `igloo-shared` | 0 | 1 | 3 | 0 | 1 | 2 | 1 | 3 |
| `igloo-ui` | 3 | 2 | 3 | 0 | 1 | 1 | 0 | 1 |
| `igloo-pwa` | 2 | 3 | 2 | 0 | 1 | 1 | 1 | 2 |
| `igloo-chrome` | 1 | 1 | 2 | 1 | 1 | 0 | 1 | 1 |
| `igloo-home` | 0 | 1 | 2 | 0 | 1 | 1 | 1 | 4 |
| `igloo-shell` | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 |

`igloo-paper` is reference-only and out of scope.

## Per-target checklist

Mark a target done once all eight domains are covered and its report is written
to `findings/<target>-audit-<date>.md`.

- [x] `frostr-infra` — report written · row complete
- [x] `bifrost-rs` — report written · row complete
- [x] `igloo-shared` — report written · row complete
- [x] `igloo-ui` — report written · row complete
- [x] `igloo-pwa` — report written · row complete
- [x] `igloo-chrome` — report written · row complete
- [x] `igloo-home` — report written · row complete
- [x] `igloo-shell` — report written · row complete
- [x] **Synthesis** — `findings/workspace-audit-synthesis-<date>.md` written

## Lifecycle

1. **Start a run:** fill in the Run / Started / Date fields above and reset the
   matrix to `—`.
2. **During the run:** finder agents tick their cells and check off targets;
   shared observations go to [`NOTES.md`](./NOTES.md), not here.
3. **Close-out:** move `findings/*` into `archive/<date>/`, copy this `TASKS.md`
   and `NOTES.md` into that folder as the run's frozen record, update
   [`archive/README.md`](./archive/README.md) with the run's H/M/L totals, then
   reset this file and `NOTES.md` for the next pass.
4. **Graduate findings:** confirmed, actionable items move to
   [`../BACKLOG.md`](../BACKLOG.md). Fixes are never written under `dev/audit/`.
