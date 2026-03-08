# Plan D: Invite Package Hardening (`bfonboard`)

Date: 2026-03-07
Status: Proposed
Scope: `frostr-utils`, `bifrost-codec`, `bifrost-signer`, `bifrost-app`, `bifrost-devtools`, docs

## Goals

1. Make invite creation a first-class workflow instead of ad hoc file/script glue.
2. Decouple inviter-owned invite creation from recipient share custody.
3. Preserve the existing over-the-wire onboarding flow once a recipient has imported an invite.
4. Make invite transport encrypted by default under the existing `bfonboard` prefix.
5. Bind onboarding to an invite-scoped challenge so invites are single-purpose and replay-resistant.
6. Make password protection mandatory for newly created and consumed invites, while allowing either user-supplied or generated passwords.

## Non-Goals

1. Redesigning the `onboard` RPC handshake itself.
2. Sending raw invite payloads over relays.
3. Redesigning the `onboard` RPC handshake beyond adding invite challenge binding.
4. Changing recipient share custody rules.
5. Changing threshold-signing, nonce, or transport semantics outside invite handling.

## Problem Statement

Today:

1. `bfonboard` is a minimal transport package containing:
   - recipient share (`idx`, `seckey`)
   - callback peer public key
   - relay list
2. Invite creation is not exposed as a first-class node/devtools command.
3. The package is plaintext, which is not sufficient for a share-bearing invite artifact.
4. The onboarding flow does not have an invite-specific challenge binding.

This leads to three gaps:

1. Operators do not have a canonical invite creation API.
2. Invite creation is currently coupled to possession of recipient share data.
3. Secret-share transport is not encrypted by default.
4. Imported invites are not strongly bound to a one-time onboarding intent.

## Design Summary

Introduce a first-class invite model with two stages:

1. inviter-owned `invite token`
   - created by the inviting node without recipient share data
   - contains callback peer public key, relays, challenge, and expiry metadata
   - stored by the inviter as pending invite state
2. recipient/share-owned `bfonboard`
   - encrypted invite envelope
   - assembled by combining an invite token with a recipient share package
   - password required
   - password may be user-supplied or generated

The final encrypted `bfonboard` package carries enough information for the recipient to:

1. import the invite locally,
2. learn which relays to use,
3. learn which peer public key to contact first,
4. call out to the inviting node using the existing onboarding flow.

The over-the-wire `onboard` exchange remains the same in shape except for one addition:

1. `OnboardRequest` gains an invite challenge field.
2. The inviting node validates that challenge against locally stored pending invites.

## High-Level Workflow

### Invite Token Creation

1. Inviting node creates an invite token using:
   - callback peer pubkey, defaulting to the inviter node's own pubkey
   - relay list
   - challenge
   - expiry metadata
   - optional label
2. Inviter stores pending invite metadata locally for later challenge validation.
3. Inviter returns the invite token to the operator or provisioning tool.

### Invite Package Assembly

1. A trusted provisioning tool or workflow combines:
   - invite token
   - recipient share package
   - password path
2. Password path must be one of:
   - user-supplied password
   - generated random password
3. Enforce minimum password length of 8 characters.
4. Tool encrypts the assembled invite payload and encodes it as `bfonboard...`
5. Password is delivered to the recipient out of band.

### Invite Consumption

1. Recipient imports `bfonboard...`.
2. Recipient supplies the password and decrypts the payload.
3. Recipient persists imported invite data locally:
   - share
   - callback peer pubkey
   - relays
   - challenge
   - expiry metadata
4. Recipient starts the existing onboarding flow over relays.
5. `OnboardRequest` includes the imported challenge.

### Invite Validation During Onboarding

1. Inviting node receives `OnboardRequest`.
2. Node validates:
   - challenge exists
   - challenge is still pending
   - challenge has not expired
   - request metadata is consistent with any stored invite-token bindings
3. If valid:
   - continue existing onboarding response path
   - mark invite challenge consumed
4. If invalid:
   - reject onboarding request

## Wire Formats

### Invite Token

Invite tokens are inviter-generated artifacts that do not contain recipient share data.

Recommended token contents:

1. `version`
2. `callback_peer_pk`
3. `relays`
4. `challenge`
5. `created_at`
6. `expires_at`
7. optional `label`

Recommended representation:

1. opaque encoded token string or compact JSON payload
2. no secret-share material
3. safe to hand to a provisioning system that later combines it with a share

### Encrypted Invite: `bfonboard`

Redefine `bfonboard` as a versioned encrypted invite envelope.

Recommended envelope fields:

1. `version`
2. `kdf`
   - `argon2id`
   - parameters: memory, iterations, parallelism
