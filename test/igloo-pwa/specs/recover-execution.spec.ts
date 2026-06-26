import { test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
  DEFAULT_BROWSER_PASSWORD,
  publishBackupForProfile,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { pages } from '../support/pages';
import { buildPwaPersistedState } from '../support/state';
import { seedPwaState } from '../support/ui';

const RECOVERY_PRIVATE_KEY_HEX = '11'.repeat(32);
// FROST recovery normalizes reconstructed signing keys to the even-y equivalent.
// This nsec is the deterministic normalized key for RECOVERY_PRIVATE_KEY_HEX.
const RECOVERY_NORMALIZED_NSEC = 'nsec1amhwamhwamhwamhwamhwamhwak5emj74ncmc724wc9xhh0e9xqcqugtgpv';

// @live — exercises the real Recover flow instead of the visual harness seam:
// launch Recover from the locked Welcome profile menu, paste threshold remote
// source packages, reconstruct the original nsec through browser WASM, and
// reveal the recovered key in the UI.
test.describe('igloo-pwa recover execution @live', () => {
  test('recovers the original nsec from threshold source packages', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();

    try {
      const artifacts = await createGeneratedBrowserArtifacts({
        groupName: 'Recover Execution',
        labelPrefix: 'Recover Device',
        threshold: 2,
        count: 3,
        relays: [relay.url],
        privateKey: RECOVERY_PRIVATE_KEY_HEX,
      });
      const [localShare, remoteShare, backupShare] = artifacts.shares;
      await Promise.all([
        publishBackupForProfile(localShare.profilePayload),
        publishBackupForProfile(remoteShare.profilePayload),
        publishBackupForProfile(backupShare.profilePayload),
      ]);
      const profile = createPwaStoredProfileSeed({
        artifact: localShare,
        groupPackageJson: artifacts.groupPackageJson,
        label: 'Recover Primary',
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
      await p.welcome.recover(profile.id);
      await p.dashboard.expectRecoverCollect('welcome');

      await p.dashboard.fillRecoverSource(0, {
        sourcePackage: remoteShare.bfshare,
        password: DEFAULT_BROWSER_PASSWORD,
      });
      await p.dashboard.fillRecoverSource(1, {
        sourcePackage: backupShare.bfshare,
        password: DEFAULT_BROWSER_PASSWORD,
      });
      await p.dashboard.recoverNext();
      await p.dashboard.expectRecoveredPrivateKey(RECOVERY_NORMALIZED_NSEC);
    } finally {
      await relay.close();
    }
  });
});
