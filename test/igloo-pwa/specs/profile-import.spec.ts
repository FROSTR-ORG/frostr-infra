import { test } from '@playwright/test';

import { createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { expectPwaDashboard, importPwaProfile } from '../support/ui';

test.describe('igloo-pwa bfprofile import', () => {
  test('imports a bfprofile package and lands on the dashboard', async ({ page }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'PWA Import',
        labelPrefix: 'Imported Browser Device',
        relays: [relay.url],
      });

      await importPwaProfile(page, generated.shares[0].bfprofile, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Imported Browser Device 1');
    } finally {
      await relay.close();
    }
  });
});
