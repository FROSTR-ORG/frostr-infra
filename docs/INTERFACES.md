# FROSTR Interfaces

## Summary

This document is the interface map for FROSTR.

It focuses on the important boundaries between subsystems:

- host and runtime
- host and portable package artifacts
- device and device peer protocol
- device and relay wire transport
- backup, recovery, onboarding, and rotation boundaries

Use this document to answer:

- what are the main interfaces in the system?
- which identities and artifacts are used at each boundary?
- which companion doc owns the deeper detail?

Use these companion docs for the full behavior behind each interface:

- [ARCHITECTURE.md](./ARCHITECTURE.md): overall system model
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md): FROST-side cryptographic model for keysets, shares, nonces, signing, and ECDH
- [PROFILE.md](./PROFILE.md): device profile and durable state
- [BACKUP.md](./BACKUP.md): `bfprofile`, `bfshare`, and encrypted backups
- [ONBOARD.md](./ONBOARD.md): onboarding and `bfonboard`
- [ROTATION.md](./ROTATION.md): trusted share rotation
- [PROTOCOL.md](./PROTOCOL.md): device-to-device protocol semantics
- [WIRE.md](./WIRE.md): relay and wire-format details
- [GLOSSARY.md](./GLOSSARY.md): canonical terminology

## Interface Taxonomy

FROSTR has five major interface classes.

### 1. Identity Interfaces

These define how the system names devices, members, and keysets.

Important identities:

- `profile_id`
  - the host-facing durable profile identity
- share public key
  - the device/member identity used for peer routing and policy
- `group_id`
  - the concrete group configuration identity
- group public key / `group_pk`
  - the keyset identity

These identities are related, but they are not interchangeable.

### 2. Package Interfaces

These are the portable artifacts that cross host or user boundaries.

Important package interfaces:

- `bfprofile`
  - full portable device profile import/export
- `bfshare`
  - compact recovery credential and rotation input artifact
- `bfonboard`
  - onboarding and rotated-share adoption artifact

### 3. Host and Runtime Interfaces

These define how a host materializes, starts, stops, and observes a signer/runtime from durable profile data.

Conceptually, this interface covers:

- profile materialization
- runtime bootstrap from durable state
- runtime status and diagnostics
- local relay and policy configuration

### 4. Peer Protocol Interfaces

These define how one share-holding device communicates with another device during runtime operations.

Core peer operations:

- `ping`
- `onboard`
- `sign`
- `ecdh`

These interfaces depend on underlying cryptographic structures such as shares, nonce pools, partial signatures, and threshold ECDH contributions.

### 5. Relay and Persistence Interfaces

These define how encrypted peer traffic and encrypted backups move through relays, and how durable profile state is reconstructed later.

Important examples:

- Nostr relay peer traffic
- NIP-44 encrypted peer envelopes
- encrypted profile backup events
- recovery from `bfshare`

## Identity Interfaces

### `profile_id`

`profile_id` is the durable host/profile identity for one local share-holding device profile.

It is used for:

- host-side lookup
- storage
- selection
- replacement during rotation

It is not used for:

- peer routing
- relay recipient tags

### Share Public Key

The share public key is the peer/device identity inside the keyset.

It is used for:

- device-to-device routing
- relay recipient targeting
- peer policy references
- deriving `profile_id`

This is the routing identity at the protocol and wire layers.

### `group_id`

`group_id` identifies one concrete group configuration.

It changes when group membership or threshold configuration changes, even if the group public key remains the same.

This is why rotation can preserve the group public key while still producing a new `group_id`.

### Group Public Key / `group_pk`

The group public key is the keyset identity.

It is used for:

- identifying the threshold signing key
- distinguishing rotation from keyset replacement

Rules:

- rotation preserves `group_pk`
- keyset replacement changes `group_pk`

## Package Interfaces

### `bfprofile`

`bfprofile` is the full encrypted portable device-profile package.

It is the interface for:

- full device export
- full device import
- carrying complete durable profile state between hosts

The canonical package payload includes:

- `profile_id`
- top-level `keyset_name`
- device state
- structured `group_package`

`bfprofile` is the full portable profile boundary, not a runtime snapshot.

### `bfshare`

`bfshare` is the compact encrypted recovery artifact.

It is the interface for:

- recovering a device from relays
- supplying threshold old shares into trusted rotation

It is not the adoption artifact for a rotated share.

