import { expect, test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
  publishBackupForProfile,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { pages } from '../support/pages';
import { buildPwaPersistedState } from '../support/state';
import { expectPwaDashboard, onboardPwaDevice, openFreshPwaPage, seedPwaState } from '../support/ui';

// @live — two-device flow over a real relay (rotate → distribute → remote
// onboard). Runs in the live lane (CI), excluded from the deterministic fast
// lane. The local onboard handshake does not complete reliably in the sandbox
// relay; tracked for live-lane verification.
test.describe('igloo-pwa rotation operator flow @live', () => {
  test('rotates from threshold bfshare sources and distributes a rotated share via bfonboard', async ({ browser, page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    let secondaryContext;
    try {
      const source = await createGeneratedBrowserArtifacts({
        groupName: 'Source Treasury',
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
      const p = pages(page);
      await p.welcome.goto();
      await p.welcome.startGenerate();
      await p.create.selectMode('rotate');
      await p.create.selectRotateSource(sourceSeed.id);
      await p.create.fillRotateSource(0, { bfshare: source.shares[0].bfshare, password: 'playwright-passphrase' });
      await p.create.addRotateSource();
      await p.create.fillRotateSource(1, { bfshare: source.shares[1].bfshare, password: 'playwright-passphrase' });
      await p.create.rotateSubmit();

      await expect(page.getByRole('heading', { name: 'Select Share' })).toBeVisible();
      await p.create.selectShareNext();
      await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
      // Relays are pre-populated from the source profile ([relay.url]).
      await expect(page.getByText(relay.url, { exact: false })).toBeVisible();
      await p.create.fillSaveProfile({ name: 'Rotated Treasury Device', password: 'playwright-passphrase' });
      await p.create.saveProfileNext();

      await expect(page.getByRole('heading', { name: 'Remote Shares', exact: true })).toBeVisible();
      const distributeCard = p.distribute.cardByName('Source Treasury Device 2');
      await p.distribute.preparePackage(distributeCard, 'rotate-remote-pass');
      await p.distribute.showQr(distributeCard);
      const onboardPackage = await p.distribute.readQrPackage();
      expect(onboardPackage.startsWith('bfonboard1')).toBe(true);
      await p.distribute.closeQr();
      await p.distribute.markDelivered(distributeCard);

      const finalCard = p.distribute.cardByName('Source Treasury Device 3');
      await p.distribute.preparePackage(finalCard, 'rotate-remote-pass');
      await p.distribute.markDelivered(finalCard);

      // Finish Setup persists the rotated profile (peer/nonce snapshot), stops the
      // runtime, and returns the primary to the locked returning Welcome.
      await p.distribute.finish();
      await p.welcome.expectReturning();

      // Unlock to restart the rotated signer runtime from its persisted snapshot so
      // it serves the remote onboarding handshake from the dashboard.
      await p.welcome.unlock('playwright-passphrase');
      await p.dashboard.expectDashboard('Rotated Treasury Device');

      // Onboard a remote device against the running rotated signer.
      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage,
        packagePassword: 'rotate-remote-pass',
        // The recipient names their own device during onboarding.
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
