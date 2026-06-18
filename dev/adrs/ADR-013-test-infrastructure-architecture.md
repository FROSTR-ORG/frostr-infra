# ADR-013: Test Infrastructure Architecture

## Status

Accepted

## Context

The 2026-06-17 test-infrastructure audit ([`dev/docs/TEST-AUDIT.md`](../docs/TEST-AUDIT.md),
97 findings across 9 themes) found systemic debt. The per-PR gate is render-only
**by design**, but the lanes around it grew by convention rather than design, so a
green PR can hide a broken unit suite, a stale selector, a failed signing flow, or
a drifted cross-client contract. Five high-severity themes recur: silent lanes,
an implicit/inconsistent tag taxonomy, WASM/artifact provenance gaps, fixture/seed
sprawl, and late (nightly-only) selector-contract enforcement.

The audit deliberately stopped at findings plus a *provisional* roadmap and
deferred the design forks to this ADR. This ADR records the **target test
architecture** so remediation has a fixed, approved target instead of drifting.

It **builds on** [ADR-004 (Cross-Repo E2E Ownership)](./ADR-004-cross-repo-e2e-ownership.md)
— cross-repo browser E2E stays in top-level `test/`; submodules keep their own
unit/integration coverage — and does not supersede it.

## Decision

The target architecture is defined by the following decisions. Remediation toward
it is sequenced in the BACKLOG roadmap and gated on this ADR.

### (a) Lane taxonomy — explicit tags, not `grep-invert`

Every spec carries **at least one primary execution-lane tag**:

- `@fast` — render-only, no relay/harness (the per-PR behavioral floor)
- `@live` — single-client behavioral, local relay
- `@cross-client` — multi-client pairing
- `@demo` — Docker 3-way demo harness

plus orthogonal **tooling tags**: `@agent` (capture tools, exempt from the lane-tag
requirement) and `@visual` (storage-seeded snapshots — its own lane). The **tag is
the contract; filenames are narrative** — Home drops its `-live` filename
convention and joins the taxonomy with a real `@fast` subset.

> Refinement (2026-06-18, during P0 #2a): the contract is **"at least one"**, not
> the literally-stated "exactly one". Demo pairing specs legitimately layer
> (`@live @cross-client @demo`), and `@visual` is orthogonal to the behavioral
> tags, so "exactly one" is unworkable. The `check-spec-primary-tags` guard
> enforces "≥ 1 lane tag, `@agent` exempt", which fully closes the silent-untagged
> gap the audit found.

_Rejected:_ continuing the `--grep-invert` convention (lane membership is implicit,
"fast" conflates "render-only" with "non-relay", and specs land accidentally narrow).

### (b) CI gating tiers

- **Global per-PR gate** (`make verify`, extended): structural guards **including
  the selector + seed contracts** + docs + targets + wasm; typecheck; `@fast` e2e
  for pwa + chrome + home; a **`@live` smoke**; the **affected submodule's
  `test:unit`**; and a **lean cargo lib-test** for affected Rust.
- **Per-client per-PR gate**: scoped selector contract + typecheck + `@fast`.
- **Nightly / dispatch**: full `@live` + `@demo` + full Rust/integration + full guards.
- **`@cross-client` (non-`@demo`)**: **manual + documented as non-gated by design.**

Definitions, so the gate is unambiguous:

- **`@live` smoke** = one onboarding + one signing round-trip **per affected
  client** (a `@live @smoke` spec each for pwa/chrome/home). It is a per-PR
  integration tripwire, **not** a replacement for the full `@live` suite (nightly).
- **affected** = resolved from `test-targets.json` (a PR's touched paths → the
  clients/submodules whose tests must run). Affected `test:unit` covers the JS
  submodules (igloo-pwa / chrome / home / shared); the lean cargo `--lib` test
  covers bifrost-rs / igloo-shell. Heavy Rust/integration stays nightly.
- **`@cross-client` / `@demo` boundary (stated explicitly):** the demo 3-way
  pairing specs are tagged `@live @cross-client @demo`, and `@demo` runs nightly —
  so **demo-path cross-client coverage stays gated nightly**. Only the pure
  `@cross-client` pairing specs that are *not* also `@demo` (chrome↔pwa,
  chrome↔home, pwa↔home) are manual-only. The documented gap is the non-demo
  pairing matrix, not all cross-client coverage.

_Rejected:_ full `@live` per-PR (multi-minute relay handshakes, flake in the gate);
all unit/Rust nightly-only (unit regressions merge silently).

### (c) Single seeding source of truth

One `ProfileSeedInput` domain type with **per-target builders** (extension blob,
PWA stored seed), a single shared **test-secrets** module (one canonical test
password, today triplicated), and a **`PersistableStoredProfile` contract type**
that the runtime owns and publishes so TypeScript rejects any seed field the app
would not persist. Transient runtime state (e.g. `runtimeSnapshot`) is bootstrapped
**in-memory, never via storage seeds** (it is not persisted, so a storage seed for
it is dead and misleading).

**Ownership / import boundary (must be resolved, not finessed):** the persistable
contract is an **app-owned, published type**, not a runtime internal. To keep the
test harness from reaching into a client's `src/` (which
`test/scripts/check-cross-client-imports.sh` forbids), the contract is consumed
through a **stable shared location** — exported from `igloo-shared` (already a test
dependency) or via a single explicitly-whitelisted re-export — and the
cross-client-imports guard is updated to permit exactly that one contract import.
This preserves ADR-004 submodule ownership: the runtime owns and versions the
contract; the parent harness imports a published surface, not internals.

