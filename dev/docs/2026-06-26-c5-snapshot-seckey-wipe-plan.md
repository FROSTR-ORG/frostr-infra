# C5 — Snapshot seckey wipe (light Secret-discipline pass) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** When restoring a runtime snapshot, derive the local share public key from the persisted `seckey` through a `SecretBytes` wrapper that is `wipe()`d immediately after use, so the secret *bytes* do not linger; and document why the snapshot-wire `seckey` field remains a bare string by policy.

**Architecture:** Extract a small WASM-free helper `sharePubkeyFromSeckeyHex` into `runtime-internal.ts` (where `normalizePubkey32Hex` already lives and `getPublicKey` from nostr-tools is available), wrapping the hex→bytes→pubkey derivation in `SecretBytes` + `wipe()`. Wire it into the snapshot-restore consumer. This is the high-value/low-cost half of finding C5.

**Tech Stack:** TypeScript, Vitest, `igloo-shared` only (single submodule).

## Global Constraints

- MIT; no new deps. Commit inside `igloo-shared` on `dev`; stage only changed files (never `git add -A`); no push. No formatter churn.
- **Scope is the snapshot wipe ONLY.** The recovered-key `Secret<string>` wrapping (6-file pwa ripple) and the rotation-draft `shareSecret` wrapping are explicitly **deferred** to a post-beta "Secret-discipline completion" fast-follow (tracked in `dev/BACKLOG.md` with the C4 test-depth tail). Do NOT touch `rotation.ts` return types, `profile-generate.ts`, `store-recover.ts`, `App.tsx`, or `recover.tsx`.
- **Behavior must be preserved:** the derived `localSharePubkey32` must be byte-identical to today's `normalizePubkey32Hex(getPublicKey(hexToBytes(seckey)), 'share public key')`.

## File Structure

- `repos/igloo-shared/src/runtime-internal.ts` — **add** the `sharePubkeyFromSeckeyHex` helper (it already exports `normalizePubkey32Hex`).
- `repos/igloo-shared/src/runtime-internal.test.ts` — **add/extend** a unit test for the helper.
- `repos/igloo-shared/src/wasm-bridge-node.ts:1019-1023` — **modify** the snapshot consumer to call the helper.
- `repos/igloo-shared/src/wire/runtime.ts:~240` — **add** a rationale comment on the `seckey` field.

---

### Task 1: SecretBytes-wiped share-pubkey helper + snapshot wiring

**Files:**
- Modify: `repos/igloo-shared/src/runtime-internal.ts`
- Test: `repos/igloo-shared/src/runtime-internal.test.ts`
- Modify: `repos/igloo-shared/src/wasm-bridge-node.ts:1019-1023`
- Modify: `repos/igloo-shared/src/wire/runtime.ts:~240`

**Interfaces:**
- Produces: `sharePubkeyFromSeckeyHex(seckeyHex: string): string` — returns the normalized 32-byte (x-only, lowercase) share public key; wipes the transient secret bytes.

- [ ] **Step 1: Write the failing test**

Add to `repos/igloo-shared/src/runtime-internal.test.ts` (create the file if absent; match the existing vitest import style used elsewhere in `src/*.test.ts`):

```ts
import { describe, expect, it } from 'vitest';
import { getPublicKey } from 'nostr-tools';
import { sharePubkeyFromSeckeyHex, normalizePubkey32Hex, hexToBytes } from './runtime-internal';

describe('sharePubkeyFromSeckeyHex', () => {
  it('derives the same normalized share pubkey as the direct path', () => {
    const seckeyHex = '11'.repeat(32);
    const expected = normalizePubkey32Hex(getPublicKey(hexToBytes(seckeyHex)), 'share public key');
    expect(sharePubkeyFromSeckeyHex(seckeyHex)).toBe(expected);
  });

  it('rejects an invalid seckey hex', () => {
    expect(() => sharePubkeyFromSeckeyHex('zz')).toThrow();
  });
});
```

