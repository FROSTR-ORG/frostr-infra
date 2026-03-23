import { expect, test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
  createRotatedBrowserArtifacts,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { buildPwaPersistedState } from '../support/state';
import {
  expectPwaDashboard,
  importPwaProfile,
  loadStoredPwaProfile,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

function shortId(value: string) {
  return value.slice(0, 8);
}

test.describe('igloo-pwa rotate key', () => {
  test('replaces the active device with a rotated bfonboard package', async ({ browser, page }) => {
    const relay = await startLocalRelay();
    let inviterContext;
    try {
      const current = await createGeneratedBrowserArtifacts({
        keysetName: 'Rotation Update',
        labelPrefix: 'Rotation Device',
        relays: [relay.url],
      });
      const rotated = await createRotatedBrowserArtifacts({
        current,
        sourceMemberIndices: [1, 2],
        keysetName: 'Rotation Update',
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

      await page.getByRole('tab', { name: /Settings\s+operator controls/i }).click();
      await page.getByRole('button', { name: 'Rotate Key' }).click();
      await page.getByPlaceholder('Paste bfonboard1...').fill(rotationPackage);
      await page.getByLabel('Package Password').fill('rotate-package-pass');
      await page.getByRole('button', { name: 'Connect Rotation Package' }).click();
      await expect(page.getByText('Replacement Preview')).toBeVisible({ timeout: 20_000 });
      await page.getByRole('button', { name: 'Replace Active Device' }).click();
      await expectPwaDashboard(page, 'Rotation Device 1');
      await expect(page.getByText(shortId(rotated.shares[0].profileId))).toBeVisible();
      await expect(page.getByText(shortId(current.shares[0].profileId))).toHaveCount(0);
    } finally {
      await inviterContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
