# igloo-shared C5 Secret Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the public-beta C5 blocker by threading `Secret<T>` through `igloo-shared` rotation/recovery secrets while preserving serialized package/snapshot JSON compatibility.

**Architecture:** Keep JSON/WASM/storage shapes bare, including runtime snapshots and `share_package_json`. Wrap in-process rotation/recovery inputs and outputs with `ShareSecretHex` / `Secret<string>`, then expose only at explicit crypto, JSON serialization, and UI-display boundaries. Apply the narrow PWA ripple where those shared return types are consumed.

**Tech Stack:** TypeScript, Vitest, React/PWA local adapter tests, independent git submodules (`igloo-shared`, `igloo-pwa`) plus parent pointer/docs commit.

---

## Global Constraints

- MIT; no new dependencies.
- Commit inside touched submodules first, then bump parent pointers.
- Do not change serialized JSON shapes:
  - `RuntimeSnapshotWire.bootstrap.share.seckey` remains `string`.
  - `RuntimeBootstrapWire.share.seckey` remains `string`.
  - profile package payloads and stored `share_package_json` remain plain JSON.
- Do not change `sharePackageToWireJson()`, `deriveProfileIdFromShareSecret()`, or `publicKeyFromSecret()` signatures in this beta pass. They are wire/crypto helpers with many bare-string call sites; this plan closes the C5 blocker by hardening rotation/recovery surfaces specifically.
- `.expose()` is acceptable only at:
  - WASM JSON request construction;
  - public-key/profile-id derivation;
  - profile/onboard/share package JSON construction;
  - PWA adapter return boundary where the UI intentionally displays recovered key material.
- Leave Chrome message types, PWA session-controller bare strings, and C4 adversarial decrypt tests as backlog work.

## Grounding

Ground check passed against the approved design:

```bash
/Users/cscott/.agents/skills/feature/scripts/ground-check.sh /Users/cscott/Repos/frostr/frostr-infra dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md
```

Result: `checked=6`, `unresolved_count=0`.

## File Structure

- Modify: `repos/igloo-shared/src/rotation.ts`
  - Owns the C5 in-process rotation/recovery boundary.
- Modify: `repos/igloo-shared/src/rotation.test.ts`
  - Proves rotation/recovery return wrapped secrets and existing validation still works.
- Modify: `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`
  - Wraps decoded share secrets before calling shared rotation/recovery APIs; exposes recovered keys at the adapter-to-UI boundary.
- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
  - Marks C5 fixed for beta once implementation is green.
- Modify: `dev/BACKLOG.md`
  - Removes rotation/recovery from the open `Secret<T>` sweep and leaves the deferred non-beta surfaces.
- Modify: `dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md`
  - Updates status from pending implementation to shipped/implemented.

---

## Task 1: Harden `igloo-shared` Rotation/Recovery Secret Types

**Files:**

- Modify: `repos/igloo-shared/src/rotation.test.ts`
- Modify: `repos/igloo-shared/src/rotation.ts`

- [x] **Step 1: Write the failing shared tests**

Replace `repos/igloo-shared/src/rotation.test.ts` with:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { publicKeyFromSecret } from './browser-profile/core';
import type { BrowserGroupPackage } from './profile-package';
import { Secret } from './secret';
import { buildRotationDraft, recoverSecretKeyFromShares } from './rotation';

const mockKeysetApi = vi.hoisted(() => ({
  rotate_keyset_bundle: vi.fn(),
  recover_secret_key_from_shares: vi.fn(),
}));

vi.mock('./bridge-wasm-runtime', () => ({
  getWasmKeysetApi: vi.fn(async () => mockKeysetApi),
}));

const secretA = '11'.repeat(32);
const secretB = '22'.repeat(32);
const rotatedSecret = '44'.repeat(32);
const recoveredSigningKey = 'aa'.repeat(32);
const groupPublicKey = '99'.repeat(32);
const sourceGroupId = '77'.repeat(32);
const nextGroupId = '88'.repeat(32);

function group(threshold: number, memberSecrets: string[]): BrowserGroupPackage {
  return {
    groupName: 'Group',
    groupPk: groupPublicKey,
    threshold,
    members: memberSecrets.map((secret, index) => ({
      idx: index + 1,
      pubkey: `02${publicKeyFromSecret(secret)}`,
    })),
  };
}

