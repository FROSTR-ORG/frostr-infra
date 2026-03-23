# ADR-012: Trusted-Dealer Rotation and Device Adoption

## Status

Accepted

## Context

FROSTR needs a concrete rotation workflow, not just a naming rule.

The system already distinguishes:

- rotation
  - same group public key
- new keyset generation
  - new group public key

What remained to be locked was the actual operational model for rotation:

- what operator input starts the rotation
- how new shares are produced
- how rotated shares are delivered to devices
- what happens to device identity and durable local state

The current living design for this workflow is:

- `docs/ROTATION.md`
- `docs/PROFILE.md`
- `docs/BACKUP.md`
- `docs/ONBOARD.md`

## Decision

FROSTR rotation is a trusted-dealer workflow with these rules:

- the operator supplies a threshold set of existing `bfshare` packages
- those threshold shares are used to reconstruct the existing signing key
- that same signing key is split into a new rotated share set
- the rotated keyset preserves the same group public key

Rotated shares are always distributed as `bfonboard` packages.

There are two supported adoption modes for those packages:

- logged-out onboarding with `bfonboard`
- logged-in in-place rotation with `bfonboard`

Rotation does not introduce a separate update package type.

Applying a rotated share to a device changes the canonical share-derived device identity:

- rotated share public key changes
- canonical `profile_id` changes with it

Preserving an existing device during rotation means preserving local installation continuity where possible, not preserving the old canonical `profile_id`.

Once the rotated configuration is adopted, the old shares are operationally invalid for the active keyset.

## Consequences

- rotation requires threshold `bfshare` input from existing devices
- rotated-share adoption uses `bfonboard` in both logged-out and logged-in flows
- rotated devices receive new canonical `profile_id`s
- host implementations may preserve local labels and other host-local context across rotated-device update
- a rotated group configuration may have a new `group_id` even while preserving the same group public key
- product and operator docs must not imply that a rotated-device update keeps the old share-derived identity

## Implementation Rule

Implementations must treat the following as fixed behavior:

- threshold `bfshare` packages are the trusted-dealer rotation input
- new keyset generation is not a substitute for rotation
- `bfshare` remains the compact recovery and threshold-input artifact
- `bfonboard` is the only rotated-share adoption artifact
- old shares and old recovery material are not the active steady-state configuration after rotation is adopted
