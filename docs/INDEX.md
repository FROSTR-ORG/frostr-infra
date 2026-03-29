# Documentation Index

Docs in this directory are the shared FROSTR system manual.

They are the canonical source for:
- shared architecture
- cross-host interfaces
- peer protocol semantics
- cryptographic model
- profile, backup, onboarding, rotation, and wire contracts
- shared terminology

Submodule docs should explain only the project they belong to. They should not redefine the shared FROSTR system model.

## Start Here

Recommended reading order for most engineers:

1. [`../README.md`](../README.md)
2. [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
3. [ARCHITECTURE.md](./ARCHITECTURE.md)
4. [INTERFACES.md](./INTERFACES.md)
5. [PROTOCOL.md](./PROTOCOL.md)
6. [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)

Then read the artifact and flow specs you need:
- [PROFILE.md](./PROFILE.md)
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)
- [WIRE.md](./WIRE.md)
- [GLOSSARY.md](./GLOSSARY.md)

## Shared Architecture And Specs

### System model

- [ARCHITECTURE.md](./ARCHITECTURE.md)
  - system-level view of signer, host, relay, and artifact responsibilities
- [INTERFACES.md](./INTERFACES.md)
  - contract map across identities, packages, host/runtime, peer protocol, and relay transport
- [GLOSSARY.md](./GLOSSARY.md)
  - canonical shared terminology

Workspace structure, contribution rules, and release coordination live at the
repo root:
- [`../README.md`](../README.md)
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
- [`../RELEASE.md`](../RELEASE.md)

### Runtime and cryptographic behavior

- [PROTOCOL.md](./PROTOCOL.md)
  - device-to-device request/response semantics
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)
  - keysets, shares, nonces, signing, ECDH, and same-key rotation
- [WIRE.md](./WIRE.md)
  - Nostr/NIP-44 event, envelope, and recipient-routing model

### Durable artifacts and lifecycle flows

- [PROFILE.md](./PROFILE.md)
  - durable device-profile model
- [BACKUP.md](./BACKUP.md)
  - `bfprofile`, `bfshare`, and encrypted relay backups
- [ONBOARD.md](./ONBOARD.md)
  - onboarding model and `bfonboard`
- [ROTATION.md](./ROTATION.md)
  - same-key trusted rotation and rotated-share adoption

## Architecture Decisions

- [design/adrs/INDEX.md](../design/adrs/INDEX.md)
  - architecture decision records for the current hard-cut design

## Repo-Local Manuals

Project-specific manuals live in the relevant repo, not in this shared doc set.

- `repos/bifrost-rs/README.md`, `TESTING.md`, `CONTRIBUTING.md`, `RELEASE.md`
  - Rust signer/runtime, bridge, codec, and utility stack
- `repos/igloo-shell/README.md`, `TESTING.md`, `CONTRIBUTING.md`
  - shell/operator host
- `repos/igloo-chrome/README.md`, `TESTING.md`, `CONTRIBUTING.md`, `RELEASE.md`, `SECURITY.md`
  - browser-extension host
- `repos/igloo-home/README.md`, `TESTING.md`, `CONTRIBUTING.md`
  - desktop host
- `repos/igloo-pwa/README.md`, `TESTING.md`, `CONTRIBUTING.md`
  - PWA host
- `repos/igloo-shared/README.md`, `TESTING.md`, `CONTRIBUTING.md`
  - shared browser/runtime adapter layer
- `repos/igloo-ui/README.md`, `TESTING.md`, `CONTRIBUTING.md`
  - shared UI package

Cross-repo demo-harness and browser E2E guidance lives in:
- [test/README.md](../test/README.md)

## Guidance For Future Work

- [design/policies/architecture-guidance.md](../design/policies/architecture-guidance.md)
- [design/policies/host-transport-guidance.md](../design/policies/host-transport-guidance.md)
- [design/policies/mobile-and-wasm-host-guidance.md](../design/policies/mobile-and-wasm-host-guidance.md)
- [design/policies/profile-and-secret-material-guidance.md](../design/policies/profile-and-secret-material-guidance.md)
- [design/policies/runtime-and-persistence-guidance.md](../design/policies/runtime-and-persistence-guidance.md)
- [design/policies/observability-and-debugging-guidance.md](../design/policies/observability-and-debugging-guidance.md)
- [design/policies/testing-guidance.md](../design/policies/testing-guidance.md)
- [design/policies/documentation-guidance.md](../design/policies/documentation-guidance.md)
