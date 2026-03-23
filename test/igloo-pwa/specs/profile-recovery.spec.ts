import { test } from '@playwright/test';

import { createGeneratedBrowserArtifacts, publishBackupForProfile } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { expectPwaDashboard, recoverPwaProfile } from '../support/ui';

test.describe('igloo-pwa bfshare recovery', () => {
  test('recovers a profile from bfshare and a relay backup', async ({ page }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'PWA Recovery',
        labelPrefix: 'Recovered Browser Device',
        relays: [relay.url],
      });
      await publishBackupForProfile(generated.shares[0].profilePayload);

      await recoverPwaProfile(page, generated.shares[0].bfshare, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Recovered Browser Device 1');
    } finally {
      await relay.close();
    }
  });
});
