import { expect, test } from '@playwright/test';

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

// @live — proves peer policy overrides are not just persisted UI state. A real
// igloo-shell co-signer successfully signs with the PWA, then the PWA operator
// denies inbound SIGN responses for that peer and the next shell-initiated sign
// fails through the live runtime path.
test.describe('igloo-pwa Permissions runtime reflection @live', () => {
  test('applies a respond SIGN deny override to live signer behavior', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;

    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Permissions Runtime Live',
        labelPrefix: 'Permissions Runtime Device',
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
        label: 'Permissions Runtime Shell Peer',
        runtimeOptions: {
          sign_timeout_secs: 5,
          ping_timeout_secs: 3,
          request_ttl_secs: 30,
          state_save_interval_secs: 1,
        },
      });
      await shell.waitConnected();

      const seededProfile = createPwaStoredProfileSeed({
        artifact: pwaShare,
        groupPackageJson: generated.groupPackageJson,
        label: 'Permissions Runtime PWA',
      });
      const profile = {
        ...seededProfile,
        signer_settings: {
          ...seededProfile.signer_settings,
          sign_timeout_secs: 5,
          ping_timeout_secs: 3,
          request_ttl_secs: 30,
          state_save_interval_secs: 1,
        },
      };
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

      const allowedSignatures = await shell.requestSign('ce'.repeat(32), 1);
      expect(allowedSignatures.length, 'baseline live sign should succeed before the override').toBeGreaterThan(0);

      await p.dashboard.openTab('permissions');
      await p.dashboard.expectPeerPermissions();
      await p.dashboard.toggleFirstPeerPermission('respond', 'sign', 'allow');
      await p.dashboard.expectPeerPermission('respond', 'sign', 'deny');

      await expect(shell.requestSign('cf'.repeat(32), 1)).rejects.toThrow(
        /failed|timeout|denied|no signatures/i,
      );
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
