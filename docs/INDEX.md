# Documentation Index

Top-level docs in this repo describe cross-repo architecture, protocol, and review guidance.

## Start Here

- [START-HERE.md](./START-HERE.md): local setup and first commands.
- [STRUCTURE.md](./STRUCTURE.md): workspace layout and ownership boundaries.

## Shared Architecture

- [ARCHITECTURE.md](./ARCHITECTURE.md): system-level view of signer, host, and infra responsibilities.
- [PROTOCOL.md](./PROTOCOL.md): high-level FROSTR protocol, onboarding, sign, and ECDH flows.
- [BROWSER-PACKAGES-AND-BACKUPS.md](./BROWSER-PACKAGES-AND-BACKUPS.md): canonical `bfshare`, `bfonboard`, `bfprofile`, and encrypted backup formats.

## Architecture Decisions

- [adrs/INDEX.md](./adrs/INDEX.md): architecture decision records for the current hard-cut design.

## Guidance for Future Work

- [policies/architecture-guidance.md](./policies/architecture-guidance.md)
- [policies/host-transport-guidance.md](./policies/host-transport-guidance.md)
- [policies/mobile-and-wasm-host-guidance.md](./policies/mobile-and-wasm-host-guidance.md)
- [policies/profile-and-secret-material-guidance.md](./policies/profile-and-secret-material-guidance.md)
- [policies/runtime-and-persistence-guidance.md](./policies/runtime-and-persistence-guidance.md)
- [policies/observability-and-debugging-guidance.md](./policies/observability-and-debugging-guidance.md)
- [policies/testing-guidance.md](./policies/testing-guidance.md)
- [policies/documentation-guidance.md](./policies/documentation-guidance.md)

## Repo-Local Manuals

- `repos/bifrost-rs/docs/`: implementation, operations, and API details for the Rust stack.
- `repos/igloo-shell/docs/`: CLI/TUI/relay/keygen/package/operator manuals for the shell surface.
- `repos/igloo-shell/scripts/`: active devnet, relay, soak, and shell-owned E2E entrypoints.
- `repos/igloo-chrome/*.md`: extension-specific workflow, testing, release, and security docs.
- `repos/igloo-web/*.md`: web-app-specific workflow and runtime docs.
- `repos/igloo-ui/README.md`: shared UI package boundary and ownership notes.
