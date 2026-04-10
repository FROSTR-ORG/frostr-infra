import { expect } from '@playwright/test';
import { COMMAND_TYPE } from '../../../repos/igloo-chrome/src/extension/messages';

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
        groupName: 'Chrome Recovery',
        labelPrefix: 'Chrome Recovered Device',
        relays: [relay.url],
      });
      await publishBackupForProfile(generated.shares[0].profilePayload);

      await clearExtensionStorage();
      const page = await openExtensionPage('options.html');
      await expect(page.getByRole('heading', { name: 'Recover bfshare' })).toBeVisible();
      await page.evaluate(
        async ({ recoverType, packageText, password }) => {
          const response = (await chrome.runtime.sendMessage({
            type: recoverType,
            packageText,
            password,
          })) as { ok?: boolean; error?: string } | undefined;
          if (!response?.ok) {
            throw new Error(response?.error || 'Extension bfshare recovery failed');
          }
        },
        {
          recoverType: COMMAND_TYPE.PROFILES_RECOVER,
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
