<!--
Cross-cutting synthesis template. Copy to
findings/workspace-audit-synthesis-<date>.md and fill in after the per-target
reports exist. This is the run's entry point — read first. Delete this comment
when filling.
-->

# Workspace audit synthesis

Date: YYYY-MM-DD

Scope: <which targets this pass covered; which were excluded and why>

<Executive summary: 1–2 paragraphs. The story across the whole tree — not a list
of every finding, but the shape of the debt and where it concentrates.>

## Highest-signal items

The few cross-cutting issues worth acting on first, in priority order. Each
references the per-target findings it aggregates.

1. **<C1 — title>** — <one paragraph; cite `target` reports and rule IDs>
2. **<C2 — title>** — <...>
<!-- ~8–10 items. -->

## Theme map

Recurring patterns that span targets, each tying together its findings.

| Theme | Domains | Where it shows up |
|---|---|---|
| <T1 — e.g. secret lifecycle> | `SEC-` | <targets + finding refs> |
| <T2 — e.g. monolith per host> | `ARC-` | <...> |

## Severity rollup

| Target | H | M | L | Total |
|---|---|---|---|---|
| `frostr-infra` | | | | |
| `bifrost-rs` | | | | |
| `igloo-shared` | | | | |
| `igloo-ui` | | | | |
| `igloo-pwa` | | | | |
| `igloo-chrome` | | | | |
| `igloo-home` | | | | |
| `igloo-shell` | | | | |
| **Totals** | | | | |

## Prioritized buckets

Findings grouped by *where the change lives*, so remediation can be sequenced.

- **Bucket A — <name>** (<target(s)>): <items>
- **Bucket B — <name>** (<target(s)>): <items>

## Suggested sequence

<Single-threaded order from highest marginal signal, with rough effort. The
buckets to do first and why; what unblocks what.>

## Graduating to backlog

<Which confirmed items should move to `../BACKLOG.md`, in what form. Fixes are
not written here.>
