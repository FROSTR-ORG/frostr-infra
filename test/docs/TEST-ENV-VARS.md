# Test environment variables

The environment variables the cross-repo test harness reads, grouped by purpose.
Most are set automatically by the `make`/`npm` lanes; you only set them by hand to
override a default or to reproduce a CI condition. See
[`WORKFLOWS.md`](./WORKFLOWS.md) for lane selection and [`../README.md`](../README.md)
for the command surface.

## Lane selection & prebuild

| Variable | Purpose |
|----------|---------|
| `FROSTR_TEST_LANE` | `fast` selects the lean `fastPrebuild` target set (per `test-targets.json`); unset uses the full `prebuild` set. |
| `FROSTR_TEST_PREPARED` | `1` asserts prebuild already ran (CI / `make test-prep`); helpers fail instead of building on demand. |
| `FROSTR_TEST_PREPARED_TARGETS` | Comma-separated targets already prepared, paired with `FROSTR_TEST_PREPARED`. |
| `FROSTR_TEST_PREBUILD_DIR` | Override the scratch prebuild root (default `./.tmp/test-prebuild`). |
| `FROSTR_TEST_PREBUILD_SKIP_SUBMODULE_CHECK` / `…_SKIP_WASM_TARGET_CHECK` | Skip the respective prebuild preflight (sandboxed agents). |

## Affected-lane detection (`make test-affected`)

| Variable | Purpose |
|----------|---------|
| `FROSTR_AFFECTED_BASE` | Git ref to diff against (default `origin/master`). |
| `FROSTR_AFFECTED_FILES` | Explicit newline-separated file list, bypassing the git diff. |
| `FROSTR_AFFECTED_DRY_RUN` | `1` prints the commands/targets it would run without executing. |

## Browser WASM

| Variable | Purpose |
|----------|---------|
| `FROSTR_BROWSER_WASM_STRICT_TRACKED` | `1` audits the committed `repos/*/public/wasm` against a fresh build (reproducibility). |
| `FROSTR_TEST_SKIP_STRICT_WASM` | `1` skips the strict wasm rebuild (e.g. a sandbox without `wasm-opt`). |
| `FROSTR_TEST_BROWSER_WASM_DIR` | Override the test-injected browser WASM directory. |

## Screenshots / visual (`make screenshot`)

| Variable | Purpose |
|----------|---------|
| `FROSTR_SCREENSHOT_STATE` | The dev-scenario state to render (e.g. `dashboard-running`, `onboarding`); home maps `dashboard-running`→`dashboard-signer`. |

## igloo-home desktop harness

| Variable | Purpose |
|----------|---------|
| `IGLOO_HOME_TEST_MODE` | `1` starts the loopback test-server dispatcher (Cargo `test-server` feature). |
| `IGLOO_HOME_TEST_PORT` / `IGLOO_HOME_TEST_TOKEN` | Loopback dispatcher port + bootstrap token (auto-allocated per run). |
| `IGLOO_HOME_TEST_APP_DATA_DIR` | Per-run app-data dir (temp). |
| `IGLOO_HOME_TEST_SKIP_BUILD` / `IGLOO_HOME_TEST_BINARY` | Reuse a prebuilt binary instead of rebuilding. |
| `IGLOO_HOME_TEST_SHOW_WINDOW` | `1` shows the desktop window (default hidden). |

## Demo harness (Docker: dev-relay + igloo-demo)

| Variable | Purpose |
|----------|---------|
| `DEV_RELAY_PORT` / `DEV_RELAY_EXTERNAL_HOST` | Relay port + host the demo containers publish (port auto-allocated). |
| `IGLOO_DEMO_RELAY_PORT` | Pin the chrome demo-harness relay port (else OS-assigned via `listen(0)`). |
| `IGLOO_SHELL_DEMO_MEMBER` / `IGLOO_SHELL_DEMO_INVITE_MEMBERS` | Which demo group member runs locally / which are invited. |
| `FROSTR_DEMO_COMPOSE_OVERRIDE` | Compose override file (CI uses `compose.ci.yml`). |
| `IGLOO_TRACE` / `IGLOO_TRACE_LEVEL` | Enable signer trace logging in the harness. |
