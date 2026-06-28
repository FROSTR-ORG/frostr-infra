# igloo-pwa C4 Real-WASM Adversarial Coverage Design

_Status: Implemented 2026-06-28._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` C4._
_Builds on: `dev/plans/igloo-shared-c4-adversarial-nip44-2026-06-28-design.md` and `dev/plans/igloo-home-c4-handler-errors-2026-06-28-design.md`._

> **For agentic workers:** this is a small feature design. Keep the
> implementation centered on `repos/igloo-pwa` repo-local Vitest coverage. Do
> not add Playwright, live relay, browser automation, signed packaging, or
> release-artifact work in this slice.

## Problem

C4 still has one remaining PWA-specific tail after the shared and Home slices:
`igloo-shared` now covers the app-facing NIP-44 wrapper boundary, and
`igloo-home` covers TS-side handler failures, but PWA unit tests still mock the
profile package WASM module through `src/test/setup.ts`.

That mock is useful for fast adapter glue tests, yet it cannot prove that PWA's
adapter surfaces reject real `bfprofile` / `bfshare` artifacts when the
passphrase is wrong or the bech32 package is corrupted. The shared package KATs
prove the checked-in WASM can reject bad inputs, but the release-plan tail calls
out `igloo-pwa`, so the PWA adapter path should exercise the real WASM loader
directly.

## Goal

Close the remaining C4 PWA tail by adding deterministic repo-local Vitest
coverage that routes PWA adapter calls through the real checked-in
`bifrost_profile_wasm` artifacts and proves wrong-password and corrupted-package
rejection.

## Chosen Approach

Add a focused real-WASM KAT file under `repos/igloo-pwa/test/frontend/`.

The test file will:

- opt out of the global injected profile WASM mock for its own cases;
- configure the shared profile loader with PWA's committed
  `public/wasm/bifrost_profile_wasm.js` and `bifrost_profile_wasm_bg.wasm`;
- create real encrypted profile/share packages from a minimal
  `BrowserProfilePackagePayload`;
- assert `adapter.importBfProfile()` rejects a wrong export password and a
  corrupted `bfprofile` package;
- assert `adapter.unlockShareFromArtifact()` rejects a wrong share passphrase
  and a corrupted `bfshare` artifact with the stable PWA message
  `Incorrect passphrase.`;
- restore the normal mocked profile module afterward so the broader PWA unit
  suite remains isolated.

## Alternatives Rejected

**Shared-only closeout.** Rejected because `igloo-shared` already has real-WASM
package KATs, while the backlog explicitly names the remaining tail as PWA
coverage.

**Playwright/browser flow.** Rejected for this slice because it adds browser
process instability and flow fixture weight without improving the specific
adapter-path assertion. The recent Chrome-for-Testing crashes make this less
attractive for a fast C4 tail.

**Production refactor.** Rejected because current behavior is expected to
already reject these inputs. The intended change is coverage plus bookkeeping
unless red-first evidence proves a PWA adapter defect.

## Scope

In scope:

1. Add one PWA real-WASM adversarial test file.
2. Reuse the existing `igloo-shared` real-WASM loader pattern.
3. Keep test isolation explicit by restoring the normal profile WASM mock after
   the real-WASM cases.
4. Update C4 release-plan/backlog wording after verification.

Out of scope:

- Playwright, live relay, demo harness, or browser UI tests.
- Production cryptography changes.
- Signed DMG, AppImage, deb, rpm, or release workflow work.
- New persistent test fixtures outside the existing checked-in WASM artifacts.

## Mechanism

The test will read the PWA WASM bytes with Node `fs` and pass them through the
existing `configureWasmProfileLoader()` escape hatch, matching the
`igloo-shared` KAT's raw-byte pattern.

Because `src/test/setup.ts` injects a profile WASM stub before each PWA unit
test, the real-WASM file must clear that injection before configuring the
loader. It should also re-inject a local copy of the normal stub in `afterEach`
so suite order cannot leak real-WASM configuration into mock-based tests.

Use adapter-level assertions rather than only low-level package functions:

- `importBfProfile()` covers the PWA import path for `bfprofile` packages.
- `unlockShareFromArtifact()` covers the PWA session-start decrypt helper for
  encrypted `bfshare` artifacts and verifies the stable non-leaky message.

## Verification

Use focused checks first, then the PWA unit suite and docs guard:

- `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/profile-real-wasm.test.ts`
- `npm --prefix repos/igloo-pwa run test:unit:raw`
- `npm --prefix test run test:guards:docs`

## Done When

- PWA has real-WASM wrong-password coverage for `bfprofile` import.
- PWA has real-WASM corrupted-package coverage for `bfprofile` import.
- PWA has real-WASM wrong-password and corrupted-package coverage for
  `unlockShareFromArtifact()`.
- C4 release-plan/backlog wording no longer lists the PWA real-WASM tail as
  open.

## Self-Review

Placeholder scan: no TBD/TODO placeholders.

Internal consistency: the design stays scoped to PWA repo-local tests and does
not widen into browser automation or release artifacts.

Scope check: this is one small test-depth feature.

Ambiguity check: production code changes are conditional on red-first test
evidence.
