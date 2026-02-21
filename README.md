# bifrost-infra

Monorepo infrastructure scaffold for running Frostr services with Docker Compose.
Each service is launched from an infra-owned container image with a dedicated
`Dockerfile` and `entrypoint.sh` in `services/containers/`.

## Included submodule layout

- `repos/`: `bifrost-ts`, `frost2x`, `igloo-core`, `android`, `igloo-web`, `igloo-cli`, `igloo-server`
- `services/`: container Dockerfiles and entrypoints for the compose services

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
- `igloo-server`: `http://localhost:8002`
- `igloo-web`: `http://localhost:5173`

`igloo-web` is allowed to start even when `igloo-server` is unavailable.

Use CLI container:

```bash
make shell
```

## Common commands

- `make dev` - start stack with generated `compose.override.yml` mounts
- `make start BG=1` - start stack using only `compose.yml` (no override mounts)
- `make start-prod BG=1` - run production-style profile (`compose.prod.yml`)
- `make stop` - stop all services
- `make reset` - clear data and local dependency caches
- `make check` - validate local setup
