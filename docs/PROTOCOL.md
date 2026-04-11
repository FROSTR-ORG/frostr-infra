# FROSTR Peer Protocol

## Summary

This document is the runtime protocol spec for peer-to-peer coordination between FROSTR devices.

It defines:
- actor roles
- request lifecycle
- peer selection and responder validation
- timeout and failure semantics
- the operation contracts for:
  - `ping`
  - `onboard`
  - `sign`
  - `ecdh`

It does not define:
- relay event bytes and envelope encoding
- package formats
- cryptographic math

Those live in:
- [WIRE.md](./WIRE.md)
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md)

## Actors

### Initiator

The device that starts an operation round.

The initiator is responsible for:
- choosing the target peer set
- generating the round request id
- sending request messages
- matching responses back to the round
- deciding terminal success or failure

### Responder

Any peer device that receives an operation request and decides whether to respond.

The responder is responsible for:
- validating recipient routing
- validating freshness and replay constraints
- applying policy and readiness checks
- validating operation-specific inputs before returning a response

### Locked Peer

A selected peer whose valid response is required for the round to succeed.

Locked-peer semantics matter most for:
- `sign`
- `ecdh`

If a locked peer does not return a valid response in time, the round fails.

### Provisioning Responder

The already-running device that answers onboarding requests from a recipient that has imported `bfonboard`.

This role is a specialized responder in the onboarding flow.

## Core Protocol Identities

The peer protocol uses:
- share public key
  - peer-routing identity
- group public key
  - keyset identity
- request id
  - round correlation token

It does not use:
- `profile_id`

`profile_id` is host-local durable identity, not a peer-routing identity.

## Request Lifecycle

Every peer round follows the same high-level lifecycle.

### 1. Round Creation

The initiator:
- decides which operation to run
- selects eligible target peers
- creates a fresh request id
- binds operation-specific context to that request id

### 2. Request Dispatch

The initiator:
- encrypts one or more request messages
- addresses them to specific recipient share public keys
- publishes them over relays

### 3. Responder Validation

Each responder validates, in order:
- recipient routing
- freshness and replay constraints
- local policy eligibility
- local operation readiness
- operation-specific request structure and semantics

If validation fails, the responder either:
- ignores the request, or
- returns an explicit error response when the operation semantics allow it

### 4. Response Matching

The initiator:
- receives encrypted responses
- decrypts and parses them
- matches them to the active round by request id
- rejects unrelated, stale, invalid, or duplicate responses

### 5. Terminal Result

A round terminates in one of two states:
- success
- failure

A failed round is terminal. Retrying the operation creates a new request id and a new round.

## Initiator Responsibilities

The initiator must:
- select peers that are eligible for the operation
- respect local policy and remote observed policy where required
- distinguish locked peers from non-required peers where the operation requires it
- reject missing, malformed, duplicate, stale, or mismatched responses
- fail the round if required locked-peer conditions are not met

For `sign`, the initiator must also ensure:
- all selected signing participants are sign-capable
- the round is bound to valid cryptographic signing context

For `ecdh`, the initiator must ensure:
- all selected participants are ECDH-capable
- the returned contributions are validated before combination

## Responder Responsibilities

Before responding, a responder must validate:

### Routing

- exactly one recipient `p` tag is present at the wire layer
- the recipient matches a local share public key

### Freshness And Replay

- the message is within acceptable freshness bounds
- the request id has not already been consumed in a way that makes the message invalid

### Policy

- the operation is permitted by local policy
- any additional local gating rules for the operation are satisfied

### Readiness

- the responder is ready for the requested operation
- for `sign`, this includes valid available nonce state

### Operation-Specific Semantics

- the request payload is structurally valid
- required operation-specific fields are well-formed
- the request is consistent with the responder’s local keyset and runtime state

## Peer Selection Rules

Peer selection is initiator-owned.

At operation start, the initiator considers:
- local manual peer-permission overrides
- remote observed peer policy
- runtime readiness and capability
- operation-specific locked-peer requirements

High-level rule:
- outbound `sign` and `ecdh` require both local allow and remote observed allow
- `ping` and `onboard` are not suppressed by remote observed policy in the same way

## Nonce Pools In The Protocol

Nonce pools are runtime-owned operational state that affect protocol eligibility for signing.

At the protocol layer:
- a responder without valid nonce state is not sign-ready
- a device must not participate in a signing round if doing so would require nonce reuse
- nonce exhaustion or invalid nonce state is a legitimate round-failure reason

Nonce pools are not portable profile state and are not shared as part of profile import/export or recovery artifacts.

The cryptographic meaning of nonce material lives in [CRYPTOGRAPHY.md](./CRYPTOGRAPHY.md).

## Operation Contracts

### `ping`

Purpose:
- confirm peer reachability
- refresh remote observed policy/profile information
- reconcile per-peer nonce inventory for signing readiness

Preconditions:
- initiator knows the target peer share public key
- target peer is routable over the active relay set

Initiator behavior:
- sends a ping request to one peer
- includes the nonce codes currently held from that peer
- includes any public nonces the peer has not yet reported holding
- treats the round as successful only if a valid ping response is received

