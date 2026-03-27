# Documentation Index

Top-level docs in this repo describe shared FROSTR architecture, protocol, and cross-repo guidance.

## Start Here

- [STRUCTURE.md](./STRUCTURE.md): workspace layout and ownership boundaries.
- [ARCHITECTURE.md](./ARCHITECTURE.md): system-level view of signer, host, and infra responsibilities.

## Shared Architecture

- [INTERFACES.md](./INTERFACES.md): boundary map for identities, packages, runtime interfaces, peer protocol, and relay transport.
- [GLOSSARY.md](./GLOSSARY.md): canonical terminology used across the shared FROSTR specs.
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md): FROST-side keyset, share, nonce, signing, and threshold ECDH model.
- [PROTOCOL.md](./PROTOCOL.md): peer-to-peer protocol semantics between FROSTR devices.
- [WIRE.md](./WIRE.md): Nostr/NIP-44 wire format, encrypted envelopes, and recipient routing.
- [PROFILE.md](./PROFILE.md): conceptual model for FROSTR device identity, durable profile state, and `bfprofile`.
- [BACKUP.md](./BACKUP.md): `bfprofile`, `bfshare`, encrypted relay backups, and recovery semantics.
- [ONBOARD.md](./ONBOARD.md): onboarding model, handshake, and `bfonboard` semantics.
- [ROTATION.md](./ROTATION.md): trusted share rotation, rotated distribution, and device adoption semantics.

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

- `repos/bifrost-rs/README.md` and `repos/bifrost-rs/docs/`: project entrypoint plus implementation, operations, and API details for the Rust stack.
- `repos/igloo-shell/README.md`, `TESTING.md`, and `CONTRIBUTING.md`: shell CLI/operator manual, validation, and contributor guidance.
- `repos/igloo-shell/scripts/`: active devnet, relay, soak, and shell-owned E2E entrypoints.
- `repos/igloo-chrome/README.md`: extension-specific workflow, testing, release, and security docs.
- `repos/igloo-home/README.md`: desktop host overview, testing, and contributor guidance.
- `repos/igloo-pwa/README.md`: PWA host overview, testing, and contributor guidance.
- `repos/igloo-shared/README.md`: shared browser/runtime adapter and package-contract guidance.
- `repos/igloo-ui/README.md`: shared UI package boundary and ownership notes.
- `repos/igloo-chrome/*.md`: extension-specific workflow, testing, release, and security docs.
- `test/DEMO_STRATEGY.md`: infra/demo-harness and browser E2E release workflow for this monorepo.
