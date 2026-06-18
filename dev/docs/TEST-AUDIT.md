# Test Infrastructure Audit

_Last updated: 2026-06-17_

> **Read this first.** A full audit of the FROSTR workspace test infrastructure —
> lanes, fixtures, harnesses, selector/guard contracts, the build/WASM pipeline,
> CI, per-submodule suites, and reliability. It is the **input to the target-state
> ADR**, [ADR-013](../adrs/ADR-013-test-infrastructure-architecture.md), which locks
> in the design before any remediation. Do not start remediation from this doc alone
> — the roadmap here is provisional; the open questions in
> [§6](#6-open-questions-for-the-adr) are decided in ADR-013.

## 1. Scope & method

Scope: **everything** — the parent `test/` harness, all `repos/` submodule suites,
the build/prebuild pipeline (`scripts/`), and CI (`.github/workflows/`).

Method: a 9-way parallel read-only audit (one agent per area) plus a synthesis
pass, run as a multi-agent workflow (run `wf_2358e63b-700`; 10 agents, ~678k
tokens, 516 tool calls). Raw structured output is archived with the session; the
**97 findings** (20 high / 40 medium / 37 low) are reproduced in full in the
[findings appendix](#8-findings-appendix). This document is the curated synthesis.

The audit independently reproduced the root cause of a bug hit during the
2026-06-17 follow-up work — the cross-client pwa-**dist** "Incorrect password" —
as a **WASM provenance** problem (stale `.tmp/` artifacts silently overriding
tracked ones), which is encouraging evidence the findings are grounded.

## 2. TL;DR

The per-PR gate is **render-only by design and honest about that** — but the
surrounding lanes have grown by convention, not design, and the result is that
**a green PR can hide a broken unit suite, a stale selector, a failed signing
flow, or a drifted cross-client contract.** Five high-severity themes dominate:

1. **Silent lanes** — Chrome/Home have *zero* per-PR e2e; unit suites and all
   `@cross-client` pairing run nowhere or nightly-only; 11 specs are untagged.
2. **Implicit lane taxonomy** — lanes are `--grep-invert` conventions, "fast"
   conflates "render-only" with "non-relay", and Home uses a `-live` *filename*
   convention divorced from the `@live` tag.
3. **WASM/artifact provenance** — stale `.tmp/` WASM can silently override tracked
   artifacts; the prebuild stamp omits toolchain + igloo-shared inputs; `check`
   mode doesn't enforce a cache hit. (Root cause of the "Incorrect password" bug.)
4. **Fixture/seed sprawl** — duplicated seed builders, seeds that accept fields the
   app silently discards, lingering legacy v2 keys, a triplicated test password.
5. **Late selector-contract enforcement** — contracts run per-client + nightly, not
   in the global per-PR gate, so stale selectors merge and fail 24h later (exactly
   what the Paper dashboard restructure did across all three clients).

Plus four medium themes: render-harness fragmentation, cross-repo inconsistency,
flake/process-lifecycle, and undocumented surfaces.

## 3. Themes

| # | Theme | Severity |
|---|-------|----------|
| 1 | **Silent lanes & per-PR coverage gaps** — large swaths run nightly, manually, or nowhere; a render-only green gate hides real regressions | **High** |
| 2 | **Tag/lane taxonomy is implicit & inconsistent** — `--grep-invert` conventions, "fast" overloaded, `-live` filename vs `@live` tag, 11+ untagged specs | **High** |
| 3 | **WASM/artifact provenance & cache integrity** — stale `.tmp/` fallback, incomplete stamp inputs, non-enforcing `check`, loader desync | **High** |
| 4 | **Fixture/seed sprawl & drift from the runtime contract** — duplicated builders, discarded seed fields, legacy keys, triplicated password | **High** |
| 5 | **Selector brittleness & late contract enforcement** — contracts gated nightly not per-PR; Chrome bypasses page objects with raw selectors | **High** |
| 6 | **Render/visual harness fragmentation** — 3 strategies, ~148 LOC duplicated capture, scattered artifact dirs, Linux-only Home path | Medium |
| 7 | **Cross-repo inconsistency & harness duplication** — divergent prebuild targets, per-submodule unit commands, re-implemented target mapping | Medium |
| 8 | **Flake, isolation & process lifecycle** — overlapping relay ports, non-idempotent close, no orphan reaper, snapshot/restore coupling | Medium |
| 9 | **Undocumented surfaces & missing ownership** — 14 lanes, the env-var contract, demo services, the tsconfig strict pilot are undiscoverable | Medium |

## 4. Prioritized remediation roadmap

Provisional — sequence/ownership firm up once the ADR decides §6. Priorities:
**P0** = correctness/coverage risk (drift that hides bugs); **P1** = high-friction
debt; **P2** = consolidation/clarity.

### P0 — stop the silent gaps

- **Gate selector contracts in the global per-PR lane** (S). Hoist
  `test:guards:selectors` into `test:verify`/`workspace-guards`. One-line wiring;
  catches the Paper-restructure class of breakage same-PR instead of 24h later.
- **Tag and gate the silent suites** (M). Tag all 11 untagged specs (the filename
  `-live` is not a contract), add Chrome:fast + Home:fast + per-client `test:unit`
  to `client-scoped-validation.yml`. Single largest correctness-risk reduction.
- **Decide & wire the `@live` / `@cross-client` CI story** (M, depends on tagging).
  Either a lighter per-PR `@live` smoke + an explicit nightly `@cross-client` lane,
  or formally document them nightly-only — but close the silent drift.
- **Enforce WASM provenance** (M). Make prebuild `check` fail hard, reject `.tmp/`
  fallback when a lane is active, add a startup hash assertion so fixtures and app
  WASM are provably the same build epoch. Fixes the "Incorrect password" class.

### P1 — pay down high-friction debt

- **Expand the WASM stamp** to cover toolchain + igloo-shared build inputs (S, depends on provenance).
- **Type-enforce fixture seeds against the persist allowlist** (M) — export a `PersistableStoredProfile` so TS rejects any seed field the app won't persist.
- **Consolidate seed builders + centralize the test password** (M, depends on the type work).
- **Robust process teardown** (M) — idempotent relay `close()`, SIGKILL escalation, a global orphan-reaper for `bifrost-devtools relay`.
- **Unify relay port allocation** to one OS-assigned source (S, depends on teardown).
- **Unified visual-harness module + single artifact tree** (L) — one `test/shared/visual-harness.ts`, all output under `.tmp/visual/<client>/`, migrate Home off system chromium, extend the manifest+guard to all clients.

### P2 — consolidation & clarity

- **Make `test-targets.json` the single source** for affected/prebuild mapping (M).
- **Document lanes, env-var schema, services, fixture ownership** (M) — a lane/coverage matrix, `TEST-ENV-VARS.md`, `services/README.md`, `FIXTURES.md`.
- **Rename lanes for honest semantics; wire-or-delete dead guards** (S) — explicit `@fast` tag; `check-wasm-toolchain` and `check-worktree-unchanged` are defined but never invoked.

## 5. Target-state sketch

The end-state the ADR will formalize:

- **Lane taxonomy (explicit tags, not `grep-invert`).** Every spec carries exactly
  one primary execution tag — `@fast` (render-only, no relay), `@live`
  (single-client behavioral, local relay), `@cross-client` (multi-client pairing),
  `@demo` (Docker 3-way) — plus orthogonal tooling tags `@agent` and `@visual`.
  Filenames are narrative; the tag is the contract. Home joins the taxonomy.
- **CI gating tiers.** (1) Global per-PR = guards (targets + wasm + **selectors** +
  docs) + typecheck + `@fast` for all three clients + each affected submodule's
  `test:unit`. (2) Per-client per-PR = scoped selector + typecheck + fast.
  (3) Nightly/dispatch = `@live` + `@cross-client` + `@demo` + Rust + full guards.
  The lean per-PR philosophy stays — but render-only green can no longer hide a
  broken unit suite or stale selector, and behavioral coverage has a named home.
- **Single seeding source of truth.** One `ProfileSeedInput` domain type with
  per-target builders, a single shared test-secrets module, and a
  `PersistableStoredProfile` exported from the runtime's persist-allowlist so TS
  rejects any seed field the app would not persist. Transient runtime state is
  bootstrapped in-memory, never via storage.
- **Unified render/verify harness.** One `captureScreenshot` helper for all
  `@agent`/`@visual` specs, output under `.tmp/visual/<client>/`, Home on bundled
  Playwright, one visual manifest + guard covering pwa/chrome/home.
- **Artifact/WASM provenance guarantee.** One canonical input hash over all WASM
  source + toolchain + igloo-shared build scripts; prebuild `check` fails hard on
  mismatch; lanes refuse `.tmp/` fallback; a startup assertion proves fixtures,
  dev-server, and dist load byte-identical WASM from the same bifrost-rs commit.

## 6. Open questions for the ADR

> **Decided.** All ten were resolved by the maintainer and are recorded with
> rationale + rejected alternatives in
> [ADR-013](../adrs/ADR-013-test-infrastructure-architecture.md). Kept here for the
> audit's traceability.

These were the genuine design forks the ADR had to decide before remediation:

1. **Per-PR `@live`?** Does `@live` (or a `@live` smoke) block every PR, or is
   nightly sufficient for a stable `main`? The central cost/coverage fork.
2. **`@cross-client` status?** Mandatory nightly, folded into `@live` (dual-tag),
   or manual-only? Must every `@cross-client` spec also be `@live`?
3. **Unify render harnesses?** Collapse Playwright `@visual`/`@agent` + Home
   system-chromium `.mjs` + tauri-driver into one Playwright abstraction, or keep
   tauri-driver separate for genuine desktop-API coverage?
4. **WASM provenance mechanism?** Disable `.tmp/` fallback entirely in test lanes
   (always tracked artifacts) vs keep the cache + a hard fail-fast hash gate. Must
   pwa and chrome WASM be byte-identical?
5. **Unit/Rust in the per-PR gate?** Enforce per-affected-submodule `test:unit` +
   a lean cargo lib-test in the global gate, or keep all unit/Rust nightly?
6. **Chrome selector strategy?** Adopt the PWA page-object pattern, or formalize a
   raw-selector-through-helpers contract with its own guard? (Converge vs diverge.)
7. **Where does the persist-allowlist contract live?** A runtime-exported
   `PersistableStoredProfile` type (couples test to app source) vs a runtime-side
   validation function imported by tests?
8. **Local hooks?** Should selector/seed contract checks also run as pre-commit/
   pre-push hooks for faster feedback, given the Claude Code harness?
9. **Renames?** Worth the churn to rename `test:guards`→`test:structural`,
   `test:guards:full`→`test:all`, and introduce an explicit `@fast` tag — or just
   document the existing names?
10. **Co-locate e2e?** Move e2e specs from `test/igloo-*/specs` into
    `repos/igloo-*/test/` (next to client code), or keep them centralized?

---

## 7. Inventory by area

_Per-area summaries and catalogued artifacts (expand each for the artifact list)._

### Test lanes and gating

FROSTR's test infrastructure spans multiple lanes with significant coverage gaps and tag-filtering inconsistencies. Per-PR gates are asymmetric (PWA fast lane only), leaving Chrome and Home without CI e2e coverage. 11 untagged test specs run nowhere systematically, including 5 igloo-home tests with "live" in filenames but no @live tags. Cross-client tests (4 suites) run only in nightly, not per-PR. The lane taxonomy conflates "fast" (render-only) with "non-live" but home tests are untagged and always run live, creating a hidden cross-lane interface.

<details><summary>Artifacts catalogued (17)</summary>

- `test/package.json (lines 5-62: all test scripts and lane definitions)`
- `Makefile (lines 178-222: test-smoke/fast/live/demo/e2e/verify/test-affected/test-release targets)`
- `.github/workflows/workspace-guards.yml (lines 1-86: per-PR workspace guards, excludes full e2e)`
- `.github/workflows/client-scoped-validation.yml (lines 1-159: per-PR client gates; PWA:fast only, Chrome/Home no e2e)`
- `.github/workflows/release-validation.yml (lines 1-118: nightly @demo + @live gates, excludes @cross-client)`
- `scripts/verify.sh (lines 1-27: canonical verify lane wraps test:verify)`
- `test/shared/playwright-config.ts (lines 1-42: centralized Playwright config, no tag semantics)`
- `test/igloo-pwa/playwright.config.ts (lines 1-45: PWA config with timer throttling notes)`
- `test/igloo-chrome/playwright.config.ts (lines 1-20: Chrome config minimal)`
- `test/igloo-home/playwright.config.ts (lines 1-14: Home config minimal)`
- `test/igloo-home/run-e2e.sh (lines 1-38: display detection wrapper, not a tag filter)`
- `scripts/test-affected.sh (lines 1-213: affected-lane orchestrator; client-specific prep + full e2e run)`
- `test/scripts/check-e2e-selector-contracts.sh (lines 1-85: selector contract enforcement, exempts @agent)`
- `test/scripts/test-affected.sh (lines 1-81: dry-run test for affected lane)`
- `Untagged test specs (11 total): Chrome: provider.spec.ts, rotation-update.spec.ts, profile-import.spec.ts; Home: generated-onboarding-live.spec.ts, rotation-live.spec.ts, raw-import-live.spec.ts, onboarding-package-live.spec.ts, rotation-update-live.spec.ts; PWA: app-shell.spec.ts, wasm-integrity.spec.ts; UI Showcase: reference-screens.spec.ts`
- `Cross-client specs (4): Chrome: chrome-pwa-pairing.spec.ts, chrome-home-pairing.spec.ts, chrome-home-demo-harness.spec.ts (@live @cross-client @demo); PWA: pwa-home-pairing.spec.ts (@cross-client)`
- `Tag filters by lane: fast excludes @live|@cross-client|@agent; live includes @live only; demo includes @demo only; affected runs full suite (no filters by client)`

</details>

### Fixtures & Seeding

The FROSTR test infrastructure has duplicated seed builders across PWA and Chrome repos, legacy storage key references that no longer align with runtime behavior (especially runtimeSnapshot persisted in test seeds but not in app), and inconsistent password constants. The 2026-06-16 PWA global/session store split is partially reflected in test fixtures but test-facing seed helpers have not been harmonized, creating migration debt and drift risk as the app's two-store model solidifies.

<details><summary>Artifacts catalogued (11)</summary>

- `test/shared/browser-artifacts.ts (createGeneratedBrowserArtifacts, createPwaStoredProfileSeed, DEFAULT_BROWSER_PASSWORD, PwaStoredProfileSeed)`
- `test/igloo-pwa/support/state.ts (PWA_GLOBAL_STORE_KEY, PWA_SESSION_STORE_KEY, PWA_STORAGE_KEY, PWA_INSTANCE_REGISTRY_KEY, applyPwaSeed, buildPwaPersistedState)`
- `test/igloo-chrome/fixtures/extension.ts (seedProfile fixture factory)`
- `test/igloo-chrome/fixtures/helpers/seed-profile.ts (buildSeedProfile, DEFAULT_SEED_SIGNER_SETTINGS, DEFAULT_SEED_LABEL)`
- `test/igloo-chrome/fixtures/helpers/seed-crypto.ts (createSeededProfileRecord, PASSWORD='playwright-passphrase')`
- `test/igloo-chrome/fixtures/helpers/storage.ts (seedProfileIntoExtension, seedPermissionPoliciesIntoExtension)`
- `test/igloo-home/fixtures/app.ts (launchIglooHome, IglooHomeHarness)`
- `repos/igloo-pwa/src/lib/persist-allowlist.ts (PROFILE_ALLOWED_KEYS, toPersistableProfile, PersistableGlobalState, PersistableSessionState)`
- `repos/igloo-pwa/src/lib/migrate-global.ts (importLegacyProfilesOnce)`
- `test/igloo-pwa/specs/{permissions,settings}.spec.ts (direct legacy key scanning with 'igloo-pwa.state.v2')`
- `test/igloo-pwa/specs/{permissions-visual,settings-visual}.spec.ts (runtimeSnapshot seeded but not persisted)`

</details>

### Render/visual/e2e/demo harness inventory across parent + submodules

The FROSTR workspace test infrastructure has three distinct rendering/visual harness patterns: (1) playwright-based headless e2e tests (@visual specs for storage-seeded snapshots + @agent screenshot tools for agent/human use), (2) submodule-specific visual smoke tests (igloo-home system chromium vs bundled playwright), and (3) demo harness orchestration via docker-compose. Across these, there is significant duplication of capture-and-write logic, inconsistent artifact output directory conventions (.tmp/agent vs .tmp/visual/igloo-pwa/*, local .tmp-visual-artifacts), platform gaps (Linux-only system chromium for igloo-home), and fragmented configuration/ownership across test/igloo-{pwa,chrome,home} and repos/ submodules.

<details><summary>Artifacts catalogued (20)</summary>

- `test/igloo-pwa/specs/{welcome,dashboard,settings,permissions,import,onboard,recover}-visual.spec.ts (7 files, ~2500 LOC each with repeated capture helpers)`
- `test/igloo-pwa/specs/agent-screenshot.spec.ts (48 LOC, writes to .tmp/agent/)`
- `test/igloo-chrome/specs/agent-screenshot.spec.ts (48 LOC, writes to .tmp/agent/, extension-specific)`
- `test/igloo-home/screenshot/agent-screenshot.spec.ts (52 LOC, writes to .tmp/agent/, scenario-mapping logic)`
- `test/igloo-home/playwright-screenshot.config.ts (separate config from playwright.config.ts, vite-based)`
- `repos/igloo-home/test/visual/run.mjs (Linux-only, probes /snap/bin/chromium + system paths, outputs to .tmp-visual-artifacts/)`
- `repos/igloo-home/test/desktop/run.mjs (tauri-driver + playwright, X11/Wayland detection)`
- `test/igloo-pwa/visual-manifest.json (25 screens, references repos/igloo-paper/, status tracking)`
- `test/igloo-pwa/playwright.config.ts (shared defineFrostrPlaywrightConfig pattern)`
- `test/igloo-chrome/playwright.config.ts (shared config, no webServer)`
- `test/igloo-home/playwright.config.ts (tauri-driver, separate from screenshot config)`
- `test/igloo-ui-showcase/playwright.config.ts (1440x1080 viewport, no webServer)`
- `test/shared/playwright-config.ts (centralized LIVE_TEST_TIMEOUT_MS, expect timeouts)`
- `compose.test.yml (dev-relay + igloo-demo services, healthcheck on socket binding)`
- `scripts/demo.sh (port resolution, onboard package/password generation, compose orchestration)`
- `test/scripts/test-demo-harness-onboard.sh (standalone smoke test, igloo-shell integration)`
- `scripts/verify.sh (mirrors output to .tmp/agent/verify.json for agent polling)`
- `test/scripts/check-pwa-visual-manifest.mjs (validates .tmp/visual/igloo-pwa/ paths only)`
- `test/package.json (test:e2e:*, test:screenshot:*, test:visual:*, guards)`
- `repos/igloo-home/package.json (test:visual, test:desktop, test:desktop:xvfb)`

</details>

### Selector strategy & guard scripts (FROSTR test infrastructure)

The selector protection model relies on three interlocking gates enforced at different cadences: (1) per-PR lean guards gate only targets+wasm, not selectors; (2) per-client validation gates client-scoped selectors via test:guards:pwa|chrome|home; (3) nightly test:guards:full includes full selector coverage. Selector contracts are correctly enforced (test-id registry imported only in ui.ts, specs route through pages.ts), but cross-client consistency is asymmetric: PWA has comprehensive page objects (527 lines, every screen), Chrome specs bypass page objects entirely for 37+ raw selectors per spec. Two guard scripts are unwired (wasm-toolchain, worktree-unchanged), and the @fast/@live/@cross-client lane filters block only nightly selector regression but permit stale selectors to merge on fast PRs (e.g., the Paper dashboard restructure cascaded across all lanes). Per-client prebuild divergence (chrome needs home+demo targets) creates brittleness when cross-client specs depend on runtime state from multiple clients.

<details><summary>Artifacts catalogued (14)</summary>

- `test/scripts/check-e2e-selector-contracts.sh (85 lines; enforces TID registry import gating, page-object routing, @agent exemption)`
- `test/igloo-pwa/support/pages.ts (527 lines; comprehensive page-object abstraction: 8 page classes, 60+ methods)`
- `test/igloo-chrome/support/ui.ts (63 lines; minimal helpers; specs use raw selectors directly)`
- `repos/igloo-ui/src/lib/e2e-test-ids.ts (131 lines; 127 test-id registry entries with data-* discriminators)`
- `test/scripts/check-browser-wasm-artifacts.sh (45 lines, per-client wasm harness contracts)`
- `test/scripts/check-cross-client-imports.sh (56 lines, client-scoped isolation enforcement)`
- `test/scripts/check-shared-test-setup.sh (43 lines, igloo-ui test-setup drift detection)`
- `test/package.json (test:verify runs test:guards+typecheck+fast per-PR; test:guards:full nightly; test:guards:pwa|chrome|home per-client scoped)`
- `.github/workflows/workspace-guards.yml (86 lines, runs npm test:guards per-PR)`
- `.github/workflows/client-scoped-validation.yml (159 lines, runs test:guards:pwa|chrome|home per-client per-PR)`
- `test/shared/test-targets.json (20 lines, single source of truth for client prebuild targets; fastPrebuild leaner for @fast lanes)`
- `Guard scripts defined: 18 total; wired: 16 (in test/package.json lanes); unwired: 2 (check-wasm-toolchain.sh, check-worktree-unchanged.sh)`
- `Test lane timing: test:verify (lean guards) per-PR; test:guards:full (16 guards) nightly; test:guards:selectors runs in both full+per-client but NOT in lean test:verify`
- `Tag-filtered test lanes: @fast (20/25 PWA specs; excludes @live|@cross-client|@agent), @live (PWA + Chrome), @cross-client (pairing specs), @agent (render-and-verify, 3 specs)`

</details>

### Build & Artifact/WASM Pipeline

The test infrastructure has critical architectural gaps in WASM provenance and cache integrity. The prebuild stamps, cache key logic, and dist-vs-test WASM sourcing create multiple failure modes where stale or mismatched WASM binaries reach tests without detection, causing runtime decryption failures ("Incorrect password" symptom observed in PWA-DIST against vite dev). Three orthogonal integrity layers (git-stamp, test-prebuild cache, vite resolution) do not compose correctly, allowing bifrost-rs source drifts to silently propagate cached WASM while the detection mechanisms remain flaky or incomplete.

<details><summary>Artifacts catalogued (20)</summary>

- `scripts/test-prebuild.sh (prebuild cache & stamp logic, per-target selection)`
- `scripts/prepare-browser-wasm.sh (WASM build, sync, and check modes)`
- `test/shared/test-prebuild.ts (test harness entry point, cache bypass logic)`
- `test/shared/browser-wasm-paths.ts (test WASM directory resolution)`
- `test/shared/browser-artifacts.ts (ensureInjectedWasmModule entry, test fixture generation)`
- `test/shared/bridge-wasm.ts (test WASM module loader)`
- `test/shared/profile-wasm.ts (test WASM module loader)`
- `test/scripts/check-browser-wasm-stamp.sh (git-based WASM source hash verification)`
- `test/scripts/check-browser-wasm-artifacts.sh (calls prepare-browser-wasm.sh check)`
- `test/scripts/check-browser-wasm-harness-contracts.sh (mock-based API contract)`
- `test/scripts/check-test-prebuild-nonmutating.sh (nonmutating build guard)`
- `test/scripts/check-worktree-unchanged.sh (git-based mutation detector)`
- `repos/igloo-pwa/vite.config.ts (wasmScratchAssetsPlugin, WASM source fallback chain)`
- `repos/igloo-chrome/scripts/build.mjs (resolveWasmSourceDir, dist copy logic)`
- `repos/igloo-pwa/scripts/sync-bridge-wasm.mjs (WASM sync into public/wasm)`
- `repos/igloo-shared/src/wasm/bridge-loader.ts (runtime WASM injection dispatch)`
- `repos/igloo-shared/src/wasm/profile-loader.ts (runtime WASM injection dispatch)`
- `repos/igloo-pwa/src/lib/configure-igloo-shared.ts (PWA WASM endpoint config)`
- `test/igloo-pwa/specs/wasm-integrity.spec.ts (SHA-384 wrapper integrity test)`
- `test/browser-wasm-source.stamp (git-committed source hash)`

</details>

### CI workflows

The frostr-infra workspace maintains a two-tier CI strategy following the 2026-06-17 lean-CI cut: per-PR scoped validation (client-scoped-validation.yml + workspace-guards.yml) paired with nightly/on-demand comprehensive testing (release-validation.yml). Critical coverage gap: @cross-client e2e tests (4 suites validating chrome<->pwa, chrome<->home, pwa<->home pairing behavior) are defined locally but execute nowhere in CI, creating silent regressions on interaction contracts. Client-scoped validation correctly blocks unrelated submodule initialization, but lacks @live lane coverage per-PR outside the nightly gate.

<details><summary>Artifacts catalogued (16)</summary>

- `.github/workflows/client-scoped-validation.yml`
- `.github/workflows/release-validation.yml`
- `.github/workflows/workspace-guards.yml`
- `compose.ci.yml`
- `test/package.json`
- `scripts/verify.sh`
- `scripts/test-prebuild.sh`
- `scripts/release-matrix.sh`
- `scripts/test-affected.sh`
- `test/scripts/check-workflow-node24-actions.sh`
- `test/scripts/check-client-scoped-submodules.sh`
- `test/scripts/check-e2e-selector-contracts.sh`
- `test/README.md`
- `test/docs/WORKFLOWS.md`
- `CONTRIBUTING.md`
- `Makefile`

</details>

### Per-submodule test suites & parent invocation

The FROSTR workspace harness has significant test coverage gaps: unit tests from igloo-chrome (5200+ LOC), igloo-pwa (2300+ LOC), and igloo-shared are orphaned—never invoked from the parent CI lanes (client-scoped-validation) that guard PRs. Bifrost-rs and igloo-shell Rust tests only run in the nightly release-validation lane, not on PR gates. Test invocation is fragmented across three frameworks (Rust cargo, Node vitest, Playwright), with inconsistent conventions per repo and duplication between parent harness targets and submodule scripts.

<details><summary>Artifacts catalogued (21)</summary>

- `Makefile (test entry points: test-smoke, test-fast, test-live, test-demo, test-e2e, test-affected, test-release, verify)`
- `test/package.json (parent harness test targets and lane definitions)`
- `.github/workflows/client-scoped-validation.yml (PWA/Chrome/Home PR validation lane)`
- `.github/workflows/release-validation.yml (nightly full matrix: Rust + e2e)`
- `.github/workflows/workspace-guards.yml (lean guards, workspace-level checks)`
- `scripts/test-affected.sh (affected-file-driven test lane: bifrost, shell, shared, ui, home, pwa, chrome)`
- `scripts/release-matrix.sh (nightly: bifrost-rs tests, igloo-shell tests, e2e suite)`
- `repos/bifrost-rs/Cargo.toml (workspace: 11 crates, unit tests in tests/ dirs, never run on PR gate)`
- `repos/igloo-shell/Cargo.toml (workspace: igloo-shell-cli, tests via cargo test, not on PR gate)`
- `repos/igloo-shared/package.json (vitest unit tests, typecheck only in parent, unit tests skipped)`
- `repos/igloo-ui/package.json (vitest 'test' target, invoked via test-affected.sh if run_ui=1)`
- `repos/igloo-chrome/package.json (test:unit via vitest, 5200+ LOC tests, never invoked from parent)`
- `repos/igloo-chrome/tests/unit/ (24 vitest files, vitest.config.ts, vitest.setup.ts)`
- `repos/igloo-pwa/package.json (test:unit via vitest, 2300+ LOC tests, never invoked from parent)`
- `repos/igloo-pwa/test/frontend/ (6 vitest files, vitest.config.ts)`
- `repos/igloo-home/package.json (test:unit via vitest, invoked from test-affected.sh)`
- `repos/igloo-home/test/frontend/ (5 vitest files, vitest.config.ts)`
- `test/igloo-chrome/playwright.config.ts (parent e2e harness, no unit tests)`
- `test/igloo-pwa/playwright.config.ts (parent e2e harness, no unit tests)`
- `test/igloo-home/playwright.config.ts (parent e2e harness, no unit tests)`
- `test/shared/test-targets.json (client->prebuild target map, excludes unit test lanes)`

</details>

### Flake, isolation & cleanup

The FROSTR test infrastructure exhibits solid process cleanup discipline in core relay and fixture teardown patterns, with try-finally guards consistently applied across 46 E2E specs. However, three key risk areas emerged: (1) multiple relay port allocation strategies that could collide under load (24,000-44,000 range for local relays + 43,000-based demo port), (2) double-close vulnerability in local relay that needs defensive handling, and (3) desktop (igloo-home) process lifecycle timeouts with 5-second hard exit guarantees that may be insufficient under resource contention.

<details><summary>Artifacts catalogued (17)</summary>

- `test/shared/local-relay.ts`
- `test/shared/playwright-config.ts`
- `test/igloo-chrome/fixtures/extension.ts`
- `test/igloo-chrome/fixtures/helpers/context.ts`
- `test/igloo-chrome/fixtures/helpers/demo-harness.ts`
- `test/igloo-chrome/fixtures/live-signer.ts`
- `test/igloo-pwa/support/shell-signer.ts`
- `test/igloo-home/fixtures/app.ts`
- `test/igloo-pwa/specs/create-keyset.spec.ts`
- `test/igloo-pwa/specs/permissions.spec.ts`
- `test/igloo-pwa/specs/dashboard-states.spec.ts`
- `test/shared/browser-artifacts.ts`
- `test/shared/observability.ts`
- `scripts/lib-scratch.sh`
- `scripts/reset.sh`
- `14 igloo-pwa specs using startLocalRelay (all with finally blocks)`
- `9 igloo-chrome specs using startLocalRelay (all with finally blocks)`

</details>

### Completeness critic: test infrastructure coverage gaps & undocumented surfaces

The FROSTR test infrastructure has substantial documentation (test/README.md, test/docs/WORKFLOWS.md, dev/docs/WORKFLOWS.md) but exhibits coverage gaps, undocumented test lanes, systemic environment-variable contract gaps, and missing routing/discovery infrastructure. Key issues: 14 npm test commands are functional but not documented in the public manual; environment variables controlling test execution are scattered across code without a schema; test-harness and demo-services infrastructure lacks ownership documentation; igloo-ui-showcase exists as a test target but has no discovery or routing; and critical guard failure modes are not consistently gated or tested.

<details><summary>Artifacts catalogued (18)</summary>

- `test/README.md (canonical lane documentation)`
- `test/docs/WORKFLOWS.md (test-selection guidance)`
- `dev/docs/WORKFLOWS.md (workspace-level process docs)`
- `test/package.json (46 npm test commands)`
- `test/shared/test-prebuild.ts (FROSTR_TEST_LANE, FROSTR_TEST_PREPARED contracts)`
- `test/shared/test-targets.json (client→prebuild mapping)`
- `scripts/test-affected.sh (affected-lane wiring)`
- `scripts/release-matrix.sh (release validation matrix)`
- `scripts/verify.sh (canonical gate)`
- `test/tsconfig*.json (6 typecheck configs with coverage drift)`
- `compose.test.yml (demo-harness service definitions)`
- `services/demo/, services/dev-relay/, services/igloo-demo/ (unowned infrastructure)`
- `dev/scripts/sync-igloo-paper-tokens-to-ui.mjs (undocumented design-token handoff)`
- `.agents/skills/frostr-paper-ui-workflows/SKILL.md (only agent skill present)`
- `test/igloo-pwa/support/, test/igloo-chrome/support/ (test helpers missing version/contract docs)`
- `test/igloo-home/run-e2e.sh (custom test runner for Tauri, xvfb fallback)`
- `test/igloo-home/playwright-screenshot.config.ts (separate screenshot-only config)`
- `test/igloo-ui-showcase/ (test suite with no public surface documentation)`

</details>


---

## 8. Findings appendix

_All 97 findings, grouped by audit area, severity-sorted. Evidence paths are repo-relative._

### Build & Artifact/WASM Pipeline

- **[HIGH] Test WASM source falls back silently through unguarded chains without cache invalidation**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** test/shared/browser-wasm-paths.ts:9-21 defaultTestBrowserWasmDir() returns `.tmp/test-prebuild/browser-wasm/igloo-shared/public/wasm` by default. repos/igloo-pwa/vite.config.ts:13-21 resolveWasmSourceDir() chains: env `IGLOO_PWA_WASM_SOURCE_DIR` → scratch `.tmp/test-prebuild/browser-wasm/igloo-pwa/public/wasm` (if exists) → tracked `public/wasm`. If scratch wasm dir exists but is stale (e.g., from a prior incomplete prebuild), the vite dev server and test/shared loaders both consume it without re-checking. repos/igloo-chrome/scripts/build.mjs:86-91 has identical logic. No explicit cache-miss detection between fallback levels.
  - **Impact:** Stale WASM from a partial or failed prebuild can persist in .tmp/ and silently override fresh tracked artifacts. Tests that rely on dev-server WASM (via vite) may load different WASM than tests that inject directly (via test/shared loaders), or may load WASM that drifts from the build-time signed loaders (whose SHA-384 hashes embed stale binaries). This explains the observed PWA-DIST 'Incorrect password' failure: the dist build copied WASM from .tmp/ (which was stale or for a different bifrost-rs commit), the app tried to decrypt a profile prepared with fresh WASM, and SHA-384 validation failed.
  - **Fix:** Implement explicit cache-miss detection: (1) read the test WASM source hash at startup (either via git or embedded); (2) compare against the actual on-disk WASM; (3) fail fast if stale. Alternatively, disable the .tmp/ fallback in test lanes entirely—always use tracked artifacts, and make 'make test-prep' idempotent. Add env-var guards: if FROSTR_TEST_LANE is set, reject fallback resolution. Update vite.config.ts and build.mjs to warn if they fall back to tracked public/wasm (which may not be current).

- **[HIGH] Prebuild cache stamp compares outputs (including dist/) but does not enforce cache hit—check-only exits 0 on stale cache**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** scripts/test-prebuild.sh:488-490 MODE='check' calls check_stamp() and exits. check_stamp() at lines 448-466 compares a freshly rendered state stamp against a saved one. If stale, it prints 'cache stale' to stderr but returns exit code 1. In MODE='ensure' (line 493-498), a check failure triggers sync. But MODE='check' does NOT fall back—it just exits 1. test/shared/test-prebuild.ts:84-95 runs 'check' first, catches the error, then runs 'sync'. However, between the check and sync, the cache directory could be partially populated or concurrent tests could race. Also, 'make test-prep' calls 'release' mode (line 479), which does NOT check the stamp first—it always rebuilds.
  - **Impact:** The 'check' mode is not a reliable gate—it returns nonzero but does not prevent subsequent code from using stale .tmp/ artifacts. Tests that run in parallel may see partially written stamps or dist/ directories. 'make test-prep' bypasses all caching and always rebuilds, which is safe but wasteful. Developers running individual test specs without 'make test-prep' first will silently use stale WASM if the .tmp/ cache is present.
  - **Fix:** Unify check/sync behavior: (1) rename 'check' mode to 'verify' and have it fail hard with actionable error (not exit 1 silently); (2) make 'ensure' the default when targets are specified (auto-rebuild if stale); (3) add a 'FROSTR_TEST_STRICT_PREBUILD=1' env var that enforces rebuild on any stamp mismatch, enabled by test:guards. Update test/shared/test-prebuild.ts to skip the separate check—just call 'sync' with 'ensure' and let it handle cache logic. Lock the stamp file during write to prevent race conditions.

- **[HIGH] WASM stamp (browser-wasm-source.stamp) checks only bifrost-rs WASM crates, not build toolchain or igloo-shared/ scripts**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** test/scripts/check-browser-wasm-stamp.sh:26-37 lists WASM_MODULES paths: bifrost-rs crates (bridge-wasm, profile-wasm, profile, router, signer, codec, core) + Cargo.toml/lock. It does NOT include: (1) /repos/igloo-shared/scripts/build-bridge-wasm.sh (the build orchestrator); (2) /repos/igloo-shared/src/wasm/ (the Rust binding glue); (3) /repos/bifrost-rs/.cargo/config.toml (potential rustc flags); (4) wasm-bindgen / wasm-opt versions in Cargo.lock. A change to any of these without touching the WASM crate source will not invalidate the stamp. The stamp also doesn't capture npm versions (igloo-shared/package-lock.json) which affect the sync/copy behavior.
  - **Impact:** Committed WASM can be silently stale relative to changes in the build pipeline. For example, upgrading wasm-bindgen without bumping bifrost-rs/Cargo.lock would regenerate WASM with different exports, but the stamp would still match the old committed blobs. Tests using test/shared loaders would fail with 'required exports are missing' (bridge-loader.ts:17-30, profile-loader.ts:33-38), but only at runtime during the first WASM load, not during the prebuild.
  - **Fix:** Expand stamp inputs to include: (1) igloo-shared/scripts/build-bridge-wasm.sh SHA; (2) igloo-shared/src/wasm/ tree SHA; (3) Cargo.lock wasm-bindgen/wasm-opt versions; (4) igloo-shared/package.json (not just pwa/chrome). Use a manifest-based approach: compute a single canonical hash of all build inputs (not just bifrost-rs) and store it with the built artifacts. Document the stamp contract as 'input hash covering all WASM source and toolchain'.

- **[MEDIUM] Cross-client WASM scope resolution (browser_wasm_scope) gates PWA-only vs Chrome-only vs all-clients, but test targets don't align with skip-logic**  _(T6 cross-repo inconsistency & T1 silent-lanes/coverage-gaps)_
  - **Evidence:** scripts/test-prebuild.sh:169-179 browser_wasm_scope() returns 'pwa', 'chrome', or 'all' based on which targets are selected. Lines 203-206 show that if shared is selected, all clients are built. PWA-only tests (select pwa-runtime) are built with scope='pwa' (lines 170-171). Chrome-only tests (select chrome-runtime) with scope='chrome'. But test/shared/test-targets.json shows: pwa prebuild=['pwa'], chrome prebuild=['chrome','home','demo']. This means the pwa lane does NOT request shared (so browser_wasm_scope() would select 'pwa'), but chrome lane requests home and demo, which do NOT request browser-wasm. If a chrome-only test is run without the 'shared' target, the WASM scope is 'chrome' but home binary was built—creating cross-client test scenarios with mismatched WASM sources.
  - **Impact:** Cross-client tests (@cross-client) that are triggered by chrome-lane changes will use chrome-scoped WASM, but if they run under PWA context or home context, the WASM may not match. For example, a test that pairs chrome and pwa may build chrome WASM in 'chrome' scope (excluding pwa-specific customizations if any). The wasm-integrity.spec.ts test would pass (it only checks SHA-384), but downstream crypto operations may fail silently or with wrong error messages.
  - **Fix:** Audit and document the WASM scope rules: (1) clarify whether pwa and chrome should ever have different WASM builds (they should not); (2) add a guard in test-prebuild.sh to ensure that if any client targets are selected, 'shared' or an explicit 'all-wasm' is also selected; (3) update test-targets.json so all client lanes request a common 'shared-wasm' target. Make 'scope' determination explicit in targeting logic, not implicit in fallback. Add test coverage: verify that pwa and chrome WASM are byte-identical when built under the same scope.

- **[MEDIUM] Mutating build risk: test-prebuild writes to dist/ but does NOT restore on failure**  _(T5 build/artifact provenance & cache integrity & T7 flake/reliability/cleanup)_
  - **Evidence:** scripts/test-prebuild.sh:500-535 runs sequential build steps. Each step (npm run build:app, cargo build) writes to repos/igloo-*/dist/, src-tauri/target/, or .tmp/test-prebuild. If a step fails mid-way (e.g., npm run build:app fails on TSC), the dist/ directory is left in an inconsistent state (partial JS, stale WASM). The next run of test-prebuild will not rebuild that target (because selected_has() is idempotent and the stamp won't be updated). test/scripts/check-test-prebuild-nonmutating.sh (line 56-58) runs test-prebuild inside check-worktree-unchanged.sh, which snapshots git status before/after. But git status does NOT track dist/ artifacts—it only tracks .gitignored changes. The guard passes even if dist/ is corrupted, as long as no .git changes occur.
  - **Impact:** A failed build leaves dist/ in limbo. The next test run will use the stale/partial dist/ if the stamp hasn't changed (e.g., if the failure was in a non-WASM step like TypeScript compilation). This can manifest as 'Incorrect password' if the dist/ WASM wrapper is outdated but the loader cache is fresh, or as mysterious JS errors if build:app partially succeeded. The nonmutating guard does not catch this.
  - **Fix:** Add a cleanup trap at the start of test-prebuild.sh: before running any build, remove the dist/ directories for selected targets (with a flag to preserve on demand). Alternatively, always run dist/ builds to a temporary directory and atomically swap it in on success. Update check-test-prebuild-nonmutating.sh to verify dist/ content (not just git status) by comparing against a prior known good snapshot. Document the contract: 'test-prebuild either fully succeeds or leaves no side effects; partial builds are not tolerated'.

- **[MEDIUM] WASM injection in tests happens once (via wasmInjected flag in browser-artifacts.ts:78), but no reset between specs—shared module state persists across tests**  _(T2 fixture/seed sprawl & migration debt & T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/shared/browser-artifacts.ts:78-104 ensureInjectedWasmModule() checks wasmInjected flag and returns early on subsequent calls. It calls setInjectedWasmBridgeModuleForTests / setInjectedWasmProfileModuleForTests once. These functions (bridge-loader.ts:33-37, profile-loader.ts:41-45) set module-level state and reset cached instances. But there's no cleanup hook between test specs. If a spec modifies the WASM module state (e.g., by calling a function with side effects), the next spec will inherit that state. Additionally, the loaders load from testBrowserWasmLoaderUrl() (browser-wasm-paths.ts:23-25), which dynamically imports from disk. If a spec changes the FROSTR_TEST_BROWSER_WASM_DIR env var, loaders won't re-resolve—they're cached by promise.
  - **Impact:** Specs that stress the WASM (e.g., rotation, decryption with wrong password, large keyset bundles) may leave the WASM module in an unexpected state. Subsequent specs could inherit this state and fail for non-obvious reasons. The test assumes WASM is deterministic and side-effect-free, which may not hold if the Rust side has internal state (e.g., thread-locals, global counters, or memoization).
  - **Fix:** Add a teardown hook at the global-setup or spec-setup level that calls setInjectedWasmBridgeModuleForTests(null) and setInjectedWasmProfileModuleForTests(null) to reset the state. Document that each spec should be independent w.r.t. WASM initialization. If WASM side effects are observed, either isolate specs or add a 'reset()' function to the WASM API. Consider lazy-loading WASM per-spec instead of globally, so each test gets a fresh instance.

- **[MEDIUM] SHA-384 integrity wrapper (bifrost_*_loader.mjs) is generated at WASM build time but NOT re-generated if WASM is manually synced into dist/ or .tmp/**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** The wasm-integrity.spec.ts (lines 1-12) documents that _loader.mjs wrappers 'embed the SHA-384 of their _bg.wasm'. These are generated by wasm-bindgen (or a post-processing step in bifrost-rs or igloo-shared build scripts). The prebuild calls npm run build:browser-wasm (prepare-browser-wasm.sh:96-110, test-prebuild.sh:506), which rebuilds the binaries AND their loaders. But if WASM is synced via sync_client_wasm (prepare-browser-wasm.sh:128-137), it only copies the .wasm and .js files—it does NOT regenerate the _loader.mjs. If a developer manually copies .wasm files into .tmp/ (e.g., via scp from a build artifact), the loaders will be out of sync. wasm-integrity.spec.ts will fail with 'wasm_integrity_check_failed' even though the WASM is correct.
  - **Impact:** Manual artifact handling or partial syncs can corrupt the SHA-384 chain. Tests fail with cryptic integrity errors rather than clear 'WASM stale' messages. Developers debugging this may spend time on cryptography instead of build provenance.
  - **Fix:** Document the contract clearly: 'SHA-384 loaders must be regenerated whenever binaries change'. Add a guard: if .wasm exists but .js or _loader.mjs is missing, fail with a clear error. Alternatively, embed WASM as part of a single atomic unit (tarball or zip) so loaders cannot be separated from binaries. Consider storing the expected SHA-384 in a manifest file (alongside test-targets.json) so tests can verify before loading.

- **[LOW] Test lane (pwa, chrome, home) targets do not mandate a common baseline WASM version—lanes can diverge**  _(T6 cross-repo inconsistency & T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/shared/test-targets.json shows pwa fastPrebuild=['pwa'], chrome fastPrebuild=['chrome']. But if igloo-shared or bifrost-rs updates WASM, the 'pwa' lane rebuilds WASM targeting pwa only (scope='pwa'), and 'chrome' lane rebuilds targeting chrome only. If the two lanes run in parallel (different CI jobs), they could pull different bifrost-rs commits (if submodule is not pinned to the same ref in git) or use different rustc versions (if CI agents have different toolchains). The wasm-integrity test would catch a tampered WASM, but it would NOT catch a legitimately different WASM built from different source, as long as the SHA-384 wrapper is in sync.
  - **Impact:** Silent WASM version skew: pwa tests use bifrost-rs@commit-A WASM, chrome tests use bifrost-rs@commit-B WASM. Cross-client tests that pair pwa and chrome would use mismatched WASM, potentially causing protocol-level incompatibilities (e.g., different encryption versions, missing fields in serialized formats). The tests might not fail immediately (if both WASMs are 'valid'), but cryptographic operations could diverge.
  - **Fix:** Document the expectation: 'all clients in a test run must use the same bifrost-rs commit'. Add a guard in test-prebuild.sh that prints the bifrost-rs commit hash at startup. For cross-client tests (@cross-client), enforce that both clients' prebuilds used the same commit (store it in the stamp or a manifest). Consider using a 'wasm-version' file at the root that all lanes read, ensuring alignment.

- **[LOW] No explicit connection between test WASM source (test/shared loaders) and dist WASM (app-shipped artifacts)—skew risk is implicit**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** Test loaders (bridge-wasm.ts, profile-wasm.ts) read from testBrowserWasmLoaderUrl() → defaultTestBrowserWasmDir() → .tmp/test-prebuild/browser-wasm or FROSTR_TEST_BROWSER_WASM_DIR. Apps (igloo-pwa, igloo-chrome) load WASM from window.location.origin + '/wasm/' paths, resolved at runtime via window.location (configure-igloo-shared.ts:18-24). In production (dist), the WASM is in repos/*/dist/wasm/ (copied via closeBundle in vite.config or copyWasmAssets in build.mjs). Tests that run against a dev server (vite --host) serve from the vite plugin's wasmSourceDir resolution chain (which may fall back to tracked public/wasm). Tests that run against a built dist/ serve from dist/wasm. The test/shared loaders always use .tmp/, so a dev-server test and a dist test could load completely different WASM. There is no assertion that the test WASM matches the app's WASM.
  - **Impact:** A test passes against the dev server (which loads fresh .tmp/ WASM) but fails against the built dist (which loaded a cached version of WASM from an earlier commit). Developers might blame the app logic when the real issue is WASM provenance. The 'Incorrect password' symptom in the issue description aligns with this: the test fixtures were generated with fresh test WASM, but the PWA dist app loaded stale WASM from dist/.
  - **Fix:** Add a setup step that verifies WASM consistency: (1) in test-setup, compute the hash of all loaded WASM files; (2) record this hash in the test context; (3) compare against a known good hash stored at build time. For specs that target dist (or run against a real server), prepend a verification step: request the WASM URLs, hash them, and fail if they don't match the test expectations. Document the invariant: 'test fixtures and app WASM must be from the same build epoch'.

### CI workflows

- **[HIGH] Silent @cross-client e2e gap: no CI execution of cross-repo pairing tests**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** .github/workflows/release-validation.yml:113-117 gates @live lane only (grep @live); test/package.json:test:e2e:igloo-pwa:live and test:e2e:igloo-chrome:live filter on '@live' regex; test/igloo-pwa/specs/pwa-home-pairing.spec.ts, test/igloo-chrome/specs/chrome-pwa-pairing.spec.ts, chrome-home-pairing.spec.ts, chrome-home-demo-harness.spec.ts all tagged @cross-client are nowhere in CI test surface (grep -r @cross-client .github/workflows/ returns empty). Local: 'npm run test:e2e:igloo-pwa' runs without --grep-invert @cross-client per test/package.json line 23.
  - **Impact:** Cross-client integration failures (chrome<->pwa, chrome<->home, pwa<->home pairing behavior) land undetected in main. These test suites exercise critical shared contracts (relay coordination, profile sync, signing coordination across clients). The @cross-client grep-invert in pwa:fast (line 24) means they're explicitly excluded from fast lane, but nightly release-validation never re-includes them—only @live and @demo.
  - **Fix:** 1) Add explicit cross-client lane to release-validation.yml OR extend @live lane gating to include @cross-client tests (both test:e2e:igloo-pwa + test:e2e:igloo-chrome). 2) Document the reason these tests are excluded from per-PR CI (if intentional) in test/README.md and test/docs/WORKFLOWS.md. 3) Verify which @cross-client suites require demo vs. local relay; assign them to the appropriate nightly tier (test-live or test-demo).

- **[HIGH] @live lane not gated on per-PR CI; only nightly**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** client-scoped-validation.yml lines 70-75 (PWA) and 115-120 (Chrome) run test:guards + test:typecheck + test:e2e:igloo-pwa:fast, but NOT test:e2e:igloo-pwa:live. test:e2e:igloo-pwa:fast uses --grep-invert '@live|@cross-client|@agent' (test/package.json:24). release-validation.yml:117 runs 'make test-live' only on nightly schedule + workflow_dispatch. Makefile:184-185 shows test-live = test:e2e:live (which is @live grep only).
  - **Impact:** Live signer, relay, and runtime integration tests (@live) do not block PR merges. This means onboarding, signing, recovery, and relay connectivity regressions can land undetected. Per test/README.md lines 86-90, the @fast lane is 'render-only' and explicitly not behavioral—green @fast + green @guards can pass while real signing is broken.
  - **Fix:** 1) Decision: does @live need to block every PR, or is nightly sufficient for a stable main? 2) If per-PR: migrate @live from release-validation.yml (nightly-only) to client-scoped-validation.yml, accepting slower per-PR cycles. 3) If nightly-ok: document in CONTRIBUTING.md that @live regressions are caught nightly, not per-PR. 4) Consider a lighter @live smoke variant (single client, single scenario) for per-PR if full @live is too slow.

