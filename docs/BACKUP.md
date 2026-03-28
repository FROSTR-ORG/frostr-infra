# Device Backup And Recovery

## Summary

This document is the shared spec for FROSTR device backup and recovery artifacts.

It covers:
- `bfprofile`
- `bfshare`
- encrypted relay profile backups
- recovery from relay backups

Use this document for package-level and payload-level behavior for full-profile export/import, compact recovery, and encrypted relay backups.

Use these companion docs for adjacent domains:
- [PROFILE.md](./PROFILE.md)
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)
- [PROTOCOL.md](./PROTOCOL.md)
- [GLOSSARY.md](./GLOSSARY.md)

## Scope

This document covers the durable profile artifacts used after a device exists or when a device must be reconstructed:

- `bfprofile`
  - the full encrypted local device-profile package
- `bfshare`
  - the compact encrypted recovery package
- encrypted profile backup event
  - the relay-published backup used by `bfshare` recovery

`bfonboard` is intentionally out of scope here. Onboarding is covered in [ONBOARD.md](./ONBOARD.md).

## Artifact Roles

These artifacts play different roles:

- `bfprofile`
  - full portable device profile
- `bfshare`
  - compact recovery credential and threshold rotation input
- encrypted backup event
  - relay-published durable profile backup used with `bfshare`

Recovery always depends on both:
- `bfshare`
- the encrypted backup event located through the share-derived author identity

## Common Package Envelope

`bfprofile` and `bfshare` both use:
- bech32m encoding
- a distinct HRP:
  - `bfprofile`
  - `bfshare`
- password-based encryption using PBKDF2-SHA256 + AES-GCM
- a versioned JSON envelope containing:
  - `version`
  - `passwordEncoding`
  - `iterations`
  - `ivBytes`
  - `saltHex`
  - `cipherText`

Current defaults:
- iterations: `600000`
- salt bytes: `16`
- IV bytes: `24`

`frostr-utils` is the canonical owner of these codecs, payload validation rules, backup cryptography, and backup-event construction/parsing.

## `bfprofile` Package Format

`bfprofile` is the full local device-profile package.

### Wire Layout

Its bech32m-decoded bytes are:

```text
<profile_id_ascii_hex_64><protected_envelope_json_bytes>
```

Rules:
- `<profile_id_ascii_hex_64>` is the canonical lowercase hex profile id
- it is exactly 64 ASCII bytes
- the remaining bytes are the protected-envelope JSON payload
- the outer profile id must match the inner plaintext payload profile id
- the outer and inner profile ids must both match the id derived from the contained share secret

### Plaintext Payload

Before encryption, the plaintext is canonical JSON containing:
- `version`
- `profileId`
- `device`
  - `name`
  - `shareSecret`
  - `manualPeerPolicyOverrides`
  - `relays`
- `groupPackage`
  - including `groupName`

`groupPackage` is structured `GroupPackage` data.

Rules:
- it is stored losslessly inside `bfprofile` and encrypted relay backups
- member public keys are full compressed secp256k1 points
- decoders must not reconstruct member pubkeys from x-only share public keys
- `groupName` lives inside `groupPackage`, not alongside it
- `groupName` is durable group metadata carried with the issued artifact, not a separate mutable local label

### Validation Rules For `bfprofile`

Decoders must reject the package unless:
- the bech32m text and HRP are valid
- the outer prefix is valid lowercase 64-char hex
- the outer prefix matches `profileId`
- `profileId` matches the id derived from `device.shareSecret`
- the decrypted JSON is complete and structurally valid

## `bfshare`

`bfshare` is the compact recovery package.

It does not contain the full device profile.

Its purpose is to carry the minimum credential needed to recover the full profile from relays and to supply threshold input to trusted rotation.

### Plaintext Form

Before encryption, the plaintext is:

```text
<secret_share>?relay=<url>&relay=<url>...
```

Rules:
- `<secret_share>` is the raw 32-byte share secret encoded as lowercase hex
- one or more `relay=` query parameters are required
- multiple relays are represented only by repeated `relay=` parameters
- query-parameter order is preserved on encode
- decoders must accept any order

### Semantics

`bfshare` is used for recovery:
1. decrypt `bfshare`
2. derive the backup author pubkey from the share secret
3. fetch the latest encrypted profile backup by that author from the provided relays
4. decrypt the backup
5. reconstruct a full local `bfprofile`

`bfshare` is also used as operator input during trusted rotation.

`bfshare` never includes:
- device name
- `profile_id`
- manual peer policy overrides
- group metadata
- runtime snapshot data

## Encrypted Profile Backups

Each share publishes its own encrypted profile backup as a Nostr event.

### Event Shape

- kind: `10000`
- author pubkey: pubkey derived from the share secret
- content: NIP-44 encrypted JSON
- lookup rule: fetch the latest `kind: 10000` event by author pubkey

### Backup Payload

The encrypted JSON contains:
- `version`
- `device`
  - `name`
  - `sharePublicKey`
  - `manualPeerPolicyOverrides`
  - `relays`
- `groupPackage`
  - including `groupName`

The backup excludes the share secret, remote peer policy observations, and effective peer policy by design.

Rules:
- `groupPackage` is structured, lossless group data
- `groupName` is part of `groupPackage`
- member pubkeys are full compressed secp256k1 points
- decoders must not reconstruct member pubkeys from x-only share pubkeys
- `groupName` is preserved as issued group metadata, not rewritten from host-local labels during backup creation

### Backup Author Identity

The backup author pubkey is derived from the share secret.

This is why `bfshare` recovery works:
1. decrypt `bfshare`
2. derive the backup author identity from the share secret
3. query relays for the latest matching backup event
4. decrypt backup content
5. reconstruct the full durable profile

### Backup Encryption Key

The backup conversation key is derived from the share secret alone with the domain string:

```text
frostr-profile-backup/v1
```

That derived symmetric key is then used for backup content encryption.

## Recovery Model

Recovery reconstructs a full durable device profile from:
- one decrypted `bfshare`
- the latest matching encrypted relay backup

Successful recovery should yield:
- the same durable profile class represented by `bfprofile`
- a usable local profile on the recovering host
- the ability to start runtime state from that recovered durable state

## Invariants

These rules should hold across backup and recovery:
- `bfprofile` is the full portable profile artifact
- `bfshare` is the compact recovery and rotation-input artifact
- encrypted backups are relay-published durable profile backups
- recovery uses `bfshare` plus encrypted backup, not `bfonboard`
- structured `groupPackage`, including `groupName`, is the canonical group payload field
- `groupPackage` must be preserved losslessly
