# Hand-off: test-infrastructure remediation (ADR-013) — P0 COMPLETE (7/7), P1 next

_Last updated: 2026-06-18_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. A full **test-infrastructure audit → ADR → remediation** program is
> in flight. The audit ([`dev/docs/TEST-AUDIT.md`](docs/TEST-AUDIT.md), 97
> findings) and the target architecture
> ([`dev/adrs/ADR-013-test-infrastructure-architecture.md`](adrs/ADR-013-test-infrastructure-architecture.md),
> **Accepted**) are done. **P0 remediation is COMPLETE (7 of 7 sub-items).** The
> roadmap lives in [`dev/BACKLOG.md`](BACKLOG.md) → "Test infrastructure
> remediation"; the next work is the **P1** tier. All work is on `dev`, committed
> and pushed (this session's #3b work is staged in the working tree — commit/push
> when the maintainer approves).

## TL;DR

P0 is finished. The last item, **#3b**, shipped this session: a dedicated
`@live @smoke` spec per client (one onboarding + signing round-trip) over an
in-process relay, new `--grep @smoke` lanes, a per-PR `cargo test --lib`
(bifrost-rs), and `@cross-client` documented as manual/non-gated. pwa+chrome
smoke gate per-PR; the home smoke gates nightly. `make verify` is green. Next:
the **P1** items (per-PR home smoke buildout, type-enforced seeds, robust
teardown, unified visual harness, etc.).

## The user

`cmdruid` (git), the FROSTR maintainer — senior, terse, signal over ceremony,
decisive on scope, picks options when asked. Wants a fast, lean dev/test cycle.
Prefers the **submodule-first → `make bump-pointers`** commit flow
([[workflow-no-new-prs]]); commits/pushes **only when asked**. Engages on genuine
design forks — surface them with a recommendation. Values honest reporting of what
is verified vs. CI-verified-only vs. deferred.

## The project

`frostr-infra` is the coordinating workspace for FROSTR (Rust signing core +
TypeScript `igloo-*` clients, all git submodules under `repos/`). The Makefile is
the public command surface; `test/` is the cross-repo harness; CI is three
workflows under `.github/workflows/` (`client-scoped-validation` per-PR,
`release-validation` nightly/dispatch, `workspace-guards`).

## What's been done (this session — P0 #3b, in the working tree, not yet committed)

All parent-repo only (test/, CI, docs) — **no submodule pointer moves**.

- **Three dedicated `@live @smoke` specs** (in-process relay, no Docker):
  - `test/igloo-pwa/specs/onboarding-smoke.spec.ts` — two-device onboard, both
    nonce pools hydrate (sign-ready). **Verified locally** (13s).
  - `test/igloo-chrome/specs/signing-smoke.spec.ts` — onboarded live signer does a
    real provider `signEvent` round-trip, asserts the group pubkey. **Verified
    locally** (59s).
  - `test/igloo-home/specs/onboarding-smoke.spec.ts` — bfonboard handshake vs a
    live inviter session (home has no sign-initiate RPC + one active session, so
    the completed handshake is the achievable round-trip). **CI-verified only**
    (desktop host: tauri + webkit2gtk + xvfb — not runnable on macOS).
- **Lanes** in `test/package.json`: `test:e2e:igloo-{pwa,chrome,home}:smoke`
  (`--grep @smoke`).
- **CI** — `client-scoped-validation.yml`: pwa+chrome jobs gained the smoke step +
  `cargo test --lib --workspace --manifest-path repos/bifrost-rs/Cargo.toml`
  (**verified locally**, 37 tests). `release-validation.yml`: added the home smoke
  step (deps already present there; home e2e ran in **no** CI lane before).
- **Docs**: `test/README.md` + `test/docs/WORKFLOWS.md` — new `@live @smoke` tier
  and `@cross-client` documented as manual/non-gated by design (ADR Q1/Q2).
- **Drive-by fix**: `test/igloo-pwa/support/ui.ts` `expectPwaSignerSignReady`
  greped a literal `sign-ready` string the Paper-redesigned dashboard no longer
  renders → re-pointed at the modern "N ready" nonce-pool signal. This un-breaks
  the 6 other `@live` specs sharing the helper (they run nightly, not re-run here —
  tracked as a P2 re-verify item).

## What's pending (priority order)

1. **Commit + push** this session's #3b work (parent-only; submodule-first flow not
   needed). Then open the `dev`→`master` PR so CI validates the live/desktop smoke
   matrix (the home smoke + the CI YAML changes only execute on GitHub Actions).
2. **P1 tier** in `dev/BACKLOG.md`: promote the home smoke to a per-PR gate (needs
   the desktop toolchain in the per-PR home job — or accept nightly); add
   `cargo test --lib` for igloo-shell to a per-PR lane; type-enforce fixture seeds
   (`PersistableStoredProfile`, ADR Q7); consolidate seed builders + central test
   password; robust process teardown + orphan-reaper; unify relay port allocation;
   unified visual-harness module (ADR Q3).
3. **P2 tier**: re-verify the 6 `@live` specs after the helper fix; make
   `test-targets.json` the single affected/prebuild source; lane/env/services/fixture
   docs; honest lane renames + wire-or-delete dead guards (ADR Q9).
4. **Pre-existing follow-ups:** `chrome-pwa-pairing.spec.ts` modernized 3/4 (full
   `@cross-client` run never re-verified, it's in no lane); the home
   `dashboard-signer` visual scenario renders a loading (not running) dashboard.

## Critical considerations (the WHY)

- **ADR-013 is the source of truth** for the target design; BACKLOG "Test
  infrastructure remediation" is the ordered worklist. Don't re-litigate the
  decided forks.
- **#3b deviates from ADR §(b) intentionally, for lean-CI:** (a) the home smoke is
  **nightly** not per-PR — the per-PR home job has no tauri/xvfb buildout and adding
  it to every home/test/shared PR fights the 2026-06-17 lean-CI cut; (b) the cargo
  lib-test is **bifrost-rs only** — igloo-shell is in no per-PR job, so its lib-test
  stays nightly; (c) smoke is wired into the per-client CI jobs, **not** literally
  into `make verify` (kept render-only/fast). Each is recorded in BACKLOG.
- **CI changes verify on the PR, not locally.** The pwa+chrome smoke and the cargo
  lib-test ran locally; the home smoke and all GitHub Actions YAML only execute when
  the `dev`→`master` PR opens. Treat a red step there as the normal loop.
- **Smoke = subset of `@live`, not a replacement.** `--grep @smoke` matches only the
  three new specs; the full `@live` suite (richer onboarding wire-assertions, the
  verifiable shell threshold signature) stays nightly via `make test-live`.
- **`@cross-client` is non-gated by design** (ADR §(b)); only the demo 3-way pairing
  (also `@demo`) is covered, nightly.
- **Commit flow:** submodule-first → `make bump-pointers`, non-recursive only
  ([[workflow-no-new-prs]]). `make verify` is the canonical gate.

## Suggested first action

Commit the #3b working-tree changes (test/, CI, docs — one focused parent commit),
then open the `dev`→`master` PR so CI exercises the home smoke + the new CI steps.
Otherwise the program is at a clean checkpoint: audit + ADR done, **P0 complete
(7/7)**, `make verify` green — start the **P1** tier from `dev/BACKLOG.md`
(suggest the per-PR home-smoke buildout or the type-enforced seeds next).