- **[MEDIUM] No explicit cross-client lane in client-scoped validation; locally run without gating**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/package.json:30 defines test:e2e:igloo-pwa:cross explicitly (--grep @cross-client), and test/README.md:158-162 documents explicit cross-client validation, but client-scoped-validation.yml (the per-PR gate) does not invoke test:e2e:igloo-pwa:cross in any job. test:e2e:igloo-pwa (line 23) runs without --grep-invert @cross-client only in full aggregate; the scoped lane (line 75) runs test:e2e:igloo-pwa:fast which excludes @cross-client (line 24).
  - **Impact:** Cross-client pairing tests exist and can be run locally ('npm run test:e2e:igloo-pwa:cross') but are never invoked in CI. If a developer assumes scoped validation gates the surface, they may miss a regression that breaks pairing (chrome<->pwa, home<->pwa, chrome<->home).
  - **Fix:** 1) Add explicit 'test:e2e:igloo-pwa:cross' invocation to client-scoped-validation.yml's PWA job, or clarify in test/README.md that cross-client pairing is a separate manual lane ('npm run test:e2e:igloo-pwa:cross'). 2) Consider marking cross-client tests with a second tag (@pairing?) if they need to run separately from @live. 3) Alternatively, remove the explicit cross-client command from test/package.json if they are meant to be tested only as @live + @cross-client (both tags) in the nightly lane.

