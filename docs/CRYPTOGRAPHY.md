# FROSTR Cryptography

## Summary

This document is the shared cryptographic overview for FROSTR.

It focuses on the FROST-side mechanics underneath the system:
- keyset generation
- shares and group data
- nonce pools and nonce safety
- threshold signing
- threshold ECDH
- trusted-dealer rotation from a cryptographic point of view

Use this document for the cryptographic model.

Use these companion docs for adjacent domains:
- [PROTOCOL.md](./PROTOCOL.md)
- [WIRE.md](./WIRE.md)
- [PROFILE.md](./PROFILE.md)
- [BACKUP.md](./BACKUP.md)
- [ROTATION.md](./ROTATION.md)
- [INTERFACES.md](./INTERFACES.md)
- [GLOSSARY.md](./GLOSSARY.md)

For lower-level implementation detail in the Rust stack, see the repo-local `bifrost-rs` root docs.

## Cryptographic Scope

FROSTR uses FROST over secp256k1 in a Schnorr-signing context.

At this layer, the important questions are:
- how one signing key is shared across multiple devices
- how nonce material is prepared and consumed safely
- how partial signing contributions are created and combined
- how threshold ECDH contributions are created and combined

This document does not define:
- relay transport
- peer-message envelope shape
- host UI or operator workflow

Those responsibilities live in [PROTOCOL.md](./PROTOCOL.md), [WIRE.md](./WIRE.md), and the host-specific docs.

## Core Cryptographic Objects

### Keyset

A keyset is the threshold-signing unit.

It consists conceptually of:
- one group public key
- one threshold
- one member set
- one set of secret shares bound to those members

### `group_package`

`group_package` is the structured group representation for the keyset.

It carries:
- the durable `group_name`
- the group public key
- the threshold
- the member list
- the member verifying pubkeys

This is the lossless structured group representation used across profiles and backups.
`group_name` helps humans identify the group, but it does not affect cryptographic identity.

### Share

A share is the per-device secret signing material for one member of the keyset.

Each share has:
- one share secret
- one share public key / member verifying pubkey
- one member index

Each device holds exactly one share for the keyset it belongs to.

### Sign Session

A sign session is the cryptographic signing context for one threshold signing round.

Conceptually, it binds:
- the keyset/group context
- the payload being signed
- the selected participants
- the nonce material for that round

### Partial Signature

A partial signature is one member’s contribution to a threshold signing round.

Partial signatures are individually validated before final aggregation.

### Nonce Pool

A nonce pool is runtime-owned cryptographic state holding signing nonce material for future signing rounds.

Its purpose is to ensure that signing rounds consume fresh nonce material exactly once.

### Threshold ECDH Contribution

Threshold ECDH uses per-member cryptographic contributions analogous to signing contributions, but for shared-secret derivation rather than signature aggregation.

## Keyset Generation

In the current FROSTR model, keyset generation is dealer-driven.

Conceptually:

```text
generate signing key K
  -> derive group public key G
  -> split K into member shares
  -> produce group data + one share per member
```

Important outcomes:
- every share belongs to the same underlying signing key
- all members agree on the same group public key
- no single device holds the full signing key after distribution unless threshold is `1`

Keyset generation is the path that creates a new group public key.

It is therefore distinct from rotation.

## Shares And Group Data

The cryptographic model distinguishes three important identities:
- group public key
  - the keyset identity
- member/share public key
  - the device/member identity inside the keyset
- share secret
  - the member’s secret signing material

Important rule:
- member/share pubkeys are not interchangeable with the group public key

`group_package` is the canonical group boundary because it preserves the full member verifying pubkeys needed by the cryptographic stack.

## Nonce Pools

Nonce pools are one of the central runtime-side cryptographic mechanisms in FROSTR.

Conceptually:

```text
runtime
  -> pre-generate signing nonce material
  -> hold it in nonce pool state
  -> consume it once during signing
  -> replenish for future rounds
```

Nonce pools matter because FROST signing requires fresh nonce material for each signing round.

Important properties:
- signing nonce material is single-use
- nonce material is runtime-owned state, not portable profile state
- missing, exhausted, or already-consumed nonce material means a device cannot safely contribute to that signing round

### Nonce Safety

Nonce reuse is a critical cryptographic failure.

For that reason:
- nonce material must never be reused across signing rounds
- already-claimed nonce state must be treated as unusable
- a runtime must treat nonce availability as part of signing readiness

The protocol-level effects of nonce pools, responder readiness, and nonce-related round failure live in [PROTOCOL.md](./PROTOCOL.md).

## Threshold Signing

Threshold signing in FROSTR follows the FROST pattern.

Conceptually:
1. establish signing-session context
2. bind valid nonce commitments to that session
3. have each participating member produce a partial signature
4. verify partial signatures
5. aggregate them into the final Schnorr signature

High-level cryptographic shape:

```text
signing session
  + fresh member nonce material
  + member key shares
  -> partial signatures
  -> verified aggregation
  -> final signature
```

The protocol-level device choreography, responder validation rules, and failure semantics live in [PROTOCOL.md](./PROTOCOL.md). This document is concerned only with what the signers are cryptographically producing and combining.

## Threshold ECDH

Threshold ECDH reuses the same threshold-share foundation, but produces shared-secret material instead of a signature.

Conceptually:
1. establish the ECDH operation context
2. each participating member computes its ECDH contribution from its share
3. the initiator verifies and combines the threshold contributions
4. the operation yields shared-secret material

Important distinction:
- threshold signing produces a final Schnorr signature
- threshold ECDH produces shared-secret output

But both depend on:
- the same keyset structure
- the same share-holding device model
- threshold participation and contribution validation

## Rotation And Cryptography

At the cryptographic level, trusted-dealer rotation means:

```text
threshold old shares
  -> reconstruct existing signing key K
  -> split K into fresh shares
  -> preserve same group public key G
```

That means:
- rotation preserves the same underlying signing key
- rotation preserves the same group public key
- rotation produces fresh share secrets and fresh member/share pubkeys

If the group public key changes, the system has created a new keyset rather than rotated the existing one.

## Cryptographic Invariants

These rules should hold across the cryptographic layer:
- one keyset has one group public key
- member/share pubkeys are distinct from the group public key
- `group_package` is the lossless group representation
- signing nonce material is single-use
- partial signatures are individually validated before aggregation
- threshold ECDH uses the same share foundation but different output semantics
- rotation preserves the group public key
- keyset replacement changes the group public key
