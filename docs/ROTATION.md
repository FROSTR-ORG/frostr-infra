# Key and Share Rotation

## Summary

This document is the living spec for FROSTR key/share rotation.

It covers:

- what rotation is
- the operator inputs required to perform it
- how rotated shares are created
- how rotated shares are distributed to devices
- how devices adopt rotated state
- what identities and artifacts change across rotation

Use this document for the conceptual and operational model of rotation.

Use these companion docs for adjacent domains:

- [PROFILE.md](./PROFILE.md): durable device/profile identity and state
- [BACKUP.md](./BACKUP.md): `bfprofile`, `bfshare`, relay backups, and recovery artifacts
- [ONBOARD.md](./ONBOARD.md): onboarding flow and `bfonboard`
- [ARCHITECTURE.md](./ARCHITECTURE.md): system-level architecture

## What Rotation Is

Rotation is the process of taking an existing FROSTR keyset and issuing a fresh set of device shares for the same signing key.

In FROSTR:

- rotation preserves the same group public key
- rotation may change threshold and member count
- rotation produces fresh share secrets and fresh share public keys
- rotation invalidates the previous share set once the rotated configuration is adopted

Rotation is not the same thing as generating a new keyset.

If the group public key changes, that is a brand-new keyset, not a rotation.

## Trusted-Dealer Rotation Model

The current alpha rotation model is trusted-dealer rotation.

The operator supplies a threshold set of existing `bfshare` packages exported from current devices. Those threshold shares are used to reconstruct the existing signing key, and that same signing key is then split into a new rotated share set.

Conceptually:

```text
threshold old shares
    -> reconstruct existing signing key K
    -> split signing key K into new shares
    -> produce rotated group configuration

old group public key G
new group public key G
```

This is the defining property of rotation:

```text
rotation
  same signing key
  same group public key
  fresh device shares
```

## Rotation Inputs

Rotation starts with operator-supplied material:

- a threshold set of `bfshare` packages from existing devices
- the passwords needed to decrypt those `bfshare` packages
- the desired rotated threshold
- the desired rotated device/member count
- the relay set to be used by the rotated devices
- an adoption intent for each rotated target:
  - bootstrap as a new device with `bfonboard`
  - rotate an existing device with `bfonboard`

The threshold set of `bfshare` packages is the critical input. Rotation does not begin from `bfprofile`, and it does not require the old devices to stay online for a live peer protocol round.

## Rotation Outputs

Successful rotation produces:

- a rotated group configuration
- one rotated share secret per target device
- one rotated share public key per target device
- one rotated device profile per target device
- one `bfonboard` package per target device
- one encrypted relay backup per rotated device

The rotated group public key is the same as the old one.

The rotated member verifying shares, threshold, and member count may differ from the previous configuration.

## Operator Hosts

FROSTR hosts do not all own the same rotation responsibilities.

- `igloo-shell` is the strongest operator host
  - it is intended for business and enterprise environments
  - it owns first-class operator-side rotation generation through `rotate-keyset`
- browser hosts focus on device adoption and simpler operator flows
  - `igloo-home` and `igloo-pwa` support rotation-oriented UI workflows
  - `igloo-chrome` remains a device-management and onboarding host, not a keyset-generation host

This means the conceptual rotation model stays the same across hosts, but the shell is the most explicit environment for staged, manifest-driven rotation work.

## Rotation Phases

FROSTR rotation proceeds in five conceptual phases.

### 1. Collect Threshold Shares

The operator gathers a threshold set of `bfshare` packages from existing devices and decrypts them.

This yields the threshold set of old share secrets needed to reconstruct the current signing key.

Conceptually:

```text
device A -> bfshare A --\
device B -> bfshare B ----> threshold set of old shares
device C -> bfshare C --/
```

### 2. Reconstruct and Rotate

The operator reconstructs the current signing key from the threshold old shares.

That same signing key is then split into a new share set using the desired rotated threshold and rotated device count.

Conceptually:

```text
old shares (threshold set)
    -> reconstruct signing key K
    -> split K into rotated shares
    -> rotated group config
```

Validation must confirm:

- the reconstructed signing key matches the existing group public key
- the rotated output preserves the same group public key

### 3. Materialize Rotated Device State

For each rotated target device, the system materializes the durable state that would underlie a full `bfprofile`.

That rotated device state includes:

- a fresh share secret
- a fresh share public key
- a new canonical `profile_id`
- top-level `keyset_name`
- structured `group_package`
- the chosen relay set
- local durable policy inputs

At this stage, the operator has the new share material and the rotated durable profile state, but it is not yet distributed to every target device.

When that durable state is serialized into `bfprofile` or encrypted relay backups, it uses the same canonical package shape as the rest of the system:

- top-level `keyset_name`
- top-level `group_package`

Rotation does not introduce a separate shadow group schema.

### 4. Distribute Rotated Shares

Each rotated target device is distributed as a `bfonboard` package.