- **[MEDIUM] release-validation.yml runs @live but lacks @cross-client merge**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** release-validation.yml:117 invokes 'make test-live', which runs test:e2e:igloo-pwa:live + test:e2e:igloo-chrome:live (grep @live only, no @cross-client). The @cross-client suites chrome-home-demo-harness.spec.ts, chrome-pwa-pairing.spec.ts, chrome-home-pairing.spec.ts, pwa-home-pairing.spec.ts are not tagged @live alone; some carry multiple tags (@live @cross-client @demo), but test:e2e:igloo-chrome:live would only match @live, leaving dual-tagged @live @cross-client tests in a grey zone depending on Playwright grep semantics.
  - **Impact:** Ambiguity: tests tagged both @live and @cross-client may or may not run in the test:e2e:igloo-*:live lane depending on Playwright's grep matching (likely they DO match 'grep @live'). However, there is no explicit nightly lane that runs @cross-client ALONE. If a test is @cross-client without @live, it is never executed in CI.
  - **Fix:** 1) Audit all @cross-client tests: count how many are also @live (dual-tagged) vs. @cross-client-only. 2) For @cross-client-only tests: either add @live tag if they use a local relay, or add a new explicit test:e2e:cross-client lane to release-validation.yml. 3) Document the tag semantics in test/README.md: clarify whether a test must have @live to run in CI, or whether @cross-client tests are expected to be run manually only.

- **[MEDIUM] Retry/flake handling: none explicit in workflows; Playwright config defaults apply**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** client-scoped-validation.yml, release-validation.yml, workspace-guards.yml do not set 'if: success() || failure()' or retry logic. No explicit --retries flag in Playwright invocations. test/igloo-pwa/playwright.config.ts, test/igloo-chrome/playwright.config.ts (not read, but referenced in test commands) likely set retries in their config. test/README.md line 79-90 documents that @fast is render-only and can pass while behavior is broken, but no mention of retry strategy.
  - **Impact:** Flaky tests are not explicitly retried by the workflow. If a Playwright test flakes once, it fails the CI job. This is conservative (avoids masking real bugs) but may cause false CI failures. Conversely, if tests are configured to retry in their Playwright config, the workflow will wait longer than expected.
  - **Fix:** 1) Audit test/igloo-pwa/playwright.config.ts and test/igloo-chrome/playwright.config.ts for retries settings. 2) Document retry policy in CONTRIBUTING.md: 'Playwright retries are configured in [config file]. If a test flakes intermittently, file a bug and mark it @flaky until fixed.' 3) Consider adding a nightly 'flake dashboard' that re-runs the release matrix 3x and logs which tests fail non-deterministically.

- **[MEDIUM] Coverage gap: @cross-client tests exist but documentation is ambiguous about CI inclusion**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/README.md:158-162 says 'Cross-client validation is explicit: npm --prefix test run test:e2e:igloo-pwa:cross' and lists it as a manual command, not a CI lane. test/docs/WORKFLOWS.md does not mention @cross-client tests at all. client-scoped-validation.yml does not invoke cross-client tests. The implication is that cross-client is manual-only, but 4 suites are implemented and tagged @cross-client, suggesting intent to gate them somewhere.
  - **Impact:** Ambiguity for contributors: reading test/README.md line 158 says cross-client is 'explicit' (manual), but the Makefile has no 'make test-cross-client' entrypoint, and the workflow docs (test/docs/WORKFLOWS.md) do not list it as a test option. A contributor might miss running cross-client tests before pushing, assuming client-scoped validation covers all @cross-client behavior.
  - **Fix:** 1) Clarify in test/README.md and CONTRIBUTING.md: are cross-client tests a manual pre-push gate or part of CI? 2) If manual: add 'make test-cross-client' entrypoint to Makefile (line 23 .PHONY list) and document as 'optional before push' in CONTRIBUTING.md. 3) If CI: move them into client-scoped-validation.yml or release-validation.yml and remove the manual-only wording.

