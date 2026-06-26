import { expect, test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
  createRotatedBrowserArtifacts,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { pages } from '../support/pages';
import { buildPwaPersistedState, pwaPartitionKey } from '../support/state';
import {
  connectPwaRotationPackage,
  confirmPwaRotationPackage,
  expectPwaDashboard,
  importPwaProfile,
  loadStoredPwaProfile,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

test.describe('igloo-pwa rotate key @live', () => {
  test('replaces the active device with a rotated bfonboard package', async ({ browser, page }) => {
    test.slow();
    const relay = await startLocalRelay();
    let inviterContext;
    try {
      const current = await createGeneratedBrowserArtifacts({
        groupName: 'Rotation Update',
        labelPrefix: 'Rotation Device',
        relays: [relay.url],
      });
      const rotated = await createRotatedBrowserArtifacts({
        current,
        sourceMemberIndices: [1, 2],
        groupName: 'Rotation Update',
        labelPrefix: 'Rotated Device',
        relays: [relay.url],
      });
      const rotationPackage = await createOnboardingPackage({
        shareSecret: rotated.shares[0].shareSecret,
        relays: [relay.url],
        peerPubkey: rotated.shares[1].sharePublicKey,
        password: 'rotate-package-pass',
      });
      const inviterSeed = createPwaStoredProfileSeed({
        artifact: rotated.shares[1],
        groupPackageJson: rotated.groupPackageJson,
        label: 'Rotation Inviter',
      });

      const inviter = await openFreshPwaPage(browser);
      inviterContext = inviter.context;
      await seedPwaState(inviter.page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(inviter.page, 'Rotation Inviter');
      await expectPwaDashboard(inviter.page, 'Rotation Inviter');

      await importPwaProfile(page, current.shares[0].bfprofile, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Rotation Device 1');

      await connectPwaRotationPackage(page, {
        packageText: rotationPackage,
        packagePassword: 'rotate-package-pass',
      });
      await expect(page.getByText('Replacement Preview')).toBeVisible({ timeout: 20_000 });
      await confirmPwaRotationPackage(page);
      await expectPwaDashboard(page, 'Rotation Device 1');
      await expect(page.getByText('Share Public Key')).toHaveCount(0);
      await pages(page).dashboard.expectNoShareKeyCopy();
      await expect
        .poll(
          async () =>
            await page.evaluate((partitionKey) => {
              const raw = window.localStorage.getItem(partitionKey);
              if (!raw) return null;
              const state = JSON.parse(raw) as {
                selectedProfileId?: string;
                profiles?: Array<{ id?: string; share_public_key?: string }>;
              };
              return state.profiles?.find((profile) => profile.id === state.selectedProfileId)?.share_public_key ?? null;
            }, pwaPartitionKey()),
          { timeout: 10_000 },
        )
        .toBe(rotated.shares[0].sharePublicKey);
      // The stored share-key swap proves the rotation persisted without showing
      // the local share public key on the dashboard.
    } finally {
      await inviterContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
