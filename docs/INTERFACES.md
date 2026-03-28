# FROSTR Interfaces

## Summary

This document is the contract map for the major interfaces in FROSTR.

For each boundary, it answers:
- what the interface is for
- who produces and consumes it
- which identity or artifact crosses the boundary
- which invariants must hold
- which failures matter
- where deeper details live

## Interface Matrix

| Interface | Producer | Consumer | Canonical Artifact / Identity | Primary Doc |
|---|---|---|---|---|
| `profile_id` | host profile layer | host profile layer | durable profile id | [PROFILE.md](./PROFILE.md) |
| share public key | keyset / runtime | runtime / peer protocol | peer-routing identity | [PROTOCOL.md](./PROTOCOL.md) |
| group public key / `group_pk` | keyset layer | hosts and runtime | keyset identity | [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md) |
| `bfprofile` | host export path | host import path | full portable profile | [BACKUP.md](./BACKUP.md) |
| `bfshare` | host export path | recovery and rotation input flow | compact recovery / rotation-input package | [BACKUP.md](./BACKUP.md) |
| `bfonboard` | onboarding or rotation distribution path | onboarding or rotate-key adoption path | bootstrap / rotated-share adoption package | [ONBOARD.md](./ONBOARD.md) |
| host ↔ runtime | host | signer/runtime | durable profile state plus runtime read models | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| device ↔ device | initiator device | responder devices | request/response operation rounds | [PROTOCOL.md](./PROTOCOL.md) |
| device ↔ relay | device | relays and subscribing devices | Nostr event + encrypted content | [WIRE.md](./WIRE.md) |
| profile backup | host backup path | recovery path | encrypted backup event | [BACKUP.md](./BACKUP.md) |
| rotation | operator flow | new or existing device host | threshold `bfshare` input + `bfonboard` adoption | [ROTATION.md](./ROTATION.md) |

## Identity Interfaces

### `profile_id`

Purpose:
- durable host-facing identity for one local share-holding profile

Producer:
- host profile-materialization logic

Consumer:
- host storage, lookup, replacement, and selection flows

Canonical identity:
- `profile_id = hex(sha256("frostr:profile-id:v1" || share_pubkey32))`

Invariants:
- derived from the share public key, not chosen arbitrarily
- stable for one share public key
- changes when the device adopts a rotated share
- never used as the peer-routing identity

Failure conditions:
- derived id does not match imported/exported durable profile material
- host uses a short display id as canonical identity

Primary doc:
- [PROFILE.md](./PROFILE.md)

### Share Public Key

Purpose:
- device/member identity inside the keyset

Producer:
- keyset generation and rotation

Consumer:
- peer routing
- relay recipient targeting
- peer policy references
- `profile_id` derivation

Canonical identity:
- lowercase x-only 32-byte hex at host/protocol boundaries

Invariants:
- this is the peer-routing identity
- it is distinct from `profile_id`
- it is distinct from the group public key

Failure conditions:
- host or protocol code confuses share public key with `profile_id`
- routing uses the wrong peer identity

Primary docs:
- [PROTOCOL.md](./PROTOCOL.md)
- [PROFILE.md](./PROFILE.md)

### `group_id`

Purpose:
- identity of one concrete group configuration

Producer:
- keyset generation and rotation logic

Consumer:
- host/runtime bookkeeping that must distinguish concrete group configurations

Invariants:
- may change when threshold or membership changes
- may change across rotation even if `group_pk` stays the same

Primary docs:
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)
- [ROTATION.md](./ROTATION.md)

### Group Public Key / `group_pk`

Purpose:
- keyset identity

Producer:
- key generation or keyset reconstruction

Consumer:
- hosts, runtime, and rotation logic

Invariants:
- identifies the threshold signing key
- preserved by rotation
- changed by keyset replacement

Failure conditions:
- flow labeled as rotation changes the group public key

Primary docs:
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)
- [ROTATION.md](./ROTATION.md)

## Package Interfaces

### `bfprofile`

Purpose:
- full portable device-profile export/import artifact

Producer:
- host export path

Consumer:
- host import path

Canonical payload:
- `profile_id`
- device durable state
- structured `group_package`
  - includes `group_name`

Invariants:
- full portable durable profile state
- not a runtime snapshot
- must preserve `group_package` losslessly

Failure conditions:
- outer/inner profile ids do not match
- imported payload does not match derived profile id from share secret
- host reconstructs group members lossy

Primary docs:
- [BACKUP.md](./BACKUP.md)
- [PROFILE.md](./PROFILE.md)

### `bfshare`

Purpose:
- compact recovery artifact and threshold rotation input

Producer:
- host export path

Consumer:
- recovery flow
- operator rotation input flow

Canonical payload:
- share secret
- relay set

Invariants:
- compact credential only
- not a full device profile
- not the rotated-share adoption artifact

Failure conditions:
- used as onboarding/adoption material
- relay set omitted or invalid

Primary docs:
- [BACKUP.md](./BACKUP.md)
- [ROTATION.md](./ROTATION.md)

### `bfonboard`

Purpose:
- bootstrap and rotated-share adoption artifact

Producer:
- onboarding distribution flow
- rotation distribution flow

Consumer:
- new-device onboarding
- existing-device rotated-share adoption

