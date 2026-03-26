import { expect } from '@playwright/test';

import { createGeneratedBrowserArtifacts, publishBackupForProfile } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { test } from '../fixtures/extension';

test.describe('extension bfshare recovery', () => {
  test('recovers a stored profile from bfshare and relay backup', async ({
    clearExtensionStorage,
    openExtensionPage,
  }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'Chrome Recovery',
        labelPrefix: 'Chrome Recovered Device',
        relays: [relay.url],
      });
      await publishBackupForProfile(generated.shares[0].profilePayload);

      await clearExtensionStorage();
      const page = await openExtensionPage('options.html');
      await expect(page.getByRole('heading', { name: 'Recover bfshare' })).toBeVisible();
      await page.evaluate(
        async ({ packageText, password }) => {
          const response = (await chrome.runtime.sendMessage({
            type: 'ext.recoverBfshare',
            packageText,
            password,
          })) as { ok?: boolean; error?: string } | undefined;
          if (!response?.ok) {
            throw new Error(response?.error || 'Extension bfshare recovery failed');
          }
        },
        {
          packageText: generated.shares[0].bfshare,
          password: 'playwright-passphrase',
        },
      );

      await expect(page.getByRole('tab', { name: /Signer/i }).first()).toBeVisible();
      await expect(page.getByText('Chrome Recovery', { exact: true })).toBeVisible();
      await page.close();
    } finally {
      await relay.close();
    }
  });
});
