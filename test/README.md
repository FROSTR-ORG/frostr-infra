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

For test workflow selection, client-scoped validation policy, visual iteration,
and browser-WASM testing guidance, use [`docs/WORKFLOWS.md`](./docs/WORKFLOWS.md).
This README remains the command reference.

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
npm run test:e2e:igloo-pwa:visual
npm run test:e2e:igloo-pwa:cross
npm run test:e2e:igloo-chrome
npm run test:e2e:igloo-chrome:fast
npm run test:e2e:igloo-chrome:live
npm run test:guards:pwa
npm run test:guards:chrome
npm run test:guards:home
npm run test:guards:wasm
npm run test:guards:wasm:strict
npm run test:guards:visual
npm run test:typecheck:pwa
npm run test:typecheck:chrome
npm run test:typecheck:home
npm run test:typecheck:strict-support
npm run test:typecheck:strict-helpers
npm run test:typecheck:strict-visual-specs
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

## Local Client Validation

Use client-scoped commands for routine local work. These commands avoid
initializing unrelated client submodules.

Minimal submodule sets:
- PWA: `repos/bifrost-rs`, `repos/igloo-shared`, `repos/igloo-ui`, and
  `repos/igloo-pwa`
- Chrome: `repos/bifrost-rs`, `repos/igloo-shared`, `repos/igloo-ui`, and
  `repos/igloo-chrome`
- Home: `repos/igloo-shared`, `repos/igloo-ui`, and `repos/igloo-home`

Scoped lanes should not require unrelated client submodules. For example, PWA
validation must not require `repos/igloo-chrome`, and Chrome validation must
not require `repos/igloo-pwa`.

PWA-only validation:

```bash
npm --prefix test run test:guards:pwa
npm --prefix test run test:typecheck:pwa
npm --prefix test run test:e2e:igloo-pwa
npm --prefix test run test:e2e:igloo-pwa:visual
```

This path requires `repos/bifrost-rs`, `repos/igloo-shared`, `repos/igloo-ui`,
and `repos/igloo-pwa`. It does not require `repos/igloo-chrome`,
`repos/igloo-home`, or `repos/igloo-shell`.
The visual command captures Welcome, Create, and Onboard screenshots under
`./.tmp/visual/igloo-pwa/` and is included in PWA scoped CI as artifact
evidence. `test/igloo-pwa/visual-manifest.json` maps each capture to its Paper
reference and current alignment status.

Chrome-only and Home-only validation:

```bash
npm --prefix test run test:guards:chrome
npm --prefix test run test:typecheck:chrome
npm --prefix test run test:e2e:igloo-chrome

npm --prefix test run test:guards:home
npm --prefix test run test:typecheck:home
npm --prefix test run test:e2e:igloo-home
```

Cross-client validation is explicit:

```bash
npm --prefix test run test:e2e:igloo-pwa:cross
```

Full workspace validation still uses:

```bash
npm --prefix test run test:guards
npm --prefix test run test:guards:docs
npm --prefix test run test:guards:workflows
npm --prefix test run test:guards:wasm
npm --prefix test run test:guards:wasm:strict
npm --prefix test run test:guards:selectors
npm --prefix test run test:guards:visual
npm --prefix test run test:typecheck
make test-release
```

Shared prep and root workflows:
- `make test-prep`
  - prebuilds shared Rust binaries, browser artifacts, and demo-harness images
  - uses `./.tmp/test-prebuild/` by default
  - prepares browser wasm under `./.tmp/test-prebuild/browser-wasm/` without
    mutating tracked `repos/*/public/wasm` artifacts
  - `FROSTR_TEST_PREBUILD_DIR` is an explicit override for custom scratch
    locations
- `make browser-wasm-refresh`
  - intentionally refreshes tracked browser wasm artifacts under
    `repos/*/public/wasm`
- `make wasm-toolchain-check`
  - verifies rustup, `wasm32-unknown-unknown`, `wasm-pack 0.14.0`, and a
    wasm-capable clang
