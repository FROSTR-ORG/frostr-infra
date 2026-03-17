# frostr-infra

Monorepo infrastructure scaffold for running Frostr services with Docker Compose.
Each service is launched from an infra-owned container image with a dedicated
`Dockerfile` and `entrypoint.sh` in `services/`.

## Included submodule layout

- `repos/`: `bifrost-rs`, `igloo-shell`, `igloo-chrome`, `igloo-home`, `igloo-ui`, `igloo-web`
- `services/`: container Dockerfiles and entrypoints for the compose services
- `test/`: infra-owned cross-repo browser E2E suites for submodules that depend on shared runtime code

## Submodule Policy

- Use non-recursive submodule commands in this repo (`git submodule update --init`, `git submodule status`).
- Avoid recursive submodule commands here (`--recursive`) due to known upstream nested-submodule metadata issues in `repos/igloo-web`.

## Quick start

```bash
cp .env.example .env
./run.sh repo init
./run.sh infra dev --bg
./run.sh infra health
```

Open services:
- `igloo-web`: `http://localhost:5173`

Set `VITE_IGLOO_SERVER_URL` if `igloo-web` should target a non-default backend.

Bring up the manual pairing relay + igloo-shell harness:

```bash
./run.sh demo start
```

If port `8194` is already in use on your host, choose another relay port:

```bash
./run.sh demo start --port 8394
```

Print the current onboarding packages:

```bash
./run.sh demo onboard
```

## Common commands

- `./run.sh infra dev --bg` - start stack with generated `compose.override.yml` mounts
- `./run.sh infra start --bg` - start stack using only `compose.yml` (no override mounts)
- `./run.sh infra start-prod --bg` - run production-style profile (`compose.prod.yml`)
- `./run.sh infra stop` - stop all services
- `./run.sh infra reset` - clear data and local dependency caches
- `./run.sh infra check` - validate local setup
- `npm --prefix test run test:e2e` - run infra-owned browser E2E suites
- `./run.sh demo start` - start `dev-relay` + `igloo-demo` in the background and print onboarding artifacts
- `./run.sh demo stop` - stop `dev-relay` + `igloo-demo`
- `./run.sh demo logs` - follow relay and demo logs
- `./run.sh demo onboard` - print the current `bfonboard...` packages and passwords from the harness
- `./run.sh demo smoke` - verify a fresh local `igloo-shell` can onboard against `igloo-demo`

`./run.sh demo start` prebuilds the required `bifrost-devtools` and `igloo-shell` binaries on the host and reuses them from the mounted workspace target directories inside the harness containers.
