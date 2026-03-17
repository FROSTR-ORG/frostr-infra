# FROSTR Protocol Overview

This is the living protocol spec for the current workspace.

Architectural history remains in `docs/adrs/`. Current onboarding, runtime-status, and peer-to-peer behavior live here.

## Model

- A FROSTR group has one group public key and multiple member shares.
- No single device holds the full signing secret.
- Peers communicate over Nostr relays using encrypted bridge envelopes.

## Transport

- Relay events carry encrypted protocol content.
- Recipient routing is enforced through a single local-recipient `p` tag.
- Signer runtimes validate routing, replay, TTL, and locked-peer response constraints before accepting protocol messages.

## Onboarding

The current onboarding model is hard-cut:

1. Provisioning combines a recipient share, relay list, callback peer pubkey, and password to produce an encrypted `bfonboard` package.
2. A recipient imports the package and password.
3. The recipient calls out to the inviter peer over relays using a signed onboarding request event.
4. The onboarding request carries bootstrap nonces for the new device; requester identity is inferred from the signed event pubkey.
5. The inviter stores those incoming nonces, returns the group package, and includes its own bootstrap nonces in the onboarding response.
6. The recipient initializes signer/runtime state directly from the onboarding response.

Important properties:

- `bfonboard` is encrypted and password-protected.
- The onboarding package is an import artifact, not long-term runtime state.
- Runtime snapshots and signer metadata replace the onboarding package after successful bootstrap.

## Sign Flow

1. The caller requests a sign operation.
2. The signer selects a threshold-valid peer set that is currently sign-capable.
3. The signer emits encrypted request events.
4. Peers respond with encrypted partial-signature material.
5. The initiating signer validates locked-peer responses and aggregates the final signature.

## ECDH Flow

1. The caller requests an ECDH operation.
2. The signer prepares an ECDH-capable peer set.
3. Peers exchange encrypted protocol messages over relays.
4. The initiating signer combines the resulting shared secret material.

## Hosted Runtime Model

- Hosted clients should use signer-owned readiness and status APIs instead of reconstructing readiness from transport events or nonce snapshots.
- `runtime_status()` is the canonical current-state surface.
- `drain_runtime_events()` is an incremental update surface.
- `prepare_sign()` and `prepare_ecdh()` are the operation-prep surfaces for hosted clients.