describe('rotation secret discipline', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockKeysetApi.rotate_keyset_bundle.mockReturnValue(
      JSON.stringify({
        previous_group_id: sourceGroupId,
        next_group_id: nextGroupId,
        next: {
          group: {
            group_pk: groupPublicKey,
            threshold: 1,
            members: [{ idx: 1, pubkey: `02${publicKeyFromSecret(rotatedSecret)}` }],
          },
          shares: [{ idx: 1, seckey: rotatedSecret }],
        },
      }),
    );
    mockKeysetApi.recover_secret_key_from_shares.mockReturnValue(recoveredSigningKey);
  });

  it('returns rotated share secrets as redacting Secret wrappers', async () => {
    const draft = await buildRotationDraft({
      groupPackage: group(1, [secretA]),
      shareSecrets: [Secret.of(secretA)],
      threshold: 1,
      count: 1,
      groupName: 'Rotated Group',
    });

    expect(draft.shares[0].shareSecret.expose()).toBe(rotatedSecret);
    expect(JSON.stringify(draft.shares[0].shareSecret)).toBe('"<redacted>"');
    expect(JSON.stringify(draft)).not.toContain(rotatedSecret);
    expect(draft.shares[0].sharePublicKey).toBe(publicKeyFromSecret(rotatedSecret));
  });

  it('returns recovered keys as redacting Secret wrappers', async () => {
    const recovered = await recoverSecretKeyFromShares({
      groupPackage: group(1, [secretA]),
      shareSecrets: [Secret.of(secretA)],
    });

    expect(recovered.signingKeyHex.expose()).toBe(recoveredSigningKey);
    expect(recovered.nsec.expose()).toMatch(/^nsec1/);
    expect(JSON.stringify(recovered)).toBe('{"nsec":"<redacted>","signingKeyHex":"<redacted>"}');
    expect(JSON.stringify(recovered)).not.toContain(recoveredSigningKey);
  });
});

describe('recoverSecretKeyFromShares validation guards', () => {
  it('rejects fewer distinct shares than the threshold', async () => {
    await expect(
      recoverSecretKeyFromShares({
        groupPackage: group(2, [secretA, secretB]),
        shareSecrets: [Secret.of(secretA)],
      }),
    ).rejects.toThrow(/at least 2 shares/i);
  });

  it('rejects a share that does not belong to the keyset', async () => {
    await expect(
      recoverSecretKeyFromShares({
        groupPackage: group(2, [secretA]),
        shareSecrets: [Secret.of(secretB)],
      }),
    ).rejects.toThrow(/does not belong/i);
  });
});
```

- [x] **Step 2: Run the shared test to verify it fails**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/rotation.test.ts
```

Expected: FAIL with TypeScript/runtime errors because `buildRotationDraft()` and `recoverSecretKeyFromShares()` still accept `string[]` and return raw string secrets.

- [x] **Step 3: Implement wrapped rotation/recovery types**

In `repos/igloo-shared/src/rotation.ts`, change the import from `./secret`:

```ts
import { Secret, type ShareSecretHex } from './secret';
```

Change `BrowserRotationDraft.shares[].shareSecret`:

```ts
  shares: Array<{
    memberIndex: number;
    shareSecret: ShareSecretHex;
    sharePublicKey: string;
  }>;
```

Change `buildDistinctShareWires()`:

```ts
function buildDistinctShareWires(groupPackage: BrowserGroupPackage, shareSecrets: ShareSecretHex[]) {
  const byIdx = new Map<number, { idx: number; seckey: string }>();
  for (const secret of shareSecrets) {
    const wire = shareWireFromSecret(groupPackage, secret.expose());
    byIdx.set(wire.idx, wire);
  }
  return [...byIdx.values()];
}
```

Change `buildRotationDraft()` input:

```ts
export async function buildRotationDraft(input: {
  groupPackage: BrowserGroupPackage;
  shareSecrets: ShareSecretHex[];
  threshold: number;
  count: number;
  groupName?: string | null;
}) {
```

Change the returned rotated share mapping:

```ts
    shares: rotated.next.shares.map((share) => {
      const shareSecret = Secret.of(normalizeHex32(share.seckey, 'rotated share secret'));
      return {
        memberIndex: share.idx,
        shareSecret,
        sharePublicKey: publicKeyFromSecret(shareSecret.expose()),
      };
    }),
```

Change `BrowserRecoveredKey`:

```ts
export type BrowserRecoveredKey = {
  nsec: Secret<string>;
  signingKeyHex: Secret<string>;
};
```

Change `recoverSecretKeyFromShares()` input:

```ts
export async function recoverSecretKeyFromShares(input: {
  groupPackage: BrowserGroupPackage;
  shareSecrets: ShareSecretHex[];
}): Promise<BrowserRecoveredKey> {
```

Change the return block in `recoverSecretKeyFromShares()`:

```ts
  const bytes = new Uint8Array(
    (signingKeyHex.match(/.{2}/g) ?? []).map((byte) => Number.parseInt(byte, 16)),
  );
  try {
    return {
      nsec: Secret.of(nip19.nsecEncode(bytes)),
      signingKeyHex: Secret.of(signingKeyHex),
    };
  } finally {
    bytes.fill(0);
  }
```

