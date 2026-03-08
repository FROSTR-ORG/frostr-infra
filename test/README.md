# Infra E2E Tests

Infra-owned browser tests that span multiple repos.

Current suites:
- `igloo-web`: onboarding/signer Playwright smoke against `repos/igloo-web`
- `igloo-chrome`: extension Playwright coverage against `repos/igloo-chrome`

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
npm run test:e2e:igloo-web
npm run test:e2e:igloo-chrome
```

Submodule convenience scripts still proxy here:
- `repos/igloo-web`: `npm run test:e2e`
- `repos/igloo-chrome`: `npm run test:e2e`
