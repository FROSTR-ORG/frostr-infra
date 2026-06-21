# Audit tasks — current run

Tracks the current audit pass: which `target × domain` cells are done, and the
per-target checklist. One run lives here at a time; see **Lifecycle** below for
how a finished run is archived and reset. For how cells get filled, see
[`RUNNER.md`](./RUNNER.md); for what each domain judges, see
[`rules/`](./rules/README.md).

**Run:** `anti-slop-frontend` (front-end targets only) · **Started:** 2026-06-19 · **Date stamp:** 2026-06-19 · **Result:** 53 findings (12H / 25M / 16L) — synthesis written, awaiting maintainer review before close-out

> **Scope note:** this is a *hybrid front-end deep pass* — reconcile the
> 2026-06-13 findings, then run fresh deep finders on the 5 front-end targets
> only (`igloo-ui`, `igloo-shared`, `igloo-pwa`, `igloo-chrome`, `igloo-home`).
> `frostr-infra`, `bifrost-rs`, and `igloo-shell` are **out of scope this pass**
> (front-end first, per the maintainer's request).
>
> Last completed full run: **2026-06-13** (81 findings — 18H/38M/25L), frozen in
> [`archive/2026-06-13/`](./archive/2026-06-13/workspace-audit-synthesis-2026-06-13.md).
> Verified follow-ups graduated to [`../BACKLOG.md`](../BACKLOG.md) under
> "Code-health audit (2026-06-13)".

## Status matrix

Rows = audit targets, columns = domains. Cell legend: `—` not started · `WIP` in
progress · `n` finding count when done (e.g. `3` = done, 3 findings; `0` = done,
clean).

| Target | LEG | ARC | CQ | RS | AES | DOC | TST | SEC |
|---|---|---|---|---|---|---|---|---|
| `frostr-infra` (parent) | oos | oos | oos | oos | oos | oos | oos | oos |
| `bifrost-rs` | oos | oos | oos | oos | oos | oos | oos | oos |
| `igloo-shared` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `igloo-ui` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `igloo-pwa` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `igloo-chrome` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `igloo-home` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `igloo-shell` | oos | oos | oos | oos | oos | oos | oos | oos |

`✓` = domain covered (per-domain finding counts live in each target's report).
`oos` = out of scope this pass (front-end first). `igloo-paper` is
reference-only and always out of scope.

## Per-target checklist

Mark a target done once all eight domains are covered and its report is written
to `findings/<target>-audit-<date>.md`.

- [x] **Reconcile** — `findings/reconcile-2026-06-13-to-2026-06-19.md` written
- [x] `igloo-shared` — report written · 10 findings (2H/6M/2L)
- [x] `igloo-ui` — report written · 11 findings (3H/5M/3L)
- [x] `igloo-pwa` — report written · 12 findings (2H/6M/4L)
- [x] `igloo-chrome` — report written · 10 findings (2H/4M/4L)
- [x] `igloo-home` — report written · 10 findings (3H/4M/3L)
- ~~`frostr-infra` / `bifrost-rs` / `igloo-shell`~~ — out of scope this pass
- [x] **Synthesis** — `findings/workspace-audit-synthesis-2026-06-19.md` written
- [ ] **Close-out** — held for maintainer review (archive + graduate confirmed)

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