_Rejected:_ a test-side persistable type + sync guard (two definitions drift); a
runtime validation function (catches at test-run, not compile time); importing the
type directly from a client's `src/` (breaks the cross-client-imports guard).

Related seed debt — duplicated builders across pwa/chrome and lingering legacy v2
storage keys — is consolidation work tracked as P1, not part of this contract decision.

### (d) Unified render/verify harness

One `test/shared/visual-harness.ts` capture helper used by all `@agent` and
`@visual` specs; all output under a single `.tmp/visual/<client>/` tree with
client-scoped JSON (no clobbering under parallelism); **Home migrates off the
Linux-only system-chromium `.mjs` smoke onto bundled Playwright**; one visual
manifest + guard covers pwa, chrome, and home. The **tauri-driver desktop suite is
retained** for genuine desktop-API coverage (window, `invoke`, native dialogs).

_Rejected:_ fully unifying onto Playwright web-render (loses real Tauri/desktop-API
testing); status quo (≈148 LOC duplicated capture, scattered artifact dirs,
Linux-only Home).

### (e) WASM / artifact provenance

Keep the `.tmp/` prebuild cache for speed, and guarantee the WASM the test process
encrypts/signs with is byte-identical to the WASM the app build under test loads:

- **A fail-fast SHA-384 provenance assertion** (`test/shared/wasm-provenance.ts`,
  `assertWasmProvenance`) — **implemented 2026-06-18.** It compares each browser
  WASM binary the app build will load against the test-injected WASM
  (`resolveTestBrowserWasmDir`) and throws an actionable error on any mismatch.
  Wired into the chrome global-setup (so it gates the per-PR chrome lane) and the
  pwa-dist server in the cross-client spec (the bug site), replacing the cryptic
  "Incorrect password" with a clear provenance error.
- **One canonical WASM (structural follow-up, P0 remainder).** `prepare-browser-wasm`
  builds one shared WASM then *copies* it per client, and a single-client prebuild
  target refreshes only some clients' copies — so a dist-serving spec can load WASM
  that lags the test-injected build. Expose ONE canonical WASM dir consumed by tests
  and all client builds (or have dist-serving specs build from
  `resolveTestBrowserWasmDir`). Also expand the prebuild stamp to cover the toolchain
  (wasm-bindgen, build scripts) so a toolchain bump invalidates the cache.

> Correction (2026-06-18): the earlier draft said to make prebuild `check`
> fail-hard "because callers continue with stale". That premise was wrong —
> `test/shared/test-prebuild.ts` already does check → catch → **sync** (auto-rebuild
> on a stale stamp), so fail-hard would *remove* a useful self-heal. The real gap is
> cross-context provenance (test vs the served dist), which the assertion above
> closes; the canonical-WASM pipeline removes the skew at the source. The `@fast` /
> dev-server lanes already load one consistent WASM, so the main gates were never
> exposed — the skew is specific to dist-serving specs.

_Rejected:_ making prebuild `check` fail-hard (removes the existing self-heal for no
real gain); tracked-artifacts-only in test lanes (loses cache speed on cold runs).

### (f) Selector strategy + contract enforcement timing

**Chrome adopts the PWA page-object + test-id pattern** (converge the cross-client
selector strategy; Chrome's raw-selector specs were the main source of the Paper
restructure brittleness). The **selector and seed contracts run in the global
per-PR gate** (hoisted from nightly-only) **and** in an **opt-in pre-push git hook**
for fast local feedback. The hook is a convenience, not a new guarantee: it is
installed explicitly (e.g. `make install-hooks`, not auto-installed), is skippable
(`git push --no-verify` / an env flag), and **CI remains the source of truth** — a
violation fails the per-PR gate regardless of the local hook.

