# FROSTR Architecture

## Summary

This document is the living architecture overview for FROSTR.

It explains:

- the core FROSTR model
- how keysets and shares work
- how signing devices are modeled
- how devices communicate over relays
- how onboarding, backup, recovery, rotation, and keyset replacement fit together
- how host surfaces relate to the runtime

Use this document for the system-level picture.

Use these companion docs for lower-level detail:

- [PROTOCOL.md](./PROTOCOL.md): peer-to-peer protocol semantics
- [WIRE.md](./WIRE.md): wire format over Nostr relays
- [PROFILE.md](./PROFILE.md): durable device/profile state
- [BACKUP.md](./BACKUP.md): backup and recovery artifacts
- [ONBOARD.md](./ONBOARD.md): onboarding/bootstrap flow
- [ROTATION.md](./ROTATION.md): trusted share rotation and rotated distribution flows
- [adrs/INDEX.md](./adrs/INDEX.md): architectural decisions and history

## System Overview

FROSTR is a threshold-signing system built around a keyset shared across multiple devices.

At a high level:

- one keyset has one group public key
- the signing secret is split into multiple shares
- each signing device holds one share secret
- no single device can sign alone unless the threshold is `1`
- devices coordinate over relays using encrypted peer-to-peer messages

That gives FROSTR three central architectural layers:

1. cryptographic structure
   - keysets, shares, threshold signing, ECDH
2. device/runtime structure
   - one local profile per share-holding device
   - one runtime that uses that share to participate in threshold operations
3. host/product structure
   - browser, shell, and other surfaces that store profiles, bootstrap devices, and expose signing functionality

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

Example:

```text
2-of-3 keyset

group public key: G
members:
  share 1 -> device A
  share 2 -> device B
  share 3 -> device C

any 2 valid participants can complete a signing round
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

The local profile is the durable identity/configuration for the device. The runtime is the live process built from that profile.

## Architectural Shape

The system can be understood with this simplified picture:

```text
                    +----------------------+
                    |      Keyset          |
                    |  group public key G  |
                    |    threshold t/n     |
                    +----------+-----------+
                               |
               +---------------+---------------+
               |               |               |
               v               v               v
        +-------------+ +-------------+ +-------------+
        |  Device A   | |  Device B   | |  Device C   |
        |  share s1   | |  share s2   | |  share s3   |
        | profile p1  | | profile p2  | | profile p3  |
        +------+------+ +------+------+ +------+------+
               |               |               |
               +---------------+---------------+
                               |
                               v
                    +----------------------+
                    |    Nostr Relays      |
                    | encrypted p2p msgs   |
                    +----------------------+
```

The relays do not hold the secret or interpret the protocol. They carry encrypted peer traffic and encrypted profile-backup events.

## Device Architecture

Each device has two major states:

- durable profile state
- live runtime state

Conceptually:

```text
device
  -> durable profile
     -> share secret
     -> relays
     -> group metadata
     -> peer policy inputs
  -> runtime
     -> relay connections
     -> nonce pool state
     -> live peer reachability
     -> in-flight operations
```

This split matters because:

- onboarding/bootstrap creates the durable profile
- runtime can be restarted or recreated from that durable profile
- backup/recovery is about reconstructing the durable profile, not preserving a live process

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
  - reachability and policy observation
- `onboard`
  - bootstrap exchange for a new device
- `sign`
  - threshold signing round
- `ecdh`
  - threshold ECDH/shared-secret round

Lower-level transport details live in [WIRE.md](./WIRE.md).

## Relay and Wire Architecture

Relays are transport infrastructure, not trusted protocol interpreters.

At the wire level:

- peer messages are Nostr events
- event `content` is NIP-44 encrypted
- the recipient is indicated by a single `p` tag
- decrypted content is a peer envelope with a request id, timestamp, and typed payload

Conceptually:

```text
Nostr event
  -> tags
     -> single recipient p tag
  -> content
     -> NIP-44 encrypted blob
        -> peer envelope
           -> typed protocol payload
```

That separation is intentional:

- relays can route and store events
- devices alone can interpret the protocol payload

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

ASCII view:

```text
            sign request
caller ----------------------> initiator device
                                 |
                                 | encrypted sign requests
                                 v
                       +---------+---------+
                       |                   |
                       v                   v
                  peer device B       peer device C
                       |                   |
                       | partial responses |
                       +---------+---------+
                                 |
                                 v
                          initiator verifies
                          and aggregates
                                 |
                                 v
                           final signature
```

Important architectural property:

- the initiator may coordinate the round
- but a threshold-valid peer set must participate
- if required locked peers fail or return invalid material, the round fails

## ECDH Architecture

ECDH follows the same broad architecture as signing:

- choose an eligible peer set
- exchange encrypted request/response material
- validate locked peer responses
- combine the final shared-secret result

The main difference is the operation semantics, not the communication model.

## Onboarding Architecture

Onboarding is how a new device enters an existing keyset.

It has two layers:

1. bootstrap artifact layer
   - the recipient gets a `bfonboard` package and password
2. peer protocol layer
   - the recipient contacts an existing signer and completes the onboarding exchange

Conceptually:

```text
existing signer/operator
  -> produces bfonboard
  -> hands package + password to recipient

recipient device
  -> decrypts bfonboard
  -> contacts provisioning signer over relays
  -> completes onboard request/response exchange
  -> materializes local profile
  -> materializes recovery package
  -> publishes encrypted backup
```

ASCII view:

```text
provisioning side                    recipient device
------------------                   ----------------
build bfonboard  ----------------->  import + decrypt
                                     |
                                     | onboard request over relays
                                     v
                              provisioning signer runtime
                                     |
                                     | onboard response
                                     v
                              materialize local profile
                              materialize bfshare
                              publish encrypted backup
