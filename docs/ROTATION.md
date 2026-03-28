# Key And Share Rotation

## Summary

This document is the shared spec for FROSTR same-key rotation.

It covers:
- what rotation is
- the operator inputs required to perform it
- how rotated shares are created
- how rotated shares are distributed to devices
- how devices adopt rotated state
- what identities and artifacts change across rotation

Use this document for the conceptual and operational model of rotation.

Use these companion docs for adjacent domains:
- [PROFILE.md](./PROFILE.md)
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [GLOSSARY.md](./GLOSSARY.md)

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

The current beta rotation model is trusted-dealer rotation.

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

## Artifact Contract

Rotation uses two distinct interface classes:

- operator input:
  - threshold `bfshare` packages
- adoption output:
  - `bfonboard`

There is no separate rotated-update artifact type in the current system.

This distinction is critical:
- `bfshare` is the operator input artifact for rotation
- `bfonboard` is the adoption artifact for rotation

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
- one rotated durable profile state bundle per target device
- one `bfonboard` package per target device
- one encrypted relay backup per rotated device

The rotated group public key is the same as the old one.

The rotated member verifying shares, threshold, and member count may differ from the previous configuration.

## Operator Hosts

Hosts do not all own the same rotation responsibilities.

- `igloo-shell` is the strongest operator host
  - intended for business and enterprise environments
  - owns first-class operator-side rotation generation through `rotate-keyset`
- browser hosts focus on device adoption and simpler operator flows
  - `igloo-home` and `igloo-pwa` support rotation-oriented UI workflows
  - `igloo-chrome` remains a device-management and onboarding host, not a keyset-generation host

The conceptual rotation model stays the same across hosts. The shell is simply the most explicit environment for staged, manifest-driven rotation work.

## Rotation Phases

### 1. Collect Threshold Shares

The operator gathers a threshold set of `bfshare` packages from existing devices and decrypts them.

This yields the threshold set of old share secrets needed to reconstruct the current signing key.

### 2. Reconstruct And Rotate

The operator reconstructs the current signing key from the threshold old shares.

That same signing key is then split into a new share set using the desired rotated threshold and rotated device count.

Validation must confirm:
- the reconstructed signing key matches the existing group public key
- the rotated output preserves the same group public key

### 3. Materialize Rotated Durable State

For each rotated target device, the system materializes the durable state that would underlie a full `bfprofile`.

That rotated durable state includes:
- a fresh share secret
- a fresh share public key
- a new canonical `profile_id`
- structured `group_package`
  - including `group_name`
- the chosen relay set
- local durable policy inputs

Rotation does not introduce a separate shadow group schema.
It also does not act as an in-place metadata rename flow for the issued group package.

### 4. Distribute Rotated Shares

Each rotated target device is distributed as a `bfonboard` package.

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

## Adoption Paths

### Logged-Out Adoption With `bfonboard`

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

### Logged-In In-Place Rotation With `bfonboard`

This is the logged-in path.

It is used when an already-running device applies a rotated `bfonboard` package directly.

The device:
1. imports the rotated `bfonboard`
2. completes the onboarding-style handshake
3. resolves the rotated durable profile state
4. replaces the active local profile in place

Identity rule:
- applying a rotated `bfonboard` produces a new share public key
- `profile_id` is derived from the share public key
- therefore rotated-device adoption produces a new canonical `profile_id`

Preserving the profile in this flow means preserving the host-local installation context where possible, not preserving the old canonical profile identity.

## Invariants

These rules should hold across rotation:
- rotation preserves the group public key
- keyset replacement changes the group public key
- threshold `bfshare` material is the operator input for rotation
- `bfonboard` is the adoption artifact for rotation
- successful rotated adoption yields a new share public key and a new `profile_id`
- `group_name` remains durable metadata carried by the rotated `group_package`
- changing `group_name` is not part of the current rotation contract
- rotation does not create a separate durable profile schema
