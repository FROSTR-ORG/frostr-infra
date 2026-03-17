# Infra E2E Tests

Infra-owned browser tests that span multiple repos.

Current suites:
- `igloo-pwa`: browser-app Playwright coverage against `repos/igloo-pwa`
- `igloo-chrome`: extension Playwright coverage against `repos/igloo-chrome`
- `igloo-home`: desktop co-signer harness against `repos/igloo-home`

These tests live here because they exercise runtime behavior sourced from other
submodules, especially `repos/bifrost-rs`.

## Install

```bash
cd test
npm install
npm run test:install-browsers
```

## Run

```bash
npm run test:e2e
npm run test:e2e:smoke
npm run test:e2e:fast
npm run test:e2e:live
npm run test:e2e:demo
npm run test:e2e:igloo-home
npm run test:e2e:igloo-pwa
npm run test:e2e:igloo-chrome
npm run test:e2e:igloo-chrome:fast
npm run test:e2e:igloo-chrome:live
```

Canonical tiers:
- `smoke`: Docker-backed demo harness smoke via `../scripts/test-demo-harness-onboard.sh`
- `fast`: `igloo-pwa` plus non-live `igloo-chrome`
- `live`: Chrome live relay/runtime/provider coverage
- `demo`: Docker-backed Chrome onboarding/sign-through against `dev-relay` + `igloo-demo`

The `igloo-chrome` suite uses Playwright global setup to prebuild the extension
and shared `igloo-shell` binaries once per run. Live browser tests reuse a
worker-scoped relay/runtime backend and a worker-scoped onboarding bootstrap by
default; isolated startup is reserved for lifecycle specs that truly need it.

Manual demo/testing flows are documented in
[`../docs/E2E-DEMO-STRATEGY.md`](../docs/E2E-DEMO-STRATEGY.md). Local
browser-facing demo relays should use `ws://localhost:<port>`.

Submodule convenience scripts still proxy here:
- `repos/igloo-pwa`: `npm run test:e2e`
- `repos/igloo-chrome`: `npm run test:e2e`

Legacy note:
- `npm run test:e2e:igloo-web` is now a compatibility alias to `igloo-pwa` while the old repo is retired.
