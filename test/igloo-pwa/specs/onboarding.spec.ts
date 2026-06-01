import { expect, test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { buildPwaPersistedState } from '../support/state';
import { startRelayEventRecorder } from '../support/onboard-diagnostics';
import {
  expectPwaDashboard,
  expectPwaRuntimeConnected,
  loadStoredPwaProfile,
  onboardPwaDevice,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

// Exercises a COMPLETE two-device onboard: an inviter device that already holds a
// share and runs its signer, plus a freshly-onboarded recipient device, negotiating
// the bfonboard handshake over a live local relay. Beyond the UI reaching each
// dashboard, we assert the request/response actually crossed the relay so a silent
// handshake regression can't pass.
test.describe('igloo-pwa bfonboard onboarding @live', () => {
  test('onboards a second browser device from a live inviter over a local relay', async ({ browser, page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    const recorder = startRelayEventRecorder(relay.url);
    let secondaryContext;
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Onboard',
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

      // Inviter: load the share and confirm its signer runtime is live on the relay
      // before the recipient starts, so the handshake can't race an unsubscribed peer.
      await seedPwaState(page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(page, 'Inviter Browser Device');
      await expectPwaDashboard(page, 'Inviter Browser Device');
      await expectPwaRuntimeConnected(page);

      // Recipient: fresh, isolated device pastes the bfonboard package and completes
      // the handshake, landing on its own dashboard.
      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage,
        packagePassword: 'onboard-package-pass',
        // The recipient names their own device during onboarding.
        label: 'Onboarded Browser Device',
        localPassword: 'playwright-passphrase',
      });
      await expectPwaDashboard(secondary.page, 'Onboarded Browser Device');

      // Prove the handshake genuinely happened over the wire: the recipient published
      // an onboard request, and the inviter published a response back to it.
      recorder.stop();
      const request = recorder.firstFrom(recipient.sharePublicKey);
      expect(request, 'recipient should publish an onboard request to the relay').toBeTruthy();
      const response = recorder.firstFromTo(
        inviter.sharePublicKey,
        recipient.sharePublicKey,
        request?.at_ms ?? 0,
      );
      expect(
        response,
        `inviter should publish an onboard response back to the recipient\n${recorder.format({
          [inviter.sharePublicKey.toLowerCase()]: 'INVITER',
          [recipient.sharePublicKey.toLowerCase()]: 'RECIPIENT',
        })}`,
      ).toBeTruthy();
    } finally {
      recorder.stop();
      await secondaryContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