```

Onboarding is therefore not just file import. It is a bootstrap exchange that ends by creating the same durable local device state used by later import/export and recovery flows.

## Backup and Recovery Architecture

FROSTR separates full profile export from compact recovery.

Artifacts:

- `bfprofile`
  - full local device profile package
- `bfshare`
  - compact recovery credential
- encrypted relay profile backup
  - latest share-authored backup event on relays

Conceptually:

```text
full export/import:
  device profile <-> bfprofile

compact recovery:
  bfshare + relays
    -> fetch encrypted backup
    -> decrypt backup
    -> reconstruct full profile
```

ASCII view:

```text
             +--------------------+
             |   local profile    |
             +----+----------+----+
                  |          |
        export/import        | publish encrypted backup
                  |          v
                  |    +-----------+
                  |    |  relays   |
                  |    +-----------+
                  |          ^
                  v          |
             +-----------+   |
             | bfprofile  |   |
             +-----------+   |
                             |
                    +--------+--------+
                    |     bfshare     |
                    | share + relays  |
                    +-----------------+
```

This architecture gives two different operational modes:

- full portability through `bfprofile`
- compact recovery through `bfshare` plus relay backup retrieval

## Rotation and Keyset Replacement

FROSTR needs a strict distinction between:

- rotation / share refresh
  - preserves the same group public key
  - refreshes the per-device share material
- keyset replacement / rollover
  - produces a new group public key
  - creates a new keyset identity

Conceptually:

```text
same keyset identity
  -> same group public key
  -> refreshed device shares

new keyset identity
  -> new group public key
  -> replacement device shares
```

Implications:

- true rotation should not change the group public key
- if the group public key changes, that is a new keyset, not a rotation
- trusted-dealer rotation is implemented by reconstructing the existing signing key from threshold shares and re-splitting that same key into new shares
- both rotation and keyset replacement require new local share material on participating devices
- device profiles and backups must be refreshed whenever the underlying share material changes
- runtime readiness must be rebuilt from the updated profile state

Conceptually:

```text
rotation / share refresh
  old shares  -> new shares
  group pk G  -> group pk G

keyset replacement / rollover
  old shares  -> new shares
  group pk G1 -> group pk G2
```

This distinction is important because FROSTR relies on the group public key as the stable identity of a keyset.

Detailed rotation inputs, distribution paths, and device-adoption behavior live in [ROTATION.md](./ROTATION.md).

## Recovery Architecture

Recovery is distinct from onboarding, rotation, and keyset replacement.

- onboarding
  - bootstrap a new device into an existing keyset
- recovery
  - reconstruct a previously existing device from compact credentials and relay backups
- rotation
  - refresh shares while preserving the same group public key
- keyset replacement
  - replace the keyset with a new group public key

Recovery starts from:

- `bfshare`
- relay access
- the latest encrypted backup

and ends at:

- reconstructed local durable profile state
- a runtime that can be started from that profile

## Host Architecture

FROSTR separates the runtime/signer core from host surfaces.

High-level ownership:

- `bifrost-rs`
  - threshold signing, ECDH, peer capability, readiness, protocol validation, and runtime logic
- `bifrost-app`
  - native host/bootstrap and runtime hosting layer
- `igloo-shell`
  - operator CLI/TUI, managed profile/vault UX, daemon lifecycle UX
- `igloo-chrome`
  - browser host, provider surface, operator UI, extension lifecycle wiring
- `frostr-infra`
  - cross-repo docs, orchestration, demo environments, and cross-repo E2E coverage

The architectural rule is:

- hosts own storage UX, lifecycle UX, and integration UX
- the runtime owns signer truth, readiness, peer capability, and protocol behavior

## Host/Runtime Boundary

The host/runtime boundary is one of the most important architectural lines in FROSTR.

The runtime owns:

- signer state
- peer capability
- readiness
- protocol validation
- threshold operation behavior

Hosts own:

- profile import/export
- onboarding UX
- backup/recovery UX
- storage management
- prompts, permissions, and operator workflows

Hosts should not reconstruct signer truth from heuristics when the runtime already owns that state.

## End-to-End System View

The whole architecture can be summarized like this:

```text
                 +-----------------------------+
                 |         Keyset              |
                 |   group pk + threshold      |
                 +-------------+---------------+
                               |
                     split into member shares
                               |
         +---------------------+---------------------+
         |                     |                     |
         v                     v                     v
   +-----------+         +-----------+         +-----------+
   | Device A  |         | Device B  |         | Device C  |
   | profile   |         | profile   |         | profile   |
   | runtime   |         | runtime   |         | runtime   |
   +-----+-----+         +-----+-----+         +-----+-----+
         \                     |                     /
          \                    |                    /
           \                   |                   /
            +------------------------------------+
            |          Nostr Relay Layer         |
            |   encrypted p2p protocol traffic   |
            |   encrypted profile backup events  |
            +----------------+-------------------+
                             |
                   host surfaces and operators
                             |
       +---------------------+----------------------+
       |                                            |
       v                                            v
  igloo-shell                                  igloo-chrome
  native/operator host                         browser/provider host
```

## Architectural Invariants

These rules should hold across FROSTR:

- a keyset is shared across multiple devices through per-device shares
- no single device should hold the full signing secret in normal threshold operation
- the runtime peer protocol operates over encrypted relay traffic
- device routing uses share public keys, not `profile_id`
- onboarding, backup/recovery, rotation, and keyset replacement are distinct lifecycle paths
- the durable local device profile is the reconstruction point for runtime state
- hosts own UX and storage integration, while the runtime owns signer truth and protocol behavior