There is no separate rotation-update package type.

The operator may still assign intent for each rotated target:

- `New Device`
- `Rotate Existing Device`

But both intents produce the same artifact:

- `bfonboard`

In `igloo-shell`, the operator-side generation workflow is explicit:

1. `rotate-keyset init`
2. edit or review `rotation.json`
3. `rotate-keyset show`
4. `rotate-keyset generate`

`rotate-keyset generate` replaces the selected local source profile immediately and emits `bfonboard` packages for the remaining rotated targets.

### 5. Adopt Rotated State

Each target device adopts the rotated share according to its distribution path.

After adoption:

- the device holds the rotated share secret
- the device has a rotated share public key
- the device has a new canonical `profile_id`
- the device uses the rotated group configuration
- the old share is no longer valid for the active rotated keyset

Once the rotated configuration is adopted, the previous share set must be treated as obsolete.

## Adoption Paths in Detail

### Logged-Out Adoption with `bfonboard`

This is the logged-out path.

It is used when the rotated share is being adopted through the normal onboarding workspace.

This can be used for:

- a genuinely new device
- an existing installation that has logged out and is setting up the rotated share as a new local profile

Result:

- new local device profile
- rotated `profile_id`
- local `bfprofile`
- local `bfshare`
- rotated encrypted relay backup

### Logged-In In-Place Rotation with `bfonboard`

This is the logged-in path.

It is used when an already-running device opens `Rotate Key` in settings and applies a rotated `bfonboard` package directly.

The device:

1. imports the rotated `bfonboard`
2. completes the onboarding-style handshake
3. resolves the rotated durable profile state
4. reviews the replacement
5. replaces the active local profile in place

Important identity rule:

- applying a rotated `bfonboard` produces a new share public key
- `profile_id` is derived from the share public key
- therefore a rotated-device adoption produces a new canonical `profile_id`

Preserving the profile in this flow means preserving the host-local installation context where possible, not preserving the old canonical profile identity.

Examples of host-local context that may be preserved:

- device label
- local preferences
- active-profile selection behavior
- host-specific local bookkeeping

What changes must still be treated as new:

- share secret
- share public key
- `profile_id`
- rotated backups
- rotated group configuration

## Identity and State Transitions

Rotation preserves some identities and changes others.

### Stable Across Rotation

- group public key
- logical keyset/signing identity

### Changed Across Rotation

- threshold may change
- member set may change
- member verifying shares
- share secret
- share public key
- `profile_id`
- `group_id`
- `bfonboard`
- `bfshare`
- `bfprofile`
- encrypted relay backup content

Conceptually:

```text
same keyset identity
    group pk:   G  -> G

rotated device identity
    share pk:   S1 -> S2
    profile_id: P1 -> P2

rotated group config
    group_id:   C1 -> C2
```

`group_id` may change even though the group public key stays the same, because the rotated configuration may change threshold and member verifying shares.

## Backup and Recovery Implications

Rotation changes the durable recovery material for every rotated device.

That means:

- rotated devices need fresh `bfshare` recovery credentials
- rotated devices need fresh encrypted relay backups
- old backups are not the active recovery material for the rotated configuration

The backup/recovery package shapes are still defined in [BACKUP.md](./BACKUP.md). Rotation uses those existing artifacts; it does not redefine their wire format.

## Failure Model

Rotation can fail in a few main places:

- fewer than threshold valid `bfshare` shares are supplied
- one or more `bfshare` packages cannot be decrypted
- reconstructed signing key does not match the existing group public key
- rotated output changes the group public key
- rotated backup publication fails
- a target device fails to adopt the rotated share
- only part of the device set adopts the rotated configuration

If rotation fails before rotated artifacts are distributed, the active keyset remains unchanged.

If some devices adopt the rotated share and others do not, the system is in a partial-rotation state and should not treat the old share set as the intended steady state.

## Invariants

These rules should hold across the system:

- rotation must preserve the same group public key
- new keyset generation is not rotation
- old shares become operationally invalid after the rotated configuration is adopted
- rotated-share adoption always uses `bfonboard`
- `bfshare` remains for recovery and threshold-share collection only
- applying a rotated share produces a new canonical `profile_id`
- preserving an existing device during rotation means preserving local installation continuity, not preserving the old share-derived identity

## ASCII Overview

### Trusted Rotation

```text
threshold set of old bfshare packages
    -> decrypt old shares
    -> reconstruct signing key K
    -> split K into rotated shares
    -> rotated group config with same group public key
```

### Distribution

```text
rotated share
   |
   +--> bfonboard --> logged-out onboarding --> fresh rotated profile
   |
   +--> bfonboard --> logged-in rotate key --> rotated profile in place
```

### Identity Transition

```text
before rotation
  group pk   = G
  share pk   = S_old
  profile_id = P_old

after rotation
  group pk   = G
  share pk   = S_new
  profile_id = P_new
```