3. `salt`
4. `nonce`
5. `ciphertext`
6. optional `hint`

Recommended crypto:

1. KDF: Argon2id
2. AEAD: XChaCha20-Poly1305

Password policy:

1. Minimum length: 8 characters
2. `invite assemble` may accept an operator-provided password
3. `invite assemble` may generate a random password when requested
4. generated passwords should be emitted once and never persisted in cleartext by the node

Rationale:

1. Keep a single user-facing invite prefix.
2. Make encryption mandatory for all supported invite packages.
3. Future-proof format upgrades via explicit envelope versioning.
4. Preserve relay onboarding behavior by encrypting the invite payload, not the network handshake.

Encrypted payload contents:

1. recipient share
2. callback peer public key
3. relay list
4. challenge
5. `created_at`
6. `expires_at`
7. optional `label`
8. optional token identifier for diagnostics/correlation

## Challenge Model

Each invite should include a randomly generated challenge.

Challenge requirements:

1. At least 128 bits of entropy.
2. Single-use.
3. Bound to one invite token and one inviter peer.
4. Subject to expiration.

Pending invite record should contain:

1. `challenge`
2. `callback_peer_pubkey`
3. `relays`
4. `created_at`
5. `expires_at`
6. `consumed_at`
7. optional operator label/note
8. optional token identifier

Important constraint:

1. The inviter does not need recipient share identity at token-creation time.
2. For invite-driven onboarding, validation can bind to challenge/token metadata plus the expected FROST group public key.
3. Fully bootstrapped inviter nodes already maintain the group's peer public key set, so they can recognize which peer public key is being onboarded when the invite is consumed.

Validation rules:

1. Unknown challenge: reject
2. Expired challenge: reject
3. Consumed challenge: reject
4. Group public key mismatch: reject
5. If the onboarding payload resolves to a peer public key outside the known group peer set: reject
6. Valid challenge: allow exactly once

## API and CLI Surface

### `frostr-utils`

Add:

1. `InviteToken`
2. `OnboardingPackageV2`
3. encrypted `bfonboard` envelope type
4. `assemble_onboarding_package(...)`
5. `encode_onboarding_package(...)`
6. `decode_onboarding_package(...)`
7. password-based encrypt/decrypt helpers

Retire:

1. plaintext `bfonboard` generation for supported flows

### `bifrost-app`

Add a first-class `invite` command group:

1. `bifrost --config ... invite create [--relay URL ...]`
2. `bifrost --config ... invite show-pending`
3. `bifrost --config ... invite revoke <challenge>`

Add invite assembly/import commands in either `bifrost-app`, `bifrost-devtools`, or both:

1. `... invite assemble --token TOKEN --share FILE (--password-env VAR | --password-file FILE | --generate-password)`
2. `... invite accept <package> (--password-env VAR | --password-file FILE | --password-stdin)`

Behavior:

1. `invite create`
   - defaults callback peer pubkey to the local node's own public key
   - emits share-free invite token
   - stores pending invite metadata
2. `invite assemble`
   - combines invite token with recipient share material
   - emits encrypted `bfonboard...`
   - rejects passwords shorter than 8 characters
   - may generate a random password and print it for out-of-band delivery
3. `invite accept`
   - imports encrypted invite
   - rejects passwords shorter than 8 characters before decrypt attempt when length is known
   - does not itself complete onboarding
   - prepares local state so existing onboarding can run

### `bifrost-devtools`

Optional convenience additions:

1. `bifrost-devtools invite ...`
2. helper flows for demo/devnet generation

This is convenience-only. Canonical invite semantics should live in shared/app layers, not only in devtools.

## Runtime Changes

### `bifrost-signer`

Add invite state management:

1. pending invite registry
2. challenge validation and consume-on-success behavior
3. invite expiration checks
4. peer-public-key recognition against bootstrapped signer state

Add onboarding validation hook:

1. `OnboardRequest` processing must validate invite challenge when present or required

Open decision:

1. Whether challenge validation should become mandatory for all onboarding requests, or
2. Whether legacy challenge-less onboarding remains supported behind an explicit compatibility mode

Recommended direction:

1. accept legacy requests only during a narrow migration window
2. require challenge-bearing onboarding for all invite-driven flows

### `bifrost-codec`

Add or extend wire types:

1. `OnboardRequestWire` gains `challenge`
2. parsing/encoding remains canonical here

Requirements:

1. strict bounds checks on challenge length and format
2. explicit version handling for new invite package types
3. no duplicate shape validation outside codec

## Storage Model

Add persisted invite metadata distinct from signer state snapshots where possible.

Desired properties:

1. challenge consumption must be durable
2. operator-created invites must survive restart
3. invite expiration cleanup should be deterministic
4. replay after restart must still fail

