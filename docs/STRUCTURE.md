# Repository Structure

- `compose.yml`: main Docker Compose stack.
- `compose.test.yml`: relay + igloo-shell demo harness for manual pairing and live/E2E testing.
- `compose.prod.yml`: production-style compose overrides (no source bind mounts).
- `compose.override.yml`: generated local package mount overrides.
- `./run.sh infra start`: uses only `compose.yml`.
- `./run.sh infra dev`: uses `compose.yml` + `compose.override.yml`.
- `build/`: local build artifacts (intentionally available for generated outputs).
- `run.sh`: curated public command router for repo-local infra, demo, test, and browser tasks.
- `repos/`: remaining upstream repos tracked as submodules (`bifrost-rs`, `igloo-shell`, `igloo-chrome`, `igloo-home`, `igloo-pwa`, `igloo-shared`, `igloo-ui`).
- `services/`: infra-owned Dockerfiles and entrypoints per service container.
- `scripts/`: private helper scripts used by `run.sh` and test harnesses.
- `test/`: infra-owned cross-repo Playwright suites and harness code.
- `data/`: persistent runtime state.
- `logs/`: service log mounts.
- Submodule operations in this repo are intentionally non-recursive.

## Ownership Boundaries

- `repos/bifrost-rs`: signer core, routing, bridge runtimes, host layer, and protocol implementation.
- `repos/igloo-shell`: CLI, relay, keygen, package tooling, and shell-owned runtime E2E.
  Active script surface: `repos/igloo-shell/scripts/` and `repos/igloo-shell/dev/scripts/`.
- `repos/igloo-chrome`: browser host/control plane over `bifrost-rs` plus provider/UI surfaces.
- `repos/igloo-home`: desktop/browser-shell host surface for local multi-profile workflows.
- `repos/igloo-pwa`: PWA host surface for browser-first onboarding, recovery, and rotation flows.
- `repos/igloo-shared`: shared browser/runtime/package bridge layer used by the browser hosts.
- `repos/igloo-ui`: shared presentational UI package consumed by browser-facing hosts.
- `docs/`: cross-repo architecture, ADRs, and guidance docs that should not live inside one submodule.

## Shared Runtime Model

- `bifrost-rs` is the source of truth for signer status, readiness, runtime events, and reset semantics.
- `igloo-chrome`, `igloo-home`, and `igloo-pwa` host that runtime through their respective browser/desktop surfaces.
- `test/` owns browser-level and cross-repo E2E harnesses, including live signer fixtures and the Docker demo harness.
