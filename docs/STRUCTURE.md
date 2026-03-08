# Repository Structure

- `compose.yml`: main Docker Compose stack.
- `compose.test.yml`: relay + bifrost demo harness for manual pairing and live/E2E testing.
- `compose.prod.yml`: production-style compose overrides (no source bind mounts).
- `compose.override.yml`: generated local package mount overrides.
- `make start`: uses only `compose.yml`.
- `make dev`: uses `compose.yml` + `compose.override.yml`.
- `build/`: local build artifacts (intentionally available for generated outputs).
- `repos/`: remaining upstream repos tracked as submodules (`bifrost-rs`, `igloo-chrome`, `igloo-web`).
- `services/`: infra-owned Dockerfiles and entrypoints per service container.
- `scripts/`: setup/check/reset/update helpers.
- `test/`: infra-owned cross-repo Playwright suites and harness code.
- `data/`: persistent runtime state.
- `logs/`: service log mounts.
- Submodule operations in this repo are intentionally non-recursive.