Change `buildRotationProfilePayload()` to expose at the profile payload JSON boundary:

```ts
  const shareSecret = share.shareSecret.expose();
  return {
    profileId: await deriveProfileIdFromShareSecret(shareSecret),
    version: 1,
    device: {
      name: assignment.label.trim(),
      shareSecret,
      manualPeerPolicyOverrides: [],
      relays,
    },
```

- [x] **Step 4: Run the shared test to verify it passes**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/rotation.test.ts
```

Expected: PASS.

- [x] **Step 5: Run shared secret regression tests**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit -- src/secret.test.ts src/rotation.test.ts
```

Expected: PASS.

- [x] **Step 6: Commit inside `igloo-shared`**

Run:

```bash
git -C repos/igloo-shared add src/rotation.ts src/rotation.test.ts
git -C repos/igloo-shared commit -m "Thread Secret wrappers through rotation recovery"
```

---

## Task 2: Update PWA Adapter Exposure Boundaries

**Files:**

- Modify: `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`

- [x] **Step 1: Run PWA typecheck to confirm the consumer break**

Run:

```bash
npm --prefix test run test:typecheck:pwa
```

Expected: FAIL with errors in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts` where `string[]` is passed to shared rotation/recovery APIs and where `share.shareSecret` is passed to `sharePackageToWireJson()`.

- [x] **Step 2: Update imports in `profile-generate.ts`**

In `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`, add `ShareSecretHex` to the existing `igloo-shared` type imports:

```ts
  sharePackageToWireJson,
  type BrowserOnboardPackagePayload,
  type ShareSecretHex,
} from 'igloo-shared';
```

- [x] **Step 3: Wrap decoded share secrets**

Change `decodeShareSecrets()` from `Promise<string[]>` to `Promise<ShareSecretHex[]>`:

```ts
async function decodeShareSecrets(
  sources: Array<{ packageText: string; password: string }>,
): Promise<ShareSecretHex[]> {
  const filled = sources.filter((source) => source.packageText.trim() && source.password);
  const decoded = await Promise.all(
    filled.map((source) => decodeBfSharePackage(source.packageText.trim(), Secret.of(source.password))),
  );
  return decoded.map((share) => Secret.of(share.shareSecret));
}
```

- [x] **Step 4: Wrap the current device share in rotation**

In `createRotatedKeyset()`, change the device-share local:

```ts
    let deviceShareSecret: ShareSecretHex;
    try {
      const deviceShare = await decodeBfSharePackage(input.encryptedShareArtifact, Secret.of(input.devicePassphrase));
      deviceShareSecret = Secret.of(deviceShare.shareSecret);
    } catch {
      throw new Error('Incorrect device passphrase.');
    }
    shareSecrets.unshift(deviceShareSecret);
```

- [x] **Step 5: Expose rotated share secrets only while writing share-package JSON**

In `createRotatedKeyset()`, change the rotated share mapping:

```ts
  const shares = draft.shares.map((share) => ({
    name: `${draft.groupName} Device ${share.memberIndex}`,
    member_idx: share.memberIndex,
    share_public_key: share.sharePublicKey,
    share_package_json: sharePackageToWireJson(share.memberIndex, share.shareSecret.expose()),
  }));
```

- [x] **Step 6: Wrap the current device share in recovery**

In `recoverNsecFromShares()`, change the device-share local:

```ts
    let deviceShareSecret: ShareSecretHex;
    try {
      const deviceShare = await decodeBfSharePackage(input.encryptedShareArtifact, Secret.of(input.devicePassphrase));
      deviceShareSecret = Secret.of(deviceShare.shareSecret);
    } catch {
      throw new Error('Incorrect device passphrase.');
    }
    shareSecrets.unshift(deviceShareSecret);
```

- [x] **Step 7: Expose recovered key material at the adapter-to-UI boundary**

Change the return at the end of `recoverNsecFromShares()`:

```ts
  const recovered = await recoverSecretKeyFromShares({
    groupPackage,
    shareSecrets,
  });
  return {
    nsec: recovered.nsec.expose(),
    signingKeyHex: recovered.signingKeyHex.expose(),
  };
