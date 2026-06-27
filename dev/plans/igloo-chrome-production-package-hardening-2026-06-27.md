# igloo-chrome Production-Package Hardening Plan

_Status: Approach approved 2026-06-27 - pending implementation._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` Phase 2._

> **For agentic workers:** this is a small feature brief that doubles as the
> implementation plan. Use checklist (`- [ ]`) steps for progress. Commit inside
> `repos/igloo-chrome` first, then bump the parent submodule pointer explicitly.

## Problem

`igloo-chrome` is close to public-beta packageable, and the profile cipher
finding is already fixed at `HEAD` (`054026e Keep profile unlock keys
non-extractable`). The remaining agent-doable Chrome beta work is narrower:
production packages must not carry test/debug control messages or local relay
CSP allowances, and the broad host-permission posture must be documented before
a reviewer or maintainer packages a candidate.

The non-agent launch operations are deliberately out of this implementation
unit: `frost2x` deprecation, Chrome Web Store listing/submission, hosted privacy
policy, store assets, and review latency remain maintainer launch gates.

## Goal

Make the built `igloo-chrome` production candidate mechanically reviewable:

- production output rejects or omits `DEBUG_COMMAND_TYPE` handlers;
- production `dist/manifest.json` has no `localhost` / `127.0.0.1` CSP
  connect-src entries;
- dev/test can still use local relays and debug controls where the harness needs
  them;
- host permissions are either as narrow as the current architecture permits or
  documented with a concrete rationale;
- automated checks prove the production package has the expected release shape.

## Chosen Approach

Add a build-mode seam to the existing extension-native build pipeline rather
than maintaining separate checked-in manifests.

`repos/igloo-chrome/scripts/build.mjs` already copies `public/` to `dist/`, then
bundles every entry with esbuild. The hardening should live there:

- derive a release/production mode from an explicit environment flag or existing
  script entrypoint;
- copy and mutate `public/manifest.json` into `dist/manifest.json` for that
  mode;
- pass the same mode into esbuild `define` values so background routing can tree
  away or reject debug controls in release builds;
- add a package-shape verifier that inspects built artifacts after
  `npm run build:app`.

This keeps one source manifest, one version source, and one candidate packaging
path, while still making release output materially different from dev/test where
needed.

## Alternatives Rejected

**Docs-only review.** Too weak. A human checklist can miss a dev CSP allowance or
debug handler in a release zip.

**Two checked-in manifests.** Clear at first glance, but it creates drift risk
for MV3 metadata, icons, permissions, content scripts, and version alignment.
The current release script already assumes `public/manifest.json` is the source
of truth.

**Cut all debug message types from shared protocol definitions.** Overbroad.
The tests and visual/dev seams still need controlled reset/seed operations; the
public package only needs them absent or inert.

## Scope

In scope:

1. Production-build gating for `DEBUG_COMMAND_TYPE` routing in
   `repos/igloo-chrome/src/background/router-state.ts` and any protocol/client
   types needed to keep TypeScript honest.
2. Production manifest mutation in `repos/igloo-chrome/scripts/build.mjs` so
   `dist/manifest.json` omits local relay CSP entries.
3. A release-shape verification script under `repos/igloo-chrome/scripts/`,
   wired into package/release commands where appropriate.
4. Repo docs updates explaining host permissions and the production/dev build
   distinction.
5. Focused unit tests around debug routing and manifest/package verification.

Out of scope:

- `frost2x` final pointer release, unpublish timeline, and key export path.
- Chrome Web Store listing, store screenshots/assets, privacy-policy hosting,
  support contact, and submission.
- Reworking the content-script injection model or provider architecture.
- Reopening the C2 profile-cipher work unless verification shows a regression.

## Implementation Tasks

### Task 1: Ground the current production surface

- [ ] Confirm C2 remains closed by reading
  `repos/igloo-chrome/src/lib/profile-blob.ts` and
  `repos/igloo-chrome/tests/unit/lib/profile-blob.test.ts`; no changes unless a
  regression is found.
- [ ] Read the current debug routing path:
  `repos/igloo-chrome/src/extension/messages.ts`,
  `repos/igloo-chrome/src/background/router-state.ts`,
  `repos/igloo-chrome/src/background/router.ts`, and
  `repos/igloo-chrome/tests/unit/background/router.test.ts`.
- [ ] Build once with the current path (`npm --prefix repos/igloo-chrome run
  build:app`) and inspect `repos/igloo-chrome/dist/manifest.json` plus
  `dist/background.js` to establish the pre-change failure shape.

### Task 2: Add explicit release-mode build plumbing

- [ ] In `repos/igloo-chrome/scripts/build.mjs`, introduce a small build-mode
  helper, for example `const isReleaseBuild = process.env.IGLOO_CHROME_RELEASE
  === '1';`.
- [ ] Replace raw `copyPublic()` manifest copying with a manifest writer that
  reads `public/manifest.json`, mutates only the CSP connect-src value for
  release builds, and writes the result to `dist/manifest.json`.
- [ ] In release mode, remove these CSP fragments from `extension_pages`:
  `ws://localhost:*`, `ws://127.0.0.1:*`, `http://localhost:*`, and
  `http://127.0.0.1:*`.
