# Repository Structure

- `compose.yml`: main Docker Compose stack.
- `compose.prod.yml`: production-style compose overrides (no source bind mounts).
- `compose.override.yml`: generated local package mount overrides.
- `make start`: uses only `compose.yml`.
- `make dev`: uses `compose.yml` + `compose.override.yml`.
- `build/`: local build artifacts (intentionally available for generated outputs).
- `repos/`: shared libraries and service repos tracked as submodules.
- `services/`: infra-owned Dockerfiles and entrypoints per service container.
- `scripts/`: setup/check/reset/update helpers.
- `data/`: persistent runtime state.
- `logs/`: service log mounts.
- Submodule operations in this repo are intentionally non-recursive.
