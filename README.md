# frostr-infra

Monorepo infrastructure scaffold for running Frostr services with Docker Compose.
Each service is launched from an infra-owned container image with a dedicated
`Dockerfile` and `entrypoint.sh` in `services/`.

## Included submodule layout

- `repos/`: `bifrost-rs`, `igloo-chrome`, `igloo-web`
- `services/`: container Dockerfiles and entrypoints for the compose services
- `test/`: infra-owned cross-repo browser E2E suites for submodules that depend on shared runtime code

## Submodule Policy

- Use non-recursive submodule commands in this repo (`git submodule update --init`, `git submodule status`).
- Avoid recursive submodule commands here (`--recursive`) due to known upstream nested-submodule metadata issues in `repos/igloo-web`.

## Quick start

```bash
cp .env.example .env
make init
make dev BG=1
make health
```

Open services:
- `igloo-web`: `http://localhost:5173`

Set `VITE_IGLOO_SERVER_URL` if `igloo-web` should target a non-default backend.

Bring up the manual pairing relay + bifrost harness:

```bash
make demo-harness BG=1
make demo-harness-onboard
```

## Common commands

- `make dev` - start stack with generated `compose.override.yml` mounts
- `make start BG=1` - start stack using only `compose.yml` (no override mounts)
- `make start-prod BG=1` - run production-style profile (`compose.prod.yml`)
- `make stop` - stop all services
- `make reset` - clear data and local dependency caches
- `make check` - validate local setup
- `npm --prefix test run test:e2e` - run infra-owned browser E2E suites
- `make demo-harness BG=1` - start `dev-relay` + `bifrost-demo` for manual pairing and live/E2E testing
- `make demo-harness-onboard` - print the current `bfonboard...` packages and passwords from the harness

`make demo-harness` prebuilds the required `bifrost` and `bifrost-devtools` binaries on the host and reuses them from the mounted `repos/bifrost-rs/target/debug` directory inside the harness containers.