Suggested shape:

1. `pending_invites`
   - map by challenge ID
   - includes consumed/expired status

Security note:

1. imported invites still contain a secret share after decryption and must be treated as sensitive local material
2. encrypted invite envelopes must never store cleartext password material

## Security Properties

### Desired Improvements

1. Mandatory encrypted invite export for out-of-band transport.
2. Replay resistance through one-time challenges.
3. Explicit expiration of stale invites.
4. Cleaner separation between inviter-owned metadata and share-bearing invite assembly.
5. Stronger binding between invite creation and onboarding acceptance.

### Risks

1. Password UX may encourage weak secrets when operator-chosen passwords are allowed.
2. Generated passwords need clear one-time display semantics.
3. Password handling in automation and E2E requires careful out-of-band injection.
4. Persisted pending-invite metadata becomes security-sensitive state.
5. Legacy compatibility paths can weaken enforcement if left indefinite.

### Security Decisions

1. `bfonboard` remains the canonical invite prefix.
2. Encryption wraps the invite payload, not the relay onboarding semantics.
3. Invite challenges must be random, opaque, and one-time-use.
4. Password-less invite creation is not supported in the target design.
5. Passwords shorter than 8 characters are invalid.
6. Inviter-owned invite token creation must not require recipient share custody.
7. Fully bootstrapped inviters may validate onboarding against both the group public key and the known peer public key set.

## Backward Compatibility

Preserve:

1. existing onboarding flow after invite import

Add:

1. inviter-generated invite tokens
2. encrypted `bfonboard` import/export
3. challenge-aware onboarding requests

Compatibility strategy:

1. Decide whether old plaintext `bfonboard` payloads are unsupported immediately or only accepted by a one-time migration/import path.
2. Generate inviter-owned invite tokens plus encrypted `bfonboard` packages once V2 lands.
3. Gate hard enforcement of challenge-bearing onboarding behind a migration switch if needed.

## Testing Plan

### Unit Tests

1. encrypted `bfonboard` encode/decode roundtrips
2. wrong-password rejection
3. short-password rejection on create/accept
4. generated-password flow coverage
5. malformed envelope rejection
6. invite-token encode/decode roundtrips
7. challenge uniqueness and format bounds

### Integration Tests

1. `invite create` -> `invite assemble` -> `invite accept` -> successful onboarding
2. invite challenge replay rejection
3. expired invite rejection
4. revoked invite rejection
5. encrypted invite flow works end-to-end
6. E2E harness can inject password out of band for automation
7. generated-password invite flow works end-to-end
8. inviter token creation works without share material present

### Adversarial Tests

1. tampered ciphertext rejection
2. tampered or forged invite-token rejection
3. mismatched group public key rejection
4. unknown peer public key rejection on fully bootstrapped inviters
5. duplicate onboarding response/request ordering does not consume invite twice

## Documentation Changes Required

1. `docs/API.md`
2. `docs/GUIDE.md`
3. `docs/CONFIGURATION.md`
4. `docs/frostr-utils/onboarding.md`
5. `README.md`
6. `TESTING.md`
7. E2E automation docs for password injection
8. invite token assembly/operator docs

## Open Questions

1. Should `invite assemble` live in `bifrost-app`, `bifrost-devtools`, or both?
2. Should imported invites be stored separately from normal runtime state?
3. Should challenge validation become mandatory immediately, or only for newly created invites?
4. Should encrypted invites allow metadata-in-clear (for UX hints), or should all metadata be encrypted?
5. Should invite expiration be enforced only by the inviter, or by both inviter and recipient?
6. What is the canonical non-interactive password input mechanism for CI/E2E (`env`, `fd`, `stdin`, or file`)?
7. What is the generated password format: human-friendly words, base64url, or raw alphanumeric?

## Recommended Execution Order

1. Define `InviteToken` plus versioned invite types in `frostr-utils`.
2. Add encrypted `bfonboard` envelope and password-based crypto helpers.
3. Add package assembly helpers (`token + share -> bfonboard`).
4. Extend codec/onboard request with `challenge`.
5. Add pending invite registry + challenge validation in signer/runtime.
6. Add `invite create` / `invite assemble` / `invite accept` CLI surfaces.
7. Update docs and add end-to-end tests.

## Definition of Done

1. Inviting nodes can create invite tokens without recipient share material.
2. Provisioning tools can assemble encrypted `bfonboard` packages from `invite token + share`.
3. Recipients can import encrypted invites and complete existing onboarding over relays.
4. Invite challenge replay is rejected deterministically.
5. Wrong-password and malformed-envelope cases fail closed.
6. Passwords shorter than 8 characters are rejected.
7. Documentation and tests reflect the new invite model.
