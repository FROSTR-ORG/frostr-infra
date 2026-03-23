# FROSTR Peer Protocol

## Summary

This document is the living spec for the peer-to-peer protocol between FROSTR devices.

It focuses on:

- the device-to-device model
- peer identities and recipient routing
- the request/response operation model
- the core peer operations:
  - `ping`
  - `onboard`
  - `sign`
  - `ecdh`

Use this document for protocol semantics between devices.

Use these companion docs for adjacent domains:

- [WIRE.md](./WIRE.md): wire format and Nostr/NIP-44 transport details
- [ONBOARD.md](./ONBOARD.md): onboarding bootstrap flow and `bfonboard`
- [PROFILE.md](./PROFILE.md): durable device/profile identity and state
- [BACKUP.md](./BACKUP.md): `bfprofile`, `bfshare`, encrypted backups, and recovery

## Model

FROSTR is a threshold signing system with one group public key and multiple share-holding devices.

At the peer-protocol level:

- no single device holds the full signing secret
- each device holds one share secret and one corresponding share public key
- devices communicate over relays using encrypted peer messages
- one device may initiate an operation, but multiple peers may participate in completing it

The peer protocol is the runtime coordination layer between devices after a device already exists and can communicate over relays.

## Peer Identities

At the peer-protocol level, devices care about these identities:

- share public key
  - the device/member identity used for peer routing and peer policy
- group public key
  - the threshold keyset identity

`profile_id` is a host/profile concept, not a peer-routing identity.

Peers route messages to each other using the recipient device identity, not `profile_id`.

## Transport Assumptions

The peer protocol assumes:

- relays are transport only
- relay metadata is not trusted as protocol payload
- protocol content is carried inside encrypted peer envelopes
- devices validate recipient routing, freshness, replay constraints, and operation-specific invariants before accepting a message

The low-level transport and envelope format live in [WIRE.md](./WIRE.md).

## Operation Model

The peer protocol uses an encrypted request/response model.

Conceptually:

1. an initiating device decides to start an operation
2. it selects one or more peer recipients
3. it sends encrypted request message(s)
4. recipient peers validate and process the request
5. recipients send encrypted response message(s)
6. the initiator validates responses and either completes the operation or fails it

Each round is scoped by a request identifier. Responses are matched to the initiating round, not treated as free-floating peer messages.

## Core Peer Operations

The current peer protocol has four core operations.

### `ping`

`ping` is the peer reachability and policy-observation operation.

It is used to:

- confirm that a peer is reachable through the current relay path
- fetch the peer's reported policy profile
- refresh remote observed peer-permission state

`ping` is part of normal runtime coordination and peer discovery.

### `onboard`

`onboard` is the peer operation used during the onboarding bootstrap handshake.

It is used only after a recipient has imported a `bfonboard` package and dialed the provisioning signer.

At the peer-protocol layer, `onboard` carries:

- the onboarding request
- bootstrap nonce material
- the onboarding response
- the returned group/bootstrap material needed to construct the new local device

The host/bootstrap side of onboarding is documented in [ONBOARD.md](./ONBOARD.md). This protocol document only covers the device-to-device exchange itself.

### `sign`

`sign` is the threshold signing operation.

It is used when an initiating device wants peers to participate in a signing round.

Conceptually:

1. the initiator selects a peer set that is currently sign-capable
2. it sends signing requests to those peers
3. peers validate the request and return partial-signature material
4. the initiator validates the locked peer responses
5. if the round succeeds, the initiator aggregates the final signature

If a required locked peer fails to provide a valid response, the round fails and must be restarted as a new request.

### `ecdh`

`ecdh` is the threshold ECDH/shared-secret operation.

It follows the same general request/response pattern as signing:

1. the initiator selects an ECDH-capable peer set
2. it sends encrypted ECDH requests
3. peers validate and return ECDH response material
4. the initiator validates the locked peer responses
5. the initiator combines the resulting shared-secret material

## Peer Selection and Policy

The peer protocol does not treat all peers as always eligible.

At operation start, the initiating device must consider:

- local manual peer-permission overrides
- remote observed peer policy
- operation capability and readiness

Current high-level rule:

- outbound `sign` and `ecdh` require both local allow and remote observed allow
- `ping` and `onboard` are not suppressed by remote observed policy

The full permission model lives in ADR-009 and the related living specs. This protocol doc records only the operational effect on peer-to-peer message eligibility.

## Onboarding in the Peer Protocol

Onboarding has two layers:

- host/bootstrap layer
  - import `bfonboard`
  - decrypt bootstrap credential
  - prepare local bootstrap context
- peer-protocol layer
  - send onboarding request event
  - exchange bootstrap nonce material
  - receive returned group/bootstrap material

At the protocol level, requester identity is inferred from the signed event pubkey, not from a separate free-form identity field.

After the onboarding exchange succeeds, the recipient host materializes:

- a full local `bfprofile`
- a local `bfshare`
- an encrypted profile backup

## Failure Model

A peer operation may fail because:

- the recipient routing is invalid
- the message is stale or replayed
- the peer is not reachable
- the peer denies the operation by local policy
- the peer returns invalid operation material
- a required locked peer does not respond in time

The initiator must treat missing or invalid required responses as round failure, not as partial success.

## Protocol Invariants

These rules should hold across the device-to-device protocol:

- devices communicate through encrypted request/response messages over relays
- relay metadata is not the protocol payload
- recipient routing is enforced per message
- peer identity for routing is the share public key, not `profile_id`
- `ping`, `onboard`, `sign`, and `ecdh` are the core peer operations
- `sign` and `ecdh` rounds fail if required locked-peer responses are missing or invalid
- onboarding at the peer-protocol layer is only one part of the larger host bootstrap flow