```

- [x] **Step 8: Run PWA typecheck to verify it passes**

Run:

```bash
npm --prefix test run test:typecheck:pwa
```

Expected: PASS.

- [x] **Step 9: Run focused PWA tests**

Run:

```bash
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
```

Expected: PASS.

- [x] **Step 10: Commit inside `igloo-pwa`**

Run:

```bash
git -C repos/igloo-pwa add src/lib/local-adapter/profile-generate.ts
git -C repos/igloo-pwa commit -m "Expose C5 rotation secrets at adapter boundary"
```

---

## Task 3: Parent Pointer, Docs, and Release-Plan Closeout

**Files:**

- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
- Modify: `dev/BACKLOG.md`
- Modify: `dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md`
- Modify: `dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-implementation.md`
- Modify: submodule pointers for `repos/igloo-shared` and `repos/igloo-pwa`

- [x] **Step 1: Bump submodule pointers**

Run:

```bash
make bump-pointers MSG="Bump shared and PWA C5 secret discipline"
```

Expected: parent commit records the moved `igloo-shared` and `igloo-pwa` pointers, unless later doc edits are intentionally folded into the same parent commit by editing before commit. If `make bump-pointers` commits immediately, use a second parent docs commit in Step 6.

- [x] **Step 2: Update the beta release plan C5 row**

In `dev/docs/2026-06-26-public-beta-release-plan.md`, change the C5 row to:

```md
| **C5** `Secret<T>` discipline | ✅ FIXED | Beta scope closed — snapshot-wire `seckey` remains a documented bare JSON exception; rotation/recovery in `igloo-shared` now use `Secret<T>` wrappers and PWA exposes only at JSON/UI boundaries. Remaining Chrome/PWA controller cleanup is deferred backlog work. |
```

- [x] **Step 3: Update the backlog C5 follow-up**

In `dev/BACKLOG.md`, replace the current C5 sweep item:

```md
- (effort: M) Complete the remaining `Secret<T>`/secret-wrapper sweep — `igloo-shared` + consumers · snapshot `seckey` is now wiped on restore via `sharePubkeyFromSeckeyHex` (2026-06-26, C5 light pass); still open: wrap `recoverSecretKeyFromShares`/`BrowserRecoveredKey` + rotation-draft `shareSecret` (the pwa recovery + rotation `.expose()` threading), Chrome message types, and PWA session-controller bare-string paths.
```

with:

```md
- (effort: M) Complete the remaining post-beta `Secret<T>`/secret-wrapper sweep — C5 beta scope is closed for snapshot restore plus shared rotation/recovery; still open: Chrome message types, PWA session-controller bare-string paths, and any broader frontend transient-secret helper work that is not required for the beta gate.
```

- [x] **Step 4: Update design status**

In `dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md`, change:

```md
_Status: Approach approved 2026-06-27 - pending implementation plan._
```

to:

```md
_Status: Implemented 2026-06-27._
```

- [x] **Step 5: Check off this implementation plan as tasks complete**

In this file, change completed task checkboxes from `- [ ]` to `- [x]` as each task lands. Do not check future tasks early.

- [x] **Step 6: Run docs guard**

Run:

```bash
npm --prefix test run test:guards:docs
```

Expected: PASS.

- [x] **Step 7: Run integration gate for changed surfaces**

Run:

```bash
npm --prefix repos/igloo-shared run test:unit
npm --prefix test run test:typecheck:pwa
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
```

Expected: PASS.

- [x] **Step 8: Commit parent docs if not already included**

If Step 1 already committed only submodule pointers, run:

```bash
git add dev/docs/2026-06-26-public-beta-release-plan.md dev/BACKLOG.md dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-implementation.md
git commit -m "Close C5 secret discipline docs"
```

If Step 1 has not committed yet, stage docs and pointers together:

```bash
git add dev/docs/2026-06-26-public-beta-release-plan.md dev/BACKLOG.md dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-design.md dev/plans/igloo-shared-c5-secret-discipline-2026-06-27-implementation.md repos/igloo-shared repos/igloo-pwa
git commit -m "Close C5 secret discipline beta gate"
```

- [x] **Step 9: Push all touched branches**

Run:

```bash
git -C repos/igloo-shared push origin dev
git -C repos/igloo-pwa push origin dev
git push origin dev
```

Expected: all pushes succeed.

---

## Plan Self-Review

**Spec coverage:** The snapshot-wire policy remains bare and documented by the existing C5 light pass; Task 1 hardens `igloo-shared` rotation/recovery inputs and outputs; Task 2 handles the narrow PWA consumer boundary; Task 3 closes release docs and keeps broader Chrome/PWA controller work in backlog.

**Placeholder scan:** No TBD/TODO placeholders. Deferred work is explicitly named and scoped out.

**Type consistency:** `ShareSecretHex` is used only for share secrets. Recovered `nsec` and signing key hex use `Secret<string>` because they are not share secrets. PWA returns plain strings only after `.expose()` at the adapter-to-UI display boundary.

**Risk:** Moderate but bounded. The main risk is TypeScript ripple from shared return-type changes; Task 2 and the PWA typecheck are the control. Wire compatibility is preserved because package and snapshot JSON shapes stay plain strings.
