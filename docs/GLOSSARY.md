# FROSTR Glossary

## Summary

This document defines the common vocabulary used across the shared FROSTR specs.

Use it to resolve terminology quickly before diving into the deeper architecture, protocol, profile, backup, onboarding, and rotation docs.

## Terms

### backup

The durable encrypted profile material published to relays for later recovery.

See [BACKUP.md](./BACKUP.md).

### `bfprofile`

The full encrypted portable device-profile package used for import and export.

### `bfshare`

The compact encrypted recovery package used for recovery and as threshold input to trusted rotation.

It is not the rotated-share adoption artifact.

### `bfonboard`

The compact encrypted onboarding/bootstrap package used for onboarding and rotated-share adoption.

### callback peer

The already-running provisioning peer that a recipient device contacts during onboarding after decrypting `bfonboard`.

### device

A share-holding signer instance for one keyset on one host.

In practice, a device is represented durably by a profile and operationally by a runtime.

### durable profile state

The portable long-lived state that defines a device profile, as distinct from host-local state or live runtime state.

It includes manual peer policy overrides, but not remote peer policy observations.

### effective peer policy

The runtime-derived policy result after combining local manual overrides and remote observed peer policy.

It is not the same thing as the durable policy inputs stored in a profile.

### encrypted profile backup

The encrypted relay-published durable backup used together with `bfshare` to recover a full device profile.

### FROST

The threshold-signing scheme underlying FROSTR.

### FROSTR

The full system built around FROST threshold signing, device profiles, relay transport, onboarding, backup, and rotation.

### `group_id`

The identity of one concrete group configuration.

It may change when membership or threshold changes, even if the group public key stays the same.

### group package / `group_package`

The structured group configuration data carried in profile and backup payloads.

It includes `groupName`, the group public key, threshold, and member pubkeys and must be preserved losslessly.

### group name / `group_name`

The canonical human-readable name carried inside `group_package`.

It helps operators recognize which shares, profiles, and backups belong to the same group.
It is durable metadata, not cryptographic identity, and not the same thing as a mutable local device label.

### group public key / `group_pk`

The public key of the threshold keyset.

This is the keyset identity.

### host

The environment that stores profiles, starts runtimes, and exposes user/operator workflows.

Examples include shell and browser hosts.

### initiator

The device that starts a protocol round and is responsible for peer selection, request dispatch, response matching, and terminal success or failure.

### keyset

The threshold-signing unit consisting of one group public key, one threshold, and one member set.

### keyset replacement

Creating a brand-new keyset with a new group public key.

This is not the same as rotation.

### locked peer

A selected peer whose valid response is required for the current round to succeed.

### member index

The participant index assigned to one share/member inside a keyset.

### nonce pool

The runtime-owned store of signing nonce material used to prepare for future signing rounds.

Nonce material is single-use and must not be reused.

### onboarding

The bootstrap process that creates a new device profile from `bfonboard` and a provisioning peer handshake.

It is not the same as import or recovery.

### partial signature

One member’s threshold-signing contribution in a FROST signing round.

### peer

Another share-holding device participating in the same FROSTR keyset.

### peer policy

The policy model that affects peer communication and participation for operations like `sign` and `ecdh`.

### portable profile state

The durable device state that can be represented by `bfprofile`.

### profile

The durable local representation of one share-holding device.

A profile is not the same thing as a runtime.

### `profile_id`

The canonical host-facing identifier for a device profile.

It is derived from the share public key, but it is not the peer-routing identity.

### recovery

The process of reconstructing a full device profile from `bfshare` plus an encrypted relay backup.

### relay

The transport infrastructure used for encrypted peer traffic and encrypted backup events.

Relays transport and store events, but do not interpret FROSTR protocol content.

### remote peer policy observation

A runtime-owned observation of a peer’s reported policy profile, stored only in live runtime state and discarded when runtime state is reset.

### responder

The peer device that receives a request, validates it, and either replies or rejects the round.

### rotation

Reissuing a fresh set of shares for the same underlying signing key and the same group public key.

Rotation is not keyset replacement.

### runtime

The live operational signer process/state built from a durable profile.

### runtime readiness

The runtime-owned view of whether the device is currently capable of participating in operations such as `sign` or `ecdh`.

### share

The per-device secret material representing one participant in a threshold keyset.

### share public key

The device/member public identity used for peer routing, peer policy references, and deriving `profile_id`.

### share secret

The secret signing share held by one device profile.

### sign session

The cryptographic signing context that binds the group, the payload being signed, the participants, and the round’s nonce material.

### structured group data

Lossless serialized group configuration data, represented in the current system as structured `group_package`.

### threshold

The minimum number of participants required to complete a threshold operation.

### threshold ECDH

The threshold shared-secret operation in which multiple share-holding devices produce and combine ECDH contributions.

### trusted-dealer rotation

The current beta rotation model in which an operator reconstructs the current signing key from a threshold set of `bfshare` inputs and splits that same key into fresh shares.

### wire envelope

The decrypted peer message envelope carried inside NIP-44 encrypted Nostr event content.

See [WIRE.md](./WIRE.md).

## Important Distinctions

- profile vs device vs runtime
  - a profile is durable state
  - a device is the conceptual signer instance
  - a runtime is the live process/state for that device
- share public key vs `profile_id` vs group public key
  - share public key is the peer-routing identity
  - `profile_id` is the host-facing profile identity
  - group public key is the keyset identity
- onboarding vs import vs recovery
  - onboarding starts from `bfonboard`
  - import starts from `bfprofile`
  - recovery starts from `bfshare`
- rotation vs keyset replacement
  - rotation preserves the group public key
  - keyset replacement creates a new group public key
- nonce pool vs durable profile state
  - nonce pools are live runtime state
  - durable profile state is portable configuration/state
- `bfshare` vs `bfonboard`
  - `bfshare` is for recovery and rotation input
  - `bfonboard` is for onboarding and rotated-share adoption