Responder validation:
- routing is valid
- request is fresh and not replayed
- local policy allows ping response behavior

Response expectations:
- peer identity matches the addressed peer
- response is correlated to the request id
- response includes the responder's current held nonce-code inventory for the requester
- response may include a public-nonce advertisement batch for the requester to store
- response may include peer-status or policy-observation data

Nonce-sync rules:
- ping is the authoritative nonce inventory reconciliation round
- a device must not infer peer receipt from its own local outgoing nonce pool
- the sender treats the peer's reported held-code inventory as the delivery signal
- when the peer-reported held inventory is below the local nonce minimum threshold, the sender refills its local outgoing pool and advertises only the codes the peer has not reported holding
- duplicate advertisement of the same unspent public nonce is valid and must be treated as idempotent by the receiver
- once a peer reports inventory at or above the local nonce minimum threshold, ping should omit nonce advertisement until the observed inventory drops again

Success criteria:
- initiator receives and validates the response from the targeted peer

Failure criteria:
- peer unreachable
- response missing or stale
- policy deny
- invalid response payload

### `onboard`

Purpose:
- bootstrap a new device that has already imported `bfonboard`

Preconditions:
- recipient has decrypted `bfonboard`
- recipient knows the callback peer public key and relay set
- provisioning responder is reachable

Initiator behavior:
- sends an onboarding request to the provisioning responder
- includes bootstrap nonce material needed by the bootstrap flow

Responder validation:
- routing is valid
- request is fresh and not replayed
- request comes from a valid requester identity
- onboarding-specific bootstrap state is valid and acceptable

Response expectations:
- returns the group/bootstrap material needed by the new device
- includes responder bootstrap nonce material required by the onboarding flow

Success criteria:
- recipient receives a valid onboarding response
- recipient can materialize complete local durable state from the result

Failure criteria:
- package import/decryption was wrong upstream
- provisioning responder unavailable
- onboarding request rejected or times out
- returned bootstrap material is invalid

The host/bootstrap side of onboarding lives in [ONBOARD.md](./ONBOARD.md). This protocol spec covers only the device-to-device exchange.

### `sign`

Purpose:
- complete one threshold signing round

Preconditions:
- initiator has a valid signing context
- selected peers are sign-capable
- required participants have valid nonce state

Initiator behavior:
- selects the signing peer set
- marks required locked peers
- sends signing requests
- validates returned partial-signature material
- aggregates the final signature only after required responses are valid

Responder validation:
- routing is valid
- request is fresh and not replayed
- local policy allows signing
- runtime is sign-ready
- valid signing nonce state is available
- signing request is structurally and cryptographically acceptable

Response expectations:
- one valid response per participating responder
- response is bound to the request id
- response contains the responder’s signing-round contribution

Success criteria:
- all required locked peers return valid responses
- initiator validates and aggregates the result successfully

Failure criteria:
- missing locked-peer response
- invalid locked-peer response
- duplicate or stale response
- nonce-state failure
- explicit deny
- timeout

Retry model:
- a failed signing round must be restarted as a new round with a new request id

### `ecdh`

Purpose:
- complete one threshold shared-secret derivation round

Preconditions:
- initiator has a valid ECDH context
- selected peers are ECDH-capable

Initiator behavior:
- selects the ECDH peer set
- marks required locked peers
- sends ECDH requests
- validates returned ECDH contribution material
- combines the final shared-secret result only after required responses are valid

Responder validation:
- routing is valid
- request is fresh and not replayed
- local policy allows ECDH
- runtime is ECDH-ready
- ECDH request is structurally and cryptographically acceptable

Response expectations:
- one valid response per participating responder
- response is bound to the request id
- response contains the responder’s ECDH-round contribution

Success criteria:
- all required locked peers return valid responses
- initiator validates and combines the final result successfully

Failure criteria:
- missing locked-peer response
- invalid locked-peer response
- duplicate or stale response
- explicit deny
- timeout

Retry model:
- a failed ECDH round must be restarted as a new round with a new request id

## Timeout And Failure Semantics

A round fails if any of the following happens:
- recipient routing is invalid
- the request is stale or replayed
- a responder denies the operation by policy
- a responder is not ready for the operation
- for signing, nonce-state requirements are not satisfied
- a locked peer does not respond in time
- a locked peer returns invalid response material
- the initiator cannot validate the response set

The initiator must treat missing or invalid required responses as terminal failure, not partial success.

## Retry Semantics

There is no implicit resume of a failed round.

A retry means:
- new request id
- new request messages
- fresh round state

For signing, retrying also means the initiator must use fresh valid signing-round state and must not attempt unsafe reuse of prior nonce-bound context.

## Protocol Invariants

These rules should always hold:
- devices communicate through encrypted request/response messages over relays
- relay metadata is not the protocol payload
- share public key is the peer-routing identity
- `profile_id` is not a peer-routing identity
- request id binds one operation round
- responders validate routing, freshness, policy, and readiness before replying
- signing readiness depends on valid nonce-pool state
- `sign` and `ecdh` rounds fail if required locked-peer responses are missing or invalid
- retries are new rounds, not resumptions
