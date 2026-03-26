import { expect } from '@playwright/test';

import { createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { test } from '../fixtures/extension';

test.describe('extension bfprofile import', () => {
  test('imports a bfprofile package into the logged-out workspace and reaches the dashboard', async ({
    clearExtensionStorage,
    openExtensionPage,
  }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'Chrome Import',
        labelPrefix: 'Chrome Imported Device',
        relays: [relay.url],
      });

      await clearExtensionStorage();
      const page = await openExtensionPage('options.html');
      await expect(page.getByRole('heading', { name: 'Load bfprofile' })).toBeVisible();
      await page.evaluate(
        async ({ packageText, password }) => {
          const response = (await chrome.runtime.sendMessage({
            type: 'ext.importBfprofile',
            packageText,
            password,
          })) as { ok?: boolean; error?: string } | undefined;
          if (!response?.ok) {
            throw new Error(response?.error || 'Extension bfprofile import failed');
          }
        },
        {
          packageText: generated.shares[0].bfprofile,
          password: 'playwright-passphrase',
        },
      );

      await expect(page.getByRole('tab', { name: /Signer/i }).first()).toBeVisible();
      await expect(page.getByText('Chrome Import', { exact: true })).toBeVisible();
      await page.close();
    } finally {
      await relay.close();
    }
  });
});