- **[MEDIUM] Silent @cross-client in fast lane: explicitly inverted, not run per-PR**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/package.json:24 test:e2e:igloo-pwa:fast uses --grep-invert '@live|@cross-client|@agent'. test:e2e:igloo-chrome:fast (line 39) uses same invert. These are the lanes run in client-scoped-validation.yml (pwa job line 75, chrome job line 118). So @cross-client tests are intentionally excluded from per-PR fast lane.
  - **Impact:** By design, per-PR validation does not include cross-client pairing tests. This is a deliberate coverage gap—cross-client tests are render-only in fast lane (no live relay), so they would not actually exercise pairing behavior anyway. However, the @live @cross-client tests (those that do run with a relay) are also excluded from per-PR, since test:e2e:igloo-pwa:fast explicitly inverts @cross-client.
  - **Fix:** Clarify in test/README.md line 83-90: add a note that @cross-client tests are excluded from fast lane (per-PR) and require either manual run ('npm run test:e2e:igloo-pwa:cross') or a nightly lane (if added). This resolves ambiguity about whether fast is supposed to cover pairing.

- **[MEDIUM] No explicit demo-pair-check in per-PR CI; only in nightly**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** release-validation.yml:91-92 runs 'make demo-pair-check' (Makefile:156-160, which checks bifrost-rs + igloo-shell compilation with --all-targets). client-scoped-validation.yml does not invoke demo-pair-check. This means per-PR changes to bifrost-rs or igloo-shell may have incompatible test-fixture changes that are only caught nightly.
  - **Impact:** Test-fixture drift between bifrost-rs and igloo-shell (struct literals in igloo-shell tests that reference bifrost-rs structs gaining fields) is not caught per-PR. As per Makefile:152-155, the gate exists to catch this, but only runs nightly. A breaking change to bifrost-rs struct can land, then be caught next morning when demo-pair-check fails.
  - **Fix:** Consider adding demo-pair-check to client-scoped-validation.yml as a fast gate (no actual compilation, just check structure compatibility) OR accept nightly-only for this check with the understanding that it's a rare class of error (bifrost + shell API drift).

- **[MEDIUM] Playwright config: verify test.describe tag matching semantics (and gate grep-invert behavior)**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/package.json uses Playwright --grep and --grep-invert flags. Lines 24, 39 use --grep-invert '@live|@cross-client|@agent' to exclude from fast lane. Lines 29, 40 use --grep @live to include in live lane. Lines 30 and others use --grep @cross-client. Playwright's grep behavior with multiple tags and pipe-delimited patterns needs verification: does 'grep @live' match 'test.describe("... @live @cross-client")'?
  - **Impact:** Uncertainty: if a test is tagged with both @live and @cross-client, 'grep @live' will match it, so it WILL run in the live lane. But 'grep-invert @cross-client' will NOT match it (invert logic is NOT). This is likely correct but depends on Playwright's regex semantics.
  - **Fix:** 1) Run a quick test: create a dummy spec tagged '@live @cross-client' and verify it runs in test:e2e:igloo-pwa:live (should match) and verify 'grep-invert "@live|@cross-client"' DOES match it. 2) Document tag matching semantics in test/README.md: clarify whether multiple tags use AND or OR logic. 3) Consider renaming one of (@live, @cross-client) if they need to be mutually exclusive, or document that they are additive.

- **[LOW] @agent and @visual lanes are render-only tools; correctly excluded from behavioral gating**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/package.json:26 (test:screenshot:pwa) and line 27-28 (test:screenshot:chrome, test:screenshot:home) use --grep @agent. test/igloo-pwa/specs/settings-visual.spec.ts etc. use @visual. Both are excluded from test:e2e:fast (--grep-invert '@live|@cross-client|@agent') and test:e2e (fast + live). test/scripts/check-pwa-visual-manifest.mjs and test/scripts/check-pwa-visual-manifest-negative.sh validate visual metadata.
  - **Impact:** None—these are correctly classified as non-test tools (@agent) or render-only scaffolding (@visual). No behavioral gap.
  - **Fix:** None. Maintain current gating.

- **[LOW] Lean post-2026-06-17 CI cut: demo/release matrix no longer per-PR; correctly scheduled nightly**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** release-validation.yml:1-10 has 'on: schedule (cron 0 7 UTC) + workflow_dispatch'. client-scoped-validation.yml runs on per-PR + push-to-master. release-validation.yml:3 comment: 'Alpha: the full ~60-90 min matrix (Rust tests + @live + @demo + demo-pair-check) no longer blocks every PR. It runs nightly and on demand.'
  - **Impact:** Correctly reduces per-PR CI cycle time. Nightly release matrix (bifrost tests, igloo-shell tests, igloo-home e2e, igloo-chrome demo/live, demo pair-check) runs off-peak. Per-PR gates are lean: guards + typecheck + @fast e2e. This is a deliberate and sound trade-off.
  - **Fix:** None. This is a strong design. Continue monitoring nightly release-validation latency and bisect regressions by rerunning nightly lane on the suspected commit.

- **[LOW] Node 24 actions guard in place; v5 actions enforce modern runner**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** test/scripts/check-workflow-node24-actions.sh checks for v1-v4 actions and rejects them; returns ok for v5+ actions. client-scoped-validation.yml:35,42,87 use actions/checkout@v5, actions/setup-node@v5, dtolnay/rust-toolchain (pinned to stable @ 2026-03-27), Swatinem/rust-cache@v2. release-validation.yml:26,31,47,52 use the same pinned versions (with commit SHAs).
  - **Impact:** Good: Node 24 runner enforcement is in place and validated by CI guards. All pinned actions are v5+, which ship with Node.js 20+.
  - **Fix:** Periodically refresh dtolnay/rust-toolchain pinned SHA (release-validation.yml:47) to pick up new stable Rust toolchain releases; Dependabot or manual quarterly bump.

- **[LOW] BuildKit cache (type=gha) for demo images in nightly lane only**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** compose.ci.yml (lines 14-17, 21-24) defines cache_from/cache_to using type=gha (GitHub Actions BuildKit cache). release-validation.yml:104 sets COMPOSE_BAKE=true when running test-demo, which activates the compose.ci.yml override (test-prebuild.sh:540-546). client-scoped-validation.yml does not set FROSTR_DEMO_COMPOSE_OVERRIDE, so client-scoped PWA/Chrome jobs skip demo compose entirely and build only the pwa-runtime or chrome-runtime targets.
  - **Impact:** Nightly demo builds leverage BuildKit cache; per-PR client scopes skip Docker entirely (client-scoped validation line 70-75 calls test-prebuild.sh ensure pwa-runtime, which builds ui + browser-wasm + pwa-wasm, not docker). This is efficient and correct.
  - **Fix:** None. Cache strategy is sound.

- **[LOW] Caching strategy: action-native npm/cargo caches; prebuild stamps for idempotent rebuilds**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** client-scoped-validation.yml:45-50 (pwa) uses actions/setup-node@v5 cache:npm with cache-dependency-path. release-validation.yml:34-41 caches test + repos npm installs + igloo-home Cargo. test-prebuild.sh:437-471 uses .state stamp files (render_state_stamp) to track input fingerprints and skip re-running prebuild if inputs haven't changed. scripts/test-affected.sh:84-93 deduplicates prebuild targets.
  - **Impact:** Good: npm lockfile-based caching (native to actions/setup-node) + hand-rolled Cargo/Docker caching. Prebuild stamps prevent redundant builds across test runs. test-affected.sh deduplicates targets to avoid re-building pwa-wasm + ui if both PWA and Chrome are affected.
  - **Fix:** Monitor cache miss rates in Actions UI quarterly. If miss rate is high (>30%), consider pre-seeding caches or widening cache-dependency-path scopes (currently per-client, which is tight but may over-invalidate).

- **[LOW] Client-scoped submodule enforcement: guard in place, correctly gates unrelated repos**  _(T6 cross-repo inconsistency)_
  - **Evidence:** test/scripts/check-client-scoped-submodules.sh (lines 17-19) verifies that client-scoped-validation.yml initializes only minimal submodule sets per client. test/README.md:117-127 documents minimal sets. client-scoped-validation.yml pwa job (line 40) initializes 'repos/bifrost-rs repos/igloo-shared repos/igloo-ui repos/igloo-pwa' only. Chrome (line 85) initializes same + igloo-chrome (no igloo-pwa). Home (line 130) initializes 'repos/igloo-shared repos/igloo-ui repos/igloo-home' (no bifrost-rs).
  - **Impact:** None—this is working as intended. Scoped validation does not download or build unrelated clients.
  - **Fix:** None. Continue enforcing via the guard script.

- **[LOW] E2E selector contract enforcement: per-client helpers; no cross-client selector leakage**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/scripts/check-e2e-selector-contracts.sh (lines 8-28) scopes selector imports to per-client support/ui.ts files. PWA specs must not use getByRole('button'), getByLabel, getByPlaceholder, or CSS classes (lines 68-82). Chrome and Home specs can use these (constraint only on PWA per line 68). Enforced in workspace-guards.yml via 'npm run test:guards' which calls 'test:guards:selectors' (test/package.json:16).
  - **Impact:** None—contract is enforced and appears sound. PWA is copy-independent via page objects; Chrome/Home are migrated separately.
  - **Fix:** Monitor whether Chrome and Home specs are migrating away from brittle selectors too; if so, harmonize the constraint across clients.

- **[LOW] Typecheck lanes per-client; strict TypeScript pilot underway for select helpers/visuals**  _(T6 cross-repo inconsistency)_
  - **Evidence:** test/package.json:41-47 runs test:typecheck (pwa + chrome + home + strict-support). test:typecheck:strict-support (line 45) runs strict-helpers + strict-visual-specs. test/README.md:214-219 documents the strict pilot: 'accepts only for sandboxed agent runs where wasm-opt cannot execute.' Strict support is non-blocking (errors are advisory).
  - **Impact:** Solid incremental approach. Strict TypeScript is being adopted in helpers and visual specs without breaking the general pwa/chrome/home typecheck. Non-strict clients can safely ignore strict errors while the pilot runs.
  - **Fix:** Once strict-helpers and strict-visual-specs mature, consider rolling strict into the main test:typecheck lanes per-client (making it mandatory, not a separate :strict-support lane).

- **[LOW] Workspace guards: docs, workflows, shared setup, targets, wasm, selectors, visual all checked per-PR**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** workspace-guards.yml runs 'npm run test:guards' which invokes (test/package.json:7-20) test:guards:docs, test:guards:workflows, test:guards:shared-setup, test:guards:targets, test:guards:wasm, test:guards:selectors, test:guards:visual. Each guard is a bash script under test/scripts/check-*. Guards enforce doc link validity, legacy surface removal, command-surface documentation, test target consistency, browser-wasm harness contracts, selector contracts, and visual manifest shape.
  - **Impact:** Strong gate on silent drift. Guards prevent undocumented surface changes, selector leakage, visual reference rot, and wasm harness breakage from landing undetected.
  - **Fix:** Continue running guards on every PR. Periodically review guard failures to catch new classes of drift (e.g., after major dependency bumps, add a guard to check new CVEs or breaking changes).

- **[LOW] test-affected script: deterministic minimal surface per branch; deduplicates targets**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** scripts/test-affected.sh (lines 8-32) resolves changed files between base (default origin/master) and HEAD. Lines 47-80 map files to test targets (pwa, chrome, home, bifrost, shell, ui, guards, shared). Lines 110-140 deduplicates prebuild targets. Lines 142-206 run targeted tests (repo-scoped cargo tests, browser prebuilds + e2e, etc.). Invoked by 'make test-affected' and workspace-guards.yml line 85 (dry-run check).
  - **Impact:** Excellent: test-affected ensures only changed subsystems are tested, reducing unnecessary CI cycles. Dry-run check in workspace-guards.yml validates that the target resolution logic stays sound.
  - **Fix:** Monitor test-affected latency; if it becomes a bottleneck, consider caching the merge-base calculation or pre-seeding changed file lists via an environment variable (already supported: FROSTR_AFFECTED_FILES, FROSTR_AFFECTED_BASE).

- **[LOW] Prebuild caching: .state stamps prevent redundant Rust + docker rebuilds**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** test-prebuild.sh:444-470 checks and writes .state stamps (input fingerprint + output state). check_stamp() (line 448) compares input fingerprint and output state; if stale, returns 1 and allows rebuild. release-matrix.sh reuses test artifacts via FROSTR_TEST_PREPARED=1 env var and calls test-prebuild.sh at the start (line 77), which caches subsequent runs.
  - **Impact:** Efficient: if inputs (source files, Cargo.lock) haven't changed, rebuilds are skipped. This reduces iteration latency and nightly CI time.
  - **Fix:** Ensure prebuild stamps are stored in scratch (./.tmp/) not tracked paths; continue current practice.

- **[LOW] No retry/backoff for failed CI workflows; hard fail per-PR**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** client-scoped-validation.yml and release-validation.yml use standard GitHub Actions with no explicit 'retry' step or concurrency override for retrying failed jobs. Flaky infrastructure is not automatically retried.
  - **Impact:** Low: per-PR failures are hard-fail, which is conservative and good for stability. Nightly release matrix (scheduled) is not retried either, so flaky nightly tests do require manual re-trigger via workflow_dispatch.
  - **Fix:** None for now. If infrastructure flakes become common (>5% failure rate), add a 'reusable workflow' that retries a job 2x with exponential backoff before failing hard.

- **[LOW] release-matrix.yml runs Rust tests from both repos, but not all repos have CI**  _(T6 cross-repo inconsistency)_
  - **Evidence:** release-matrix.sh:81-95 runs cargo tests for bifrost-rs, igloo-shell, and igloo-home (Tauri). repos/igloo-pwa, igloo-chrome, igloo-ui have no Rust components. However, repos/igloo-shell/Cargo.toml likely has a test suite. Verify: are there unit tests in igloo-shell that should run per-PR?
  - **Impact:** Likely none—igloo-shell unit tests (shell-local CLI tests) probably should not block PWA-only or Chrome-only PRs. Running them nightly is correct.
  - **Fix:** Verify that igloo-shell unit tests are scoped only to igloo-shell changes (test-affected.sh already does this, line 150-155), and that they are not required for cross-client pairing (if they are, consider migrating them to test-affected flow).

- **[LOW] Dry-run affected check in workspace-guards.yml validates test-affected logic**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** workspace-guards.yml:84-85 runs 'FROSTR_AFFECTED_DRY_RUN=1 FROSTR_AFFECTED_FILES='' make test-affected'. This invokes scripts/test-affected.sh with DRY_RUN=1 and empty files, so the script prints the commands that would run instead of running them. Validates that the target resolution logic is sound.
  - **Impact:** Good: catches silent changes to test-affected.sh that would break the automation without actually running tests. This is a lightweight safety check.
  - **Fix:** None. Continue validating test-affected logic in every workspace-guards.yml run.

### Completeness critic: test infrastructure coverage gaps & undocumented surfaces

- **[HIGH] 14 test lanes are undocumented in public manual**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** Comparison of test/package.json (46 commands) vs test/README.md documented lanes shows undocumented commands: test:e2e:igloo-chrome:demo, test:e2e:igloo-pwa:fast, test:e2e:igloo-pwa:live, test:guards:full, test:guards:shared-setup, test:guards:targets, test:igloo-ui-showcase, test:run-sh, test:screenshot (and variants), test:verify, test:visual:report. File: test/package.json lines 6-48.
  - **Impact:** Developers cannot discover or route to legitimate test lanes through documented channels; test:guards:full, test:verify, test:visual:report are used in CI and downstream docs (release-matrix.sh, .agents/skills/), but users find them only via code-diving or agent hints, not documented workflow.
  - **Fix:** Add all 14 undocumented lanes to test/README.md canonical entry points. For internal/debug lanes (test:guards:full, test:run-sh), mark them explicitly as internal with deprecation notes if applicable. Document test:igloo-ui-showcase as a reference-screen harness. Add test:verify (machine-readable gate output) and test:visual:report (Paper-PWA comparison) to test/docs/WORKFLOWS.md visual loop section. Ensure release-matrix.sh comments link to test lane docs.

- **[HIGH] Environment variable contract is undocumented and scattered**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** Environment variables controlling test execution scattered across code: FROSTR_TEST_PREPARED, FROSTR_TEST_LANE, FROSTR_TEST_PREBUILD_DIR, FROSTR_TEST_HARNESS_DIR, FROSTR_DEMO_BINARIES_PREPARED, FROSTR_DEMO_LIVE_REPRO, IGLOO_HOME_TEST_SKIP_BUILD, IGLOO_HOME_TEST_BINARY, IGLOO_PWA_TEST_PORT, IGLOO_HOME_TEST_PORT, DEV_RELAY_PORT, IGLOO_SHELL_DEMO_*, HOST_UID/GID, DOCKER_PLATFORM, FROSTR_TEST_SKIP_STRICT_WASM, FROSTR_BROWSER_WASM_STRICT_TRACKED, and others. No schema or centralized documentation. Files: test/shared/test-prebuild.ts (6-30), compose.test.yml (full), test/igloo-pwa/playwright.config.ts (22, 28-34), scripts/test-affected.sh, test/README.md sparse references.
  - **Impact:** Test configuration is brittle and underdocumented. Agents/users cannot know what env vars control which behavior without reading source. Cross-workspace scripts like test-affected.sh manipulate FROSTR_TEST_PREPARED without broadcasting the contract. Demo-harness env vars (IGLOO_SHELL_DEMO_*) are driven by compose but missing from manual.
  - **Fix:** Create dev/docs/TEST-ENV-VARS.md (or section in test/docs/WORKFLOWS.md) documenting all FROSTR_*/IGLOO_* test environment variables: scope (lane-level, script, demo), default value, when/why to override, validation/guard. Centralize in one source of truth. Cross-reference from test/README.md, dev/docs/WORKFLOWS.md. Add validation guard: test/scripts/check-test-env-vars.sh that spots undeclared env-var usage in test code.

- **[HIGH] Demo-harness services (dev-relay, igloo-demo) lack ownership documentation**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** services/dev-relay/ and services/igloo-demo/ exist in compose.test.yml (26-92) but no README, CLAUDE.md, or ownership statement in test/README.md ownership section (lines 429-436). compose.test.yml references undocumented env-var contracts (IGLOO_SHELL_DEMO_*, DEV_RELAY_EXTERNAL_HOST). Entrypoint scripts exist (services/dev-relay/entrypoint.sh, services/igloo-demo/entrypoint.sh) but are unlinked from docs.
  - **Impact:** Services are de facto black boxes. Changes to service contracts (e.g., new env vars, port logic, health checks) can break test harness silently. Developers maintain services without clear ownership, contract docs, or test-integration guidelines. Health-check logic in compose (lines 82-91) is undocumented.
  - **Fix:** Add services/README.md documenting each service: ownership, environment-variable contract, health-check semantics, integration points with test harness. Link from test/README.md ownership section. Mark services/ as 'test infrastructure owned' in dev/docs/WORKFLOWS.md ownership boundaries. Optionally add services/dev-relay/CLAUDE.md if Rust details warrant separate guidance.

