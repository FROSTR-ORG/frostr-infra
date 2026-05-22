# Igloo Paper Follow-Up Hard-Cut Plan

Date: 2026-05-22

## Summary

Push the committed Welcome/Create work, stabilize the local verification blockers, and continue the Paper hard cut from `create-generate` into `shared/2-create-profile`.

## Key Changes

- Push `igloo-ui` `master`, push `igloo-pwa` detached `HEAD` to `paper-welcome-create-hard-cut`, and push root `igloo-paper-hard-cut`.
- Fix the PWA unit-test harness so `window.localStorage` behaves like browser Storage in jsdom.
- Avoid changing product code for the rotation E2E blocker; prefer using an already prepared `bifrost-devtools` binary when `FROSTR_TEST_PREPARED=1`.
- Convert `StepProgress` to Paper-style completed, active, and pending states while preserving the current `steps` plus `active` API.
- Add a shared Paper-style create-profile setup surface in `igloo-ui` and wire the PWA `create-profile` route through it.
- Extend the visual harness with `.tmp/igloo-pwa-create/02-create-profile.png`.

## Public Interfaces

- Keep `StepProgress({ steps, active })` source-compatible.
- Add an exported create-profile setup component that owns local-share selection, profile name, password/confirm password, relays, and continue action.
- Do not import `igloo-paper` or generated Paper artifacts into runtime packages.

## Test Plan

Required checks:

```sh
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw
npm --prefix repos/igloo-pwa run build:app
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/welcome-visual.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/app-shell.spec.ts
```

Conditional check after binary prep is available:

```sh
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/rotation-create.spec.ts
```

## Assumptions

- `repos/igloo-pwa/README.md` and `repos/igloo-pwa/package.json` remain unrelated and unstaged.
- The `New Keyset` / `Rotate Existing` mode control remains temporary until the rotate-keyset Paper flow gets its own hard cut.
- Root `test:typecheck` remains a separate `igloo-chrome` cleanup task.
