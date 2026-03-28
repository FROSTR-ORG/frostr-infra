# FROSTR Architecture

## Summary

This document is the shared architecture overview for FROSTR as a released system.

It explains:
- the core FROSTR model
- how keysets, shares, and devices relate
- how durable artifacts and live runtimes fit together
- how devices communicate over relays
- how onboarding, backup, recovery, rotation, and keyset replacement fit together
- how host surfaces relate to the runtime

Use this document for the system-level picture.

Use these companion docs for lower-level detail:
- [INTERFACES.md](./INTERFACES.md)
- [GLOSSARY.md](./GLOSSARY.md)
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)
- [PROTOCOL.md](./PROTOCOL.md)
- [WIRE.md](./WIRE.md)
- [PROFILE.md](./PROFILE.md)
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [ROTATION.md](./ROTATION.md)

## System Overview

FROSTR is a threshold-signing system built around a keyset shared across multiple devices.

At a high level:
- one keyset has one group public key
- the signing secret is split into multiple shares
- each signing device holds one share secret
- no single device can sign alone unless the threshold is `1`
- devices coordinate over relays using encrypted peer-to-peer messages

That gives FROSTR four central architectural layers:

1. cryptographic structure
   - keysets, shares, threshold signing, ECDH
2. device/runtime structure
   - one local profile per share-holding device
   - one runtime that uses that share to participate in threshold operations
3. artifact and lifecycle structure
   - durable profiles
   - recovery artifacts
   - onboarding artifacts
   - rotation-distribution artifacts
4. host/product structure
   - browser, shell, and other surfaces that store profiles, bootstrap devices, and expose signing functionality

## Host Asymmetry

Hosts do not all own the same responsibilities.

- `igloo-shell` is the strongest operator host and the primary enterprise/business surface
- browser hosts prioritize profile management, onboarding, recovery, and rotated-share adoption
- operator-only workflows such as staged trusted rotation are therefore most explicit in `igloo-shell`

The shared architecture does not require every host to expose the same control surface. It requires all hosts to preserve the same identities, artifacts, and runtime contracts.

## Core Model

### Keyset

A FROSTR keyset is the threshold-signing unit.

It has:
- one group public key
- one threshold `t`
- one participant count `n`
- one member list

Conceptually:

```text
keyset
  -> group public key
  -> threshold t
  -> n member shares
```

### Share

A share is the per-device secret material derived from keyset generation and, in a mature system, from share-refresh/rotation operations that preserve the same group public key.

Each share corresponds to:
- one share secret
- one share public key
- one member index in the keyset

Each device holds exactly one share for the keyset it belongs to.

### Device

A FROSTR device is one host-local signer instance holding one share.

A device has:
- one share secret
- one share public key
- one local device label
- one canonical `profile_id`
- one relay set
- one local policy view
- one durable local profile

The local profile is the durable identity and configuration for the device. The runtime is the live process built from that profile.

## Device State Model

Each device has three major state classes:

- durable portable profile state
- host-local state
- live runtime state

Conceptually:

```text
device
  -> durable profile
     -> share secret
     -> relays
     -> structured group_package, including group_name
     -> peer policy inputs
  -> host-local state
     -> selection, manifests, vault references, local bookkeeping
  -> runtime
     -> relay connections
     -> nonce pool state
     -> live peer reachability
     -> in-flight operations
```

This split matters because:
- onboarding/bootstrap creates the durable profile
- runtime can be restarted or recreated from that durable profile
- backup/recovery reconstructs durable profile state, not a live process
- host-local state may survive runtime restarts, but it is not the portable profile contract

## Artifact Architecture

FROSTR has three major portable artifact classes:

- `bfprofile`
  - full portable device profile
- `bfshare`
  - compact recovery artifact and threshold rotation input
- `bfonboard`
  - bootstrap and rotated-share adoption artifact

These artifacts are intentionally distinct:
- `bfprofile` moves complete durable device state
- `bfshare` enables recovery and operator rotation input
- `bfonboard` enables onboarding and rotated-share adoption

Encrypted relay backups complement those artifacts by publishing durable backup state derived from a device profile.

## Host And Runtime Architecture

Hosts and runtimes meet at a concrete control and read-model boundary built on the durable profile.