- **[MEDIUM] igloo-ui-showcase test suite is not routable or discoverable**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/igloo-ui-showcase/ directory exists with playwright.config.ts and specs/reference-screens.spec.ts. npm script exists (test/package.json line 22: 'test:igloo-ui-showcase'). Not mentioned in test/README.md canonical entry points (lines 30-59) or any documented lane. No discoverable purpose or routing.
  - **Impact:** Developers cannot discover that igloo-ui showcase tests exist. No clear link between UI component development and the reference-screen harness. Visual iteration workflow (test/docs/WORKFLOWS.md) focuses on PWA @visual specs, not UI showcase.
  - **Fix:** Document igloo-ui-showcase in test/README.md as a reference-screen harness for igloo-ui component verification. Add routing in test/docs/WORKFLOWS.md: when to run, relationship to PWA visual tests, what it validates. Link from igloo-ui's submodule docs if applicable. If it is internal/debug-only, mark and exclude from canonical lane list.

- **[MEDIUM] TypeScript typecheck configuration covers inconsistent scopes and exceeds docs**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** 6 tsconfig files exist: tsconfig.json (base, strict: false), tsconfig.pwa.json, tsconfig.chrome.json, tsconfig.home.json, tsconfig.strict-helpers.json, tsconfig.strict-visual-specs.json. test/README.md documents only first 5 lanes (lines 53-58). No docs explain strict-helpers scope (global.d.ts + shared/**/*.ts + support/**/*.ts + igloo-home/fixtures/**/*.ts), strict-visual-specs scope (subset of PWA screens), or why some files are included/excluded (e.g., pwa-home-pairing.spec.ts is excluded from tsconfig.pwa.json line 15 but included in test:typecheck:pwa via npm script overrides).
  - **Impact:** Typecheck coverage is opaque. Strict pilot may be unfinished or underdocumented (evidence: dev/BACKLOG.md references 'strict TypeScript pilot'). Developers don't know which files are strictly checked, why, or what the migration plan is. Test contracts are implicit in tsconfig includes/excludes.
  - **Fix:** Add test/docs/TYPECHECK.md documenting each tsconfig: coverage scope, strict-mode status, why specific files are included/excluded, migration plan for strict-helpers/strict-visual-specs pilots. Link from test/README.md and dev/docs/WORKFLOWS.md. Align typecheck guards with documented lane contracts.

