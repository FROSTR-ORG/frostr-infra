# Igloo PWA Welcome Hard-Cut Follow-Up

Date: 2026-05-22

## Scope

This follow-up records the hard-cut Welcome implementation now shared between `igloo-ui` and `igloo-pwa`.

Covered Paper targets:

- `repos/igloo-paper/screens/welcome/1-welcome/screenshot.png`
- `repos/igloo-paper/screens/welcome/1b-returning/screenshot.png`
- `repos/igloo-paper/screens/welcome/1c-returning-multi/screenshot.png`
- `repos/igloo-paper/screens/welcome/1d-returning-many/screenshot.png`
- `repos/igloo-paper/screens/welcome/1c-1-unlock-profile-modal/screenshot.png`
- `repos/igloo-paper/screens/welcome/1c-2-unlock-error-modal/screenshot.png`

## Implementation Notes

- `WelcomeReturningHero` now renders the returning Welcome family from a shared `layout` plus profile list API.
- `WelcomeUnlockModal` is the shared unlock surface for normal and incorrect-password states.
- `igloo-pwa` now uses the Paper Welcome surface for every landing profile count.
- Stored-profile unlock goes through the modal and validates the entered password through the existing runtime start path.
- The previous generic multi-profile landing card is no longer used by the PWA landing surface.

## Screenshot Harness

Repeatable Playwright harness:

```sh
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/welcome-visual.spec.ts
```

Generated captures:

- `.tmp/igloo-pwa-welcome/01-first-launch.png`
- `.tmp/igloo-pwa-welcome/02-returning-single.png`
- `.tmp/igloo-pwa-welcome/03-returning-multi.png`
- `.tmp/igloo-pwa-welcome/04-returning-many.png`
- `.tmp/igloo-pwa-welcome/05-unlock-modal.png`
- `.tmp/igloo-pwa-welcome/06-unlock-modal-error.png`

## Remaining Deltas

- Footer fourth icon remains representative rather than an exact Paper glyph.
- Secondary button color and border tuning still needs one Paper-vs-browser visual pass.
- Returning row and modal spacing are structurally aligned, but should be tightened with direct screenshot review before calling them pixel-close.
- The next hard-cut target is `create-generate`, mapped to `repos/igloo-paper/screens/create/1-create-keyset/screenshot.png`.

## Create Flow Follow-Up Slice

The first `create-generate` and `create-profile` slices are now included in the visual harness. They cover the default create-keyset entry screen reached from Welcome and the subsequent Paper-style local profile setup screen.

Generated capture:

- `.tmp/igloo-pwa-create/01-create-keyset.png`
- `.tmp/igloo-pwa-create/02-create-profile.png`

Implementation notes:

- `StepProgress` now renders Paper-style complete, active, and pending states while preserving the existing `steps` plus `active` API.
- `igloo-ui` exports `CreateFlowProfileSetup` for the local share chooser, profile name, password/confirm password, relays, and continue action.
- `igloo-pwa` now routes `create-profile` through the shared Paper-style setup surface.
- The PWA unit harness now restores a browser-like `window.localStorage` before each test, which unblocks the unit app shell suite under the current Vitest environment.
- `FROSTR_TEST_PREPARED=1` rotation E2E runs now fail fast with a clear missing prepared binary error instead of attempting an offline Cargo dependency resolution path.

Remaining deltas:

- The legacy `New Keyset` / `Rotate Existing` mode control is intentionally retained below the primary action to preserve the existing rotate-keyset entry path until that flow receives its own Paper hard cut.
- The private-key field is presentational in this slice; the current runtime still generates the keyset from the existing `groupName`, `threshold`, and `count` contract.
- The create-profile spacing and typography are browser-aligned, but should receive one direct Paper overlay pass before calling it pixel-close.
- The relays block remains a functional textarea with a Paper-style status header; the exact Paper interaction model may need adjustment when relay editing becomes first-class.

## Verification

Passed:

```sh
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw
npm --prefix repos/igloo-pwa run build:app
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/welcome-visual.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/app-shell.spec.ts
```

Known non-pass:

```sh
npm --prefix test run test:typecheck
```

This root typecheck is blocked by existing `igloo-chrome` path/type errors outside the Welcome change set. Do not treat it as a Welcome regression.

Additional known non-pass:

```sh
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/rotation-create.spec.ts
```

The rotation-create Playwright spec is still blocked until a prepared `bifrost-devtools` binary exists under the expected browser-artifacts path. With `FROSTR_TEST_PREPARED=1`, the spec now reports that missing binary directly and instructs the operator to run `make test-prep`.
