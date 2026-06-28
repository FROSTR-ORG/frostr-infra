# igloo-shared C4 Adversarial NIP-44 Design

_Status: Implemented 2026-06-28._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` C4._

> **For agentic workers:** this is a small feature design. Keep the first C4
> implementation centered on `repos/igloo-shared`; do not widen into
> `igloo-home`, `igloo-pwa`, live relays, or real-WASM package tests in this
> slice.

## Problem

C4 is marked partial because the runtime already has NIP-44 error handling, but
test coverage is thin at the app-facing decrypt/encrypt boundary. Existing
`igloo-shared` tests cover lower-level bridge command failure draining and
positive NIP-44 interop, yet `BrowserBridgeNode.nip44Encrypt()` and
`BrowserBridgeNode.nip44Decrypt()` do not have direct adversarial coverage for
bad inputs, ECDH orchestration failures, or malformed ciphertext reaching the
public wrapper boundary.

That leaves a beta verification gap: a later refactor could accidentally move
validation after an ECDH command, swallow a drained ECDH failure, leak pending
bridge-command state, or bypass ciphertext normalization without a focused
shared test failing.

## Goal

Close the `igloo-shared` portion of C4 by adding focused adversarial tests for
the app-facing NIP-44 wrapper methods, without changing production behavior
unless those tests expose a real defect.

## Chosen Approach

Add direct unit tests in `repos/igloo-shared/src/wasm-bridge-node.test.ts` that
exercise `BrowserBridgeNode.nip44Encrypt()` and `BrowserBridgeNode.nip44Decrypt()`
through the same internal runtime injection pattern already used by the bridge
failure tests.

The tests should prove:

- non-string plaintext/ciphertext rejects before any ECDH command is issued;
- drained ECDH failures propagate through `nip44Encrypt()` and `nip44Decrypt()`;
- pending ECDH command state is cleared after those failures;
- malformed ciphertext is rejected cleanly at the decrypt boundary.

The slice is intentionally test-first and production-code-light. If all desired
behavior already exists, the implementation is the tests plus release-plan
bookkeeping.

## Alternatives Rejected

**Onboarding relay simulation in `igloo-shared`.** Rejected for this first C4
slice because onboarding has existing decrypt-attempt cap and validation tests,
while a relay simulation would add fixture weight before proving the thinner
public wrapper boundary.

**Full cross-client C4 sweep now.** Rejected because `igloo-home` handler tests
and real-WASM `igloo-pwa` wrong-password/corrupted-package tests are separate
failure surfaces. They should remain independent follow-up slices after the
shared wrapper boundary is locked.

**Production refactor before tests.** Rejected because the release plan says
error handling already exists. The highest-signal action is to write the missing
adversarial tests and let them determine whether code changes are required.

## Scope

In scope:

1. Add focused adversarial tests to `repos/igloo-shared/src/wasm-bridge-node.test.ts`.
2. Reuse existing fake-runtime/internal-injection patterns from the same suite.
3. Preserve current public behavior and NIP-44 wire compatibility.
4. Update C4 release-plan/backlog wording to show the shared slice is complete
   while home/pwa tails remain deferred.

Out of scope:

- `igloo-home` TS-side unlock/rotate/recover handler tests.
- `igloo-pwa` real-WASM wrong-password/corrupted-package tests.
- Relay-backed onboarding simulations.
- Signed or unsigned release artifact work.

## Mechanism

Use a small helper in the test file to create a `BrowserBridgeNode` with:

- runtime readiness reporting `ecdh_ready: true` and `restore_complete: true`;
- fake bridge drains for either one ECDH failure or one ECDH completion;
- an observable `handle_command` spy so validation-before-command assertions are
  explicit.

The malformed-ciphertext test should provide a valid-looking ECDH completion so
the wrapper reaches `normalizeNip44PayloadForJs()` and `nip44.v2.decrypt()`, then
asserts the invalid base64 payload rejects without orphaning bridge state.

## Verification

Use focused checks first, then the shared unit suite and docs guard:

- `npm --prefix repos/igloo-shared run test:unit -- src/wasm-bridge-node.test.ts`
- `npm --prefix repos/igloo-shared run test:unit`
- `npm --prefix test run test:guards:docs`

## Done When

- The shared NIP-44 wrapper boundary has adversarial coverage for validation,
  ECDH failure propagation, pending-state cleanup, and malformed ciphertext.
- No production behavior changes are made unless required by a failing test.
- C4 release-plan/backlog wording distinguishes the completed `igloo-shared`
  slice from deferred `igloo-home` and `igloo-pwa` tails.

## Self-Review

Placeholder scan: no TBD/TODO placeholders.

Internal consistency: the design stays scoped to `igloo-shared` and treats
home/pwa as later slices.

Scope check: this is one small test-depth feature, not a cross-client C4 closeout.

Ambiguity check: production code changes are conditional on red-first test
evidence.
