# igloo-shared C5 Secret Discipline Design

_Status: Approach approved 2026-06-27 - pending implementation plan._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` C5._
_Builds on: `dev/docs/2026-06-26-c5-snapshot-seckey-wipe-plan.md`._

> **For agentic workers:** this is a small feature design. Keep the
> implementation centered on `repos/igloo-shared`; do not change serialized JSON
> package or snapshot shapes, and do not widen into Chrome message types or PWA
> session-controller follow-ups.

## Problem

C5 tracks a half-applied `Secret<T>` discipline in `igloo-shared`. The previous
light pass closed the highest-value snapshot-restore byte-copy issue:
`sharePubkeyFromSeckeyHex()` now derives the local share public key through
`SecretBytes` and wipes the transient byte form immediately after use.

The remaining beta-relevant gap is type discipline at in-process boundaries:
rotation, recovery, profile bootstrap, profile reconstruction, and key-derived
helpers still accept or return share secrets as ordinary `string` values even
when they are not crossing JSON, WASM, or storage boundaries. That makes
accidental propagation, stringification, or logging harder to review because no
explicit `.expose()` call marks the unavoidable raw-string boundary.

There is also a policy decision embedded in the snapshot path:
`RuntimeSnapshotWire.bootstrap.share.seckey` is serialized JSON. A runtime
`Secret<T>` wrapper cannot survive that wire shape without breaking consumers or
silently serializing to `"<redacted>"`, which would make restore impossible.

## Goal

Close C5 for the public beta by making secret exposure explicit at the shared
runtime boundaries that can use `Secret<T>`, while ratifying the existing bare
serialized-wire policy for runtime snapshots and bootstrap/package JSON.

## Chosen Approach

Keep serialized wire and storage payloads as plain JSON, but tighten
`igloo-shared` in-process APIs around `ShareSecretHex` and `Secret<string>`.

The boundary rule is:

- JSON/WASM/storage wire types remain plain data: runtime snapshots,
  bootstrap wires, stored `share_package_json`, and package payload JSON keep
  `seckey` / `shareSecret` as `string`.
- Shared runtime helpers that receive share secrets before writing those wire
  shapes should accept `ShareSecretHex` where practical.
- Shared runtime helpers that return secret-bearing values for UI display or
  later package generation should return `ShareSecretHex` / `Secret<string>` so
  every raw-string use requires `.expose()`.
- `.expose()` is allowed only at unavoidable cryptographic, JSON serialization,
  NIP-19 encoding, profile-id derivation, and UI reveal boundaries.

This preserves behavior and wire compatibility while making secret movement
reviewable in TypeScript.

## Alternatives Rejected

**Wrap `seckey` inside wire types.** Rejected because runtime snapshots and
bootstrap packages are JSON/WASM boundary objects. `Secret<T>.toJSON()` redacts
by design, so putting wrappers into those shapes would either break restore or
force unsafe serialization escape hatches.

**Docs-only closeout.** Rejected because comments already explain the snapshot
policy, but rotation and recovery still expose share secrets through normal
in-process signatures. The code should require explicit exposure at those
sites.

**Broad workspace sweep.** Rejected for this beta unit. Chrome message types,
PWA session-controller bare strings, and full frontend transient-secret helpers
remain valuable backlog work, but this C5 closeout should stay scoped to the
shared runtime surfaces listed by the beta release plan.

## Scope

In scope:

1. Ratify the snapshot-wire policy in docs and, if useful, a focused test that
   demonstrates wrappers redact under JSON serialization.
2. Update `repos/igloo-shared/src/rotation.ts` so rotation and recovery accept
   wrapped share secrets and return wrapped secret-bearing outputs.
3. Update shared key/profile helper functions that directly consume share
   secrets to accept `ShareSecretHex` where doing so does not change wire
   shapes.
4. Thread `.expose()` through affected `igloo-shared` tests and unavoidable
   serialization/crypto call sites.
5. Update browser-profile runtime/session helpers where they reconstruct
   payloads from runtime snapshots or stored package JSON.
6. Preserve existing JSON shapes and public behavior.

Out of scope:

- Changing `RuntimeSnapshotWire`, `RuntimeBootstrapWire`, profile package JSON,
  or stored `share_package_json` shapes to carry wrappers.
- Developer-facing UI redesign.
- Chrome host message-type cleanup.
- PWA session-controller transient-secret refactors.
- Additional C4 adversarial decrypt tests.

## Mechanism

Start from `repos/igloo-shared/src/secret.ts`, which already defines:

- `Secret<T extends string>`;
- `ShareSecretHex = Secret<string>`;
- redacting `toJSON()` / `toString()`;
- `SecretBytes` for wipeable byte-array copies.

The implementation should adjust the shared surfaces in small test-backed
steps:

1. Add or extend tests that fail until rotation/recovery APIs use wrapped
   secrets and preserve redaction.
2. Update `buildDistinctShareWires()` and its callers in `rotation.ts` so input
   shares are `ShareSecretHex[]` and wire serialization calls `.expose()` in one
   obvious place.
3. Return wrapped values from `BrowserRotationDraft.shares[].shareSecret` and
   `BrowserRecoveredKey.signingKeyHex` / recovered `nsec` if the display layer
   still needs to carry them.
4. Update helper functions such as `publicKeyFromSecret()`,
   `deriveProfileIdFromShareSecret()`, `sharePackageToWireValue()`, and local
   profile reconstruction paths only where the type change stays inside
   `igloo-shared` or has a narrow consumer update.
5. Leave snapshot restore as the explicit exception: the parsed snapshot has a
   bare string, and `sharePubkeyFromSeckeyHex()` is the approved read boundary.

If a candidate type change forces a large PWA/Home UI cascade, stop and keep
that edge at the wire boundary for this beta unit; record the residual work in
`dev/BACKLOG.md` instead of widening the implementation.

## Verification

Use the smallest checks that prove the changed shared surface:

- `npm --prefix repos/igloo-shared run test:unit -- src/secret.test.ts`
- `npm --prefix repos/igloo-shared run test:unit -- src/rotation.test.ts`
- targeted browser-profile tests touched by the implementation;
- `npm --prefix repos/igloo-shared run test:unit`;
- `npm --prefix test run test:guards:docs` after parent doc updates.

If consumer type changes are required, add the corresponding focused client
unit test before running the broader gate for that client.

## Done When

- The snapshot-wire `seckey` policy is documented as the intentional exception,
  not an unresolved design question.
- C5's `igloo-shared` rotation/recovery shared-runtime surfaces require
  explicit `Secret<T>.expose()` at raw-string boundaries.
- Existing package/snapshot JSON compatibility is preserved.
- Focused tests and docs guards pass.
- The public beta release plan no longer lists C5 as open; any Chrome/PWA
  controller leftovers are tracked as deferred backlog work.

## Self-Review

Placeholder scan: no TBD/TODO placeholders.

Internal consistency: the design keeps JSON wire shapes bare and applies
wrappers only to in-process shared-runtime boundaries.

Scope check: this is one small feature centered on `igloo-shared`; cross-client
or Chrome/PWA controller cleanup is explicitly deferred.

Ambiguity check: `.expose()` is allowed only at named boundary categories, and
snapshot restore is the documented exception.
