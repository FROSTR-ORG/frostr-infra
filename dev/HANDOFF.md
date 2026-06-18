# Hand-off: test-infrastructure remediation (ADR-013) — P0 done, P1/P2 substantially done

_Last updated: 2026-06-18_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The **test-infrastructure remediation** program (audit →
> [ADR-013](adrs/ADR-013-test-infrastructure-architecture.md) → fix) is now
> **P0 complete (7/7)** and **P1/P2 substantially complete**. Remaining items are
> small and tracked in [`dev/BACKLOG.md`](BACKLOG.md) → "Test infrastructure
> remediation". All work is committed on `dev` (local — submodule commits on their
> `dev` branches are **unpushed**; nothing pushed this session).

## TL;DR

This session executed the approved 6-phase P1/P2 plan
(`/Users/cscott/.claude/plans/sounds-like-a-plan-mighty-pine.md`), each phase its
own commit, each gated green by `make verify`. The seed/persist contract, process
lifecycle/ports, build-stamp/affected single-source, igloo-shell CI, visual harness,
and test docs all landed. A few low-risk tails remain (below).

## What's been done this session (commits on `dev`, local)

- `4d1508e` + `2b38a21` (+ submodule commits `igloo-shared d30eec4`, `igloo-pwa 420cecf`)
  — **Phase 1**: `PersistableStoredProfile` contract in igloo-shared; igloo-pwa
  derives its persist allow-list from it (compile-time drift guard); PWA seeds typed
  against it (non-persisted fields are now compile errors); `test/shared/test-secrets.ts`
  centralizes the 3 passwords (fixture-level wired); legacy PWA keys retired.
- `ba937dd` — **Phase 2**: `port-allocation.ts` (`allocatePort` via `listen(0)`)
  replaces 3 colliding strategies; `process-lifecycle.ts` (`closeChild` idempotent +
  SIGKILL); `process-registry.ts` + `global-teardown.ts` orphan-reaper.
- `304c04f` — **Phase 3**: WASM stamp now covers the igloo-shared build driver +
  toolchain pin; `test-targets.json` is the single source for the path→client mapping
  (`test_client_for_path`).
- `e1d8144` — **Phase 5**: per-PR `shell` CI job runs `cargo test --lib` for
  igloo-shell; home `@live @smoke` decided **nightly** (lean-CI).
- `3c7ce97` — **Phase 4**: `test/shared/visual-harness.ts` (`captureVisual` +
  `captureAgentArtifact`); all 10 capture sites migrated (7 pwa `@visual` + 3 `@agent`).
- `87ea05c` — **Phase 6**: lane/coverage matrix + `TEST-ENV-VARS.md` + `services/README.md`
  + `FIXTURES.md`; lane-rename deferred (documented instead); dead-guard claim corrected.

## What's pending (small tails, all in BACKLOG)

1. **Phase 1 remainder** — swap the ~25 per-spec inline password literals to
   `test-secrets` imports + add a ban-inline-password guard (the guard depends on the
   swap; good `delegate-to-codex` job); unify the chrome/home seed builders under one
   `ProfileSeedInput` (PWA already type-enforced).
2. **Phase 4 remainder (4d)** — one visual manifest + guard covering chrome + home
   (today only pwa has `visual-manifest.json`).
3. **Phase 5c** — confirm the 6 other `@live` specs sharing the fixed
   `expectPwaSignerSignReady` go green on the next nightly `release-validation`.

## Critical considerations (the WHY)

- **Nothing is pushed.** Submodule commits (`igloo-shared d30eec4`, `igloo-pwa 420cecf`)
  are on their local `dev` branches; the parent `dev` is ahead by this session's
  commits. Push submodules **before** the parent so the pointer bump (`4d1508e`)
  resolves remotely. `dev` is ~100 commits ahead of `master` — a `dev→master` PR is a
  full RELEASE.md event, not a per-feature PR (see prior session's note).
- **CI-only verification:** the igloo-shell `shell` job, the home smoke, and all
  GitHub Actions only run on the PR / nightly — not locally on macOS. Treat a red
  step there as the normal loop.
- **Deliberate deviations from ADR-013 §(b), for lean-CI** (each recorded in BACKLOG):
  home smoke is nightly not per-PR; cargo lib-test is bifrost-rs (pwa/chrome) +
  igloo-shell (shell job); smoke wired into per-client CI jobs, not `make verify`;
  lane renames documented rather than performed.
- **Commit flow:** submodule-first → `make bump-pointers`, non-recursive
  ([[workflow-no-new-prs]]). `make verify` is the canonical gate (green at every phase).

## Suggested first action

If continuing: knock out the **Phase 1 remainder** (per-spec password swap + ban
guard) — mechanical, `delegate-to-codex`-friendly, completes the "centralize test
password" goal. Otherwise the program is at a clean checkpoint: P0 done, P1/P2
substantially done, `make verify` green, everything committed on `dev` (ask before
pushing — submodules first, then parent).
