# igloo-shared C4 Adversarial NIP-44 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Add adversarial coverage for `igloo-shared` app-facing NIP-44 wrapper
methods without changing runtime behavior unless tests expose a defect.

**Architecture:** Extend the existing `wasm-bridge-node.test.ts` fake-runtime
pattern. Test public `nip44Encrypt()` / `nip44Decrypt()` methods against
validation-before-command, drained ECDH failure propagation, pending-state
cleanup, and malformed ciphertext rejection.

**Tech Stack:** TypeScript, Vitest, `BrowserBridgeNode`, fake WASM bridge runtime,
parent release-plan docs.

---

## Global Constraints

- MIT; no new dependencies.
- Commit inside `repos/igloo-shared` first if the submodule changes, then commit
  parent docs/pointer updates.
- Keep this slice test-only unless a red-first test exposes a production defect.
- Do not widen into `igloo-home`, `igloo-pwa`, real-WASM package tests, relay
  simulations, or release-artifact work.
- Preserve current NIP-44 interop behavior and ciphertext normalization policy.

## File Structure

- Modify: `repos/igloo-shared/src/wasm-bridge-node.test.ts`
  - Adds adversarial tests and local fake-runtime helpers.
- Maybe modify: `repos/igloo-shared/src/wasm-bridge-node.ts`
  - Only if the red-first tests expose a missing behavior.
- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
  - Notes that the `igloo-shared` C4 slice is covered.
- Modify: `dev/BACKLOG.md`
  - Narrows remaining C4 backlog to home/pwa tails if the shared slice lands.
- Modify: `dev/plans/igloo-shared-c4-adversarial-nip44-2026-06-28-design.md`
  - Marks the design implemented after verification.

---

## Task 1: Add Red-First Shared NIP-44 Wrapper Tests

**Files:**

- Modify: `repos/igloo-shared/src/wasm-bridge-node.test.ts`

- [x] **Step 1: Add failing tests**

Add a new `describe('NIP-44 adversarial wrapper coverage (C4)', ...)` block that
constructs `BrowserBridgeNode` internals with a fake ready runtime. Include tests
for:

- `nip44Encrypt()` rejects non-string plaintext before calling `handle_command`;
- `nip44Decrypt()` rejects non-string ciphertext before calling `handle_command`;
- `nip44Encrypt()` propagates a drained ECDH failure and clears ECDH pending
  command state;
- `nip44Decrypt()` propagates a drained ECDH failure and clears ECDH pending
  command state;
- `nip44Decrypt()` rejects malformed ciphertext after a successful ECDH
  completion and leaves no pending ECDH state.

- [x] **Step 2: Verify the focused tests fail for the intended reason**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/wasm-bridge-node.test.ts
```

Result: the focused run failed on an over-specific malformed-ciphertext
assertion. The existing production behavior threw the expected typed
`Nip44NormalizeError`; the test was corrected to match that contract.

---

## Task 2: Apply Minimal Production Fix If Needed

**Files:**

- Maybe modify: `repos/igloo-shared/src/wasm-bridge-node.ts`

- [x] **Step 1: Implement only the behavior required by red tests**

If a test fails, make the smallest change that preserves the current method
contract:

- validation must happen before `prepareEcdh()` / `runBridgeCommand()`;
- ECDH failures must propagate;
- pending command state must clear after failures or malformed decrypt payloads;
- ciphertext normalization must remain in the decrypt path.

Result: no production change was required.

- [x] **Step 2: Re-run the focused test**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/wasm-bridge-node.test.ts
```

Expected: PASS.

Result: PASS, 17 tests.

---

## Task 3: Update C4 Tracking Docs

**Files:**

- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
- Modify: `dev/BACKLOG.md`
- Modify: `dev/plans/igloo-shared-c4-adversarial-nip44-2026-06-28-design.md`

- [x] **Step 1: Update release-plan C4 wording**

Mark the `igloo-shared` NIP-44 wrapper adversarial tests as covered, while
leaving `igloo-home` handler tests and `igloo-pwa` real-WASM package tests as
deferred backlog tails.

- [x] **Step 2: Narrow the backlog C4 item**

Remove `igloo-shared` from the remaining C4 backlog item and keep the home/pwa
tail explicit.

- [x] **Step 3: Mark the design implemented**

Change the design status line to implemented with the completion date.

---

## Task 4: Verification and Commit

**Files:**

- Verify touched submodule and parent docs.

- [x] **Step 1: Run focused shared test**

```bash
npm --prefix repos/igloo-shared run test:unit -- src/wasm-bridge-node.test.ts
```

Result: PASS, 1 file / 17 tests.

- [x] **Step 2: Run shared unit suite**

```bash
npm --prefix repos/igloo-shared run test:unit
```

Result: PASS, 30 files / 177 tests.

- [x] **Step 3: Run docs guard**

```bash
npm --prefix test run test:guards:docs
```

Result: PASS.

- [x] **Step 4: Commit**

Commit `repos/igloo-shared` first if changed, then commit parent pointer/docs.

## Self-Review

Spec coverage: all design requirements map to Tasks 1-4.

Placeholder scan: no TBD/TODO placeholders.

Type/name consistency: task names and file paths match the current tree.
