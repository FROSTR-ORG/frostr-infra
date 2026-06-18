# Hand-off: test-infrastructure remediation (ADR-013) — P0 6/7 done, #3b remaining

_Last updated: 2026-06-18_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. A full **test-infrastructure audit → ADR → remediation** program is
> in flight. The audit ([`dev/docs/TEST-AUDIT.md`](docs/TEST-AUDIT.md), 97
> findings) and the target architecture
> ([`dev/adrs/ADR-013-test-infrastructure-architecture.md`](adrs/ADR-013-test-infrastructure-architecture.md),
> **Accepted**) are done. **P0 remediation is 6 of 7 sub-items shipped**; the only
> remaining P0 item is **#3b** (`@live` smoke + cargo lib-test in CI). The roadmap
> lives in [`dev/BACKLOG.md`](BACKLOG.md) → "Test infrastructure remediation". All
> work is on `dev`, committed and pushed.

## TL;DR

This session: fixed the chrome `@fast` red gate + built a chrome/home
render-and-verify tool, then ran a multi-agent **audit** of all test infra, wrote
+ accepted **ADR-013** (target test architecture, all 10 design forks decided by
the maintainer), and executed **P0 remediation**: selector contracts now gate
per-PR, every spec is tag-enforced, chrome e2e + unit suites run per-PR in CI, and
WASM provenance is both caught fast and fixed at the source. Next: **P0 #3b**.

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
workflows under `.github/workflows/`.

## What's been done (this session, all pushed to `dev`)

**Earlier arc** (chrome red gate → render tool → follow-ups): `b201147`..`2a26a32`
— fixed the chrome `@fast` gate, built `make screenshot CLIENT=chrome|home`,
split-copy keys, gated dev-scenario seams, selector-contract `@agent` exemption.
Detail in `dev/BACKLOG.md` history + those commits.

**Audit + ADR:** `9fa6f1b` `dev/docs/TEST-AUDIT.md` (9-agent audit, 97 findings);
`6d6a126` **ADR-013 Accepted** (lane taxonomy, CI tiers, single seed source,
unified harness, WASM provenance, chrome page objects, honest renames, pre-push
hook, centralized e2e — each decision + rejected alternative recorded).

**P0 remediation (6/7):**
- `9373da6` **#1** — `test:guards:selectors` added to `test:guards`, so the global
  selector contract runs in `make verify` + CI `workspace-guards` per-PR.
- `b0eb09e` **#2a** — tagged the 11 untagged spec files; added
  `check-spec-primary-tags.sh` (`test:guards:tags`, ≥1 lane tag, `@agent` exempt).
- `353ae5d` **#2b** — chrome `@fast` e2e gated in CI (the "chrome zero per-PR e2e"
  gap); fast grep-invert completed (`@live|@cross-client|@demo|@agent`).
- `353ae5d` **#3a** — per-affected unit suites (shared/pwa/chrome/home) wired into
  the per-client CI jobs (all green locally).
- `311503c` **#4a** — `test/shared/wasm-provenance.ts` `assertWasmProvenance`
  fail-fast SHA-384 check, wired into the chrome global-setup + the pwa-dist server.
- `353ae5d` **#4b** — added `pwa` to the chrome lane's full `prebuild` in
  `test-targets.json` so `@cross-client` pwa-dist specs rebuild the pwa dist from
  the same shared WASM the test injects (root-cause fix; `fastPrebuild` stays lean).

## What's pending (priority order)

1. **P0 #3b — the last P0 item** (`dev/BACKLOG.md` has it scoped). Add a
   `@live @smoke` spec per client (one onboarding+signing round-trip; specs use
   in-process relays — no external infra) wired into the per-PR lanes; a lean
   `cargo test --lib` for `bifrost-rs`/`igloo-shell`; and document `@cross-client`
   as nightly/manual (ADR Q1/Q2). **Best as a focused PR** — the chrome smoke needs
   the live-signer Rust worker and the **home** smoke runs via tauri-driver + xvfb
   (not verifiable on macOS), so the smoke matrix is validated in CI, not locally.
2. **Deferred (non-blocking), tracked in BACKLOG:** explicit per-test `@fast` tag
   (ADR Q9 — large churn; the completed grep-invert gives identical gating today);
   expand the prebuild stamp to cover toolchain inputs (P0 #4 optional (c)).
3. **P1 / P2** from ADR-013 + the audit: type-enforced seeds
   (`PersistableStoredProfile`), seed-builder consolidation, robust teardown +
   orphan-reaper, unified visual-harness module, honest lane renames, docs/ownership.
4. **Pre-existing follow-ups:** `chrome-pwa-pairing.spec.ts` is modernized 3/4 but
   its full `@cross-client` run was never re-verified (it's in no lane); the home
   `dashboard-signer` visual scenario renders a loading (not running) dashboard.

## Critical considerations (the WHY)

- **ADR-013 is the source of truth** for the target design; the BACKLOG "Test
  infrastructure remediation" section is the ordered worklist, each item gated on
  the ADR. Don't re-litigate the 10 decided forks.
- **CI changes verify on the PR, not locally.** This session's CI additions
  (`client-scoped-validation.yml`) mirror the proven pwa job and ran their commands
  locally, but GitHub Actions execution is only exercised when `dev` → `master`
  opens a PR. Treat a red CI step there as the normal verification loop.
- **`@cross-client` vs `@demo` boundary** (ADR §(b)): pure `@cross-client` pairing
  specs are manual/non-gated by design; the demo 3-way pairing is also `@demo` and
  runs nightly, so demo-path cross-client *is* covered.
- **WASM provenance** is now defended two ways: `assertWasmProvenance` (#4a) catches
  any test-vs-app WASM skew fast with a clear message; the test-targets fix (#4b)
  removes the cross-client skew at the source. The skew was intermittent and
  specific to dist-serving specs — the `@fast`/dev-server lanes were never exposed.
- **Commit flow:** submodule-first → `make bump-pointers`, non-recursive only
  ([[workflow-no-new-prs]]). This session's remediation was parent-only (test/, CI,
  docs) — no submodule pointer moves. `make verify` is the canonical gate.

## Suggested first action

If continuing remediation: pick up **P0 #3b** from `dev/BACKLOG.md`. Start by
documenting `@cross-client` as nightly (cheap, in `test/README.md` + ADR), then add
one `@live @smoke`-tagged spec per client and a `--grep "@smoke"` smoke lane, wire
it + a `cargo test --lib` step into `client-scoped-validation.yml`, and open the PR
so CI validates the live/desktop smoke matrix. Otherwise the program is at a clean
checkpoint: audit + ADR done, P0 6/7 shipped, `make verify` green.
