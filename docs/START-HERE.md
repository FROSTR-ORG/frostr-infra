# Start Here

1. Copy `.env.example` to `.env`.
2. Run `./run.sh repo init` to initialize submodules.
   Note: this repo intentionally uses non-recursive submodule commands.
3. Run `./run.sh infra dev --bg` for local development mounts.
4. For production-style containers, run `./run.sh infra start-prod --bg` instead.
5. Check status with `./run.sh infra health`.
6. Follow logs with `./run.sh infra logs`.

## Read Next

- [INDEX.md](./INDEX.md): top-level docs map.
- [ARCHITECTURE.md](./ARCHITECTURE.md): shared system architecture across `bifrost-rs`, `igloo-chrome`, and infra.
- [PROTOCOL.md](./PROTOCOL.md): high-level protocol and onboarding flow.
- [STRUCTURE.md](./STRUCTURE.md): repo layout and ownership boundaries.
- `repos/igloo-shell/docs/INDEX.md`: shell/operator manual for local relay, keygen, package, and TUI workflows.

## Design and Review

- [adrs/INDEX.md](./adrs/INDEX.md): architecture decisions already locked in.
- [policies/architecture-guidance.md](./policies/architecture-guidance.md): how new work should fit the current design.
- [policies/testing-guidance.md](./policies/testing-guidance.md): where tests belong and what should be covered.
