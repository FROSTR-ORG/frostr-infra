# Hand-off: lean dev/test-loop program COMPLETE — top priority next is the red @fast gate

_Last updated: 2026-06-17_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The **lean dev/test/deploy-loop program is now complete** — all five
> threads of the approved plan (`~/.claude/plans/twinkling-tinkering-phoenix.md`)
> have shipped. The agent-facing command surface is documented in
> [`AGENTS.md`](../AGENTS.md) → "Verification recipes". The single most important
> thing to know going in: **`make verify` / `make test-fast` is RED on `dev` HEAD**
> from a pre-existing pwa test-fixture issue (not the program's doing) — see below.

## TL;DR

The lean-dev program is done. This session shipped **Thread 3**, the last thread,
with one deliberate change of plan: **the root npm workspace was dropped** in
favour of a thin per-leaf `make install`. Empirically, an npm workspace hoists
deps and breaks the self-contained leaf build scripts (igloo-ui/chrome/pwa/home),
which is exactly the cross-cutting friction the hybrid-not-monorepo decision
avoids — the user confirmed the pivot. The rest of Thread 3 landed as planned:
`make bump-pointers`, `.tmp/agent/*.json` machine-readable output for
dev/screenshot/verify, and the `AGENTS.md` "Verification recipes". All work is on
`dev` (parent only — **no submodule changes this session**) and **not pushed**.

## The user

`cmdruid` (git), the FROSTR maintainer — senior, terse, wants signal over
ceremony, decisive on scope. This program he gave broad authority ("this is an
alpha… make our development cycle fast and lean"). He picks options decisively
when asked, prefers the **submodule-first → bump-pointer** commit flow, and likes
a follow-up harvest (`dev/BACKLOG.md`) at thread boundaries. He engages on genuine
design forks — surface them with a recommendation rather than guessing.

## The project

`frostr-infra` is the coordinating workspace for FROSTR: a Rust signing core
(`repos/bifrost-rs`, native + browser WASM) wrapped by TypeScript `igloo-*`
clients (`repos/igloo-{shared,ui,pwa,chrome,home,shell,paper}`), all git
submodules under `repos/`. The **Makefile is the public command surface**;
`scripts/`, `dev/scripts/`, `test/scripts/` are private impl behind it.

## What shipped this session (Thread 3 — all on `dev`, parent-only)

Commits, newest first:

- `0078594` Docs: AGENTS.md "Verification recipes" + surface `make verify`/`install`;
  fix stale release-validation-on-PRs facts.
- `a9d43c4` Backlog harvest: the red @fast gate, the relay leak, corrected
  `test:guards:full` premise.
- `9c69312` Machine-readable status: `.tmp/agent/{dev,screenshot,verify}.json`.
- `7c06049` `make bump-pointers` (one-step submodule pointer bumps).
- `c61521a` `make install` (self-contained per-leaf npm setup; the workspace pivot).

**New command surface** (also in AGENTS.md → Verification recipes):
- `make install [INSTALL_UPDATE=1]` — one `npm ci` per JS client into its own
  `node_modules`. Deliberately not an npm workspace ([[no-npm-workspace-thin-install]]).
- `make bump-pointers [MSG= PUSH=1 DRY_RUN=1]` — stages every moved submodule
  pointer into one parent commit; refuses a submodule with uncommitted changes.
- `.tmp/agent/<command>.json` — `make dev` writes `dev.json` (+ `READY <url>`),
  `make screenshot` writes `screenshot.json`, `make verify` writes `verify.json`.

## What's pending (priority order)

1. **RED @fast gate (top priority).** `make verify` / `make test-fast` is red on
   `dev` HEAD: two pwa specs (`app-shell.spec.ts` *persists settings across
   reloads* / *…preserving saved profiles*) hard-fail at line 276 (`dashboardRoot`
   not visible). They seed `localStorage` under the **old** partition key with a
   fake `encrypted_bfshare_artifact`; after the 2026-06-16 two-store move the
   seeded state no longer hydrates to a dashboard. Pre-existing, reproducible in a
   clean env, **not** caused by Thread 3 (all submodules pristine). Fix: reseed via
   the supported two-store helper (`test/igloo-pwa/support/state.ts`) — or fix pwa
   hydration if a stored artifact genuinely must rehydrate. Full diagnosis in
   `dev/BACKLOG.md` (Test harness / CI → "RED GATE").
2. **Not pushed.** All five commits are local on `dev` (parent only). Push when the
   user asks; the pre-push gate (`make verify`) is red per #1, so resolve that first
   or push knowingly.
3. **Tracked BACKLOG follow-ups** (the usual sink): de-gated-guard deletion + the
   visual-harness doc cleanup that rides with it; exempt `@agent` specs from the
   selector contract (greens nightly `test:guards:full`); leaked `bifrost-devtools
   relay` processes from the Playwright harness; gate `dev-scenario` behind
   `import.meta.env.DEV`; `make verify` affected-aware; WASM watch; signer-core perf.

## Critical considerations (the WHY)

- **No npm workspace — by decision.** [[no-npm-workspace-thin-install]]. Don't
  reintroduce a root `package.json`/`workspaces`; orchestrate via `make` targets
  that loop over the self-contained leaves.
- **The gate is red, independent of this work.** Don't trust a green assumption —
  `make verify` currently fails on two pre-existing pwa fixture specs (#1). The
  machine signal works: `.tmp/agent/verify.json` correctly reports `ok:false`.
- **Commit flow:** commit inside the submodule first, then `make bump-pointers`
  ([[workflow-no-new-prs]]). Non-recursive submodule commands only.
- **igloo-ui source-vs-dist:** the pwa resolves igloo-ui JS from source but CSS
  from `igloo-ui/dist/styles.css` — rebuild dist (or `make igloo-ui-watch`) after
  CSS edits ([[igloo-pwa-ui-source-vs-dist]]).
- **`dev/fixtures/` are throwaway devnet keys** (password `devpass`) so `make dev`
  never keygens/onboards. Never reuse for anything real.

## Suggested first action

Decide the red @fast gate (#1): either reseed the two `app-shell.spec.ts` specs via
`test/igloo-pwa/support/state.ts`'s two-store helper to get `make verify` green, or
confirm with the user that pushing Thread 3 with a known-red pre-existing gate is
acceptable. Then push `dev` if the user wants. Thread 3 itself is complete and
verified (its own `make install` / `bump-pointers` / `*.json` outputs all work).