- [ ] Preserve local CSP entries for normal dev/test builds, because the harness
  and manual demo relays use local browser-facing URLs.
- [ ] Add an esbuild define such as
  `import.meta.env.IGLOO_CHROME_RELEASE` so code can branch on the same mode.

### Task 3: Gate debug commands out of release routing

- [ ] Refactor `createStateRouter()` so the three `DEBUG_COMMAND_TYPE` handlers
  are added only when the release define is false.
- [ ] Keep normal command routing unchanged.
- [ ] Update `repos/igloo-chrome/tests/unit/background/router.test.ts` or add a
  focused state-router test that proves debug commands route in normal test mode.
- [ ] Add a release-mode unit test if practical by extracting the debug handler
  map behind a pure function; otherwise rely on the artifact verifier in Task 4
  for release-mode proof.

### Task 4: Add a production-package verifier

- [ ] Create `repos/igloo-chrome/scripts/check-production-package.mjs`.
- [ ] The script reads `dist/manifest.json` and fails if the CSP contains
  `localhost` or `127.0.0.1`.
- [ ] The script reads `dist/background.js` and fails if it contains the debug
  command string literals:
  `ext.debug.reload`, `ext.debug.clearProfileUnlocks`, or
  `ext.debug.seedProfileUnlock`.
- [ ] Wire a package/release script so release candidates run:
  `IGLOO_CHROME_RELEASE=1 npm run build:app` followed by the verifier before
  packaging.
- [ ] Keep default `npm run build` behavior compatible with current dev/test
  lanes unless the release candidate script is explicitly used.

### Task 5: Document host permissions and release shape

- [ ] Update `repos/igloo-chrome/README.md` or `RELEASE.md` with a short
  production package note: release builds strip debug handlers and local relay
  CSP entries.
- [ ] Document the current broad host permissions rationale: the provider bridge
  must be injectable on arbitrary `http`/`https` sites that request Nostr
  signing, and relay connectivity needs `ws`/`wss` hosts configured by the
  signer profile. If a narrower architecture is later desired, it is a separate
  product/design change.
- [ ] Add a changelog `[Unreleased]` entry for the production-package hardening.

### Task 6: Verify and commit

- [ ] Run focused checks:
  `npm --prefix repos/igloo-chrome run test:unit:raw` and the new release-shape
  script through its wired package command.
- [ ] Run the smallest workspace proof for Chrome:
  `make igloo-chrome-build` and, if the code touches router behavior materially,
  `npm --prefix test run test:e2e:igloo-chrome:fast`.
- [ ] Commit inside `repos/igloo-chrome`.
- [ ] From the parent, stage only `repos/igloo-chrome` and commit the pointer
  bump. Do not push.

## Verification Gate

The implementation is done when:

- Chrome unit tests pass.
- A release-mode build fails the verifier if debug strings or local CSP entries
  are present, and passes with the intended production output.
- `repos/igloo-chrome/dist/manifest.json` in release mode contains no
  `localhost` / `127.0.0.1` CSP entries.
- `repos/igloo-chrome/dist/background.js` in release mode contains no
  `ext.debug.*` command strings.
- Host-permission rationale is documented in tracked Chrome docs.

## Critical Considerations

- Do not change the runtime signer model; the extension stays a thin MV3 host
  over `bifrost-rs`.
- Do not remove local relay support from dev/test builds; the workspace harness
  depends on browser-facing local relay URLs.
- Do not use `git add -A`. Commit in the submodule first, then explicitly stage
  the parent pointer.
- Do not push; the maintainer owns integration and remote updates.
