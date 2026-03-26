# Device Profile

## Summary

This document is the living spec for a FROSTR device profile.

It covers:

- what a FROSTR device profile is
- the canonical device identity model
- durable device/profile state
- host-local versus runtime-owned state
- the role of `bfprofile`

Use this document for the conceptual model of the local device profile itself.

Use these companion docs for adjacent domains:

- [BACKUP.md](./BACKUP.md): backup, recovery, `bfshare`, and encrypted relay backups
- [ONBOARD.md](./ONBOARD.md): onboarding flow and `bfonboard`
- [ROTATION.md](./ROTATION.md): share rotation and rotated device adoption
- [PROTOCOL.md](./PROTOCOL.md): high-level runtime protocol
- [ARCHITECTURE.md](./ARCHITECTURE.md): host/runtime ownership boundaries

## What a Device Profile Is

A FROSTR device profile is the durable local representation of one share-holding signer device for one keyset.

Each device profile corresponds to:

- one share secret
- one share public key derived from that share secret
- one group/keyset membership
- one canonical `profile_id`
- one local device label
- one relay set
- one local peer-permission configuration

A profile is not the same thing as a running signer process. It is the durable identity and configuration needed to reconstruct that signer on a host.

## Canonical Identity

The canonical device/profile identifier is:

```text
profile_id = hex(sha256("frostr:profile-id:v1" || share_pubkey32))
```

Important distinctions:

- `profile_id`
  - the host-facing identifier for the local device profile
- share public key
  - the device's signer/member identity inside the keyset
- group public key
  - the keyset identity

`profile_id` is stable for a given share public key, but it is not the same value as the share public key.

Short ids are display-only:

- compact UI may show the first 8 hex characters
- storage, lookup, filenames, and protocol references must use the full 64-char id

Because `profile_id` is derived from the share public key, applying a rotated share produces a new canonical `profile_id`. Rotation can preserve host-local installation continuity, but it does not preserve the old share-derived identity.

## Profile State Model

FROSTR device state is best understood in three layers.

### 1. Durable Portable Profile State

This is the portable state that defines the device profile itself.

It includes:

- `profile_id`
- device label
- share secret
- relay list
- group metadata:
  - keyset name
  - group public key
  - threshold
  - total count
  - member index/share-public-key list
- manual peer policy overrides
- remote peer policy observations

This is the state fully represented by `bfprofile`.

### 2. Host-Local Configuration State

This is host-owned state used to manage the local installation.

Examples:

- browser entries for saved encrypted profiles
- shell profile manifests
- shell vault references
- daemon socket paths
- UI preferences
- active profile selection

This state is not part of the portable profile format. Different hosts may store it differently.

### 3. Operational Runtime State

This is mutable live state owned by the runtime while the device is active.

Examples:

- runtime readiness
- connected relays
- peer reachability
- nonce pool state
- pending requests
- live diagnostics
- process/offscreen/daemon state

This state is derived or reconstructed at runtime. It is not the canonical device profile.

## Required Durable Configuration

Every FROSTR host must be able to recover or reconstruct the following durable configuration for a device profile:

- `profile_id`
- device label
- share secret or a secure path to recover it
- relay list
- group metadata
- manual peer policy overrides
- remote peer policy observations

Effective peer policy is not part of the durable profile contract. It is always recomputed by the runtime from:

- local manual overrides
- remote observed peer policy

## `bfprofile`

`bfprofile` is the full encrypted local device-profile package.

It is the portable artifact used for full device import/export.

Conceptually, `bfprofile` contains:

- `profile_id`
- `keyset_name`
- device label
- share secret
- relay list
- structured `group_package`
- manual peer policy overrides
- remote peer policy observations

`bfprofile` does not contain:

- host-local persistence metadata
- active runtime/session state
- effective peer policy

Semantically, `bfprofile` is the complete portable device profile.

The canonical serialized shape stores:

- top-level `keyset_name`
- top-level `group_package`

`group_package` is structured `GroupPackage` data with full compressed member pubkeys. Hosts must preserve it losslessly rather than reconstructing group members from x-only share public keys.

Use `bfprofile` when:

- exporting a device from one host to another
- importing a full device onto a new host
- preserving the complete durable local profile state

Low-level wire and payload details for `bfprofile` live in [BACKUP.md](./BACKUP.md), because profile export/import sits alongside backup and recovery formats.

## Host Expectations

Different hosts may manage local device profiles differently, but they must preserve the same conceptual model.

Examples:

- browser hosts may store encrypted profile blobs in browser storage and unlock material in session storage
- shell/native hosts may split profile management across manifests, vault records, and runtime state directories

What must remain consistent across hosts:

- the canonical `profile_id`
- the meaning of the durable profile fields
- the distinction between durable portable profile state and host-local/runtime state

## Invariants

These rules should hold across the system:

- `bfprofile` is the only full portable device-profile package
- `profile_id` is derived from the share public key, not chosen by the host
- short ids are display-only
- effective peer policy is runtime-derived and not serialized as canonical profile state
- host-local runtime/process/session state is not part of the durable device profile
