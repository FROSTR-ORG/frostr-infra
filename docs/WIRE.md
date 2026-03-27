# FROSTR Wire Format

## Summary

This document is the living spec for the wire format used by the FROSTR peer protocol.

It focuses on:

- Nostr relay transport
- NIP-44 encrypted event content
- recipient routing using `p` tags
- the encrypted peer envelope shape
- payload variants and validation boundaries

Use this document for wire-level transport and envelope structure.

Use these companion docs for adjacent domains:

- [INTERFACES.md](./INTERFACES.md): boundary map for runtime, protocol, and wire interfaces
- [PROTOCOL.md](./PROTOCOL.md): peer-protocol semantics between devices
- [ONBOARD.md](./ONBOARD.md): onboarding/bootstrap flow
- [GLOSSARY.md](./GLOSSARY.md): canonical terminology for relay, envelope, routing, and identity terms

## Transport Layer

FROSTR peer messages are carried over Nostr relay events.

The wire layer assumes:

- relays transport events but do not interpret protocol content
- protocol payloads are stored only inside encrypted event content
- recipient routing is expressed in relay tags, but the protocol body remains inside the encrypted envelope

## Event Model

At the relay layer, a peer message is a Nostr event with:

- an author pubkey
- a `kind` used for FROSTR peer traffic
- event tags
- encrypted `content`

The encrypted `content` is a NIP-44 payload carrying the peer envelope JSON.

No protocol structure should be inferred from relay metadata alone beyond recipient routing and subscription filtering.

## Recipient Routing

Every peer-protocol event must include exactly one lowercase `p` tag.

Rules:

- the `p` value must be the recipient device identity key
- the recipient identity is the share public key encoded as lowercase hex
- events with zero `p` tags are invalid and must be dropped
- events with multiple `p` tags are invalid and must be dropped
- events whose single `p` tag does not match a local device recipient are ignored

This is the canonical relay-level recipient-routing rule.

## Encrypted Content

The event `content` carries a NIP-44 encrypted blob.

After decryption, the content is a peer envelope JSON object.

Conceptually, the wire structure is:

```text
nostr event
  -> content = NIP-44 encrypted JSON
    -> plaintext = BridgeEnvelope JSON
      -> payload = protocol message
```

## Peer Envelope

The current conceptual peer envelope shape is:

```json
{
  "request_id": "6d12e4af53c84965a91b1130b0a940cf",
  "sent_at": 1700000000,
  "payload": {
    "type": "...",
    "data": {}
  }
}
```

Envelope fields:

- `request_id`
  - identifies one operation round
  - opaque to peers except for request/response correlation
- `sent_at`
  - sender timestamp
  - used for freshness validation
- `payload`
  - the operation-specific message body

## Payload Variants

Current payload variants are:

- `PingRequest`
- `PingResponse`
- `SignRequest`
- `SignResponse`
- `EcdhRequest`
- `EcdhResponse`
- `OnboardRequest`
- `OnboardResponse`
- `Error`

The semantic meaning of those operations lives in [PROTOCOL.md](./PROTOCOL.md).

This document only defines their wire-level role as payload variants inside the encrypted envelope.

## Validation Boundaries

Wire validation happens in layers.

### Relay/Event Layer

At the event layer, implementations must validate:

- event kind is appropriate for FROSTR peer traffic
- exactly one recipient `p` tag is present
- the `p` tag targets a local recipient

### Encryption Layer

At the encrypted content layer, implementations must validate:

- NIP-44 decryption succeeds
- decrypted content is valid JSON

### Envelope Layer

At the peer-envelope layer, implementations must validate:

- `request_id` is present, non-empty, and bounded
- `sent_at` is present and acceptable for freshness checks
- `payload` exists and has a recognized variant

### Payload Layer

At the payload layer, implementations must validate:

- payload-specific structure
- payload-specific bounds
- operation-specific invariants

## Freshness and Replay

The wire layer is not just a serializer. Devices must also enforce:

- freshness checks using `sent_at`
- replay protections
- recipient validation before handing content to operation handlers

These protections are mandatory before a peer message is accepted as a valid protocol operation.

## Request/Response Correlation

The wire format supports a request/response model.

Rules:

- one initiating request starts an operation round
- responses refer back to that round by `request_id`
- devices must not treat unrelated envelopes as interchangeable just because they share a payload variant

`request_id` is therefore the round-correlation token at the wire level.

## Relationship to Higher Layers

This document does not define:

- how hosts store device profiles
- how onboarding packages are imported
- how backups are published or recovered
- how a host decides which peers to select

Those responsibilities live in other docs:

- [PROFILE.md](./PROFILE.md)
- [BACKUP.md](./BACKUP.md)
- [ONBOARD.md](./ONBOARD.md)
- [PROTOCOL.md](./PROTOCOL.md)

## Wire Invariants

These rules should hold across the wire layer:

- peer traffic is carried over Nostr relay events
- event `content` is NIP-44 encrypted
- decrypted content is a peer envelope JSON object
- every valid peer event has exactly one lowercase recipient `p` tag
- routing identity is the recipient share public key
- `request_id` is the wire-level round correlation token
- payload structure is interpreted only after decryption and envelope validation
