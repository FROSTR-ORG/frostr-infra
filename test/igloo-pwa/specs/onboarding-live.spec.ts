import { test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { buildPwaPersistedState } from '../support/state';
import {
  expectPwaDashboard,
  loadStoredPwaProfile,
  onboardPwaDevice,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

test.describe('igloo-pwa bfonboard onboarding @live', () => {
  test('onboards a second browser device from a live inviter over a local relay', async ({ browser, page }) => {
    const relay = await startLocalRelay();
    let secondaryContext;
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Live Onboard',
        labelPrefix: 'Live Onboard Source',
        relays: [relay.url],
      });
      const inviter = generated.shares[0];
      const recipient = generated.shares[1];
      const inviterSeed = createPwaStoredProfileSeed({
        artifact: inviter,
        groupPackageJson: generated.groupPackageJson,
        label: 'Live Inviter Browser Device',
      });
      const onboardPackage = await createOnboardingPackage({
        shareSecret: recipient.shareSecret,
        relays: [relay.url],
        peerPubkey: inviter.sharePublicKey,
        password: 'live-onboard-pass',
      });

      await seedPwaState(page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(page, 'Live Inviter Browser Device');
      await expectPwaDashboard(page, 'Live Inviter Browser Device');

      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage,
        packagePassword: 'live-onboard-pass',
        label: 'Live Onboarded Browser Device',
        localPassword: 'playwright-passphrase',
      });
      await expectPwaDashboard(secondary.page, 'Live Onboarded Browser Device');
    } finally {
      await secondaryContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
