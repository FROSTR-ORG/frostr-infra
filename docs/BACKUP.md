# Device Backup and Recovery

## Summary

This document is the living spec for FROSTR device backup and recovery artifacts.

It covers:

- `bfshare`
- encrypted relay profile backups
- recovery from relay backups
- the low-level package details for `bfprofile`

Use this document for the package-level and payload-level model for portable full-profile export, compact recovery, and encrypted relay backups.

Use these companion docs for adjacent domains:

- [PROFILE.md](./PROFILE.md): device profile identity and durable state
- [ONBOARD.md](./ONBOARD.md): onboarding flow and `bfonboard`
- [ROTATION.md](./ROTATION.md): trusted share rotation and rotated device distribution
- [PROTOCOL.md](./PROTOCOL.md): high-level runtime protocol

## Scope

This document covers the durable profile artifacts used after a device exists or when a device must be reconstructed:

- `bfprofile`
  - the full encrypted local device-profile package
- `bfshare`
  - the compact encrypted recovery package
- encrypted profile backup event
  - the latest relay-published backup used by `bfshare` recovery

`bfonboard` is intentionally out of scope here. Onboarding is covered in [ONBOARD.md](./ONBOARD.md).

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

From the backup/recovery point of view, `bfprofile` is the portable full-state artifact that recovery reconstructs.

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

Before encryption, the plaintext is canonical JSON:

```json
{
  "version": 1,
  "profileId": "<hex64>",
  "device": {
    "name": "Primary Browser Device",
    "shareSecret": "<hex32>",
    "manualPeerPolicyOverrides": [
      {
        "pubkey": "<hex32>",
        "policy": {
          "request": { "ping": "unset", "onboard": "unset", "sign": "deny", "ecdh": "unset" },
          "respond": { "ping": "unset", "onboard": "unset", "sign": "unset", "ecdh": "unset" }
        }
      }
    ],
    "remotePeerPolicyObservations": [
      {
        "pubkey": "<hex32>",
        "profile": {
          "forPeer": "<hex32>",
          "revision": 3,
          "updated": 1773472608,
          "blockAll": false,
          "request": { "echo": true, "ping": true, "onboard": true, "sign": true, "ecdh": true },
          "respond": { "echo": true, "ping": true, "onboard": true, "sign": false, "ecdh": true }
        }
      }
    ],
    "relays": ["wss://relay.example.com"]
  },
  "group": {
    "keysetName": "Treasury",
    "groupPublicKey": "<hex32>",
    "threshold": 2,
    "totalCount": 3,
    "members": [
      { "index": 1, "sharePublicKey": "<hex32>" }
    ]
  }
}
```

### Validation Rules for `bfprofile`

Decoders must reject the package unless:

- the bech32m text and HRP are valid
- the outer prefix is valid lowercase 64-char hex
- the outer prefix matches `profileId`
- `profileId` matches the id derived from `device.shareSecret`
- the decrypted JSON is complete and structurally valid

## `bfshare`

`bfshare` is the compact recovery package.

It does not contain the full device profile.

Its purpose is to carry the minimum credential needed to recover the full profile from relays.

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
2. derive the author pubkey from the share secret
3. fetch the latest encrypted profile backup by that author from the provided relays
4. decrypt the backup
5. reconstruct a full local `bfprofile`

`bfshare` is also used as operator input during trusted rotation, because a threshold set of existing recovery credentials is used to reconstruct the current signing key before issuing rotated shares.

`bfshare` never includes:

- device name
- `profile_id`
- manual peer policy overrides
- remote peer policy observations
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

```json
{
  "version": 1,
  "device": {
    "name": "Primary Browser Device",
    "sharePublicKey": "<hex32>",
    "manualPeerPolicyOverrides": [
      {
        "pubkey": "<hex32>",
        "policy": {
          "request": { "ping": "unset", "onboard": "unset", "sign": "deny", "ecdh": "unset" },
          "respond": { "ping": "unset", "onboard": "unset", "sign": "unset", "ecdh": "unset" }
        }
      }
    ],
    "remotePeerPolicyObservations": [
      {
        "pubkey": "<hex32>",
        "profile": {
          "forPeer": "<hex32>",
          "revision": 3,
          "updated": 1773472608,
          "blockAll": false,
          "request": { "echo": true, "ping": true, "onboard": true, "sign": true, "ecdh": true },
          "respond": { "echo": true, "ping": true, "onboard": true, "sign": false, "ecdh": true }
        }
      }
    ],
    "relays": ["wss://relay.example.com"]
  },
  "group": {
    "keysetName": "Treasury",
    "groupPublicKey": "<hex32>",
    "threshold": 2,
    "totalCount": 3,
    "members": [
      { "index": 1, "sharePublicKey": "<hex32>" }
    ]
  }
}
```

The backup excludes the share secret and effective peer policy by design.

### Backup Encryption Key

The backup encryption key is not ECDH-derived.

The host derives a 32-byte conversation key from the share secret alone using domain-separated key derivation:

- input: share secret bytes
- domain/info string: `frostr-profile-backup/v1`
- KDF: HMAC-SHA256 or HKDF-SHA256
- output length: 32 bytes

That derived key is used directly as the NIP-44 conversation key.

This keeps recovery possible from `bfshare` alone and avoids a circular dependency on group metadata before decryption.

## Recovery Flow

`Recover from Share` uses the following sequence:

1. decrypt `bfshare`
2. extract `shareSecret + relays`
3. derive the share public key from the share secret
4. fetch the latest `kind: 10000` event by that author from the relays
5. derive the backup conversation key from the share secret
6. decrypt the NIP-44 content
7. validate the decrypted backup payload
8. reconstruct a full `bfprofile`

## Validation Rules

Implementations must reject:

- malformed bech32m text or wrong HRP
- malformed relay URLs
- malformed 32-byte hex secrets or pubkeys
- malformed or incomplete `bfprofile` JSON
- malformed backup payloads after decryption

## Ownership

- `frostr-utils` owns package formats, payload validation, backup payload encryption/decryption, and backup-event construction/parsing
- host layers own relay transport:
  - `igloo-shared` for browser hosts
  - `igloo-shell` for native/operator flows
- `igloo-pwa` and `igloo-chrome` consume the shared browser host semantics
- `igloo-ui` remains UI-only