(If `hexToBytes` is not exported from `runtime-internal`, compute `expected` with whatever byte helper the module already exports — confirm the exact export names before writing.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm --prefix repos/igloo-shared run test:unit -- src/runtime-internal.test.ts`
Expected: FAIL — `sharePubkeyFromSeckeyHex` is not exported.

- [ ] **Step 3: Implement the helper**

In `repos/igloo-shared/src/runtime-internal.ts`, add `getPublicKey` (from `nostr-tools`) and `SecretBytes` (from `./secret`) to the imports, then add:

```ts
/**
 * Derive the normalized share public key from a share seckey hex, wiping the
 * transient secret bytes immediately after the pubkey is computed.
 *
 * The seckey arrives as a bare string on the snapshot wire by policy (see
 * `wire/runtime.ts` — a serialized wire cannot carry a runtime `Secret`
 * wrapper, and the observability schema already forbids logging it). A JS
 * string cannot be zeroized, but the `Uint8Array` form can: this keeps the
 * byte copy from lingering until GC.
 */
export function sharePubkeyFromSeckeyHex(seckeyHex: string): string {
  const bytes = SecretBytes.fromHex(seckeyHex);
  try {
    return normalizePubkey32Hex(getPublicKey(bytes.expose()), 'share public key');
  } finally {
    bytes.wipe();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npm --prefix repos/igloo-shared run test:unit -- src/runtime-internal.test.ts`
Expected: PASS (both cases).

- [ ] **Step 5: Wire it into the snapshot consumer**

In `repos/igloo-shared/src/wasm-bridge-node.ts`, add `sharePubkeyFromSeckeyHex` to the existing `from './runtime-internal'` import, then replace the snapshot-restore derivation (lines ~1020-1023):

```ts
      this.localSharePubkey32 = normalizePubkey32Hex(
        getPublicKey(hexToBytes(snapshot.bootstrap.share.seckey)),
        'share public key'
      );
```

with:

```ts
      this.localSharePubkey32 = sharePubkeyFromSeckeyHex(snapshot.bootstrap.share.seckey);
```

(Leave the onboarding-path derivation at ~line 943 unchanged — out of scope.)

- [ ] **Step 6: Add the wire rationale comment**

In `repos/igloo-shared/src/wire/runtime.ts`, immediately above the `seckey` field (~line 240), add:

```ts
    // Bare string by policy: a serialized wire cannot carry a runtime `Secret`
    // wrapper. It is never logged (forbidden by the observability schema), and
    // the consumer derives its pubkey via `sharePubkeyFromSeckeyHex`, which
    // wipes the transient byte form on read.
```

- [ ] **Step 7: Typecheck + full unit run**

Run: `npm --prefix repos/igloo-shared run test:unit`
Expected: PASS (full suite), no type errors. (No existing test covers `tryRestoreRuntime`; behavior preservation is enforced by Step 1's equality assertion + typecheck.)

- [ ] **Step 8: Commit (inside the submodule)**

```bash
git -C repos/igloo-shared add src/runtime-internal.ts src/runtime-internal.test.ts src/wasm-bridge-node.ts src/wire/runtime.ts
git -C repos/igloo-shared commit -m "Wipe transient snapshot seckey bytes on restore (C5 light pass)"
```

---

### Task 2: Bump pointer + verify

- [ ] **Step 1: Bump the pointer**

```bash
make bump-pointers MSG="Bump igloo-shared: wipe snapshot seckey bytes on restore (C5)"
```

- [ ] **Step 2: Gate**

Run: `make verify`
Expected: green (exit 0); `.tmp/agent/verify.json` `ok:true`.

---

## Deferred (record in `dev/BACKLOG.md` as one fast-follow)

**Secret-discipline completion (post-beta):** wrap `recoverSecretKeyFromShares`'s `BrowserRecoveredKey` and `buildRotationDraft`'s `shares[].shareSecret` in `Secret<string>`, threading `.expose()` through the pwa recovery flow (`profile-generate.ts` → `store-recover.ts` → `App.tsx:132` → `recover.tsx:62,69,75`) and the rotation distribution path. Log-safety only; verified mostly by typecheck. Bundle with the **C4 test-depth tail** (NIP-44 orchestration failure tests in `igloo-shared`, TS-side handler tests in `igloo-home`, real-WASM adversarial test in `igloo-pwa`).

## Self-Review

**Spec coverage:** the snapshot wipe (helper + wiring + wire comment) is Task 1; the pointer/gate is Task 2; the deferred remainder is explicitly recorded. **Placeholder scan:** Step 1 flags the one thing to confirm (the `hexToBytes` export name in `runtime-internal`). **Type consistency:** `sharePubkeyFromSeckeyHex(seckeyHex: string): string` is defined and consumed with that exact signature. **Risk:** low — behavior-preserving; the equality assertion in Step 1 guards the derivation, and `SecretBytes.wipe()` is already covered by `secret.test.ts`.
