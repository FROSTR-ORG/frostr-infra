# ADR-011: Rotation Preserves Group Public Key

## Status

Accepted

## Context

FROSTR uses a threshold keyset identified by its group public key.

Recent documentation and utility code drifted into using the word `rotation` for a dealer-generated successor keyset that produced a new group public key. That is not the intended design.

If the group public key changes, the system has a new keyset identity. That is not the same thing as rotating or refreshing the shares of the existing keyset.

Current architecture details live in:

- `docs/ARCHITECTURE.md`
- `docs/PROFILE.md`
- `docs/BACKUP.md`

## Decision

In FROSTR:

- rotation / share refresh preserves the same group public key
- keyset replacement / rollover produces a new group public key

Therefore:

- `rotation` must not be used to describe a successor keyset with a different group public key
- code and docs must distinguish:
  - share rotation/refresh
  - keyset replacement/reissue/rollover

## Consequences

- the group public key remains the stable identity of a keyset across rotation
- if a workflow emits a different group public key, it must be described as a new keyset or keyset replacement
- API and utility names must not imply that a new-keyset reissue is a rotation
- host and operator docs must preserve this distinction

## Implementation Rule

The trusted-dealer rotation implementation must:

- take threshold shares from the current keyset
- reconstruct the existing signing key
- split that same signing key into a new share set
- preserve the same group public key across the rotation

Because threshold and member verifying shares may change, a rotated group configuration may produce a different derived `group_id` even though the group public key stays the same.

## Current Hard-Cut Implication

The alpha utility code must not expose any successor-keyset reissue feature.

- rotation is the only supported same-key share renewal path
- generating a new keyset is the supported way to get a different group public key