- `npm --prefix test run test:guards:pwa` / `test:guards:chrome`
  - build browser wasm into `./.tmp/browser-wasm-check/` and verify client sync
    behavior without mutating tracked wasm artifacts
  - set `FROSTR_BROWSER_WASM_STRICT_TRACKED=1` for an explicit tracked-artifact
    reproducibility audit
- `npm --prefix test run test:guards:wasm`
  - runs the routine browser-WASM harness contract check without invoking
    `wasm-pack`
  - verifies that test prebuild and Playwright helper paths stay scratch-based
    and client-neutral
- `npm --prefix test run test:guards:wasm:strict`
  - builds aggregate browser wasm once through the non-mutating prebuild path
  - compares scratch shared, PWA, and Chrome wasm outputs
  - respects `FROSTR_BROWSER_WASM_STRICT_TRACKED=1` for the tracked-artifact
    reproducibility audit
  - accepts `FROSTR_TEST_SKIP_STRICT_WASM=1` only for sandboxed agent runs
    where `wasm-opt` cannot execute; do not use that skip for release
    validation
- `npm --prefix test run test:guards:visual`
  - validates the PWA visual manifest shape and screenshot/reference paths
  - checks Paper screenshot references when `repos/igloo-paper` is populated
  - runs a fixture-backed negative check for missing Paper references
- `npm --prefix test run test:typecheck:strict-support`
  - aggregate compatibility entrypoint for the strict TypeScript pilot
- `npm --prefix test run test:typecheck:strict-helpers`
  - runs strict TypeScript over shared helpers, support modules, and fixtures
- `npm --prefix test run test:typecheck:strict-visual-specs`
  - runs strict TypeScript over selected visual/reference specs
- `make test-affected`
  - runs the deterministic minimal test surface for the current branch
- `make test-release`
  - runs the full coordinated release matrix after shared prep
  - prints a compact timing summary for the root phases

If the root `./.tmp/` tree becomes stale or unwritable, repair it with
`make repo-reset` before rerunning prep or demo commands.

macOS sandboxed command runners can fail inside `wasm-pack` at the `wasm-opt`
step with `Operation not permitted`. When that happens, rerun only the affected
WASM guard or `make browser-wasm-refresh` outside the sandbox. Do not use
`make browser-wasm-refresh` as a routine test command; it intentionally updates
tracked `public/wasm` artifacts.

For sandboxed agent verification where strict WASM cannot be rerun outside the
sandbox, `FROSTR_TEST_SKIP_STRICT_WASM=1 npm --prefix test run
test:guards:wasm:strict` records an explicit skip. Release validation must run
the strict rebuild without that environment variable.

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

### Demo: multiple `igloo-pwa` tabs coordinating a signature

The PWA is a responder-only signer — it answers sign requests but cannot start
one. To watch two PWA tabs coordinate a real threshold signature, a headless
`igloo-shell` co-signer initiates it. One command scaffolds everything:

```bash
make pwa-multisig-demo
```

That builds `bifrost-devtools` + `igloo-shell`, starts a local relay, generates a
**3-of-3** keyset (so every participant is required), imports the coordinator
share into a throwaway `igloo-shell` store, starts its daemon, and prints two
`bfonboard` packages — one per browser tab — plus the onboarding password.

Then:

1. In another terminal: `make igloo-pwa-dev`.
2. Open **two** tabs at the dev URL. In each, choose **Onboard New Device**, paste
   the matching package, use the printed onboarding password, set a profile
   password, and launch the signer.
3. Wait until both dashboards show the signer running with peers connected.
4. Press **ENTER** in the demo terminal. `igloo-shell` initiates the signature;
   both tabs' event logs show the request and their partial responses, and the
   command prints the completed `signatures_hex`.

This is the manual counterpart to the automated `sign-shell.spec.ts` (`@live`),
which proves the same PWA-co-signs-a-real-signature path in CI with a single tab.

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

Root script directories are private implementation detail. Public root
workflows should use `make ...`; `scripts/` backs workspace operations,
`dev/scripts/` backs development-only bridge tooling, and `test/scripts/`
backs harness guards and test-only helpers.

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
