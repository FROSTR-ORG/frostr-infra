import { test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
  DEFAULT_BROWSER_PASSWORD,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { pages } from '../support/pages';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { buildPwaPersistedState } from '../support/state';
import { expectPwaSignerSignReady, seedPwaState } from '../support/ui';

// @live — proves the stored-profile Welcome unlock path boots a real signer and
// reaches sign-ready when a cooperating peer is already online. This complements
// the full sign-shell test, which proves onboarding plus signature production.
test.describe('igloo-pwa Welcome unlock runtime @live', () => {
  test('unlocks a stored profile into a running sign-ready dashboard signer', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;

    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Welcome Unlock Live',
        labelPrefix: 'Welcome Unlock Device',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const shellShare = generated.shares[0];
      const pwaShare = generated.shares[1];
      shell = await startShellSigner({
        bfprofile: shellShare.bfprofile,
        packageSecret: DEFAULT_BROWSER_PASSWORD,
        relayUrl: relay.url,
        label: 'Welcome Unlock Shell Peer',
      });
      await shell.waitConnected();

      const profile = createPwaStoredProfileSeed({
        artifact: pwaShare,
        groupPackageJson: generated.groupPackageJson,
        label: 'Welcome Unlock PWA',
      });
      await seedPwaState(
        page,
        buildPwaPersistedState({
          profiles: [profile],
          selectedProfileId: profile.id,
          activeView: 'landing',
        }),
      );

      const p = pages(page);
      await p.welcome.goto();
      await p.welcome.expectReturning(1);
      await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
      await p.dashboard.expectDashboard();
      await expectPwaSignerSignReady(page, 1);
      await shell.signReady(60_000);
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
