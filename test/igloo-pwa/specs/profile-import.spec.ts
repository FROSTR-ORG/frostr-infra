import { expect, test } from '@playwright/test';

import { createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { pages } from '../support/pages';
import { expectPwaDashboard, importPwaProfile } from '../support/ui';

test.describe('igloo-pwa bfprofile import @live', () => {
  test('imports a bfprofile package and lands on the dashboard', async ({ page }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Import',
        labelPrefix: 'Imported Browser Device',
        relays: [relay.url],
      });

      await importPwaProfile(page, generated.shares[0].bfprofile, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Imported Browser Device 1');
    } finally {
      await relay.close();
    }
  });

  test('exports an encrypted profile package from settings @live', async ({ page }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Export',
        labelPrefix: 'Export Browser Device',
        relays: [relay.url],
      });

      await importPwaProfile(page, generated.shares[0].bfprofile, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Export Browser Device 1');

      const dashboard = pages(page).dashboard;
      await dashboard.openTab('settings');
      // Re-encrypt with a fresh export password; the complete state surfaces a real
      // bfprofile package (the WASM decode→re-encode path actually runs).
      const exported = await dashboard.exportProfileWithPassword('export-passphrase');
      expect(exported.startsWith('bfprofile1')).toBe(true);
    } finally {
      await relay.close();
    }
  });
});
