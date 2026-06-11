import { expect, test } from '@playwright/test';

import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { pages } from '../support/pages';
import { expectPwaRuntimeConnected } from '../support/ui';

// @live — exercises a FRESH Create Keyset end to end: generate a brand-new
// threshold keyset in WASM, keep a local share, distribute the remote shares,
// Finish Setup, then unlock and boot the signer. Proves the created profile
// persists and brings up a live runtime — today this path has only a @visual
// screenshot walkthrough (welcome-visual) with no behavioral assertion.
//
// Tier-1 readiness: a freshly-created device has no peer online, so we assert
// the runtime connects (expectPwaRuntimeConnected) rather than full sign-ready
// (which needs a cooperating signer — see sign-shell.spec.ts / pwa-home-pairing).
test.describe('igloo-pwa create keyset @live', () => {
  test('generates a new keyset, distributes shares, and boots the saved signer', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    try {
      await page.goto('/');
      const p = pages(page);

      // Generate a brand-new keyset (real WASM keygen) and keep the first share.
      await p.welcome.startGenerate();
      await p.create.fillGenerate({ groupName: 'Created Keyset' });
      await p.create.generateNext();
      await expect(page.getByRole('heading', { name: 'Select Share' })).toBeVisible({ timeout: 30_000 });
      // Group members are 1-indexed (idx 1..count); keep the first share locally.
      await p.create.selectShare(1);
      await p.create.selectShareNext();

      // Save the local profile. The create form defaults to DEFAULT_RELAYS
      // (ws://127.0.0.1:8194); add this run's random-port relay so the saved
      // signer has a reachable relay to connect to.
      await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
      await p.create.fillSaveProfile({ name: 'Created Device', password: 'playwright-passphrase' });
      await p.create.addRelay(relay.url);
      await p.create.expectRelay(relay.url);
      await p.create.saveProfileNext();

      // Distribute every remote share (prepare + mark delivered), then Finish
      // Setup, which persists the profile, stops the runtime, and returns to the
      // locked returning Welcome.
      await expect(page.getByRole('heading', { name: 'Remote Shares', exact: true })).toBeVisible();
      const remoteCount = await p.distribute.cards().count();
      expect(remoteCount).toBeGreaterThan(0);
      for (let i = 0; i < remoteCount; i += 1) {
        const card = p.distribute.cards().nth(i);
        await p.distribute.preparePackage(card, 'create-remote-pass');
        await p.distribute.markDelivered(card);
      }
      await p.distribute.finish();
      await p.welcome.expectReturning();

      // Unlock to boot the freshly-created signer from its persisted snapshot and
      // confirm it brings up a live runtime, not just a rendered dashboard.
      await p.welcome.unlock('playwright-passphrase');
      await p.dashboard.expectDashboard('Created Device');
      await expectPwaRuntimeConnected(page);
    } finally {
      await relay.close();
    }
  });
});
