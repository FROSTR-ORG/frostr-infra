# Device Packages And Key Recovery

## Summary

This document is the shared spec for FROSTR durable device packages and for
reconstructing the group secret key from a threshold of shares.

It covers:
- `bfprofile`
- `bfshare`
- key recovery (reconstructing the group secret from a threshold of shares)

Use this document for package-level and payload-level behavior for full-profile
export/import and for threshold key recovery.

> **Removed:** relay-published *encrypted profile backups* (a `kind: 10000` Nostr
> event used to rebuild a single device's profile from one `bfshare`) are no
> longer part of FROSTR. There is no relay-assisted recovery. A lost device is
> restored by importing its self-contained `bfprofile`; the group secret key is
> recovered locally from a threshold of shares (see [Key Recovery](#key-recovery)).

Use these companion docs for adjacent domains:
- [PROFILE.md](./PROFILE.md)
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)
- [PROTOCOL.md](./PROTOCOL.md)
- [GLOSSARY.md](./GLOSSARY.md)

## Scope

This document covers the durable artifacts used after a device exists and the
local reconstruction of the group secret key:

- `bfprofile`
  - the full encrypted local device-profile package (self-contained restore)
- `bfshare`
  - the compact encrypted share package: threshold input for rotation and key
    recovery

`bfonboard` is intentionally out of scope here. Onboarding is covered in
[ONBOARD.md](./ONBOARD.md).

## Artifact Roles

These artifacts play different roles:

- `bfprofile`
  - full portable device profile; importing it restores a device with no relay
    and no other shares
- `bfshare`
  - compact share credential; one threshold input to trusted rotation and to key
    recovery

## Common Package Envelope

`bfprofile`, `bfshare`, and `bfonboard` all use:
- bech32m encoding
- a distinct HRP:
  - `bfprofile`
  - `bfshare`
  - `bfonboard`
- password-based authenticated encryption using **Argon2id** key derivation
  over the **XChaCha20-Poly1305** AEAD. The legacy v1 scheme (PBKDF2-SHA256 +
  AES-256-GCM) was retired in the 2026-04-22 remediation; `BF_PACKAGE_VERSION`
  was bumped `1 → 2` and v1 envelopes are no longer readable.
- a versioned, domain-separated envelope. The current envelope version is
  `BF_PACKAGE_VERSION = 2`.

Current v2 KDF/AEAD parameters (canonical defaults — see
[CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md#envelope-encryption-v2)):
- KDF: Argon2id (v0x13), `m_cost = 262144` KiB (256 MiB), `t_cost = 4`,
  `p_cost = 1`
- KDF salt: `16` bytes; derived key: `32` bytes
- AEAD: XChaCha20-Poly1305 with a `24`-byte nonce
- length-prefixed associated data binds the envelope version and salt so a
  ciphertext cannot be replayed under a different envelope shape

`frostr-utils` is the canonical owner of these codecs and payload validation
rules.

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
- it is stored losslessly inside `bfprofile`
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

`bfshare` is the compact share package.

It does not contain the full device profile. Its purpose is to carry the minimum
credential needed as threshold input to trusted rotation and to key recovery.

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

`bfshare` carries a single share secret. It is consumed as one threshold input:
- during trusted rotation (see [ROTATION.md](./ROTATION.md))
- during key recovery (see [Key Recovery](#key-recovery))

A bare `bfshare` is **not** sufficient to rebuild a device profile on its own: it
carries no group package and no member index. The consuming host supplies the
group context from its own profile and maps each share secret to its member index
by matching the share's derived public key against the group members.

`bfshare` never includes:
- device name
- `profile_id`
- manual peer policy overrides
- group metadata
- runtime snapshot data

## Key Recovery

Key recovery reconstructs the **group secret key** (an `nsec`) from a threshold of
shares. It is entirely local — no relay, and no per-device profile reconstruction.

Inputs:
- the recovering device's own profile `groupPackage` (public, unencrypted) — the
  source of member indices and the group public key
- a threshold of share secrets:
  - the recovering device's own share, unlocked from its `bfprofile`/share
    artifact with the device passphrase
  - additional shares pasted as `bfshare` packages (with their package passwords)

Procedure:
1. read the group package from the local profile
2. unlock the device's own share secret with the device passphrase
3. decode each pasted `bfshare` to its share secret
4. for each share secret, derive its public key and match it to a group member to
   obtain that share's index (reject a secret that is not a member of the group)
5. once at least `threshold` distinct shares are collected, reconstruct the group
   secret key and encode it as an `nsec`

The reconstructed key is held in memory for display/export only and is never
persisted.

## Restoring A Lost Device

There is no relay-assisted device recovery. To restore a device, import its
self-contained `bfprofile` (which carries the full group package and the device
share). A `bfshare` alone cannot restore a device profile.

## Invariants

These rules should hold across packages and recovery:
- `bfprofile` is the full portable profile artifact and the only self-contained
  device-restore path
- `bfshare` is the compact share artifact: threshold input for rotation and key
  recovery, never a standalone profile-restore credential
- key recovery is local: a threshold of share secrets plus the local group package
- a share secret is only accepted if its public key is a member of the group
- structured `groupPackage`, including `groupName`, is the canonical group payload field
- `groupPackage` must be preserved losslessly inside `bfprofile`
