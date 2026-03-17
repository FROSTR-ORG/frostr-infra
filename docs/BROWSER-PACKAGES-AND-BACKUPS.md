# Browser Packages and Backups

## Summary

This document is the living spec for browser-facing package formats and encrypted profile backups shared by `frostr-utils`, `igloo-shared`, `igloo-pwa`, `igloo-chrome`, and `igloo-shell`.

Architectural decisions remain in `docs/adrs/`, especially ADR-008 and ADR-010. Current wire and payload details live here.

The package types are:

- `bfshare`: compact recovery package
- `bfonboard`: compact onboarding package
- `bfprofile`: full encrypted device profile package

The backup type is:

- Nostr `kind: 10000` encrypted profile backup event

`frostr-utils` is the canonical owner of these payloads, codecs, backup-content cryptography, and backup-event construction/parsing.

Host layers consume those primitives:

- `igloo-shared`: browser transport, publish/fetch, lifecycle, and storage
- `igloo-shell`: native/operator transport and managed profile integration
- `igloo-ui`: UI only

## Common Envelope

All three package types use:

- bech32m encoding
- a distinct HRP:
  - `bfshare`
  - `bfonboard`
  - `bfprofile`
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

## `bfshare`

`bfshare` is a compact recovery package. It does not contain full profile metadata.

### Plaintext Form

Before encryption, the plaintext is:

```text
<secret_share>?relay=<url>&relay=<url>...
```

Rules:

- `<secret_share>` is the raw 32-byte share secret encoded as lowercase hex.
- One or more `relay=` query parameters are required.
- Multiple relays are represented only by repeated `relay=` parameters.
- Query-parameter order is preserved on encode.
- Decoders must accept any order.

### Semantics

`bfshare` is used for recovery/login:

1. decrypt `bfshare` with the provided password
2. derive the author pubkey from the share secret
3. fetch the latest encrypted profile backup (`kind: 10000`) by that author from the provided relays
4. decrypt the backup
5. reconstruct a full local `bfprofile`

`bfshare` never includes:

- device name
- manual peer policy overrides
- remote peer policy observations
- group metadata
- runtime snapshot data

## `bfonboard`

`bfonboard` is a compact onboarding package. It uses the same URI-like plaintext shape as `bfshare`, with one additional required field.

### Plaintext Form

Before encryption, the plaintext is:

```text
<secret_share>?relay=<url>&relay=<url>...&peer_pk=<pubkey>
```

Rules:

- `<secret_share>` is the raw 32-byte share secret encoded as lowercase hex.
- `peer_pk` is required.
- `peer_pk` is the callback public key for the running signer that will complete onboarding.

### Semantics

`bfonboard` is used to:

1. decrypt the compact onboarding credential
2. dial out to the callback peer
3. complete the onboarding handshake
4. build a full local `bfprofile`
5. build a local `bfshare`
6. publish an encrypted profile backup

`bfonboard` remains distinct from `bfshare` so onboarding callback metadata stays type-visible.

## `bfprofile`

`bfprofile` is the full local device profile package.

Its bech32m-decoded bytes are:

```text
<profile_id_ascii_hex_64><protected_envelope_json_bytes>
```

Rules:

- `<profile_id_ascii_hex_64>` is the canonical lowercase hex profile id.
- It is exactly 64 ASCII bytes.
- The remaining bytes are the current protected-envelope JSON payload.
- The outer profile id must match the inner plaintext payload profile id.
- The outer and inner profile ids must both match the id derived from the contained share secret.

### Plaintext Form

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

### Required Contents

`bfprofile` must include:

- profile id:
  - canonical profile id derived from the share public key
- device information:
  - device name
  - share secret
  - manual peer policy overrides
  - remote peer policy observations
  - relays
- keyset group information:
  - keyset name
  - group public key
  - threshold
  - total count
  - member index/share-pubkey list

`bfprofile` does not include:

- effective peer policy
- runtime snapshot data
- host-specific persistence metadata

### Profile Id

The canonical profile id is:

```text
hex(sha256("frostr:profile-id:v1" || share_pubkey32))
```

`bfprofile` stores this id twice:

- outside the encrypted payload as the 64-byte bech32-decoded prefix
- inside the encrypted plaintext JSON as `profileId`

Decoders must reject the package unless:

- the outer prefix is valid lowercase 64-char hex
- the outer prefix matches `profileId`
- `profileId` matches the id derived from `device.shareSecret`

### Peer Permission Semantics

Persisted package and backup payloads carry only the durable permission inputs:

- `manualPeerPolicyOverrides`
  - local operator intent
  - tri-state `unset | allow | deny`
  - per direction and per method
- `remotePeerPolicyObservations`
  - last ping-reported peer willingness
  - persisted with `revision` and `updated`

Effective peer policy is always recomputed by the runtime and is never serialized into `bfprofile` or backups.

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

The browser host derives a 32-byte conversation key from the share secret alone, using domain-separated key derivation:

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
- missing `peer_pk` for `bfonboard`
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