### `bfonboard`

`bfonboard` is the compact onboarding/bootstrap artifact.

It is the interface for:

- onboarding a new device
- adopting a rotated share on a new device
- adopting a rotated share into an existing device through in-place rotation flows

It is the only rotated-share adoption artifact in the current model.

## Profile and Backup Interfaces

The durable profile and backup boundaries use the same conceptual shape:

- top-level `keyset_name`
- structured `group_package`
- device-local relay and policy inputs

This is an important contract:

- `group_package` is structured group data
- member pubkeys are full compressed secp256k1 pubkeys
- hosts must preserve `group_package` losslessly
- hosts must not reconstruct member pubkeys from x-only share public keys

The full payload details for these package interfaces live in [BACKUP.md](./BACKUP.md).

## Host and Runtime Interfaces

Hosts and runtimes meet at the durable profile boundary.

Conceptually:

```text
host
  -> load durable profile
  -> materialize runtime inputs
  -> start runtime
  -> observe status / diagnostics / policy state
```

This interface is responsible for:

- turning durable profile state into runtime state
- starting and stopping the live signer
- surfacing runtime readiness and diagnostics
- applying host-local relay and policy configuration

This interface is host-specific in implementation, but it must preserve the same profile and identity semantics across hosts.

## Device and Device Interfaces

The peer protocol is the device-to-device runtime coordination boundary.

It uses:

- encrypted request/response messages
- share public keys as recipient identities
- one request id per operation round

Core peer operations:

- `ping`
  - reachability and observed peer policy
- `onboard`
  - bootstrap handshake
- `sign`
  - threshold signing
- `ecdh`
  - threshold shared-secret derivation

The peer protocol owns runtime coordination after a device already exists and can communicate over relays.

The detailed semantics live in [PROTOCOL.md](./PROTOCOL.md).

## Device and Relay Wire Interfaces

The wire interface is the transport boundary between devices and relays.

It uses:

- Nostr events
- NIP-44 encrypted `content`
- exactly one recipient `p` tag

This interface is responsible for:

- encrypted transport
- recipient routing
- request/response correlation
- freshness and replay boundaries

Relays are transport only. They do not interpret the protocol payload.

The detailed wire rules live in [WIRE.md](./WIRE.md).

## Onboarding Interfaces

Onboarding sits between package import and peer protocol bootstrap.

The interface sequence is:

```text
bfonboard
  -> recipient imports package
  -> recipient contacts provisioning peer
  -> onboard peer handshake
  -> durable local profile is materialized
```

Important boundary rule:

- `bfonboard` is a bootstrap artifact
- successful onboarding produces the same class of durable profile later represented by `bfprofile`

The conceptual onboarding model lives in [ONBOARD.md](./ONBOARD.md).

## Backup and Recovery Interfaces

Recovery is the interface between compact recovery credentials and durable profile reconstruction.

The sequence is:

```text
bfshare
  -> derive backup author identity
  -> fetch encrypted profile backup
  -> decrypt backup
  -> reconstruct full device profile
```

Important boundary rule:

- `bfshare` is a recovery credential
- encrypted profile backup carries durable profile data without the share secret
- recovery reconstructs a full local profile from those two inputs together

The low-level recovery artifact model lives in [BACKUP.md](./BACKUP.md).

## Rotation Interfaces

Rotation spans two distinct interfaces.

### Operator Input Interface

Trusted rotation begins from:

- a threshold set of existing `bfshare` packages

This is the operator-side reconstruction boundary.

### Device Adoption Interface

Rotated shares are adopted through:

- `bfonboard`

This is the device-side adoption boundary.

Important rules:

- `bfshare` is rotation input, not rotation adoption
- `bfonboard` is rotation adoption
- local in-place replacement and new-device bootstrap both use the same adoption artifact

The full rotation model lives in [ROTATION.md](./ROTATION.md).

## Interface Invariants

These rules should hold across the system:

- `profile_id` is the host-facing durable profile identity
- share public key is the peer-routing identity
- `group_id` identifies a concrete group configuration
- group public key identifies the keyset
- `bfprofile` is the full portable profile package
- `bfshare` is recovery and rotation-input material
- `bfonboard` is onboarding and rotated-share adoption material
- structured `group_package` must be preserved losslessly across profile and backup boundaries
- peer protocol semantics and relay wire format are separate interfaces
