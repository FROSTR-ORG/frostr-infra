# Paper Create Flow Hard-Cut and Branch Merge Plan

Date: 2026-05-22

## Summary

Finalize the current Paper Welcome/Create integration by merging `igloo-pwa` and `frostr-infra` feature branches with fast-forward merges, keep feature branches for ongoing work, then continue the next hard-cut slice on mainline from the shared Paper screens.

Current merge facts:

- `repos/igloo-pwa`: `paper-welcome-create-hard-cut` is ahead of `master`.
- Root `frostr-infra`: `igloo-paper-hard-cut` is ahead of local `master` and `origin/master`.
- `repos/igloo-ui` is already clean on `master` and in sync with `origin/master`.

## Key Changes

- Merge `repos/igloo-pwa/paper-welcome-create-hard-cut` into `repos/igloo-pwa/master` using fast-forward, then push `origin/master`.
- Merge root `igloo-paper-hard-cut` into root `master` using fast-forward, then push `origin/master`.
- Keep both feature branches after merge:
  - `repos/igloo-pwa/paper-welcome-create-hard-cut`
  - root `igloo-paper-hard-cut`
- Run `make test-prep` to restore the prepared `bifrost-devtools` binary, then rerun `rotation-create.spec.ts`.
- Continue the next Paper hard-cut slice from:
  - `repos/igloo-paper/screens/shared/3-distribute-shares`
  - `repos/igloo-paper/screens/shared/3b-distribution-completion`
  - existing PWA routes `create-confirm` and `create-distribute`

## Implementation Changes

- Replace the legacy `HostFlowShell` create-confirm and create-distribute surfaces in `igloo-pwa` with `PublicTaskShell`, the Paper stepper labels, and shared Paper-style `igloo-ui` components.
- Add or refactor shared `igloo-ui` create-flow components for:
  - read-only local profile review
  - remaining-share distribution cards
  - distribution completion state
- Preserve existing runtime behavior:
  - `Accept and Continue` still calls `acceptGeneratedProfile()`.
  - `Copy`, `QR`, and `Save` still call the existing distribution callbacks.
  - `Finish` still lands on the dashboard.
- Extend the visual harness to capture:
  - `.tmp/igloo-pwa-create/03-create-confirm.png`
  - `.tmp/igloo-pwa-create/04-distribute-shares.png`
  - `.tmp/igloo-pwa-create/05-distribution-completion.png`
- Update the follow-up report in `dev/reports` with new captures, remaining visual deltas, and verification results.

## Test Plan

Run before merging:

```sh
git status --short
git -C repos/igloo-pwa status --short
git -C repos/igloo-ui status --short
npm --prefix repos/igloo-pwa run prepare:dev
```

Merge validation:

```sh
git -C repos/igloo-pwa switch master
git -C repos/igloo-pwa merge --ff-only paper-welcome-create-hard-cut
git -C repos/igloo-pwa push origin master

git switch master
git merge --ff-only igloo-paper-hard-cut
git push origin master
```

Post-hard-cut validation:

```sh
make test-prep
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw
npm --prefix repos/igloo-pwa run build:app
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/welcome-visual.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/app-shell.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/rotation-create.spec.ts
```

## Assumptions

- Use fast-forward merges only; abort if either branch has diverged.
- Keep feature branches after merge for handoff and continued Paper work.
- Do not import `igloo-paper` into runtime packages.
- If `make test-prep` fails because of environment or network constraints, do not change product code; document the blocker in the report.