Hosts own:
- profile storage
- local manifests and selection state
- UX and operator workflows
- runtime lifecycle orchestration
- issuing config and policy updates
- issuing operation requests such as `ping`, `onboard`, `sign`, and `ecdh`

The runtime owns:
- readiness
- peer status
- live policy/effective policy computation
- nonce pools
- pending operations
- live diagnostics
- operation completions and failures
- runtime events

The host/runtime boundary therefore has two directions:

- host -> runtime
  - durable profile inputs
  - start/stop/reset
  - config and policy mutation
  - operation requests
- runtime -> host
  - `status`
  - `runtime_status`
  - `readiness`
  - peer status
  - effective peer policy state
  - completions/failures
  - diagnostics and runtime events

Hosts should treat `runtime_status()` as the canonical aggregated read model rather than inferring readiness or round-state truth from local heuristics.

## Protocol Architecture

FROSTR devices talk to each other through encrypted request/response messages over relays.

High-level flow:

```text
initiating device
   -> choose peers
   -> send encrypted request(s)
   -> peers validate and respond
   -> initiator validates responses
   -> operation succeeds or fails
```

The core peer operations are:
- `ping`
- `onboard`
- `sign`
- `ecdh`

The request lifecycle, responder validation rules, locked-peer semantics, and timeout/failure model live in [PROTOCOL.md](./PROTOCOL.md).

## Relay And Wire Architecture

Relays are transport infrastructure, not trusted protocol interpreters.

At the wire level:
- peer messages are Nostr events
- event `content` is NIP-44 encrypted
- the recipient is indicated by a single `p` tag
- decrypted content is a peer envelope with a request id, timestamp, and typed payload

That separation is intentional:
- relays can route and store events
- devices alone interpret protocol payloads

## Signing Architecture

Threshold signing is the central runtime operation.

Conceptually:

```text
caller
  -> local device runtime
     -> choose sign-capable peers
     -> send sign requests
     -> collect partial responses
     -> verify required peer responses
     -> aggregate final signature
```

Signing readiness is partly cryptographic and partly operational:
- the runtime must have valid nonce state
- selected peers must be sign-capable
- required locked-peer responses must be valid

## ECDH Architecture

Threshold ECDH follows a similar model:

```text
caller
  -> local device runtime
     -> choose ECDH-capable peers
     -> send ECDH requests
     -> collect ECDH responses
     -> verify required peer responses
     -> combine shared secret
```

The output is shared-secret material, not a signature, but the request/response lifecycle is parallel to signing.

## Onboarding Architecture

Onboarding has two layers:

- host/bootstrap layer
  - import `bfonboard`
  - decrypt bootstrap credential
  - create temporary bootstrap context
  - materialize durable local state after success
- peer protocol layer
  - send onboarding request
  - exchange bootstrap nonce material
  - receive returned group/bootstrap material

Successful onboarding should leave the recipient with:
- a local durable profile
- a local `bfshare`
- an encrypted relay backup
- initialized runtime state

## Backup And Recovery Architecture

Recovery reconstructs a device profile from:
- one `bfshare`
- the latest encrypted profile backup event addressed by the share-derived backup author identity

The recovered result is durable device state, not runtime state.

`bfprofile` is the full portable export/import artifact for that same durable profile state.

## Rotation Architecture

Rotation is same-key redistribution, not keyset replacement.

Current rotation is trusted-dealer rotation:
- operator gathers threshold `bfshare` inputs
- current signing key is reconstructed
- the same signing key is re-split into a fresh share set
- the group public key stays the same
- new shares are distributed as `bfonboard`

This means:
- `bfshare` is rotation input
- `bfonboard` is rotation adoption output
- successful adoption of a rotated share yields a new share public key and therefore a new `profile_id`

## Invariants

These rules should hold across the system:
- group public key is the keyset identity
- share public key is the peer-routing identity
- `profile_id` is the durable host-facing profile identity
- durable profile state is distinct from host-local and runtime-only state
- `bfprofile`, `bfshare`, and `bfonboard` have distinct roles
- rotation preserves the group public key
- keyset replacement changes the group public key
- relays carry encrypted traffic but do not interpret the protocol
