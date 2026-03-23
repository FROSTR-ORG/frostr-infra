import { expect, test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
  publishBackupForProfile,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { buildPwaPersistedState } from '../support/state';
import { expectPwaDashboard, onboardPwaDevice, openFreshPwaPage, seedPwaState } from '../support/ui';

test.describe('igloo-pwa rotation operator flow', () => {
  test('rotates from threshold bfshare sources and distributes a rotated share via bfonboard', async ({ browser, page }) => {
    const relay = await startLocalRelay();
    let secondaryContext;
    try {
      const source = await createGeneratedBrowserArtifacts({
        keysetName: 'Source Treasury',
        labelPrefix: 'Source Device',
        relays: [relay.url],
      });
      const sourceSeed = createPwaStoredProfileSeed({
        artifact: source.shares[0],
        groupPackageJson: source.groupPackageJson,
        label: 'Source Device 1',
      });
      await publishBackupForProfile(source.shares[0].profilePayload);
      await publishBackupForProfile(source.shares[1].profilePayload);

      await seedPwaState(page, buildPwaPersistedState({ profiles: [sourceSeed] }));
      await page.goto('/');
      await page.getByRole('button', { name: 'Start' }).click();
      await page.getByRole('button', { name: 'Rotate Existing Keyset' }).click();
      await page.getByLabel('Keyset Name').fill('Rotated Treasury');
      await page.getByLabel('Source Profile').selectOption(sourceSeed.id);
      await page.getByPlaceholder('Paste bfshare1...').first().fill(source.shares[0].bfshare);
      await page.getByLabel('Package Password').first().fill('playwright-passphrase');
      await page.getByRole('button', { name: 'Add bfshare' }).click();
      await page.getByPlaceholder('Paste bfshare1...').nth(1).fill(source.shares[1].bfshare);
      await page.getByLabel('Package Password').nth(1).fill('playwright-passphrase');
      await page.getByRole('button', { name: 'Rotate Keyset' }).click();

      await expect(page.getByText('Select the Device Share')).toBeVisible();
      await page.getByRole('button', { name: /Rotated Treasury Device 1/i }).click();
      await page.getByLabel('Device Profile Name').fill('Rotated Treasury Device');
      await page.getByLabel('Relays').fill(relay.url);
      await page.getByLabel('Device Password').fill('playwright-passphrase');
      await page.getByLabel('Confirm Password').fill('playwright-passphrase');
      await page.getByRole('button', { name: 'Continue to Review' }).click();
      await page.getByRole('button', { name: 'Accept and Continue' }).click();

      await expect(page.getByRole('heading', { name: 'Distribute the Keyset', exact: true })).toBeVisible();
      const distributeCard = page.locator('.igloo-generated-card').filter({ hasText: /Member 2/ }).first();
      await distributeCard.getByLabel('Share Name').fill('Rotated Remote Device');
      await distributeCard.getByLabel('Password', { exact: true }).fill('rotate-remote-pass');
      await distributeCard.getByLabel('Confirm Password').fill('rotate-remote-pass');
      await distributeCard.getByRole('button', { name: 'QR' }).click();
      const onboardPackage = (await page.locator('pre.igloo-code-block').textContent())?.trim();
      expect(onboardPackage?.startsWith('bfonboard1')).toBe(true);
      await page.keyboard.press('Escape');
      await page.getByRole('button', { name: 'Finish' }).click();
      await expectPwaDashboard(page, 'Rotated Treasury Device');

      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage: onboardPackage ?? '',
        packagePassword: 'rotate-remote-pass',
        label: 'Rotated Remote Device',
        localPassword: 'playwright-passphrase',
      });
      await expectPwaDashboard(secondary.page, 'Rotated Remote Device');
    } finally {
      await secondaryContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
