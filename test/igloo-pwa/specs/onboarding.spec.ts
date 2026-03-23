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

test.describe('igloo-pwa bfonboard onboarding', () => {
  test('onboards a second browser device from a live inviter over a local relay', async ({ browser, page }) => {
    const relay = await startLocalRelay();
    let secondaryContext;
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'PWA Onboard',
        labelPrefix: 'Onboard Source',
        relays: [relay.url],
      });
      const inviter = generated.shares[0];
      const recipient = generated.shares[1];
      const inviterSeed = createPwaStoredProfileSeed({
        artifact: inviter,
        groupPackageJson: generated.groupPackageJson,
        label: 'Inviter Browser Device',
      });
      const onboardPackage = await createOnboardingPackage({
        shareSecret: recipient.shareSecret,
        relays: [relay.url],
        peerPubkey: inviter.sharePublicKey,
        password: 'onboard-package-pass',
      });

      await seedPwaState(page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(page, 'Inviter Browser Device');
      await expectPwaDashboard(page, 'Inviter Browser Device');

      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage,
        packagePassword: 'onboard-package-pass',
        label: 'Onboarded Browser Device',
        localPassword: 'playwright-passphrase',
      });
      await expectPwaDashboard(secondary.page, 'Onboarded Browser Device');
    } finally {
      await secondaryContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
