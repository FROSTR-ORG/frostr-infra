# Cross-Repo E2E and Demo Tests

This directory owns the infra-level browser, desktop, and demo-harness tests
that span multiple repos.

Current suites:
- `igloo-pwa`
  - browser-app Playwright coverage against `repos/igloo-pwa`
- `igloo-chrome`
  - extension Playwright coverage against `repos/igloo-chrome`
- `igloo-home`
  - desktop co-signer harness against `repos/igloo-home`

These tests live here because they exercise runtime behavior sourced from
multiple repos, especially `repos/bifrost-rs` and the host repos under
`repos/`.

## Install

```bash
cd test
npm install
npm run test:install-browsers
```

## Canonical Entry Points

From `test/`:

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

From the repo root:

```bash
./run.sh test smoke
./run.sh test fast
./run.sh test live
./run.sh test demo
./run.sh test e2e
./run.sh test prep
./run.sh test affected
./run.sh test release
```

## Automated Tiers

- `smoke`
  - validates the Docker-backed demo harness and local host onboarding path
  - command: `npm --prefix test run test:e2e:smoke`
- `fast`
  - non-live browser tests
  - command: `npm --prefix test run test:e2e:fast`
- `live`
  - local relay plus live signer/runtime browser tests
  - command: `npm --prefix test run test:e2e:live`
- `demo`
  - Docker-backed browser onboarding and sign-through flow against
    `dev-relay` plus `igloo-demo`
  - command: `npm --prefix test run test:e2e:demo`

The canonical aggregate browser matrix is:

```bash
npm --prefix test run test:e2e
./run.sh test e2e
```

That aggregate currently means `fast + live`. The `demo` tier stays separate so
the focused Docker-backed onboarding path can be run independently.

Shared prep and root workflows:
- `./run.sh test prep`
  - prebuilds shared Rust binaries, browser artifacts, and demo-harness images
  - uses `./.tmp/test-prebuild/` by default
  - `FROSTR_TEST_PREBUILD_DIR` is an explicit override for custom scratch
    locations
- `./run.sh test affected`
  - runs the deterministic minimal test surface for the current branch
- `./run.sh test release`
  - runs the full coordinated release matrix after shared prep
  - prints a compact timing summary for the root phases

If the root `./.tmp/` tree becomes stale or unwritable, repair it with
`./run.sh repo reset` before rerunning prep or demo commands.

## Manual Demo Flows

Browser-facing local demo flows should use `ws://localhost:<port>`.

First-class entrypoints:

```bash
./run.sh demo start
./run.sh demo onboard
./run.sh demo logs
./run.sh demo stop
```

`./run.sh demo start` is the normal local path. It:
- builds the host demo binaries
- starts `services/dev-relay` and `services/igloo-demo`
- writes onboarding artifacts under `./.tmp/test-harness/`
- prints the current `bfonboard` packages, passwords, and relay URL

Direct `docker compose -f compose.test.yml ...` commands remain available for
advanced/operator use when explicit project names, environment variables, or log
control are needed.

## Ownership

- `test/` owns the automated browser matrix and shared Playwright fixtures
- `services/dev-relay` and `services/igloo-demo` own the Docker-backed demo
  environment
- `test/scripts/test-demo-harness-onboard.sh` owns the automated `smoke` tier
- `./run.sh demo ...` wraps the manual demo flow but does not replace direct
  compose usage

Root `scripts/` are private implementation detail. Public root workflows should
use `./run.sh ...`.

Submodule convenience scripts still proxy here:
- `repos/igloo-pwa`: `npm run test:e2e`
- `repos/igloo-chrome`: `npm run test:e2e`

## Chrome Live Fixture Policy

Chrome `@live` tests use worker-scoped cached responder state by default.

- worker-scoped stable fixtures reuse one relay, responder, and profile bundle
- isolated fixtures are reserved for tests that deliberately tear down the
  runtime, relay, or extension context in a destructive way
- reset should prefer restoring cached shell state and restarting the relay and
  daemon over re-running keygen/import/export for every spec

## Troubleshooting

- Prefer `localhost` over `127.0.0.1` for browser-facing local relay URLs.
- If the manual demo stack is stale, use `./run.sh demo stop` or
  `docker compose -f compose.test.yml down -v`.
- If a port is occupied, `./run.sh demo start` may auto-pick a free port; check
  `.tmp/test-harness/demo-relay-port.txt` and `./run.sh demo onboard`.
