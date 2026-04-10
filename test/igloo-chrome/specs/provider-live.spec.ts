import { test, expect } from '../fixtures/extension';
import {
  assertNoncePoolHydrated,
  type RuntimeSnapshotResult
} from '../support/runtime';

test.describe('provider bridge live signer @live', () => {
  test.setTimeout(180_000);

  test('manual onboard requests resolve by sender share public key', async ({
    liveSigner
  }) => {
    const firstCount = await liveSigner.requestOnboardNonceCount();

    expect(firstCount).toBeGreaterThan(0);
    const secondCount = await liveSigner.requestOnboardNonceCount();
    expect(secondCount).toBeGreaterThan(0);
  });

  test('runtime snapshot reports nonce pool state once peers are hydrated', async ({
    activateProfile,
    fetchRuntimeSnapshot,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);

    await expect
      .poll(async () => {
        const snapshot = await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
        try {
          assertNoncePoolHydrated('provider-live runtime snapshot', snapshot, 2, 1);
          return true;
        } catch {
          return false;
        }
      })
      .toBe(true);

    const snapshot = await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
    expect(['ready', 'degraded']).toContain(snapshot.runtime);
    expect(snapshot.snapshotError).toBeNull();
    expect(snapshot.snapshot?.state?.nonce_pool?.peers).toEqual(
      expect.arrayContaining([expect.objectContaining({ pubkey: stableLiveSigner.profile.peerPubkey })])
    );
  });
});
