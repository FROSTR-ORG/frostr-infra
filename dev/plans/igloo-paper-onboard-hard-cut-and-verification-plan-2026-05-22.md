# Paper Onboarding Hard-Cut and Verification Cleanup Plan

Date: 2026-05-22

## Summary

Implement the next Paper hard-cut around recipient onboarding, clean up merged feature branches, and remove the current validation blockers so the full PWA/create/onboard path can be verified from `master`.

Primary Paper targets:

- `repos/igloo-paper/screens/onboard/1-enter-package`
- `repos/igloo-paper/screens/onboard/2-handshake`
- `repos/igloo-paper/screens/onboard/2b-onboarding-failed`
- `repos/igloo-paper/screens/onboard/3-onboarding-complete`

## Key Changes

- Delete merged feature branches after confirming `master` is pushed and clean:
  - root local/remote `igloo-paper-hard-cut`
  - `repos/igloo-pwa` local/remote `paper-welcome-create-hard-cut`
- Fix validation prerequisites:
  - Install `wasm-pack` if missing, preferring `brew install wasm-pack` on this macOS workspace.
  - Refresh Cargo cache for `repos/bifrost-rs` with `cargo fetch --manifest-path repos/bifrost-rs/Cargo.toml --locked`, then keep the existing offline `make test-prep` path.
- Correct distribution completion semantics before onboarding:
  - `prepare` creates the package and puts the row in “ready to distribute”.
  - `copy`/`qr` put the row in “waiting for handoff”.
  - `save` keeps the row ready unless explicitly marked.
  - `mark` completes the handoff.
  - Future echo support can complete handoff using the same completed result shape.

## Implementation Changes

- Extend the shared distribution result contract in `igloo-ui` and `igloo-pwa` from the current prepared-as-complete model to explicit states:
  - `package_ready`
  - `handoff_pending`
  - `completed`
- Add shared Paper-style recipient onboarding components in `igloo-ui`:
  - enter-package form for `bfonboard` plus password
  - handshake/progress surface for the async connect step
  - save/complete surface for profile review, local label, local password, and finish action
  - failed state surface for invalid package/password or handshake failure
- Wire `igloo-pwa` recipient onboarding routes through the new shared components:
  - `onboard-connect` uses the Paper enter-package screen.
  - async `connectOnboardingPackage()` shows the Paper handshake state while running.
  - connect errors show the Paper failed state without losing entered package text.
  - `onboard-save` uses the Paper completion/save surface and still calls `finalizeOnboardedDevice()`.
- Preserve runtime behavior:
  - No `igloo-paper` imports in runtime packages.
  - Existing adapter methods remain the source of package decoding, handshake, profile creation, and persistence.
  - Existing `bfonboard` Playwright helpers continue to work with updated selectors.

## Test Plan

Validation prerequisite checks:

```sh
command -v wasm-pack
cargo fetch --manifest-path repos/bifrost-rs/Cargo.toml --locked
make test-prep
npm --prefix test run test:guards
```

Focused package checks:

```sh
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run test:unit:raw
npm --prefix repos/igloo-pwa run build:app
```

Browser checks:

```sh
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/welcome-visual.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/app-shell.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/onboarding.spec.ts
FROSTR_TEST_PREPARED=1 npm --prefix test exec -- playwright test -c test/igloo-pwa/playwright.config.ts test/igloo-pwa/specs/rotation-create.spec.ts
```

Visual artifacts to add:

- `.tmp/igloo-pwa-onboard/01-enter-package.png`
- `.tmp/igloo-pwa-onboard/02-handshake.png`
- `.tmp/igloo-pwa-onboard/03-onboarding-complete.png`
- `.tmp/igloo-pwa-onboard/04-onboarding-failed.png`

## Assumptions

- Work happens on `master` now that the previous feature branches are merged.
- Delete merged feature branches after the plan artifact is committed and pushed.
- Use network only for prerequisite installation/fetching; do not remove the repo’s offline `make test-prep` behavior.
- Echo confirmation remains future runtime work; this slice adds the explicit UI/data state needed for echo without implementing live echo telemetry.
