# Start Here

1. Copy `.env.example` to `.env`.
2. Run `make init` to initialize submodules.
   Note: this repo intentionally uses non-recursive submodule commands.
3. Run `make dev BG=1` for local development mounts.
4. For production-style containers, run `make start-prod BG=1` instead.
5. Check status with `make health`.
6. Follow logs with `make logs`.