_Rejected:_ a raw-selector-through-helpers contract for Chrome (keeps strategy
divergent); leaving Chrome as-is (stays brittle); pre-commit hook (interrupts the
WIP commit loop); CI-only (violations caught only after push).

### (g) Honest lane naming

Rename lanes so names match what they cover (e.g. `test:guards` →
`test:structural`, `test:guards:full` → `test:all`) and introduce the explicit
`@fast` tag instead of overloading `--grep-invert`. Wire-or-delete the orphan
guards `check-wasm-toolchain` and `check-worktree-unchanged` (defined but never
invoked).

_Rejected:_ documenting the existing names (they stay misleading for newcomers).

### (h) E2E location

E2E specs **stay centralized in `test/`** (the parent owns cross-repo
orchestration; the demo and cross-client harnesses already live there). Submodules
keep their own unit/integration suites; the per-PR gate **runs** the affected
submodule's `test:unit`, but ownership stays with the submodule. Reaffirms ADR-004.

_Rejected:_ co-locating e2e into `repos/igloo-*/test/` (a large move that
complicates the cross-repo harness and submodule coupling).

## Consequences

- Per-PR cost rises modestly: a `@live` smoke + the affected submodule's
  `test:unit` + lean cargo lib-test + the selector/seed contracts now run on every
  PR. In exchange, behavioral, unit, selector, and WASM-provenance regressions are
  caught **same-PR** instead of nightly-or-never.
- Behavioral (`@live`), demo (`@demo`), and provenance coverage get **named,
  mandatory homes**; render-only green can no longer hide them.
- The **non-demo `@cross-client` pairing matrix is knowingly non-gated** between
  manual runs (demo-path pairing is still covered nightly via `@demo`). This is an
  accepted, documented risk, revisited if pairing regressions recur.
- Migration churn is real and has blast radius: the lane renames touch
  `test/package.json`, the `Makefile`, the CI workflows, and the docs at once (done
  atomically with deprecation aliases); the Chrome page-object migration spans every
  Chrome spec (~all of `test/igloo-chrome/specs`, the bulk of the raw-selector
  surface); plus the `PersistableStoredProfile` coupling and the visual-harness
  consolidation. The roadmap front-loads the low-churn, high-correctness P0 items.
- The pre-push hook adds local friction (push-time, not commit-time) and must be
  installable/skippable; CI remains the source of truth.
- Builds on ADR-004; introduces no change to E2E ownership.

## Implementation Rule

Remediation follows the **"Test infrastructure remediation (audit 2026-06-17)"**
roadmap in [`dev/BACKLOG.md`](../BACKLOG.md) (P0 → P2), each item gated on this ADR
being **Accepted**. Fixed sequencing constraints:

- P0 lands first: hoist the selector contract into the per-PR gate; tag every spec
  and gate the silent suites; wire the `@live` smoke + per-affected `test:unit`;
  add the WASM hash gate.
- **Tag completeness before gating.** The `@fast` tag rollout (a/g) precedes the
  lane-gating change (b): the `check-spec-primary-tags` guard asserts **every spec
  carries at least one lane tag** (`@agent` exempt) and must pass *before* the gate
  filters on `@fast` — otherwise an untagged spec is silently skipped and a green
  gate hides it. (Done 2026-06-18 for fully-untagged spec files; per-test `@fast`
  tagging lands with the lane-filter switch in (b).)
- **Atomic rename.** The lane renames (g) land in a single change across
  `test/package.json` + `Makefile` + CI workflows, with deprecation aliases for the
  old names and a `check-lane-names` guard that fails on obsolete references.
- The Chrome page-object migration (f) is P1, **after** the selector contract is in
  the per-PR gate (P0) — so the gate catches any stale selector introduced during
  the migration itself.
- The `PersistableStoredProfile` export (c) precedes the seed-builder consolidation.
- The Home visual harness migrates off the system-chromium `.mjs` onto bundled
  Playwright under the unified harness (d); the legacy `.mjs` is retired, the
  separate screenshot config folds into the main one, and tauri-driver stays for
  desktop-API e2e.
- Live behavior is verified via the `@live` / `@demo` lanes, never inferred from a
  green `@fast` run.

Roadmap scope at a glance (full detail + acceptance criteria in the BACKLOG):
**P0** = gating + tagging + core provenance/guard fixes; **P1** = consolidation &
type safety (seed builders, the contract type, the unified visual harness, WASM
stamp inputs, the Chrome migration, lane renames); **P2** = clarity & ownership
docs. This ADR is satisfied when the P0 items merge and P1/P2 are unblocked.
