# services/ — infra-owned compose services

Docker build contexts for the demo/test stack defined in
[`../compose.test.yml`](../compose.test.yml). These back the Docker demo harness
(`make demo-start`, `make test-demo`) and the cross-client `@demo` lane. Local
behavioral testing without Docker uses the in-process relay
(`test/shared/local-relay.ts`) instead — these services are only for the
demo/onboarding path.

| Dir | Role |
|-----|------|
| `dev-relay/` | A throwaway Nostr relay (`entrypoint.sh` runs `bifrost-devtools relay`). Published on `DEV_RELAY_PORT` (auto-allocated per run; override via env). The signers connect here. |
| `igloo-demo/` | Generates a demo 2-of-3 keyset and runs the demo co-signers (`entrypoint.sh`), writing onboarding artifacts to the shared harness dir for the test to import. |
| `demo/` | Base `Dockerfile` (the in-image native Rust build) the above services build from. |

Ports are OS-assigned (`listen(0)`) by the harness and passed in via
`DEV_RELAY_PORT`; see [`../test/docs/TEST-ENV-VARS.md`](../test/docs/TEST-ENV-VARS.md)
for the full env-var schema. CI builds these with BuildKit caching via
`compose.ci.yml` (`FROSTR_DEMO_COMPOSE_OVERRIDE`).
