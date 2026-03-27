# E2E and Demo Strategy

This document defines the canonical manual and automated demo/testing flows for
the infra workspace.

## Manual Demo Flows

Browser-facing local demo flows use `ws://localhost:<port>`.

First-class entrypoints:

- `./run.sh demo start`
- `./run.sh demo onboard`
- `./run.sh demo logs`
- `./run.sh demo stop`
- direct `docker compose -f compose.test.yml ...` commands for advanced/operator use

`./run.sh demo start` is the normal local path. It:

- builds the host demo binaries
- starts `services/dev-relay` and `services/igloo-demo`
- writes onboarding artifacts under `data/test-harness/`
- prints the current `bfonboard` packages, passwords, and relay URL to the console

Direct compose remains supported when an operator needs explicit control over
project names, environment variables, or log handling.

## Automated Tiers

The canonical browser/demo tiers are:

- `smoke`
  - validates the Docker-backed demo harness and local host onboarding path
  - command: `npm --prefix test run test:e2e:smoke`
- `fast`
  - non-live browser tests
  - command: `npm --prefix test run test:e2e:fast`
- `live`
  - local relay + live signer/runtime browser tests
  - command: `npm --prefix test run test:e2e:live`
- `demo`
  - Docker-backed browser onboarding/sign-through flow against `dev-relay` + `igloo-demo`
  - command: `npm --prefix test run test:e2e:demo`

The canonical aggregate browser matrix is:

- `npm --prefix test run test:e2e`
- `./run.sh test e2e`

That aggregate currently means `fast + live`. The `demo` tier stays separate so
the focused Docker-backed onboarding path can be run independently.

## Ownership

- `test/` owns the automated browser matrix and shared Playwright fixtures.
- `services/dev-relay` and `services/igloo-demo` own the Docker-backed manual/demo environment.
- `test/scripts/test-demo-harness-onboard.sh` owns the automated `smoke` tier.
- `./run.sh demo ...` wraps the manual Docker demo flow but does not replace direct compose usage.

Root `scripts/` are private implementation detail. Public root workflows should use `./run.sh ...`.

## Chrome Live Fixture Policy

Chrome `@live` tests use worker-scoped cached responder state by default.

- worker-scoped stable fixtures reuse one relay/responder/profile bundle
- isolated fixtures are reserved for tests that deliberately tear down the
  runtime, relay, or extension context in a destructive way
- reset should prefer restoring cached shell state and restarting the relay and
  daemon over re-running keygen/import/export for every spec

## Troubleshooting

- Prefer `localhost` over `127.0.0.1` for browser-facing local relay URLs.
- If the manual demo stack is stale, use `./run.sh demo stop` or
  `docker compose -f compose.test.yml down -v`.
- If a port is occupied, `./run.sh demo start` may auto-pick a free port; consult
  `data/test-harness/demo-relay-port.txt` and `./run.sh demo onboard`.
