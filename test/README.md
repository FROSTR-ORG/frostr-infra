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
make test-smoke
make test-fast
make test-live
make test-demo
make test-e2e
make test-prep
make test-affected
make test-release
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
  - required in the `release-validation` GitHub Actions workflow

The canonical aggregate browser matrix is:

```bash
npm --prefix test run test:e2e
make test-e2e
```

That aggregate currently means `fast + live`. The `demo` tier stays separate so
the focused Docker-backed onboarding path can be run independently.
The release-facing CI gate runs that `demo` tier explicitly through
`make test-demo`.

Shared prep and root workflows:
- `make test-prep`
  - prebuilds shared Rust binaries, browser artifacts, and demo-harness images
  - uses `./.tmp/test-prebuild/` by default
  - `FROSTR_TEST_PREBUILD_DIR` is an explicit override for custom scratch
    locations
- `make test-affected`
  - runs the deterministic minimal test surface for the current branch
- `make test-release`
  - runs the full coordinated release matrix after shared prep
  - prints a compact timing summary for the root phases

If the root `./.tmp/` tree becomes stale or unwritable, repair it with
`make repo-reset` before rerunning prep or demo commands.

## Manual Demo Flows

Browser-facing local demo flows should use `ws://localhost:<port>`.

First-class entrypoints:

```bash
make demo-start
make demo-onboard
make demo-logs
make demo-stop
```

Direct `docker compose -f compose.test.yml ...` commands remain available for
advanced/operator use when explicit project names, environment variables, or log
control are needed.

### Demo Setup

Start the shared demo stack from the workspace root:

```bash
make demo-start
```

That command:

- refreshes the shared browser-WASM artifacts from the current `bifrost-rs` source and syncs them into browser hosts
- starts `services/dev-relay` plus `services/igloo-demo`
- provisions the live demo signer inside `igloo-demo`
- exports the current relay URL, onboarding packages, and passwords
- writes the artifacts under `./.tmp/test-harness/`

`make demo-start` launches the stack in the background. Use
`make demo-foreground` to stay attached to compose output in the current
terminal and stop the stack with `Ctrl-C`.

The important local files are:

- `./.tmp/test-harness/demo-relay-port.txt`
- `./.tmp/test-harness/onboard-bob.txt`
- `./.tmp/test-harness/onboard-bob.password.txt`
- `./.tmp/test-harness/onboard-carol.txt`
- `./.tmp/test-harness/onboard-carol.password.txt`

At any point you can reprint the current packages and relay URL with:

```bash
make demo-onboard
```

By default the demo harness exports two remote shares, `bob` and `carol`. That
means one demo run can onboard two separate host projects at the same time. If
you want to demo a third host from a clean package, stop and restart the demo
stack so the onboarding artifacts are regenerated.

### Demo `igloo-pwa`

Start the PWA host from the workspace root:

```bash
make igloo-pwa-dev
```

That command also refreshes and syncs browser-WASM artifacts before starting the host.

Then in the browser:

1. Open the printed local URL, normally `http://localhost:1430`.
2. Click `Continue Onboarding`.
3. Paste one of the exported packages, for example the contents of
   `./.tmp/test-harness/onboard-bob.txt`.
4. Paste the matching package password from
   `./.tmp/test-harness/onboard-bob.password.txt`.
5. Click `Connect`.
6. On `Review Onboarded Profile`, confirm the imported group and relay preview.
7. Enter `Device Profile Name`, `Device Password`, and `Confirm Password`.
8. Leave `Relays` pointed at the demo relay unless you are intentionally
   overriding the package defaults.
9. Click `Save Device`.

The onboarded PWA profile will connect to the relay URL printed by
`make demo-start`, for example `ws://localhost:8194`, and can then interact
with the live signer running inside `igloo-demo`.

### Demo `igloo-shell`

Use a different onboarding package than the one consumed by the PWA if you are
showing multiple hosts in the same session.

From `repos/igloo-shell`:

```bash
cargo run -p igloo-shell-cli -- \
  onboard ../../.tmp/test-harness/onboard-carol.txt \
  --label demo-carol-shell \
  --onboard-secret "$(cat ../../.tmp/test-harness/onboard-carol.password.txt)" \
  --passphrase demo-passphrase \
  --start
```

That command:

- imports the `bfonboard` package
- saves the local shell-managed profile
- unlocks it with the supplied passphrase
- starts the runtime and attaches to the daemon log

Useful follow-up commands from `repos/igloo-shell`:

```bash
cargo run -p igloo-shell-cli -- profile list
cargo run -p igloo-shell-cli -- daemon status --profile <profile-id>
cargo run -p igloo-shell-cli -- runtime status --profile <profile-id>
```

The imported profile already carries the relay information for the live demo
stack, so no extra relay setup is required when onboarding from the demo
package.

### Demo `igloo-home`

Start the desktop host from the workspace root:

```bash
make igloo-home-tauri-dev
```

Then in the desktop app:

1. Click `Continue Onboarding` from the landing page.
2. Enter the onboarding package password from
   `./.tmp/test-harness/onboard-bob.password.txt` or
   `./.tmp/test-harness/onboard-carol.password.txt`.
3. Paste the matching `bfonboard` package text from
   `./.tmp/test-harness/onboard-bob.txt` or
   `./.tmp/test-harness/onboard-carol.txt`.
4. Click `Connect`.
5. On `Review Onboarded Profile`, confirm the resolved group and relay preview.
6. Enter a local device label.
7. Enter a passphrase for the desktop profile.
8. Click `Save Device`.

The imported desktop profile will load with the relay settings supplied by the
demo package, connect to `dev-relay`, and land on the shared dashboard shell.

### Demo Cleanup

When the session is done:

```bash
make demo-stop
```

If you want to inspect the live demo services during the session:

```bash
make demo-logs
```

## Ownership

- `test/` owns the automated browser matrix and shared Playwright fixtures
- `services/dev-relay` and `services/igloo-demo` own the Docker-backed demo
  environment
- `test/scripts/test-demo-harness-onboard.sh` owns the automated `smoke` tier
- `make demo-...` wraps the manual demo flow but does not replace direct
  compose usage

Root `scripts/` are private implementation detail. Public root workflows should
use `make ...`.

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
- If the manual demo stack is stale, use `make demo-stop` or
  `docker compose -f compose.test.yml down -v`.
- If a port is occupied, `make demo-start` may auto-pick a free port; check
  `.tmp/test-harness/demo-relay-port.txt` and `make demo-onboard`.
