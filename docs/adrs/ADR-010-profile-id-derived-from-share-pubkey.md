# ADR-010: Profile ID Derived from Share Pubkey

## Status

Accepted

## Current Source of Truth

Current `profile_id` package and backup details live in `docs/BROWSER-PACKAGES-AND-BACKUPS.md`.

## Context

Encrypted device profiles need a stable identifier outside the encrypted payload.

That external identifier serves several purposes:

- distinguish encrypted profiles on disk or in browser storage
- provide a stable handle for host tooling and operator flows
- commit the outer profile record to something inside the encrypted payload

At the same time, we do not want to expose the raw share public key in unencrypted profile metadata, file names, or storage keys.

Using the raw share public key as the profile id would satisfy uniqueness and stability, but it would leak signer identity metadata outside the encrypted payload.

Using a random opaque id would hide the share public key, but it would not be deterministically bound to the profile identity unless extra binding machinery were added.

## Decision

The canonical `profile_id` is a domain-separated SHA-256 hash of the share public key:

- `profile_id = hex(sha256("frostr:profile-id:v1" || share_pubkey32))`

The same `profile_id` is stored:

- outside the encrypted payload as the host-visible profile identifier
- inside the encrypted payload as part of the canonical profile contents

On profile load or import, hosts must decrypt the payload and verify that:

- outer `profile_id == inner profile_id`

The full hex-encoded SHA-256 digest is the canonical identifier.

Any shortened form, such as the first 8 hex characters, is:

- display-only
- not a lookup key
- not a storage key
- not a protocol identifier

### Rationale

This gives us:

- a stable external identifier
- deterministic binding between outer metadata and inner encrypted contents
- no direct leakage of the raw share public key outside the encrypted payload
- simpler operator/debug flows than a random opaque id

The hash must be domain-separated so that profile ids are not reused accidentally across unrelated derivation contexts.

SHA-256 is preferred over RIPEMD-160 because:

- it preserves a larger collision margin
- it is already a standard dependency and operator expectation across the stack
- output length can be shortened for display without weakening the canonical stored id

## Consequences

- `bfprofile` payloads must include the canonical `profile_id` inside the encrypted contents
- profile/package loaders must reject any package where the outer and inner ids do not match
- host storage keys, file naming, and operator references should use `profile_id`, not the raw share public key
- the raw share public key remains part of the cryptographic/runtime model, but not the host-visible profile identifier
- UI surfaces may display a short id prefix for readability, but all persistence and lookup paths must use the full id
- any existing profile id scheme that is not derived from the share public key is no longer the canonical model
