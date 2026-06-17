# Hand-off: next = fix the chrome `@fast` red gate + extend render-and-verify to chrome

_Last updated: 2026-06-17_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The **lean dev/test-loop program is complete** (all five threads of
> `~/.claude/plans/twinkling-tinkering-phoenix.md` shipped; agent-facing commands
> are in [`AGENTS.md`](../AGENTS.md) → "Verification recipes"). This session also
> fixed the pwa half of a pre-existing red gate. **The two chosen next tasks:**
> (1) fix the **chrome `@fast` red gate**, and (2) **extend `make screenshot`
> (render-and-verify) to chrome** — and (2) makes (1) much easier, so do it first.

## TL;DR

`make verify` is green on the pwa lane but **still red on the chrome lane** from a
pre-existing test-vs-UI drift (the 2026-06-16 Paper dashboard restructure). The
plan: build a chrome render-and-verify tool (mirror the pwa dev-scenario seam) so
you can *see* the restructured chrome dashboard DOM, then modernize the two stale
chrome smoke specs against it. All work this session is on `dev` (parent-only) and
**not pushed**.

## The user

`cmdruid` (git), the FROSTR maintainer — senior, terse, wants signal over
ceremony, decisive on scope. Broad authority for this alpha ("make our development
cycle fast and lean"). Picks options decisively when asked, prefers the
**submodule-first → bump-pointer** commit flow, likes a follow-up harvest
(`dev/BACKLOG.md`). Engages on genuine design forks — surface them with a
recommendation rather than guessing. He wants the chrome gate green and the
render-and-verify loop extended to chrome.

## The project

`frostr-infra` is the coordinating workspace for FROSTR: a Rust signing core
(`repos/bifrost-rs`, native + browser WASM) wrapped by TypeScript `igloo-*`
clients (`repos/igloo-{shared,ui,pwa,chrome,home,shell,paper}`), all git
submodules under `repos/`. The **Makefile is the public command surface**;
`scripts/`, `dev/scripts/`, `test/scripts/` are private impl behind it.

## Next tasks (priority order)

### 1. Extend render-and-verify to chrome (`make screenshot`) — do this first

`make screenshot` renders only the **pwa** today, via the `?__frostr_dev=<scenario>`
seam in `repos/igloo-pwa/src/lib/dev-scenario.ts` → writes `.tmp/agent/<state>.{png,txt}`
+ `screenshot.json` (driven by `test/igloo-pwa/specs/agent-screenshot.spec.ts`,
tagged `@agent`). Build the **chrome** equivalent:

- Mirror the dev-scenario seam for the chrome **options page** (a dev/test-only
  injected `runtimeSnapshot` so a *running* dashboard can render headlessly).
  **igloo-home already has a `currentVisualScenario` seam — model it on that.**
- Add a `make screenshot CLIENT=chrome STATE=…` (or `make chrome-screenshot`) +
  a chrome `@agent` capture spec writing to `.tmp/agent/`.
- Payoff: it lets you capture the restructured chrome dashboard DOM directly,
  which is exactly what task 2 needs (no more inferring selectors from source).

Backlog: "Extend render-and-verify (`make screenshot`) to chrome (+ home)" (M).

### 2. Fix the chrome `@fast` red gate

`make verify` is red on the chrome lane: two smoke specs fail, both stale selectors
after the **2026-06-16 Paper dashboard restructure** (not a runtime bug — the
`ensure_session_failed` log line is a benign cold-state warning):

- `test/igloo-chrome/specs/dashboard.spec.ts:34` — `getByRole('heading', { name:
  'Pending Operations' })`. The OperatorSignerPanel section titles (Peers / Pending
  Approvals / Pending Operations / Event Log) are now
  `<span class="igloo-dashboard-section-title">` (see
  `repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx:407`), **not** headings.
  The same test then asserts `Site Policies` / `Peer Policies` (permissions tab) and
  `Device Profile` (settings tab, now a `ContentCard` title) — likely also drifted;
  verify each against the real DOM (← task 1's tool).
- `test/igloo-chrome/specs/profile-import.spec.ts:43` — `getByText('Chrome Import',
  { exact: true })` (the imported group name) no longer matches; check where/how the
  identity card renders it now.

**Open fork (decide):** (a) modernize the chrome smoke selectors to the restructured
DOM (test-side, fastest, no submodule change), or (b) treat section-titles-as-spans
as an a11y regression and restore heading roles in `igloo-ui` (submodule change +
pointer bump; also greens the tests). The render tool (task 1) helps you judge (a)
vs (b). Watch the HelpHint ambiguity noted in the test: a loose `getByText('Pending
Operations')` matches the help tooltip too — scope to the section-title span.

Full diagnosis: `dev/BACKLOG.md` → "RED GATE — chrome `@fast`".

### 3. Then: push, and the rest

All session commits are local on `dev` (parent-only). Push when the gate is green
(or knowingly). Other tracked follow-ups: `chrome-pwa-pairing.spec.ts` still seeds
the legacy `PWA_STORAGE_KEY`; exempt `@agent` specs from the selector contract
(greens nightly `test:guards:full`); leaked `bifrost-devtools relay` processes;
de-gated-guard deletion + the visual-doc cleanup that rides with it.

## What shipped this session (all on `dev`, parent-only)

Commits, newest first:

- `bbc2bb6` Backlog: bump-pointers-push + verify-JSON follow-ups.
- `f500d66` Backlog/handoff: pwa gate fixed, chrome scoped separately.
- `eafdb4a` **Fix pwa half of the red `@fast` gate** — reseed the two
  `app-shell.spec.ts` persistence specs via the supported two-store helper
  (`applyPwaSeed`/`buildPwaPersistedState`), read the settings poll from the global
  store, add an opt-in `PwaSeedPayload.ifAbsent` for the reloading spec. pwa `@fast`
  green (20 passed).
- `09459a0`/`0078594` Handoff + AGENTS.md "Verification recipes" + doc fact fixes.
- `a9d43c4` Backlog harvest (red gate, relay leak, corrected `test:guards:full`).
- `9c69312` `.tmp/agent/{dev,screenshot,verify}.json` machine output.
- `7c06049` `make bump-pointers`. `c61521a` `make install` (the workspace pivot).

**Command surface** (also AGENTS.md → Verification recipes): `make install
[INSTALL_UPDATE=1]`, `make bump-pointers [MSG= PUSH=1 DRY_RUN=1]`, `make verify`,
`make screenshot STATE=…` — all write `.tmp/agent/<command>.json`.

## Critical considerations (the WHY)

- **No npm workspace — by decision.** [[no-npm-workspace-thin-install]]. Hoisting
  breaks the self-contained leaf build scripts; orchestrate via `make` targets over
  the leaves, never a root `package.json`/`workspaces`.
- **The chrome `@fast` failures are pre-existing**, from the Paper restructure — not
  this session's work (chrome + igloo-ui are pristine) and not environmental
  (igloo-ui `dist` is gitignored / always rebuilt). `.tmp/agent/verify.json`
  correctly reports the red, so the machine signal works.
- **Commit flow:** commit inside the submodule first, then `make bump-pointers`
  ([[workflow-no-new-prs]]). Non-recursive submodule commands only. The chrome fix,
  if it touches igloo-ui (fork option b), is a submodule commit + pointer bump.
- **igloo-ui source-vs-dist:** clients resolve igloo-ui JS from source but CSS from
  `igloo-ui/dist/styles.css` — rebuild dist (or `make igloo-ui-watch`) after CSS
  edits ([[igloo-pwa-ui-source-vs-dist]]).
- **chrome runtime is native-ish:** the background hosts the live signer over the
  WASM bridge; `ensure_session_failed` for a cold seeded profile is expected, not a
  failure to fix.

## Suggested first action

Build the chrome render-and-verify seam (task 1): mirror igloo-home's
`currentVisualScenario` to inject a running `runtimeSnapshot` into the chrome
options page, add a chrome `@agent` capture + `make screenshot CLIENT=chrome`, and
capture the seeded chrome dashboard to `.tmp/agent/`. Use that DOM to modernize the
two stale chrome smoke specs (task 2), deciding the test-side-vs-igloo-ui-a11y fork.
Then `make verify` should go fully green; push `dev` when the user wants.
