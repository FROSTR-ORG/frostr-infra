# FROSTR Agent Documentation Workflow Plan

Date: 2026-05-23

## Summary

Create a documentation-first agent support system that keeps always-loaded
context small. Use `AGENTS.md` as a concise router, move durable workflow detail
into canonical docs, and defer repo-local skills until repeated failures prove
that documentation is not enough.

## Design Principles

- Prefer documentation over skills for broad workspace knowledge.
- Keep `AGENTS.md` short and routing-oriented; it should tell agents where to
  look, not duplicate manuals.
- Avoid repo-local skills in the first implementation because skill metadata
  consumes agent context.
- Store detailed command matrices, repo boundaries, and reference policies in
  docs that agents discover through `AGENTS.md`.
- Do not store volatile plans or investigation reports in skills.
- Add skills later only for narrow, repeated failure modes that docs and routing
  do not prevent.

## Key Changes

### Agent Routing

- Update `AGENTS.md` with an "Agent Routing Map" that points agents to:
  - `README.md` for root commands and workspace entry.
  - `dev/README.md` for where engineering notes belong.
  - `dev/docs/WORKFLOWS.md` for workspace workflows, documentation drift
    control, and follow-up harvests.
  - `test/README.md` for test commands and demo harness reference.
  - `test/docs/WORKFLOWS.md` for test workflow selection, scoped validation,
    visual loops, and WASM test guidance.
  - `dev/docs/DESIGN.md` for Paper design handoff rules.
  - `dev/docs/RELEASE.md` for coordinated release and submodule pointer work.
  - `docs/INDEX.md` for FROSTR architecture, protocol, artifact, and wire specs.

### Workflow Documentation

- Add `dev/docs/WORKFLOWS.md` as the canonical workspace workflow guide:
  - workspace ownership and submodule boundaries
  - scratch/output policy under `./.tmp/`
  - when to use plans vs reports vs canonical docs
  - documentation drift control
  - follow-up harvest workflow
  - validation escalation principles
- Add `test/docs/WORKFLOWS.md` as the canonical test workflow guide:
  - how to choose PWA, Chrome, Home, visual, cross-client, demo, or release
    lanes
  - minimal submodule expectations per client
  - scratch browser-WASM vs tracked browser-WASM behavior
  - visual screenshot iteration loop and manifest expectations
  - macOS sandbox / `wasm-opt` rerun guidance
- Keep lasting rules out of `dev/plans` and `dev/reports`; move them into
  `dev/docs/WORKFLOWS.md`, `test/docs/WORKFLOWS.md`, `test/README.md`,
  `dev/docs/DESIGN.md`, or `dev/docs/RELEASE.md`.
- Keep `test/README.md` as the command reference and link it to
  `test/docs/WORKFLOWS.md`.
- Link `dev/docs/WORKFLOWS.md` from `dev/README.md` and `AGENTS.md`.

### Documentation Drift

- Add documentation drift rules to `dev/docs/WORKFLOWS.md`:
  - public command changes update `README.md`, relevant workflow docs, and
    command-surface guards in the same pass
  - test lane or CI changes update `test/README.md`, `test/docs/WORKFLOWS.md`,
    and workflow guards
  - design handoff changes update `dev/docs/DESIGN.md`
  - release sequencing changes update `dev/docs/RELEASE.md`
  - lasting rules discovered in plans or reports are promoted into canonical
    docs before the work stream closes
- Add follow-up harvest guidance to `dev/docs/WORKFLOWS.md` instead of creating
  a skill.

### Deferred Skills

- Do not create `.agents/skills` in this pass.
- Do not create `agents/openai.yaml` or other vendor-specific skill metadata.
- Revisit skills only after observing a repeated failure mode that docs and
  `AGENTS.md` routing do not solve.

## Test Plan

Validate documentation and guard coverage with:

```sh
npm --prefix test run test:guards:docs
npm --prefix test run test:guards:workflows
git diff --check
```

Also manually inspect:

```sh
find .agents -maxdepth 3 -type f | sort
sed -n '1,180p' AGENTS.md
sed -n '1,220p' dev/docs/WORKFLOWS.md
sed -n '1,220p' test/docs/WORKFLOWS.md
sed -n '1,140p' test/README.md
```

Acceptance criteria:

- No `.agents/skills` directory is created.
- `AGENTS.md` stays concise and points to canonical docs instead of duplicating
  workflow detail.
- `dev/docs/WORKFLOWS.md` contains workspace workflow, documentation drift, and
  follow-up harvest guidance.
- `test/docs/WORKFLOWS.md` contains test-specific workflow guidance.
- `test/README.md` remains the command/reference entrypoint.
- Documentation guards pass and include the new workflow docs.

## Assumptions

- Documentation-first is the preferred default because skill metadata consumes
  agent context.
- Follow-up harvest remains a documented workflow, not a skill.
- Skills may be added later only for repeated failure modes that docs and
  `AGENTS.md` routing do not solve.
