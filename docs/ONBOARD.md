# Device Onboarding

## Summary

This document is the living spec for onboarding a FROSTR device.

It covers:

- what onboarding is for
- the roles involved
- the `bfonboard` bootstrap package
- the relay-based onboarding handshake
- the artifacts produced by successful onboarding

Use this document for the conceptual onboarding model.

Use these companion docs for adjacent domains:

- [PROFILE.md](./PROFILE.md): device profile identity and durable state
- [BACKUP.md](./BACKUP.md): backup, recovery, `bfshare`, and full-profile package details
- [ROTATION.md](./ROTATION.md): trusted share rotation and rotated share distribution
- [PROTOCOL.md](./PROTOCOL.md): high-level runtime protocol

## What Onboarding Is

Onboarding is the process of bringing a new device into an existing FROSTR keyset.

It is not the same as:

- importing an existing full device profile with `bfprofile`
- recovering an existing device from relays with `bfshare`

Onboarding is the bootstrap path for a new local device that has not yet materialized its full durable local profile.

## Roles

Onboarding involves three roles.

### 1. Provisioning Side

This is the already-running signer or operator flow that prepares onboarding for a recipient device.

Its job is to:

- choose the target recipient share
- choose the relay set
- produce the encrypted `bfonboard` package
- remain reachable for the callback onboarding handshake

### 2. Recipient Device

This is the new device being brought online.

Its job is to:

- import the encrypted `bfonboard` package
- decrypt it with the provided password
- contact the provisioning signer over relays
- complete the onboarding handshake
- materialize local durable device state

### 3. Relays

Relays carry the onboarding request and onboarding response events between the recipient device and the provisioning signer.

Relays are transport only. They do not interpret onboarding semantics.

## The `bfonboard` Package

`bfonboard` is the compact encrypted onboarding/bootstrap package.

Conceptually, it contains:

- the share secret
- one or more relay URLs
- the callback peer public key (`peer_pk`)

It is intentionally distinct from `bfshare` because onboarding requires callback metadata that recovery does not.

What `bfonboard` is for:

- bootstrap a new device into an existing keyset
- provide the minimum credential needed to dial the provisioning signer
- distribute a rotated share during a rotation workflow:
  - to a newly provisioned device
  - or to an existing device through an in-place `Rotate Key` flow

What `bfonboard` is not:

- not a full device profile
- not a long-term runtime artifact
- not the final local device state

## Onboarding Flow

FROSTR onboarding proceeds in four conceptual phases.

### 1. Provisioning

The provisioning side assembles:

- recipient share secret
- relay set
- callback peer public key
- user-facing password

It encrypts that material into a `bfonboard` package and hands the package plus password to the recipient device through an out-of-band channel.

### 2. Import and Connect

The recipient device:

1. imports the `bfonboard` package
2. decrypts it with the password
3. extracts:
   - share secret
   - relay list
   - callback peer public key
4. brings up a temporary bootstrap context
5. dials the provisioning signer over the listed relays

At this stage, the recipient has enough information to begin onboarding, but it does not yet have a complete local durable profile.

### 3. Relay-Based Handshake

The recipient sends a signed onboarding request event.

Important properties of the request:

- it is sent over relays
- requester identity is inferred from the signed event pubkey
- it carries bootstrap nonce material for the new device

The provisioning signer:

- validates the request
- stores the incoming bootstrap nonces
- returns the keyset/group material needed by the recipient
- includes its own bootstrap nonce material in the response

This handshake is what turns the compact onboarding credential into a complete local signer bootstrap.

### 4. Local Materialization

After the handshake succeeds, the recipient device:

1. constructs the full durable local device profile
2. materializes a local `bfprofile`
3. materializes a local `bfshare`
4. publishes an encrypted profile backup
5. initializes local signer/runtime state

At this point, onboarding is complete and the device is no longer dependent on the original `bfonboard` package.

## Result of Successful Onboarding

Successful onboarding should leave the recipient with:

- a full local device profile equivalent to `bfprofile`
- a local recovery credential equivalent to `bfshare`
- a published encrypted profile backup on relays
- initialized signer/runtime state ready for normal operations

That means onboarding is a bootstrap path into the same durable device state that later import/export and recovery flows operate on.

## Relationship to Other Artifacts

Onboarding sits alongside, but separate from, the other durable profile artifacts.

- `bfonboard`
  - compact onboarding/bootstrap credential
  - used once to create a local device profile
- `bfprofile`
  - full local device profile package
  - used for full import/export after the device exists
- `bfshare`
  - compact recovery credential
  - used to recover a previously onboarded/imported device from relays

In short:

- onboarding starts from `bfonboard`
- full import starts from `bfprofile`
- recovery starts from `bfshare`

## Security and Persistence Properties

Important onboarding properties:

- `bfonboard` is encrypted and password-protected
- the package is a bootstrap artifact, not long-term runtime state
- the callback peer public key is required so the recipient can reach the provisioning signer
- after successful onboarding, durable local state should replace the package

The long-term durable artifacts are:

- local `bfprofile`
- local `bfshare`
- encrypted relay backup

The onboarding package itself should be treated as a transient secret bootstrap credential.

## Failure Model

Onboarding can fail in a few main places:

- package decryption fails
- relay connection fails
- provisioning signer is unavailable
- onboarding request is rejected or times out
- local profile materialization fails
- backup publication fails

If onboarding fails before local materialization completes, the device should not treat itself as fully onboarded.

If onboarding completes locally but backup publication fails, the host may have a usable local device but degraded recovery posture until the backup is published successfully.

## Invariants

These rules should hold across the system:

- onboarding is the bootstrap path for a new device, not a full-profile import path
- `bfonboard` is never the final durable local device profile
- successful onboarding produces the same durable profile class represented by `bfprofile`
- successful onboarding should also produce `bfshare` recovery material
- after onboarding, runtime state should be derived from the new local durable profile, not from continued dependence on the original onboarding package
