# Device Profile

## Summary

This document is the shared spec for a FROSTR device profile.

It covers:
- what a FROSTR device profile is
- the canonical device identity model
- durable portable profile state
- host-local versus runtime-owned state
- the role of `bfprofile`

Use this document for the conceptual model of the local device profile itself.

Use these companion docs for adjacent domains:
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)
- [PROTOCOL.md](./PROTOCOL.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [GLOSSARY.md](./GLOSSARY.md)

## What A Device Profile Is

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
  - the device’s signer/member identity inside the keyset
- group public key
  - the keyset identity

`profile_id` is stable for a given share public key, but it is not the same value as the share public key.

Because `profile_id` is derived from the share public key, applying a rotated share produces a new canonical `profile_id`.

## Profile State Model

FROSTR device state is best understood in three layers.

### 1. Durable Portable Profile State

This is the portable state that defines the device profile itself.

It includes:
- `profile_id`
- device label
- share secret
- relay list
- structured `group_package`
  - includes `group_name`
- manual peer policy overrides

`group_name` is durable group metadata carried inside `group_package`.
It helps operators identify which shares and packages belong to the same group.
It is not a mutable host-local label.

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
- remote peer policy observations
- pending requests
- live diagnostics
- process/offscreen/daemon state

This state is derived or reconstructed at runtime. It is not the canonical device profile.

## Durable Profile State vs Portable Profile State

In the current system, the portable profile contract and the durable profile contract are effectively the same conceptual state:
- `bfprofile` carries the portable representation
- hosts persist that same durable state in host-specific local forms

What differs across hosts is the host-local wrapping around that durable state, not the canonical durable profile meaning.

## Required Durable Configuration

Every FROSTR host must be able to recover or reconstruct the following durable configuration for a device profile:
- `profile_id`
- device label
- share secret or a secure path to recover it
- relay list
- structured `group_package`
  - includes `group_name`
- manual peer policy overrides

Effective peer policy is not part of the durable profile contract. It is always recomputed by the runtime from:
- local manual overrides
- remote observed peer policy

`group_name` remains part of the durable profile contract because issued profiles, backups, and onboarding material need to carry the same shared group identifier.
Hosts may rename local device labels freely, but changing `group_name` is not a local-label edit.
Once artifacts are issued, `group_name` is effectively immutable unless a future product flow explicitly reissues group-bearing artifacts with a new value.

## `bfprofile`

`bfprofile` is the full encrypted local device-profile package.

It is the portable artifact used for full device import/export.

Conceptually, `bfprofile` contains:
- `profile_id`
- device label
- share secret
- relay list
- structured `group_package`
  - includes `group_name`
- manual peer policy overrides

`bfprofile` does not contain:
- host-local persistence metadata
- active runtime/session state
- remote peer policy observations
- effective peer policy

Semantically, `bfprofile` is the complete portable device profile.

The canonical serialized shape stores:
- top-level `group_package`
  - including `group_name`

`group_package` is structured `GroupPackage` data with full compressed member pubkeys. Hosts must preserve it losslessly rather than reconstructing group members from x-only share public keys.

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
- effective peer policy is runtime-derived and not serialized as canonical profile state
- host-local runtime/process/session state is not part of the durable device profile
- structured `group_package` must be preserved losslessly
- `group_name` is durable metadata carried by `group_package`, not a host-local rename field