Canonical payload:
- share secret
- relay set
- callback peer public key

Invariants:
- bootstrap artifact only
- not a full device profile
- the only rotated-share adoption artifact in the current model

Failure conditions:
- treated as a durable final profile
- missing callback peer identity

Primary docs:
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)

## Profile And Backup Interfaces

### Durable Profile State

Purpose:
- stable long-lived state needed to reconstruct a device runtime

Producer:
- onboarding, import, recovery, and rotation-adoption flows

Consumer:
- host profile storage
- runtime materialization

Canonical fields:
- `profile_id`
- device label
- share secret
- relay list
- manual peer policy overrides
- structured `group_package`
  - includes `group_name`

Invariants:
- distinct from host-local state
- distinct from runtime-only state
- effective peer policy is not canonical durable state
- `group_name` is durable group metadata carried with `group_package`
- hosts may rename local device/profile labels, but they must not treat `group_name` as independently mutable issued-artifact state

Primary doc:
- [PROFILE.md](./PROFILE.md)

### Encrypted Relay Backup

Purpose:
- durable relay-published backup used with `bfshare` recovery

Producer:
- host backup publication path

Consumer:
- host recovery path

Canonical artifact:
- latest encrypted `kind: 10000` event by author pubkey derived from the share secret

Invariants:
- excludes the share secret
- includes structured `groupPackage`, including `groupName`
- group data must remain lossless

Failure conditions:
- backup published without enough durable profile information
- host reconstructs group members from lossy fields

Primary doc:
- [BACKUP.md](./BACKUP.md)

## Host And Runtime Interface

Purpose:
- control and read-model boundary between durable host-managed profile state and live signer/runtime state

Producer:
- host profile-management and operator-action layer

Consumer:
- signer/runtime bootstrap and control layer

Canonical inputs:
- durable profile state
- runtime lifecycle commands:
  - start
  - stop
  - reset/wipe
- config and policy updates
- operation requests:
  - `ping`
  - `onboard`
  - `sign`
  - `ecdh`
- host-local context such as active profile selection and local bookkeeping

Canonical outputs:
- `status`
- runtime readiness
- `runtime_status`
- runtime diagnostics
- peer status
- effective peer policy / peer permission state
- operation completions and failures
- incremental runtime events

Invariants:
- runtime is derived from durable profile state
- nonce pools and pending operations are runtime-owned state
- remote peer policy observations are runtime-owned state
- effective peer policy is runtime-owned state
- hosts are the source of truth for local profile storage and UX state
- hosts must not invent their own readiness or round-state model
- `runtime_status()` is the canonical aggregated read model

Failure conditions:
- host treats runtime snapshot as portable profile state
- host infers readiness or pending-round truth from local heuristics instead of runtime output
- host caches stale runtime truth and treats it as authoritative

Out of scope:
- package formats
- peer wire protocol
- cryptographic internals

Primary docs:
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [PROFILE.md](./PROFILE.md)

## Device And Device Interface

Purpose:
- live request/response coordination between share-holding devices

Producer:
- initiator device

Consumer:
- responder devices

Canonical operations:
- `ping`
- `onboard`
- `sign`
- `ecdh`

Canonical identities:
- recipient share public key
- request id for round correlation

Invariants:
- request/response model
- initiator owns peer selection and response matching
- responders validate routing, freshness, policy, readiness, and operation-specific semantics before replying

Failure conditions:
- invalid recipient routing
- replayed or stale request
- policy deny
- readiness or nonce-state failure
- invalid locked-peer response

Primary doc:
- [PROTOCOL.md](./PROTOCOL.md)

## Relay And Wire Interface

Purpose:
- transport encrypted peer traffic and encrypted backups over relays

Producer:
- devices and hosts that publish relay events

Consumer:
- relays and subscribing devices

Canonical artifact:
- Nostr event carrying NIP-44 encrypted content

Canonical routing rule:
- exactly one lowercase `p` tag naming the recipient share public key for peer traffic

Invariants:
- relays transport and store events but do not interpret protocol payloads
- protocol payload is inside encrypted content
- request correlation happens through the decrypted peer envelope

Failure conditions:
- zero or multiple `p` tags on peer traffic
- decrypted content not parseable as a peer envelope
- recipient tag does not target a local recipient

Primary doc:
- [WIRE.md](./WIRE.md)

## Rotation Interfaces

### Operator Input Interface

Purpose:
- collect existing threshold material needed to perform same-key rotation

Producer:
- current devices exporting `bfshare`

Consumer:
- operator rotation workflow

Canonical artifact:
- threshold set of `bfshare` packages

Invariants:
- rotation begins from threshold recovery material
- rotation preserves the same group public key

Primary doc:
- [ROTATION.md](./ROTATION.md)

### Rotated-Share Adoption Interface

Purpose:
- deliver rotated share material to a target device

Producer:
- operator rotation workflow

Consumer:
- new device or existing device adopting the rotated share

Canonical artifact:
- `bfonboard`

Invariants:
- both new-device and existing-device rotated adoption use `bfonboard`
- successful adoption yields a new share public key and therefore a new `profile_id`

Primary docs:
- [ROTATION.md](./ROTATION.md)
- [ONBOARD.md](./ONBOARD.md)
