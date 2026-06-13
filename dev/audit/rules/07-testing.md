# Testing

Judges whether the tests prove the code does what it must — especially the core
user journeys and the adversarial paths a signing system lives or dies by. Happy
paths that pass tell you little; the gaps are where this domain looks.

The core journeys to hold to account (per `NOTES.md`): **create, unlock, rotate,
import, onboard, replace.** The target is full coverage of these across
`igloo-pwa`, `igloo-chrome`, and `igloo-home`.

## What good looks like

- Every core journey is covered end-to-end at the lowest useful layer.
- Adversarial inputs are tested, not just the golden path.
- Crypto has known-answer and property tests, not only round-trips.
- Tests live in the right repo for the behavior they verify.

## Rules

### TST-01 — Core journey not covered
- **Severity:** High
- **Look for:** which of create / unlock / rotate / import / onboard / replace have an end-to-end test in each host; gaps in the cross-repo Playwright suite.
- **Fails when:** a core journey has no end-to-end coverage in a host that supports it.
- **Passes when:** each supported journey is exercised end-to-end at the lowest useful layer.
- **Prompt:** "If this journey broke for a user tomorrow, which test goes red?"

### TST-02 — Happy-path-only coverage
- **Severity:** High
- **Look for:** tests that only assert success; no cases for wrong passphrase, corrupted ciphertext, partial-write recovery, hostile envelopes, stale completions.
- **Fails when:** the failure and attack paths of a security-relevant flow are untested.
- **Passes when:** adversarial and error paths are tested alongside the golden one.
- **Prompt:** "What does this code do when the input is wrong or hostile — and is that asserted?"

### TST-03 — Missing KAT / property tests at the crypto layer
- **Severity:** High
- **Look for:** crypto crates with no known-answer vectors or property tests; round-trip-only coverage; crates with no integration tests at all.
- **Fails when:** cryptographic behavior rests on round-trips without KATs or invariants.
- **Passes when:** crypto has known-answer vectors and property tests for its invariants (nonce single-use, constant-time, etc.).
- **Prompt:** "Would this catch a subtly wrong-but-self-consistent crypto change?"

### TST-04 — Test in the wrong layer / repo
- **Severity:** Medium
- **Look for:** cross-repo browser tests living inside submodules; behavior tested through a heavy E2E that a unit test would pin better; per `../../policies/testing-guidance.md`.
- **Fails when:** a test sits at the wrong layer for what it verifies, making it slow or fragile.
- **Passes when:** behavior is tested at the lowest useful layer; cross-repo tests live in top-level `test/`.
- **Prompt:** "Is this verified at the cheapest layer that actually proves it?"

### TST-05 — Mock drift from real shapes
- **Severity:** Medium
- **Look for:** large hand-maintained mocks/normalizers that re-declare runtime shape and can mask drift; a green render-only lane standing in for behavior (`make test-fast` is render-only).
- **Fails when:** tests pass against a mock that no longer matches the real contract.
- **Passes when:** mocks derive from or are checked against the real shape; behavioral coverage exists beyond render.
- **Prompt:** "Could this test stay green while the real thing it mocks is broken?"

### TST-06 — Brittle or shallow assertions
- **Severity:** Low
- **Look for:** tests asserting incidental detail (exact log strings), or asserting almost nothing; flaky timing-dependent tests.
- **Fails when:** a test breaks on harmless change or passes regardless of correctness.
- **Passes when:** assertions target behavior that matters and are stable.
- **Prompt:** "Does this test fail for the right reasons — and only those?"

## Review prompts

- For each core journey, name the test that protects it.
- Where is the golden path covered but the hostile path empty?
- Which green checks could hide a broken behavior?
