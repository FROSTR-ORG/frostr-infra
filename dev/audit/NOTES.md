# Audit notes — shared scratchpad

Append-only shared memory for the agents running the current audit pass. Use it
for cross-cutting observations that don't belong to a single target's report:
patterns seen in more than one repo, "this looks like the same issue as X",
questions for the synthesis step, and dead-ends worth not repeating.

**Conventions**

- **Append only.** Don't edit or delete others' entries; add a new one.
- **One entry per observation**, newest at the bottom.
- **Header format:** `## YYYY-MM-DD HH:MM — <agent/target> — <topic>`
- Cite evidence as `repo/path:line` and the relevant rule ID (e.g. `ARC-03`).
- Cross-link with `[[anchor]]`-style references to other entries' topics when
  one observation builds on another.
- This file is reset at the start of each run; the prior run's copy is frozen in
  `archive/<date>/NOTES.md`. See [`TASKS.md`](./TASKS.md) Lifecycle.

---

<!-- Entries begin below. Template:

## 2026-06-13 14:30 — igloo-pwa finder — secret persistence
`igloo-pwa/src/lib/store.tsx:NNN` writes share secrets to localStorage in clear
(SEC-01). Same shape likely in igloo-chrome — flag for that finder to confirm.

-->

_No entries yet — this run hasn't started. The 2026-06-19 run's notes are frozen
in [`archive/2026-06-19/NOTES.md`](./archive/2026-06-19/NOTES.md)._