- **[MEDIUM] Test fixture/setup ownership and versioning is undocumented**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** Fixtures scattered: test/igloo-pwa/support/ (pages.ts, ui.ts, shell-signer.ts, state.ts, deterministic-keys.ts, flows.ts, onboard-diagnostics.ts), test/igloo-chrome/fixtures/ (extension.ts, live-signer.ts, server.ts, constants.ts, types.ts, helpers/*), test/igloo-home/fixtures/ (app.ts, harness.ts). No ownership statement, versioning strategy, or contract documentation. test/shared/ fixtures (test-prebuild.ts, browser-artifacts.ts, test-targets.json) are owned by infra but implicit. Support modules are checked under strict-helpers typecheck (tsconfig.strict-helpers.json line 14) without being marked as part of the fixture contract.
  - **Impact:** Fixture evolution is ad hoc and untracked. Changes to support/ or fixtures/ modules can break multiple test lanes without visible tracing. No clear deprecation or migration path for fixture changes. strict-helpers pilot conflates shared helpers with test fixtures without clear boundaries.
  - **Fix:** Add test/docs/FIXTURES.md documenting fixture scopes: test/shared/* (infra-owned test harness and configuration), test/igloo-*/support/* (client-scoped page objects and helpers), test/igloo-*/fixtures/* (Playwright fixture definitions). Mark ownership, versioning strategy, breaking-change protocol, and links to guard contracts. Consider promoting fixtures to first-class documented surfaces with versioning.

- **[MEDIUM] Design-token handoff (igloo-paper → igloo-ui) is undocumented in test context**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** dev/scripts/sync-igloo-paper-tokens-to-ui.mjs exists and is routed via make igloo-ui-paper-token-sync / make igloo-ui-paper-token-check (Makefile 266-270). Documented in dev/docs/DESIGN.md and Makefile help, but not in test infrastructure docs or WORKFLOWS. Has no guard in test/package.json, no test:guards entry, no test lane routing. test/package.json test:guards does not include token-sync validation.
  - **Impact:** Token-sync is gated outside the test harness. igloo-ui design tokens can drift from Paper without test detection if a developer forgets make igloo-ui-paper-token-check. The script is not discoverable from test/README.md or test/docs/WORKFLOWS.md, so developers following test-lane docs alone may miss the handoff.
  - **Fix:** Add test/scripts/check-igloo-ui-paper-tokens.sh guard that runs make igloo-ui-paper-token-check and fails if tokens are stale. Integrate into test:guards (via test:guards:docs or new test:guards:tokens lane). Document in test/docs/WORKFLOWS.md under design-token handoff section. Ensure Makefile routes are visible from test docs.

- **[MEDIUM] Home E2E runner has separate screenshot config and undocumented Tauri/xvfb fallback**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/igloo-home/run-e2e.sh is a custom runner that detects DISPLAY/WAYLAND_DISPLAY and falls back to xvfb-run. test/igloo-home/playwright-screenshot.config.ts (separate from playwright.config.ts) serves the home web frontend via vite for headless screenshots. test/README.md lines 39-41 mention 'igloo-home' E2E but do not explain the Tauri-specific runner, screenshot-only config, or xvfb fallback logic. Comments in playwright-screenshot.config.ts (lines 10-16) document the seam but it is not routed from test docs.
  - **Impact:** Developers working on home E2E or CI debugging cannot understand why test:e2e:igloo-home uses run-e2e.sh instead of playwright directly, or why make screenshot CLIENT=home uses a different playwright config. Tauri-specific constraints (Xvfb requirement, vite server setup, visual scenario seam) are buried in code comments.
  - **Fix:** Document igloo-home E2E runner and screenshot config in test/docs/WORKFLOWS.md or test/README.md igloo-home section. Explain Tauri E2E path (runs actual Tauri app), screenshot-only path (headless vite render with visual-scenario seam), xvfb fallback on headless CI. Link to run-e2e.sh logic. Add guard: test/scripts/check-igloo-home-test-setup.sh validates Tauri binary, vite server config, xvfb setup if running headless.

- **[MEDIUM] Demo-harness smoke lane has no routing from test infrastructure docs**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/scripts/test-demo-harness-onboard.sh implements the 'smoke' tier (test/README.md lines 80-82: validation of Docker-backed demo harness and local host onboarding path). npm script exists (test/package.json line 33: 'test:e2e:smoke'). Routed via make test-smoke (Makefile line 178). test/README.md describes it (lines 80-82) but test/docs/WORKFLOWS.md makes no mention of when to run test-smoke, how it differs from test-demo, or when to escalate from smoke to live/demo.
  - **Impact:** test/docs/WORKFLOWS.md lane-selection guide (lines 6-19) does not include smoke tier routing, so developers unsure whether to run test-smoke or test-demo locally may skip it or run the wrong one.
  - **Fix:** Add smoke-lane routing to test/docs/WORKFLOWS.md lane-selection section: 'Demo-harness changes: run test-smoke (Docker onboarding validation) for basic demo stack checks, or test-demo for full integration.' Link test/README.md smoke tier description.

- **[LOW] Cross-client test pairing specs lack coordination documentation**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** Cross-client specs exist: test/igloo-pwa/specs/pwa-home-pairing.spec.ts (@cross-client), test/igloo-chrome/specs/chrome-home-pairing.spec.ts (@cross-client, @demo), test/igloo-chrome/specs/chrome-pwa-pairing.spec.ts (@cross-client), test/igloo-chrome/specs/chrome-home-demo-harness.spec.ts (@cross-client, @demo). test/README.md documents test:e2e:igloo-pwa:cross (lines 158-161) but does not explain coordination: which specs are paired, why some use @demo tag, whether they require specific fixture setup, how to run them in isolation.
  - **Impact:** Developers working on cross-client changes may not know which paired specs to validate. @demo-tagged cross-client specs may have different demo-harness setup requirements that are implicit.
  - **Fix:** Add cross-client coordination section to test/docs/WORKFLOWS.md: document paired specs, @demo tags, fixture requirements, when to run paired vs. solo lanes. Link from test/README.md cross-client section.

- **[LOW] Test guards are not consistently gated or verified in CI**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** 24 guard scripts exist in test/scripts/check-*.sh. test/package.json test:guards aggregates them (line 7), but test:guards:full (line 8) is not run in release-matrix.sh or verify.sh. dev/BACKLOG.md references 'nightly test:guards:full' but no CI routing is visible in release-matrix.sh (scripts/release-matrix.sh lines 77-128 run individual guards, not test:guards:full). No evidence that test:guards:full is run in GitHub Actions or documented as nightly.
  - **Impact:** Comprehensive guard coverage (test:guards:full) is not consistently validated. Some guards may be stale or fail without being caught by CI. No clear owner or schedule for full guard suite.
  - **Fix:** Document which guards run in CI vs. local vs. nightly. If test:guards:full is nightly-only, make that explicit in dev/docs/WORKFLOWS.md and comment in test/package.json. Otherwise, integrate into release-matrix.sh or verify.sh as applicable. Audit and mark guards as PR-gating, nightly, or optional.

### Fixtures & Seeding

- **[HIGH] No enforcement that fixture seeds match runtime persistence contract**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** PwaStoredProfileSeed in test/shared/browser-artifacts.ts:42-76 includes fields like runtime_snapshot_json, onboarding_package, peer_pubkey that are not in PROFILE_ALLOWED_KEYS per repos/igloo-pwa/src/lib/persist-allowlist.ts:38-56. buildPwaPersistedState and applyPwaSeed do not validate against the allowlist. There is no automated check that seeds only include persistable fields.
  - **Impact:** Test fixtures can seed non-persisted fields, creating false confidence that seeding works. If app persistence logic changes, tests that relied on non-persisted fields will fail silently (the field is written to the seed, discarded by applyPwaSeed, lost on reload). The test contract diverges from the runtime contract with no warning.
  - **Fix:** Create a validation function validateSeedAgainstAllowlist(profile: PwaStoredProfileSeed, allowedKeys: PERSISTABLE_PROFILE_KEYS) that runs in buildPwaPersistedState and in createPwaStoredProfileSeed. Add a type-level contract: export a PersistableStoredProfile type from persist-allowlist.ts and use it in buildPwaPersistedState, so TypeScript enforces the contract at fixture definition time. Document the rule: anything seeded via storage fixtures must be in PERSISTABLE_PROFILE_KEYS or it will not survive a page reload.

- **[MEDIUM] runtimeSnapshot seeded in test fixtures but intentionally non-persisted in app**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-pwa/support/state.ts:81-151 buildPwaPersistedState accepts and returns runtimeSnapshot; test/igloo-pwa/specs/permissions-visual.spec.ts:95 and settings-visual.spec.ts:84 seed it via buildPwaPersistedState; but applyPwaSeed (line 57-79) discards it when writing to localStorage. repos/igloo-pwa/src/lib/persist-allowlist.ts:38-56 PROFILE_ALLOWED_KEYS excludes runtimeSnapshot; persist-allowlist comment (line 18-20) explicitly states runtime snapshots with secrets must never be persisted. Per page-runtime-host.ts, runtimeSnapshotJson is intentionally NOT surfaced on the persisted session.
  - **Impact:** Visual test fixtures build runtimeSnapshot expecting persistence that never occurs. If app code ever migrates to direct persistence, or if seeding logic changes, these fixtures would silently fail to initialize the expected state. runtimeSnapshot field in buildPwaPersistedState is dead code for persistence (only used in-memory via dev-scenario.ts).
  - **Fix:** Clarify buildPwaPersistedState return type: split it into persistableState (what is actually stored) vs fullState (what includes transient fields like runtimeSnapshot). Document that runtimeSnapshot is in-memory-only and must be seeded separately via dev-scenario.ts or a dedicated in-memory bootstrap helper, not via localStorage. Remove runtimeSnapshot from the PwaStoredProfileSeed type or mark it explicitly as non-persisted.

- **[MEDIUM] peerPermissionStates in test seeds but excluded from persist-allowlist, no hydration path**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-pwa/support/state.ts:87 buildPwaPersistedState accepts peerPermissionStates; test/igloo-pwa/specs/permissions-visual.spec.ts:96 seeds peerPermissionStates via the builder; but repos/igloo-pwa/src/lib/persist-allowlist.ts:31-35 explicitly documents peerPermissionStates as OMITTED and runtime state, not durable config. applyPwaSeed does not write peerPermissionStates to either store.
  - **Impact:** Test fixtures accept a parameter that is silently discarded. Visual test harness expects seeded peer states but they don't hydrate. This creates a contract mismatch: tests appear to set up peer state but the app rebuilds it live from the runtime, not from storage.
  - **Fix:** Remove peerPermissionStates parameter from buildPwaPersistedState. If visual tests need to mock peer state, use a dev-scenario-only helper or in-memory bootstrap, not storage seeding. Document the policy: peer permission states are runtime state tied to the active session, not persisted config.

- **[MEDIUM] Legacy PWA storage keys still referenced in live test specs, migrated in app**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-pwa/support/state.ts:14 exports PWA_STORAGE_KEY ('igloo-pwa.state.v2'); test/igloo-pwa/specs/permissions.spec.ts:36 and settings.spec.ts:30 scan localStorage for keys starting with 'igloo-pwa.state.v2' to verify persisted overrides; repos/igloo-pwa/src/lib/migrate-global.ts:23-26 defines LEGACY_STATE_PREFIX and LEGACY_PARTITIONED_PREFIX, confirming the split from pre-2026-06-16 (state.v2::*) to post-split (igloo-pwa.profiles.v1 + igloo-pwa.session.v1::*).
  - **Impact:** Test specs use legacy key prefixes to verify persistence across reloads. The app migrates these keys on first boot (importLegacyProfilesOnce) but tests that manually scan for 'igloo-pwa.state.v2' are brittle: they will fail if the migration completes before the assertion, or if the legacy keys are deleted. The test harness is not exercising the real two-store model; it is asserting against intermediate/transient state.
  - **Fix:** Update permissions.spec.ts and settings.spec.ts to scan the new storage keys (igloo-pwa.profiles.v1 for profiles, igloo-pwa.session.v1::* for session state). Create a test helper persistedHasProfileOverride that searches the actual persisted global + session stores, not the legacy partition. This decouples test assertions from the migration layer and ensures tests verify the post-split schema.

- **[MEDIUM] Duplicated seed profile builders across Chrome and PWA test harnesses**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/igloo-chrome/fixtures/helpers/seed-profile.ts:26-74 buildSeedProfile builds a LocalProfileBlobPayload for extension profiles. test/shared/browser-artifacts.ts:358-402 createPwaStoredProfileSeed builds a PwaStoredProfileSeed from a GeneratedBrowserShareArtifact. test/igloo-pwa/support/state.ts:81-151 buildPwaPersistedState wraps PwaStoredProfileSeed arrays into app state. Each takes a different input shape and produces a different output shape, despite modeling the same domain concept (a persisted profile + signer settings).
  - **Impact:** No single source of truth for profile seed semantics. Adding a new profile field (e.g., a new signer setting) requires updates in three places, with no central contract. Tests importing cross-client (chrome-pwa-pairing.spec.ts) must manually map between the three types, increasing coupling and error surface.
  - **Fix:** Consolidate around a single seed builder interface. Define a unified ProfileSeedInput (independent of storage schema) and builders for each target (extensionBlobPayload, pwaStoredProfileSeed). Share signer settings defaults (DEFAULT_SEED_SIGNER_SETTINGS) and profile initialization logic. This reduces duplication and makes it explicit when a new field must be propagated.

- **[MEDIUM] applyPwaSeed discards unlisted fields silently; no validation that seed payload is used**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-pwa/support/state.ts:57-79 applyPwaSeed hardcodes which fields to write to each store (lines 61-78); any fields in payload.state not explicitly written are silently discarded. buildPwaPersistedState constructs state with runtimeSnapshot, peerPermissionStates, unlockPhrase, generatedKeyset, etc. that are not passed to applyPwaSeed.
  - **Impact:** Seeds can include fields that are never applied. If a test author adds a field to buildPwaPersistedState expecting it to hydrate on page load, it silently fails. The function signature implies that the entire state blob is seeded, but only a subset is actually persisted.
  - **Fix:** Explicitly type applyPwaSeed to accept only PersistableGlobalState + PersistableSessionState (the actual storable shapes), not a full PwaPersistedState. Split buildPwaPersistedState into two helpers: buildPersistableState (what gets seeded) and buildFullAppState (what includes transient runtime state). This makes the contract explicit at the type level and prevents accidental dead seeding.

- **[LOW] Password constant defined in three places with different scopes**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/shared/browser-artifacts.ts:20 DEFAULT_BROWSER_PASSWORD = 'playwright-passphrase'. test/igloo-chrome/fixtures/helpers/seed-crypto.ts:5 PASSWORD = 'playwright-passphrase'. test/igloo-chrome/specs use hardcoded 'playwright-passphrase' (e.g., dashboard.spec.ts:184). test/igloo-pwa/specs also hardcode 'playwright-passphrase' (e.g., create-keyset.spec.ts:38, 59).
  - **Impact:** Three independent copies of the same constant. A test that seeds a profile with DEFAULT_BROWSER_PASSWORD and then unlocks it with a hardcoded string works only by accident. If the constant ever needs to change (e.g., for security policy), three updates are required and some may be missed.
  - **Fix:** Export the password constant from test/shared/browser-artifacts.ts and import it everywhere. Or create a test/shared/test-passwords.ts module with all password/passphrase test secrets. This centralizes the contract and makes it visible when secrets are being replicated.

- **[LOW] Legacy PWA_INSTANCE_REGISTRY_KEY not cleaned up in test harness constants**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-pwa/support/state.ts:15 exports PWA_INSTANCE_REGISTRY_KEY ('igloo-pwa.instances.v1'); repos/igloo-pwa/src/lib/migrate-global.ts:26 defines LEGACY_REGISTRY_KEY with the same value and only references it during migration cleanup. This key is no longer written by the app post-split.
  - **Impact:** Test constants export a key that has no active use post-migration. Any new test code that uses it (e.g., assuming registry structure) will be working with an orphaned schema. The constant is a vestigial interface.
  - **Fix:** Move PWA_INSTANCE_REGISTRY_KEY to test/igloo-pwa/support/legacy-keys.ts or similar, with a comment marking it as migration-only. Keep DEFAULT exports lean: export only the active keys (PWA_GLOBAL_STORE_KEY, PWA_SESSION_STORE_KEY, PWA_INSTANCE_ID_KEY, pwaSessionKey, pwaPartitionKey). This clarifies the active contract.

### Flake, isolation & cleanup

- **[MEDIUM] Port allocation collision risk: overlapping relay port ranges**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/shared/local-relay.ts:7 randomRelayPort() returns 24000-44000; test/igloo-chrome/fixtures/helpers/context.ts:12-14 and demo-harness.ts:12-14 both use fixed DEMO_RELAY_PORT = 43000 + (pid % 1000), creating overlap in 43000-44000 range. Two concurrent test workers could collide if both independently start local relays and the demo harness on same machine.
  - **Impact:** Port bind failures causing test hangs/timeouts, orphaned relay processes if startup fails partway through, cascading test failures in parallel CI environments (though current workers=1 mitigates).
  - **Fix:** Unify port allocation to a single source-of-truth function that respects both local-relay and demo-relay needs, or allocate deterministically from OS (net.createServer + listen(0) like igloo-home/fixtures/app.ts:25-45).

- **[MEDIUM] Local relay double-close vulnerability**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/igloo-pwa/specs/dashboard-states.spec.ts:100-109 documents defensive workaround: 'The test closes the relay during the all-relays-offline step. Don't re-close: the local relay is SIGKILLed (no clean SIGTERM exit), leaving exitCode null, so a second close() awaits an exit that never re-fires.' The close() method (test/shared/local-relay.ts:65-87) doesn't guard against double invocation when exitCode is null after SIGKILL.
  - **Impact:** Specs that close relay early (as intended) must manually track state to avoid hanging in finally block. Risk of forgotten guard causing test timeout. Pattern is not enforced by API, only by documentation.
  - **Fix:** Make LocalRelayHandle.close() idempotent: check child.killed or store internal closePromise to avoid double-waiting on 'exit' event. Or expose a nonBlockingKill() variant for early-close scenarios.

- **[MEDIUM] Missing global teardown for orphaned bifrost-devtools relay processes**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/shared/local-relay.ts spawns bifrost-devtools relay binary as child process. No global Playwright afterAll() hook or process.on('exit') handler registered to SIGKILL any orphaned relays if test suite itself crashes. Browser-artifacts.ts and observability.ts have no process-level cleanup registration.
  - **Impact:** If a spec hangs or Playwright crashes, relay processes remain running on the allocated ports, blocking subsequent test runs on the same machine (observed in your comment: 'orphaned bifrost-devtools relay processes after Playwright runs').
  - **Fix:** Add a global-setup or beforeAll hook that registers process.on('exit') to enumerate and kill any orphaned bifrost-devtools relays by name (ps -ef | grep bifrost-devtools) or maintain a registry of spawned pids.

- **[LOW] Chrome extension context cleanup swallows Playwright artifact errors**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/igloo-chrome/fixtures/extension.ts:62-79 disposeExtensionContext() catches and logs-then-ignores ENOENT errors for artifact paths (playwright-artifacts-, recording, .zip) but still attempts rm -rf on userDataDir afterward. If Playwright's artifact cleanup is incomplete, the rm may fail silently.
  - **Impact:** Stale userDataDir entries accumulating in /tmp/igloo-chrome-pw-* if repeated failures; not a runtime failure but cleanup hygiene issue.
  - **Fix:** Ensure artifact errors are logged at WARN level (already done via logE2E), and consider a post-test audit script that validates /tmp/igloo-chrome-pw-* entries are cleaned after test completion.

- **[LOW] Desktop (igloo-home) process termination: hard 5-second timeout may be insufficient**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/igloo-home/fixtures/app.ts:178-182 waitForExit() uses 5-second hard timeout: 'child.once(exit) → resolve after 5s' with no escalation to SIGKILL if process doesn't exit cleanly. If igloo-home is under load or has pending I/O, SIGTERM may not be honored within 5s.
  - **Impact:** Under resource contention, the harness.close() call may complete before the binary fully exits, potentially leaving zombie processes or interfering with subsequent test's port allocation.
  - **Fix:** Implement graceful escalation: SIGTERM with 5s wait, then SIGKILL if still alive, then wait for final exit (as local-relay.ts does at lines 72-78).

- **[LOW] Live signer fixture: responder state snapshot/restore couples teardown to next test**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/igloo-chrome/fixtures/live-signer.ts uses SharedLiveSignerController for worker-scoped (@file fixture). On resetForTest(), it captures shell state snapshot (copy of XDG dirs), then on next use restores from that snapshot. If a test crashes before completing resetForTest(), the snapshot is stale, causing subsequent test to start with incorrect responder state.
  - **Impact:** Subsequent @live specs using the same live-signer fixture may inherit stale nonce pools or peer state from a failed predecessor, causing mysterious failures or timeouts in relay handshakes.
  - **Fix:** Add a pre-reset verification step that validates the snapshot is fresh (e.g., mtime within test-window) or log a warning if restoring from stale snapshot. Consider making snapshot capture happen after daemon fully stops, not concurrently.

- **[LOW] No integration contract for test setup/teardown sequencing across fixtures**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** Three separate fixture hierarchies (igloo-chrome: context → extension setup, igloo-pwa: page → relay setup, igloo-home: app harness) each manage their own lifecycle. test/shared/test-prebuild.ts tracks prepared targets via environment variable but does not enforce or document fixture dependency ordering (e.g., what happens if liveSignerWorker is used before demo binaries are prepared).
  - **Impact:** Risk of subtle ordering bugs if fixture setup changes (e.g., demo binaries prepared asynchronously but spec immediately tries to start demo harness).
  - **Fix:** Document fixture lifecycle contract in test/README.md or add a fixture dependency graph validation script. Ensure test-prebuild dependency tree is enforced before fixture use.

- **[LOW] Selector/DOM contract enforced only in CI; no pre-commit enforcement**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/scripts/check-e2e-selector-contracts.sh polices test-id imports (must be in support/ui.ts only) and forbids direct getByTestId in specs. Run in 'npm run test:guards' (gated by CI forbidOnly), but not in pre-commit hooks or on every developer build. igloo-pwa specs must route through page objects, but the check doesn't run locally by default.
  - **Impact:** Developers can commit selector changes in specs without knowing they've violated the contract, catching issues only in CI (10-15 minute delay).
  - **Fix:** Add test/scripts/check-e2e-selector-contracts.sh as a git pre-commit hook (if tooling supports it) or reference it in a local .claude/pre-hooks.sh for the Claude Code harness.

- **[LOW] Browser timer throttling workaround insufficient for relay loop; no fallback described**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** test/igloo-pwa/playwright.config.ts:23-34 documents launchOptions disabling background timer throttling: '--disable-background-timer-throttling' + '--disable-backgrounding-occluded-windows'. Comment states it 'did NOT resolve the sign-shell partial-sign round-trip, which is a browser responder gap, not throttling (see dev/BACKLOG.md).' This suggests the workaround is incomplete.
  - **Impact:** Long @live specs on headless Chromium may still stall the websocket/relay loop if Playwright window becomes occluded for other reasons, causing sign timeouts.
  - **Fix:** Add a fallback heartbeat timer in the PWA runtime pump (or Playwright host) that pings the relay periodically to keep the loop awake, independent of browser tab visibility.

### Per-submodule test suites & parent invocation

- **[HIGH] igloo-chrome unit tests (5200+ LOC) orphaned from PR gate**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** repos/igloo-chrome/package.json defines 'test:unit'; .github/workflows/client-scoped-validation.yml (chrome job, line 115-120) runs test:guards:chrome + test:typecheck:chrome + build, never runs test:unit. test-affected.sh (line 200-205) invokes test:e2e:igloo-chrome only when run_chrome=1 (path change), never test:unit. Release-matrix.sh (line 101-131) also omits igloo-chrome test:unit. repos/igloo-chrome/tests/unit/ contains 24 vitest spec files (5201 total LOC).
  - **Impact:** Regressions in igloo-chrome background logic, services, and components land undetected in PRs. Unit test failures only surface in post-merge or nightly runs. Chrome-specific features (runtime-service, onboarding-service, permission-service, profile-service, state-projector) lack pre-PR coverage.
  - **Fix:** Add 'npm --prefix repos/igloo-chrome run test:unit:raw' to client-scoped-validation.yml chrome job after typecheck (line 119). Ensure test-affected.sh calls test:unit when run_chrome=1. Update test:guards:chrome to include unit test invocation or create a separate test:unit:chrome target.

- **[HIGH] igloo-pwa unit tests (2300+ LOC) never invoked from parent harness**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** repos/igloo-pwa/package.json defines 'test:unit'; .github/workflows/client-scoped-validation.yml (pwa job, line 70-75) runs test:guards:pwa + test:typecheck:pwa + test:e2e:igloo-pwa:fast, never test:unit. test-affected.sh (line 192-198) calls test:e2e:igloo-pwa only, not test:unit. repos/igloo-pwa/test/frontend/ has 6 vitest files (2317 LOC). Release-matrix.sh also omits igloo-pwa test:unit.
  - **Impact:** Regressions in igloo-pwa app logic (dashboard-view, clear-session-logs, onboard-persist, instance-storage, session-controller) only surface after merge or during nightly runs. Unit test failures are invisible in the PR gate.
  - **Fix:** Add 'npm --prefix repos/igloo-pwa run test:unit:raw' to client-scoped-validation.yml pwa job after typecheck. Update test-affected.sh to call test:unit when run_pwa=1. Include test:unit in test:guards:pwa or create a separate invocation.

- **[HIGH] Bifrost-rs and igloo-shell unit tests only in nightly, not PR gate**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** .github/workflows/client-scoped-validation.yml (pwa/chrome/home jobs) never initializes bifrost-rs or igloo-shell submodules, never runs cargo test. Release-matrix.sh (line 81-96) runs 'cargo test --manifest-path repos/bifrost-rs/Cargo.toml --workspace' + igloo-shell tests, but only on nightly/manual dispatch. scripts/test-affected.sh (line 142-156) conditionally runs bifrost/shell tests only if those repos are modified. Makefile has no 'test-rust' or 'test-bifrost' target.
  - **Impact:** Regressions in bifrost-rs signer logic (bifrost-signer, bifrost-router, bifrost-profile, bifrost-codec) and igloo-shell CLI can land in master without PR-time detection. Fixes only surface in nightly runs, delaying feedback.
  - **Fix:** Create a lean cargo test lane (e.g., 'cargo test --manifest-path repos/bifrost-rs/Cargo.toml --lib' excluding integration tests) and invoke it in client-scoped-validation.yml. Alternatively, ensure bifrost changes trigger test-affected.sh with run_bifrost=1. Add Makefile targets: 'test-bifrost' (lib tests) and 'test-shell' (CLI tests).

- **[MEDIUM] igloo-shared unit tests skipped, only typecheck runs**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** repos/igloo-shared/package.json defines 'test:unit: vitest run'; test-affected.sh (line 158-164) calls only 'npm --prefix repos/igloo-shared run test:typecheck', never test:unit. Release-matrix.sh (line 97-99) also calls only test:typecheck. Client-scoped-validation.yml does not directly invoke igloo-shared tests.
  - **Impact:** Core runtime and wire-protocol logic in igloo-shared (runtime-api, runtime-projections, wasm-bridge-node, relay-transport, rotation, onboarding-transport, nip44-interop) lacks unit test coverage in PR and nightly gates.
  - **Fix:** Update test-affected.sh to call 'npm --prefix repos/igloo-shared run test:unit' when run_shared=1 (line 158). Add igloo-shared test:unit to client-scoped-validation.yml or ensure test-affected.sh is always invoked during guards.

- **[MEDIUM] Inconsistent unit test invocation across submodules (framework & naming mismatch)**  _(T6 cross-repo inconsistency)_
  - **Evidence:** igloo-ui: 'npm test' (runs vitest); igloo-shared: 'npm run test:unit' (vitest); igloo-chrome: 'npm run test:unit' (vitest with prepare:workspace); igloo-pwa: 'npm run test:unit' (vitest with prepare:workspace); igloo-home: 'npm test' (typecheck + vitest); bifrost-rs: 'cargo test'; igloo-shell: 'cargo test'. Parent harness calls different targets per repo (test vs test:unit vs test:typecheck). Client-scoped-validation.yml does not standardize.
  - **Impact:** Developers must remember which repo uses which command (test vs test:unit). Maintenance burden: changes to unit test runner require updates across multiple Makefile targets and CI workflows. Harder to automate unit test coverage metrics.
  - **Fix:** Standardize on 'npm run test:unit' for all JS repos (rename igloo-ui/igloo-home 'test' to 'test:unit'). Create a root-level Makefile target 'test-units' that invokes all submodule unit tests. Add a test/scripts/check-unit-tests.sh guard that validates all submodules define test:unit.

- **[MEDIUM] Duplication: test-affected.sh reimplements target mapping (should use test-targets.json)**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/shared/test-targets.json (line 3-19) defines client->path mappings and prebuild targets (pwa, chrome, home only). scripts/test-affected.sh (line 48-79) has inline path-to-client dispatch logic (case statement), distinct from test-targets.json. test-affected.sh also maintains run_bifrost, run_shell, run_shared flags (not in test-targets.json), diverging from the source of truth.
  - **Impact:** Changes to client path detection must be made in both places; risk of drift. New clients or test lanes require editing shell script instead of updating JSON manifest. Harder to verify coverage.
  - **Fix:** Extend test-targets.json to include bifrost, shell, shared as special 'platforms' with path patterns and test commands. Update test-affected.sh to load and iterate test-targets.json instead of hardcoded cases. Create a lib (lib-test-targets.sh already exists) that centralizes target resolution.

- **[MEDIUM] Test lane names obscure what runs: 'test:guards' includes e2e, typecheck omitted from verify**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/package.json: 'test:guards: targets && wasm' + 'test:guards:full' calls test-run-sh.sh + test-igloo-home-run-e2e.sh + test-affected.sh (line 8). 'test:verify' calls 'test:guards && test:typecheck && test:e2e:fast' (line 9). Makefile: 'make verify' calls 'scripts/verify.sh' (does not directly call test:guards or test:verify, but wraps them). Client-scoped-validation.yml: Chrome calls 'test:guards:chrome' which includes test-affected.sh, which conditionally runs e2e, conflating guards and e2e.
  - **Impact:** Unclear what 'verify' covers (guards + typecheck + e2e:fast, but not all unit tests). 'test:guards' name misleading: it runs more than structural guards (includes full test-affected.sh). Harder to document, harder for developers to know what to run locally before pushing.
  - **Fix:** Rename: 'test:guards' -> 'test:structural' (structural checks only); 'test:guards:full' -> 'test:all'. Redefine 'verify' to include 'test:unit' targets for all affected submodules. Create a 'test:pr-gate' target that matches CI's client-scoped-validation lane. Document each lane in test/README.md with explicit coverage matrix.

- **[MEDIUM] No parent-level Makefile target for unit tests; test-affected.sh is single invocation point**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** Makefile (lines 16-30) has test-smoke, test-fast, test-live, test-demo, test-e2e, test-prep, test-affected, test-release, verify. None invoke 'make igloo-*-test-unit'. Client-scoped-validation.yml does not call any Makefile targets for unit tests. test-affected.sh is the only shell script that dispatches to submodule unit tests (lines 158-189), but only if changed_files match a path.
  - **Impact:** Developers must use test-affected.sh or remember which 'npm run test:unit' to run per repo. No Makefile target to 'make test-units' or 'make test-unit-all'. Harder to parallelize unit tests or integrate into CI lanes that don't use test-affected.sh.
  - **Fix:** Add Makefile targets: 'test-units' (all submodule unit tests), 'igloo-*-test-unit' (per-repo). Ensure client-scoped-validation.yml invokes 'make test-units' or 'npm run test:units' lane in test/. Update verify.sh to include unit tests.

- **[LOW] igloo-home test layout split: unit tests in test/frontend, e2e in test/desktop & test/visual**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** repos/igloo-home/ has: src/test/ (empty?), test/frontend/ (5 vitest files), test/desktop/ (run.mjs for playwright desktop tests), test/visual/ (visual regression tests). igloo-home/package.json defines test:unit (runs vitest), test:desktop (runs run.mjs), test:visual (runs run.mjs). test-affected.sh (line 176-189) calls test + test:visual + test:e2e:igloo-home, conflating unit, visual, and e2e.
  - **Impact:** Test structure is non-obvious: unclear if src/test/ should exist, unclear which tests run where. test:desktop and test:visual use .mjs runners (igloo-home/test/desktop/run.mjs, test/visual/run.mjs), diverging from vitest convention. Harder to onboard contributors, harder to ensure all tests run in CI.
  - **Fix:** Clarify igloo-home test layout: consolidate unit tests (vitest) into test/ or src/test/. Move desktop and visual runners to test/desktop/ and test/visual/ as named scripts in package.json. Update client-scoped-validation.yml home job to separately call test:unit, test:visual, e2e if needed. Add a guard (test/scripts/check-test-layout.sh) to ensure consistency.

- **[LOW] E2E test configs (Playwright) in parent harness, duplicated setup per client**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/igloo-pwa/playwright.config.ts, test/igloo-chrome/playwright.config.ts, test/igloo-home/playwright.config.ts are all in the parent harness. Each references igloo-pwa/, igloo-chrome/, igloo-home/ submodule specs respectively. No shared e2e config structure (e.g., no parent/igloo-pwa/specs symlink to repos/igloo-pwa/test/). test/shared/playwright-config.ts provides a base config helper.
  - **Impact:** E2E specs are not in repos/ but in test/, making it unclear where to add new tests. Updating e2e harness requires understanding test/igloo-*/ layout rather than living with the client code.
  - **Fix:** Consider moving test/igloo-pwa/specs -> repos/igloo-pwa/test/e2e/, with a symlink in test/ for backward compatibility. Document that e2e tests live in repos, not test/. Ensure new e2e coverage is added to the correct repo.

- **[LOW] Visual test runner fragmented: igloo-home uses test/visual/run.mjs; igloo-pwa/ui use Playwright @visual tag**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** repos/igloo-home/test/visual/ contains a visual test runner (run.mjs). test/package.json does not have a test:visual target (only test:e2e:igloo-pwa:visual greps Playwright @visual tag). test-affected.sh (line 179) calls 'npm --prefix repos/igloo-home run test:visual', a different invocation from Playwright visual specs.
  - **Impact:** Visual test conventions differ: igloo-home uses a custom runner, others use Playwright tags. Harder to standardize visual regression tooling or metrics.
  - **Fix:** Migrate igloo-home visual tests to Playwright @visual tags if possible, or document why igloo-home requires a custom runner. Consolidate test:visual invocation into test/package.json (create test:visual:igloo-home target).

### Render/visual/e2e/demo harness inventory across parent + submodules

- **[HIGH] Three parallel visual harness patterns with inconsistent ownership**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/igloo-pwa/specs/*-visual.spec.ts (storage-seeded snapshots, 7 files each with identical capture() boilerplate), test/igloo-home/test/visual/run.mjs (standalone system chromium harness, ~138 LOC), test/igloo-home/test/desktop/run.mjs (tauri-driver based, ~400+ LOC). Agent screenshot specs live at test/igloo-*/specs/agent-screenshot.spec.ts (3 variants, each ~48-52 LOC). Makefile delegates to igloo-home/package.json for test:visual (Makefile:319), igloo-home/test/desktop/run.mjs (node script, not playwright), and test/package.json for pwa/chrome screenshot commands.
  - **Impact:** No single canonical render pipeline: visual testing for igloo-home bypasses the parent test infrastructure entirely (igloo-home/test/visual/run.mjs uses system chromium + manual import invocations), making it hard to add shared visual assertions, coordinate artifact output, or share platform/browser logic. PWA/Chrome use playwright storage-seeded @visual tests + @agent screenshots; home uses system chromium for .mjs smoke and tauri-driver for desktop e2e—three different rendering strategies for the same problem.
  - **Fix:** Create a unified visual-harness abstraction layer at test/shared/visual-harness.ts with (1) a captureScreen(client, state, outputDir) helper used by all @agent specs, eliminating 148 LOC of near-identical code; (2) a PlaywrightScreenshotFixture that wraps page.screenshot() with consistent output routing (all @agent screenshots → .tmp/agent/, all @visual storage-seeded → .tmp/visual/<client>/); (3) migrate igloo-home's system chromium smoke to use playwright bundled (via test-prebuild), retire igloo-home/test/visual/run.mjs, and use the same @agent spec pattern as pwa/chrome. Document the single harness in test/README.md.

- **[HIGH] Artifact output directory fragmentation across .tmp/agent, .tmp/visual/*, .tmp-visual-artifacts, os.tmpdir()**  _(T5 build/artifact provenance & cache integrity)_
  - **Evidence:** test/igloo-pwa/specs/{welcome,dashboard,etc}-visual.spec.ts write to .tmp/visual/igloo-pwa/{welcome,dashboard,etc}/ (WELCOME_CAPTURE_DIR, DASHBOARD_CAPTURE_DIR, etc at test/igloo-pwa/specs/welcome-visual.spec.ts:11-12); test/igloo-*/specs/agent-screenshot.spec.ts write to .tmp/agent/ (OUT_DIR at test/igloo-pwa/specs/agent-screenshot.spec.ts:17); repos/igloo-home/test/visual/run.mjs writes to .tmp-visual-artifacts/run-*/ (localArtifactRoot, test/visual/run.mjs:7-8); test/igloo-home/screenshot/agent-screenshot.spec.ts writes to .tmp/agent/ (OUT_DIR at test/igloo-home/screenshot/agent-screenshot.spec.ts:21); desktop tests write to os.tmpdir() temp dirs (test/desktop/run.mjs:35, appDataDir at test/desktop/run.mjs:54); check-pwa-visual-manifest.mjs only validates .tmp/visual/igloo-pwa/ paths (test/scripts/check-pwa-visual-manifest.mjs:67), making igloo-home/chrome visuals invisible to the validator.
  - **Impact:** Agent tools (make screenshot CLIENT=home) write to .tmp/agent/, but igloo-home's test:visual lane writes to .tmp-visual-artifacts/ (wrong tree for CI artifact collection). No single source of truth for where a rendered screenshot lives—hard to surface visuals in CI reports, write coverage guards, or retroactively audit what rendered. Screenshots scattered across .tmp/agent/ and .tmp/visual/igloo-pwa/ make it impossible to diff all clients' visual output in one pass.
  - **Fix:** Centralize all visual outputs under .tmp/visual/<client>/{<scenario>|agent}/: establish convention (1) .tmp/visual/pwa/agent/{state}.png + .txt (from @agent specs); (2) .tmp/visual/pwa/<feature>/{scenario}.png (from @visual specs); (3) .tmp/visual/chrome/agent/ and .tmp/visual/home/agent/ for chrome/home agent screenshots; (4) retire .tmp/agent/ and .tmp-visual-artifacts/ in favor of .tmp/visual/. Update check-pwa-visual-manifest.mjs to validate all clients' output dirs. Ensure compose.test.yml, scripts/demo.sh, and test prebuild write their artifacts to a unified .tmp location.

- **[MEDIUM] Repeated capture-and-write boilerplate across 7 PWA visual specs + 3 agent screenshots**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/igloo-pwa/specs/{welcome,dashboard,settings,permissions,import,onboard,recover}-visual.spec.ts each define `async function capture(page: Page, fileName: string)` that calls `mkdir(..., { recursive: true })` + `page.screenshot({ path: ..., fullPage: true })` (e.g., welcome-visual.spec.ts:76-78, dashboard-visual.spec.ts:69-72, settings-visual.spec.ts:69-72). test/igloo-pwa/specs/agent-screenshot.spec.ts, test/igloo-chrome/specs/agent-screenshot.spec.ts, test/igloo-home/screenshot/agent-screenshot.spec.ts each independently mkdir(.tmp/agent) + page.screenshot() + writeFile(screenshot.json) + writeFile(*.txt), with only minor client-specific differences (state mapping in home, extension fixture in chrome).
  - **Impact:** 148 LOC of nearly identical capture logic, no shared test helpers, making it hard to change screenshot naming, add metadata (test name, timestamp), coordinate across clients, or introduce a new rendering feature (e.g., viewport tracking, dom-to-markdown export). Changes to capture semantics (e.g., add a visible-text dump) require updates in 10+ files.
  - **Fix:** Extract a shared CaptureScreenshotHelper at test/shared/visual-harness.ts: `async captureScreenshot(page, { state, outputDir, clientName })` that handles mkdir, page.screenshot, metadata JSON, text dump. Offer both a low-level version for specs and a higher-level fixture for tests. Update all visual specs to import and use it. Reduces duplication to ~5 LOC per spec.

- **[MEDIUM] Platform parity gap: igloo-home visual harness uses system chromium (Linux-only), other clients use bundled playwright**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** repos/igloo-home/test/visual/run.mjs probes ['snap/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/chromium'] (run.mjs:15); if not found, exits with 'igloo-home visual smoke requires chromium or chromium-browser' (run.mjs:21). test/igloo-pwa and test/igloo-chrome use playwright via defineFrostrPlaywrightConfig (which inherits @playwright/test's bundled chromium). test/igloo-home/playwright-screenshot.config.ts also uses playwright (line 8-14, vite webserver). Desktop test uses tauri-driver (test/desktop/run.mjs, not browser-based).
  - **Impact:** igloo-home visual smoke fails on macOS unless system chromium is installed (common in CI images); CI may silently skip it if xvfb-run missing (test-demo-harness-onboard.sh:27-33 guards). Other clients use bundled playwright (platform-agnostic, reproducible). Different code paths for the same screenshot task (system binary vs bundled) means different rendering quirks, version mismatches, and hidden platform failures.
  - **Fix:** Migrate igloo-home/test/visual/run.mjs to use playwright bundled (via test-prebuild, same as @agent specs). Add igloo-home target to test/shared/test-targets.json prebuild list (currently pwa, chrome, home, demo). Retire the system chromium probe. Validate in .github/workflows that test:visual passes on all platforms.

- **[MEDIUM] Separate playwright config for igloo-home screenshot (@agent) vs e2e (tauri-driver)**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/igloo-home/playwright-screenshot.config.ts (testDir: 'test/igloo-home/screenshot', vite webServer, port 1420, Makefile:28 invokes 'test:screenshot:home' which uses -c playwright-screenshot.config.ts) vs test/igloo-home/playwright.config.ts (testDir: 'test/igloo-home/specs', tauri-driver in global-setup, 120s timeout). Configs are separate because @agent specs run headless vite, while e2e specs run tauri app. Selectors in agent-screenshot.spec.ts (test/igloo-home/screenshot/agent-screenshot.spec.ts:29-31) wait for 'Signer' tab, same selector used in e2e tauri specs. If selectors change, both configs must be updated.
  - **Impact:** Two playwright configs for one client, making it unclear which one applies to what lane. Global-setup for screenshot config does not run test-prebuild; if prebuild was skipped, screenshot tests silently use stale igloo-ui build. Selector contract between vite headless and tauri app is implicit, not enforced at config time.
  - **Fix:** Merge both configs into one test/igloo-home/playwright.config.ts with multipleWebServers (vite for screenshot, tauri for e2e). Use `FROSTR_IGLOO_HOME_TEST_MODE=screenshot` env var to toggle webServer. Alternatively, keep separate but add a guard in global-setup.ts that fails fast if the wrong webServer is unavailable. Add selector contracts to test/README.md: 'All igloo-home tests must wait for [role=tab name=/Signer/]'.

- **[MEDIUM] Visual manifest (igloo-pwa) is not enforced for other clients; incomplete coverage tracking**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/igloo-pwa/visual-manifest.json (25 screens, .tmp/visual/igloo-pwa/ outputs, references repos/igloo-paper/, status='aligned'|'needs-work'); test/scripts/check-pwa-visual-manifest.mjs validates only igloo-pwa outputs (checks output startsWith('.tmp/visual/igloo-pwa/')), not chrome or home. test/package.json includes 'test:guards:visual' which runs check-pwa-visual-manifest.mjs (test/package.json:17), but no equivalent check for chrome agent screenshots or home visual output. Chrome @agent spec writes to chrome-{state}.png but there is no manifest entry, no Paper reference, no status tracking. Home agent writes to home-{state}.png, also untracked.
  - **Impact:** PWA visual parity is tracked (manifest + Paper references); Chrome and home visual states are orphaned—no way to know if all intended surfaces are captured, no audit trail of which screens are aligned with Paper, no guards against screenshot regressions. A developer can delete chrome-dashboard-running.png without CI noticing.
  - **Fix:** Extend visual-manifest.json to include chrome and home entries (or create separate manifests). Add `test:guards:visual:chrome` and `test:guards:visual:home` to test/package.json, update check-pwa-visual-manifest.mjs to accept a --client flag and validate all three. Enforce that every @agent spec has a corresponding manifest entry with status and Paper reference.

- **[LOW] Agent screenshot tools write state + PNG + TXT + JSON to .tmp/agent/, but agent coordination/polling is implicit**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/igloo-pwa/specs/agent-screenshot.spec.ts:30-44 writes {ok:true, state:STATE, png:pngPath, txt:txtPath} to .tmp/agent/screenshot.json after page.screenshot() + writeFile(txt); test/igloo-chrome/specs/agent-screenshot.spec.ts:30-44 writes {ok:true, client:'chrome', state:STATE, png, txt} to the same .tmp/agent/screenshot.json; test/igloo-home/screenshot/agent-screenshot.spec.ts:34-48 writes {ok:true, client:'home', state:STATE, png, txt} to the same .tmp/agent/screenshot.json. Each @agent spec overwrites the same screenshot.json file; if multiple agents run in parallel, the last one wins, losing pwa/chrome results.
  - **Impact:** Agents (or humans) calling make screenshot expect a single artifact path in .tmp/agent/, but parallel runs (e.g., make screenshot CLIENT=pwa && make screenshot CLIENT=chrome concurrently) silently lose one result. scripts/verify.sh writes to .tmp/agent/verify.json (same dir), no coordination.
  - **Fix:** Use client-scoped output files: pwa writes .tmp/agent/pwa.png + .tmp/agent/pwa-screenshot.json, chrome writes .tmp/agent/chrome.png + chrome-screenshot.json, home → home.png + home-screenshot.json. Update Makefile screenshot targets to poll for the correct client-specific file. Ensure make screenshot CLIENT=pwa && make screenshot CLIENT=chrome can run in parallel without data loss.

- **[LOW] Demo harness and test-demo-harness-onboard.sh have inconsistent artifact handling and no unified harness interface**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** scripts/demo.sh (starts docker compose, writes onboard packages to FROSTR_TEST_HARNESS_DIR/.tmp/test-harness/onboard-{member}.txt + .password.txt, healthcheck on igloo-shell control socket); test/scripts/test-demo-harness-onboard.sh (standalone smoke, creates its own temporary ARTIFACT_DIR, spawns docker compose with FROSTR_TEST_HARNESS_DIR override, writes output to .tmp/igloo-demo-artifacts.XXXXXX, cleans up on exit); compose.test.yml defines IGLOO_SHELL_DEMO_ARTIFACT_DIR env var (compose.test.yml:72-74) but test-demo-harness-onboard.sh does not use it consistently. test/igloo-chrome/fixtures/helpers/demo-harness.ts replicates demo.sh logic inline (starts docker compose, waits for onboard files, reads packages). Makefile delegates demo-start/demo-stop to scripts/demo.sh but test:e2e:demo to test/igloo-chrome/specs/demo-harness.spec.ts + demo-harness.ts fixture.
  - **Impact:** No single interface for 'start the demo and get onboarding packages'—three code paths (demo.sh, test-demo-harness-onboard.sh, demo-harness.ts fixture) each manage docker lifecycle, artifact paths, cleanup differently. Changes to demo harness configuration (e.g., member names) must be updated in three places. Smoke tests and e2e tests use different startup logic, making it hard to isolate whether a failure is due to harness flakiness or test logic.
  - **Fix:** Create test/shared/demo-harness-client.ts (or bin/demo-harness.mjs) with a unified interface: DemoHarness { start(), onboardPackage(member), stop(), artifactDir }. Have demo.sh, test-demo-harness-onboard.sh, and demo-harness.ts fixture all delegate to this module. Reduce maintenance to one code path.

- **[LOW] igloo-home test:visual uses system chromium with manual import invocation; no vite dev server startup**  _(T7 flake/reliability/cleanup)_
  - **Evidence:** repos/igloo-home/test/visual/run.mjs spawns 'npm run dev' (vite server, test/visual/run.mjs:25), waits for http://127.0.0.1:1420 (waitForDevServer, test/visual/run.mjs:44-59), then calls spawnSync(chromeBinary, [..., '--screenshot=...', url]) for each scenario (test/visual/run.mjs:89-104). Uses 'import' command (ImageMagick) to validate screenshot dimensions/colors (test/visual/run.mjs:108-119). No playwright, no test fixtures, just raw spawnSync + manual validation. Tauri desktop test (test/desktop/run.mjs) also spawns 'npm run dev' (line 45) but then invokes tauri app + playwright (line 106+).
  - **Impact:** igloo-home has two render workflows: (1) test:visual via system chromium + import validation (brittle, platform-dependent, no color histogram guards), (2) test:desktop via tauri app + playwright (e2e, requires X11/Wayland). Neither is integrated with the parent playwright infrastructure. If igloo-ui CSS changes, test:visual may silently pass with a mis-rendered screenshot (no visual regression detection, only dimension/color heuristics).
  - **Fix:** Retire igloo-home/test/visual/run.mjs and test/desktop/run.mjs as standalone runners. Consolidate into test/igloo-home/specs/ with playwright @visual and @agent specs (same pattern as pwa). For desktop-specific tests (tauri-specific APIs), keep them in test/igloo-home/specs/ but mark @desktop and run them via tauri-driver in global-setup, not standalone. Use visual-manifest.json to track expected states.

### Selector strategy & guard scripts (FROSTR test infrastructure)

- **[HIGH] Selector guards gate only nightly, not per-PR — stale selectors merge via fast lane**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/package.json line 7: test:verify runs test:guards (targets+wasm only), omits test:guards:selectors. test:guards:selectors defined line 16 but only runs in test:guards:full (nightly) + per-client jobs. workspace-guards.yml line 82 runs lean test:guards, not full. Evidence of impact: commit 59f9227 (2026-06-17) fixed cascading stale selectors across @fast/@live/@cross-client after Paper dashboard restructure (dashboard.spec.ts, profile-import.spec.ts, 21 lines changed).
  - **Impact:** Stale test-id selectors and page-object mismatches merge on fast PRs and only fail nightly, delaying discovery by 24h. Paper dashboard restructure required post-merge fixes to all three clients, bypassing early gate. Cross-client specs (pwa-chrome-pairing, chrome-home-pairing) can fail due to stale selectors in one client blocking validation of another.
  - **Fix:** Move test:guards:selectors into test:verify (the per-PR gate). This requires: (1) Add selector guarding to the lean per-client lanes (test:guards:pwa, test:guards:chrome include check-e2e-selector-contracts scoped to that client); (2) Document per-client selector coverage responsibilities: PWA maintains comprehensive pages.ts; Chrome must either adopt page objects or formalize raw-selector contracts; (3) Add selector timing to per-client CI workflows (client-scoped-validation.yml already runs test:guards:pwa|chrome but verify they include selector checks). Acceptance: 'make verify' blocks stale selectors same-PR.

- **[HIGH] Cross-client selector inconsistency — PWA has pages.ts, Chrome relies on raw selectors in specs**  _(T6 cross-repo inconsistency)_
  - **Evidence:** test/igloo-pwa/support/pages.ts: 527 lines, 8 page classes (Welcome, CreateFlow, Distribute, etc.), every screen has page-object methods. test/igloo-chrome/support/ui.ts: 63 lines, only 6 helper functions, no page classes. test/igloo-chrome/specs/dashboard.spec.ts: 37+ direct selector calls (getByRole, getByText, getByPlaceholder) per test. test/igloo-chrome/specs/runtime-lifecycle.ts: 200+ lines of test helpers (onboarding.ts, not page objects). Contrast: PWA specs import from support/pages and ui; Chrome specs inline raw selectors throughout.
  - **Impact:** Chrome specs are 5-10x more brittle to UI changes (no abstraction layer). When the Paper dashboard shipped, Chrome required manual post-merge fixes (commit 59f9227); PWA page objects absorbed same restructure with only locator-routing updates. Chrome cross-client specs (chrome-pwa-pairing, chrome-home-pairing) depend on selectors in other clients they don't own, creating blocking failures when igloo-ui or igloo-pwa change.
  - **Fix:** Formalize Chrome's selector strategy: (1) Adopt page-object pattern for Chrome (extend igloo-chrome/support with pages.ts covering onboarding, provider, dashboard, runtime-lifecycle screens, parallel to PWA). OR (2) If Chrome keeps inline selectors, enforce a contract: wrap all selectors in support/ helpers (not inline in specs), add a check-chrome-selector-contracts.sh parallel to PWA (validate all specs route through helpers), and gate per-PR. PWA already models the working approach; Chrome should follow or be explicit about trading maintainability for simplicity.

- **[HIGH] Selector enforcement timing — test:guards:selectors runs only in full (nightly) + per-client, not in lean verify (per-PR)**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** test/package.json line 7 test:verify does NOT call test:guards:selectors. Line 16 test:guards:selectors defined as 'check-cross-client-imports + check-e2e-selector-contracts'. Line 8 test:guards:full includes test:guards:selectors (nightly only). client-scoped-validation.yml lines 73,118,157 run test:guards:pwa|chrome|home which INCLUDE selector checks (via check-e2e-selector-contracts.sh <client>). workspace-guards.yml line 82 runs lean test:guards, skipping selectors. Code path: make verify → scripts/verify.sh → npm test:verify → test:guards (lean) + typecheck + test:e2e:fast. Never includes selector contracts.
  - **Impact:** Stale selectors block nightly (test:guards:full), not PR (test:verify). A developer can submit a PR that breaks selectors, it passes per-PR gates, merges, fails nightly 24h later. This happened in practice (commit 449eda5: latent selector violation in dashboard-states.spec.ts, caught by full guards only). Cross-client changes (igloo-ui restructure) only validated after merge.
  - **Fix:** Hoist test:guards:selectors into test:verify. Current per-client jobs (client-scoped-validation.yml) already gate per-client selectors (good). But workspace-guards.yml (the global per-PR gate) must also enforce selectors. Action: Move check-e2e-selector-contracts into lean test:guards (line 7) or create a dedicated test:verify step. Document: per-PR blocks selector regressions; nightly (test:guards:full) does additional coverage (docs, workflows, etc.).

- **[HIGH] stale selectors after Paper dashboard restructure required post-merge fixes across all three clients**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** Commit 59f9227 (2026-06-17, post-merge): 'Modernize the stale chrome smoke selectors after the 2026-06-16 Paper restructure: dashboard.spec.ts cold state asserts Start Signer + Readiness copy (the cold dashboard has no Pending Operations section); the @live diagnostics test uses the ~N ready nonce pill + SIGN capable chip; and profile-import matches the Chrome Import header chip as a substring.' Changes: test/igloo-chrome/specs/dashboard.spec.ts (21 lines), test/igloo-chrome/specs/profile-import.spec.ts (4 lines), agent-screenshot.spec.ts (48 lines). Earlier: eafdb4a (2026-06-17) fixed @fast red gate in PWA (app-shell specs seeded under legacy partition). Commit 9e0f7a9 (2026-06-09) reconciled Paper design but visual manifest stayed needs-work until 59f9227.
  - **Impact:** The Paper dashboard UI restructure landed in igloo-ui but selectors in all three client test suites became stale. The guard (test:guards:selectors) was only run nightly, so stale selectors merged and had to be fixed post-PR. If selectors had been gated per-PR globally, the Paper PR would have failed at CI, forcing fixes before merge.
  - **Fix:** See recommendations for T4 findings 1 and 5: hoist test:guards:selectors into test:verify (lean per-PR gate). This would have caught stale selectors on the Paper dashboard PR before merge. Acceptance: 'npm test:verify' (make verify, the per-PR gate) must pass with stale selectors already flagged before CI approval.

- **[MEDIUM] Per-client prebuild targets diverge (chrome needs home+demo), creating cascading cross-client failures**  _(T6 cross-repo inconsistency)_
  - **Evidence:** test/shared/test-targets.json: chrome.prebuild=[chrome, home, demo] vs pwa.prebuild=[pwa]; chrome.fastPrebuild=[chrome] (drops home+demo). test/igloo-chrome/specs/chrome-home-pairing.spec.ts and chrome-pwa-pairing.spec.ts are @cross-client. If igloo-home changes, test:affected.sh triggers test:guards:chrome, which rebuilds home+demo. But test:guards:pwa does NOT rebuild home/demo, so a pwa cross-client spec fails waiting for home runtime that was never built. CI jobs: client-scoped-validation.yml PWA job initializes only igloo-pwa/bifrost-rs/igloo-shared, Chrome job initializes igloo-chrome/igloo-home/bifrost-rs/igloo-shared (asymmetric).
  - **Impact:** Cross-client specs are fragile to prebuild ordering. test:guards:pwa and test:guards:chrome may succeed locally but fail in CI if the dependency graph is walked in the wrong order. Chrome test depends on home but PWA does not; if a cross-client spec tries to pair PWA+Chrome on the same page, PWA specs see missing chrome fixtures.
  - **Fix:** Consolidate prebuild targets: (1) Align fastPrebuild across clients (if @cross-client specs are in the lane, they must all be prebuilt). (2) Document: which prebuild targets are needed for which cross-client specs (pwa-chrome-pairing → [pwa, chrome, bifrost-rs], chrome-home-pairing → [chrome, home]). (3) Verify test-affected.sh computes prebuild correctly: if a file in igloo-home changes and crosses @cross-client, ensure all clients that pair with home rebuild. (4) Test: run a mock scenario where igloo-home changes, verify test:affected triggers full prebuild for all clients, not just home.

- **[MEDIUM] Selector contract guards run at different cadences, creating blind spots — full guards (nightly) include parts missing from per-PR**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/package.json: test:verify (per-PR) = test:guards + typecheck + test:e2e:fast. test:guards = targets + wasm (2 guards, both also in full). test:guards:full (nightly) = 13 different guards including selectors, visual, workflows, docs, shared-setup. Mapping: test:guards (lean) covers 2; full covers 13 (+8 e2e lane runs). Selectors, visual, and cross-client checks are only in full/nightly. CI timing: workspace-guards.yml runs per-PR (line 82 test:guards lean), per-client validation runs per-PR (test:guards:pwa|chrome|home which DO include selectors). So selectors ARE gated per-client per-PR, but NOT in the global lean gate.
  - **Impact:** The global per-PR gate (workspace-guards.yml / test:verify) is incomplete: it gates targets+wasm but not selectors, visual, docs, workflows. A cross-repo change (e.g., reorganizing test/ docs or adding a GitHub action) only validates in nightly. A selector-breaking change in shared/central e2e-test-ids.ts only fails per-client jobs, not the global gate.
  - **Fix:** Clarify and document the gate tiers. Current model: (1) Workspace-guards (global, per-PR, lean): targets + wasm. (2) Client-scoped-validation (per-client, per-PR): selectors + typecheck + e2e:fast. (3) Nightly (full): everything. This is defensible IF the docs explain the split. Alternatively: elevate selectors/docs/workflows to workspace-guards (line 82) so the global gate is truly 'does the infrastructure remain consistent.'  Recommend: promote test:guards:selectors + test:guards:docs to workspace-guards (per-PR global), keep test:guards:full for nightly comprehensive (visual, workflows, shared-setup, affected-list validation).

- **[LOW] Two guard scripts defined but unwired — check-wasm-toolchain.sh and check-worktree-unchanged.sh never execute**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/scripts/check-wasm-toolchain.sh: 58 lines, validates rustc/rustup/wasm-pack/clang wasm32 support. test/scripts/check-worktree-unchanged.sh: 42 lines, snapshot guard to prevent test commands from mutating files. Neither appears in test/package.json (grep check-wasm-toolchain and check-worktree-unchanged yields zero). Not invoked in CI workflows. check-test-prebuild-nonmutating.sh (15 lines) serves as a partial worktree guard (test:guards:wasm:strict) but is also not in the default test:verify lane.
  - **Impact:** Low: wasm-toolchain checks are implicit (CI GH Actions setUp-Rust + install wasm-pack); developers may not know they need these tools. worktree-unchanged is a useful safeguard for commands that should be read-only but isn't gated (e.g., wrapping make demo-start or make test-prep to catch commands that leave files behind).
  - **Fix:** Either wire or delete: (1) check-wasm-toolchain.sh could run as part of setup (or document it's redundant with CI setup). (2) check-worktree-unchanged.sh could become a test:guard if there are known commands that mutate workspace (e.g., wrap certain prebuild scripts). OR remove them as technical debt if they're not needed. Document reasoning in test/scripts/ comments.

- **[LOW] @agent exemption allows screenshot specs to bypass page-object routing, but exemption is undocumented in the guard**  _(T4 selector/DOM brittleness & contract-enforcement timing)_
  - **Evidence:** check-e2e-selector-contracts.sh lines 51-62: Exempts agent-screenshot.spec.ts from getByTestId rule ('specs must not call getByTestId directly'). Comment line 51-54 explains: '@agent render-and-verify tools are headless capture tools, not gated tests; waiting on a stable surface test-id is the right primitive.' 7 @agent specs found (3 agent-screenshot.spec.ts per client + 3 uses in playwright configs + 1 comment). Pattern is correct (use test-ids for reliability), but exemption relies on filename matching (glob **/agent-screenshot.spec.ts), not tag matching.
  - **Impact:** Low: Exemption is accurate (agent specs need test-ids to wait for stable surfaces without a full test framework). But if a new agent tool is added with a different filename, it won't be exempted. Filename-based exemption is fragile.
  - **Fix:** Document the @agent exemption pattern clearly in the guard script and CONTRIBUTING.md. Consider: (1) Make the exemption tag-based instead of filename-based (grep for @agent in specs, not filenames), which would require integrating with Playwright's test filtering. (2) Or require all agent-rendering specs to follow the agent-screenshot.spec.ts naming convention (enforce via guide, not code). (3) Add a comment in the guard explaining why agent specs are exempt.

### Test lanes and gating

- **[HIGH] Asymmetric per-PR e2e gating: PWA fast only, Chrome/Home zero coverage**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** .github/workflows/client-scoped-validation.yml line 75 (PWA: npm test:e2e:igloo-pwa:fast) vs lines 120, 158 (Chrome/Home: only build + typecheck, NO e2e)
  - **Impact:** Chrome and Home e2e regressions land undetected in PRs. Provider interface breaks, extension rotation bugs, desktop app lifecycle issues only surface in nightly. PWA fast excludes @live + @cross-client but chrome/home have no fast lane to compare.
  - **Fix:** Add per-PR e2e gates for Chrome (fast lane equivalent, --grep-invert @live|@cross-client|@agent) and Home (existing run-e2e.sh without display requirement). Rebalance: PWA:fast + Chrome:fast + Home (untagged subset) per PR; reserve @live/@cross-client/@demo for nightly only.

- **[HIGH] 11 untagged test specs run nowhere in gated lanes**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** find /test -name *.spec.ts | grep -L '@live|@cross-client|@agent|@visual|@demo' returns: Chrome (provider.spec.ts, rotation-update.spec.ts, profile-import.spec.ts); Home (5 specs with 'live' in filenames but no @live tag); PWA (app-shell.spec.ts, wasm-integrity.spec.ts); UI Showcase (reference-screens.spec.ts)
  - **Impact:** Untagged tests only run via test-affected when those client repos change—zero coverage in fast/live/demo lanes. App shell, WASM integrity, provider smoke, rotation update, and profile import logic rot silently. Home tests with 'live' in filenames actually require the demo harness but are untagged, creating a silent contract.
  - **Fix:** Tag all untagged specs: Chrome provider/rotation/profile → @live (require relay fixture). Home 5 specs → @live (require demo harness, rename filenames to drop '-live' suffix and rely on tag). PWA app-shell/wasm-integrity → @live (or add new @integrity tag if non-relay). Remove naming ambiguity: tags are the contract, filenames are narrative.

- **[MEDIUM] Cross-client tests (4 suites) gated only in nightly, not per-PR**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/package.json: test:e2e:igloo-pwa:cross (--grep @cross-client) is manual-only. test:e2e:igloo-chrome runs full suite with NO filters only in test-affected (line 200-206 scripts/test-affected.sh). No per-PR lane calls either. .github/workflows/release-validation.yml gathers @live but NOT @cross-client; @cross-client would require separate explicit lane.
  - **Impact:** Chrome-PWA and Chrome-Home pairing, PWA-Home pairing contracts drift between PRs and master. Cross-device relay coordination bugs land undetected. Only stress-tested nightly or in manual test:e2e:igloo-pwa:cross.
  - **Fix:** Define an explicit @cross-client lane (test:e2e:cross) that runs Chrome-PWA + Chrome-Home + PWA-Home pairing specs together, scoped by shared fixture requirements. Gate it in nightly/dispatch only (they require demo harness and cross-app state sharing). Document that @cross-client is NOT per-PR coverage by design.

- **[MEDIUM] Home E2E tests untagged, lack lane taxonomy, silently coupled to display/harness**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-home/specs: 10 specs total, 5 with 'live' in filenames (generated-onboarding-live.spec.ts, rotation-live.spec.ts, raw-import-live.spec.ts, onboarding-package-live.spec.ts, rotation-update-live.spec.ts) but NONE tagged @live. igloo-home/run-e2e.sh (lines 1-38) detects display/xvfb but uses NO playwright tag filters. test/package.json line 21: test:e2e:igloo-home calls run-e2e.sh with no modifiers.
  - **Impact:** Home tests don't participate in the tag-filter taxonomy (fast/live/cross/demo). Can't run a 'fast' home variant (e.g., seedable tests without relay). Can't distinguish which tests require relay/harness vs static state. Filename-based 'live' convention conflicts with @live tag convention. Home E2E always runs full suite, making affected lane ordering unpredictable.
  - **Fix:** Migrate igloo-home specs to playwright tag system: tag relay-dependent tests @live, pure-state tests untagged (or @fast equivalent). Rename specs to drop '-live' suffix (tag is the contract). Implement fast/live lanes in igloo-home/playwright.config.ts (or via FROSTR_TEST_LANE env var in global-setup). Align with PWA/Chrome tag contracts.

- **[MEDIUM] Nightly release-validation runs @live + @demo, skips explicit @cross-client lane**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** .github/workflows/release-validation.yml: line 106 (make test-demo → @demo only), line 117 (make test-live → @live only). Neither lane includes @cross-client. test/package.json: no explicit test:e2e:all-cross or test:e2e:cross that runs cross-client suite in CI.
  - **Impact:** Cross-client test coverage (chrome-pwa-pairing, chrome-home-pairing, pwa-home-pairing, demo harness 3-way) is optional/manual. Contract drift between clients stays hidden until post-merge or manual test run.
  - **Fix:** Add explicit nightly test:e2e:cross lane (after @live completes, or in parallel). Document: @live gate ensures single-client relay flows; @cross-client gate ensures multi-client coordination; @demo gate ensures 3-way demo harness onboarding. Make all three mandatory nightly (or at least include @cross-client in release-validation).

- **[MEDIUM] Test lane taxonomy conflates 'fast' (render-only) with 'non-live' (excludes relay)**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/package.json lines 24, 39: test:e2e:igloo-pwa:fast and test:e2e:igloo-chrome:fast both use --grep-invert '@live|@cross-client|@agent'. Comment in test/shared/test-prebuild.ts (lines 6-11) explains: fast lane excludes @live + @cross-client to avoid needing home/relay clients. But 'fast' implies performance, not 'non-relay'.
  - **Impact:** Unclear semantics: is @fast a tag or an implicit property? Developers may think 'fast' = render-only and miss that it also excludes @cross-client and @agent. New tests tagged only @live will break the fast lane even if they're render-fast. No explicit @fast tag exists; convention is --grep-invert.
  - **Fix:** Introduce explicit @fast tag for genuinely fast tests (no relay, no harness). Make --grep filters explicit: fast = --grep @fast (opt-in), live = --grep @live, cross = --grep @cross-client. Migrate existing untagged fast-lane specs to explicit @fast. Document that @live, @cross-client, @fast, @demo, @agent, @visual are mutually exclusive or at least form a clear hierarchy.

- **[LOW] test:guards (lean) vs test:guards:full (with e2e) undocumented and asymmetrically used**  _(T3 harness fragmentation/duplication)_
  - **Evidence:** test/package.json lines 7-8: test:guards = 'test:guards:targets && test:guards:wasm' (lean). test:guards:full = 'test:guards:docs && ... && test:e2e:igloo-home && test-affected' (includes full e2e). workspace-guards.yml line 82 runs test:guards (lean). No comment explains why lean. No -full variant in CI.
  - **Impact:** Easy to confuse which guards run where. test:guards:full is never invoked in CI, making it a dead code path or a documented-elsewhere escape hatch. Developers may assume test:guards gates all critical checks.
  - **Fix:** Rename test:guards to test:guards:lean and test:guards:full to test:guards (making it the default/comprehensive version). Or document the distinction in the Makefile and test/README.md with rationale (e.g., 'lean for quick PR feedback, full for pre-merge validation').

- **[LOW] Provider smoke, app-shell, wasm-integrity specs untagged; no relay dependency declared**  _(T2 fixture/seed sprawl & migration debt)_
  - **Evidence:** test/igloo-chrome/specs/provider.spec.ts (lines 1-50): uses server fixture, seedProfile, no @live tag. test/igloo-pwa/specs/app-shell.spec.ts, wasm-integrity.spec.ts: untagged, no visible @live requirement. Comments in other specs (e.g., approve-queue.spec.ts) explicitly note '@live — behavioral coverage', but these lack such clarity.
  - **Impact:** Fixture requirements hidden. test-affected lane runs full suite with FROSTR_TEST_PREPARED=1, but it's unclear whether prep builds are strictly necessary. Might run in fast lane accidentally or fail if harness isn't pre-built. Maintenance burden: next dev touching these specs has to guess whether they need relay or state.
  - **Fix:** Tag provider.spec.ts, rotation-update.spec.ts, profile-import.spec.ts with @live (they use seedProfile/provider bridge, which requires relay state). Tag app-shell.spec.ts, wasm-integrity.spec.ts with @smoke or @integrity (explicit dependencies, no relay). Document in spec headers why each tag is needed.

- **[LOW] UI Showcase reference-screens.spec.ts untagged, no lane ownership**  _(T1 silent-lanes/coverage-gaps)_
  - **Evidence:** test/igloo-ui-showcase/specs/reference-screens.spec.ts: untagged. test/package.json line 22: test:igloo-ui-showcase runs its own playwright config. Never called by any test lane (test:e2e, test:fast, test:live, test-affected, test:guards).
  - **Impact:** UI showcase is orphaned: no lane gates it. Only runs via direct npm run invocation. Breaking changes to igloo-ui component surfaces may land undetected.
  - **Fix:** Either integrate igloo-ui-showcase into test:e2e lanes (add to test:guards:visual or similar), or explicitly document it as manual-only reference tool (not a gated test). If gated, tag specs and add to a test:e2e:showcase lane.

