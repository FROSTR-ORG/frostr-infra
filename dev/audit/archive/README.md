# `dev/audit/archive/`

Completed audit runs, one dated folder per pass. These artifacts are **frozen**:
their `file:line` references reflect the codebase at run time and will have
drifted since. To start a new pass, see [`../RUNNER.md`](../RUNNER.md); the live
system entry point is [`../README.md`](../README.md).

## Runs

| Date | Scope | H / M / L | Entry point |
|---|---|---|---|
| 2026-06-13 | Parent workspace + 7 submodules (excl. `igloo-paper`) | 18 / 38 / 25 | [`2026-06-13/`](./2026-06-13/workspace-audit-synthesis-2026-06-13.md) |
| 2026-04-22 | Parent workspace + 6 submodules (excl. `igloo-chrome`, `igloo-paper`) | 29 / 42 / 22 | [`2026-04-22/`](./2026-04-22/workspace-audit-synthesis-2026-04-22.md) |

Older point-in-time reviews predating this system live under
[`../../reports/`](../../reports/) (e.g. `igloo-chrome-audit-2026-04-02.md`).
