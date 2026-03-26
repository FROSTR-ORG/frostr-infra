# ADR-008: Browser Package and Backup Formats

## Status

Accepted

## Current Source of Truth

Current package, backup, and `profileId` format details live in `docs/BACKUP.md`.

## Context

The browser hosts now support:

- onboarding via `bfonboard`
- local device-profile import/export via `bfprofile`
- recovery/login via `bfshare`
- encrypted profile backups published to relays

Earlier UI-first work introduced provisional browser package formats in `igloo-pwa`. Those formats are not sufficient as a shared contract across browser hosts.

We need one canonical definition for:

- package ownership
- package semantics
- encrypted backup semantics
- browser-host implementation boundaries

## Decision

`frostr-utils` owns the canonical package codecs, payload models, backup-content crypto, and backup-event construction/parsing.

Host layers own relay transport and host integration:

- `igloo-shared` for browser hosts
- `igloo-shell` for native/operator flows

The canonical package types are:

- `bfshare`: compact recovery package
- `bfonboard`: compact onboarding package
- `bfprofile`: full encrypted device profile package

The canonical encrypted backup event is:

- Nostr `kind: 10000`

### Package Semantics

`bfshare` and `bfonboard` remain separate package types.

`bfshare` is a compact URI-like payload containing:

- the raw share secret
- one or more suggested relays

`bfonboard` uses the same compact payload model and additionally requires:

- `peer_pk`

`bfprofile` is the only full local device-profile package and includes:

- canonical `profileId`
- top-level `keysetName`
- share secret
- device name
- manual peer policy overrides
- remote peer policy observations
- relays
- structured `groupPackage`

`bfprofile` is encoded as one single `bfprofile1...` token whose decoded bytes are:

- `profile_id_ascii_hex_64`
- followed immediately by the protected-envelope JSON bytes

The same canonical `profileId` is also present inside the encrypted plaintext payload and must match the outer prefix.

### Backup Semantics

Each share publishes its own encrypted profile backup as the latest `kind: 10000` event authored by the pubkey derived from the share secret.

Backup content excludes the share secret.

Backup decryption uses a symmetric conversation key derived from the share secret alone, with explicit domain separation, not an ECDH key derived from the group public key.

## Consequences

- `igloo-pwa` and `igloo-chrome` must consume package and backup behavior through `igloo-shared`, which in turn consumes the canonical `frostr-utils` spec implementation
- `igloo-shell` must consume the same `frostr-utils` package and backup behavior
- duplicate package/backup codecs outside `frostr-utils` are architectural drift
- `bfshare` recovery can start from share secret + relays alone
- `bfonboard` stays type-distinct from `bfshare`, preserving onboarding callback semantics
- `bfprofile` stays the sole full device-profile import/export package
- `bfprofile` and encrypted backups preserve full compressed member pubkeys through structured `groupPackage` data
- runtime snapshot data remains outside the package spec
- relay publish/query/fetch is explicitly out of scope for `frostr-utils`
