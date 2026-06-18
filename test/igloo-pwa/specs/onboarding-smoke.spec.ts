import { test } from '@playwright/test';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { buildPwaPersistedState } from '../support/state';
import {
  expectPwaDashboard,
  expectPwaRuntimeConnected,
  expectPwaSignerSignReady,
  loadStoredPwaProfile,
  onboardPwaDevice,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

// @live @smoke — the per-PR-tier PWA integration tripwire (ADR-013 §(b)): one
// onboarding handshake + a real signing-round-trip readiness check over an
// in-process relay, no external infra. A live inviter device onboards a fresh
// recipient over the relay, and BOTH devices reach genuine sign-ready (nonce
// pools hydrated with the other as a can-sign peer) — proof the onboarded signer
// can participate in a signature, not just that a dashboard rendered.
//
// This is a deliberately minimal subset of the full @live suite (which adds the
// over-the-wire handshake assertion in onboarding.spec and the verifiable
// threshold signature in sign-shell.spec); it stays shell-free so the per-PR
// pwa lane needs no extra submodule or native build.
test.describe('igloo-pwa onboarding + signing smoke @live @smoke', () => {
  test('onboards a second device and both reach sign-ready over a local relay', async ({ browser, page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    let secondaryContext;
    try {
      // 2-of-3 group (builder default): two online devices clear the threshold,
      // so both can reach sign-ready.
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Smoke',
        labelPrefix: 'Smoke Source',
        relays: [relay.url],
      });
      const inviter = generated.shares[0];
      const recipient = generated.shares[1];
      const inviterSeed = createPwaStoredProfileSeed({
        artifact: inviter,
        groupPackageJson: generated.groupPackageJson,
        label: 'Inviter Smoke Device',
      });
      const onboardPackage = await createOnboardingPackage({
        shareSecret: recipient.shareSecret,
        relays: [relay.url],
        peerPubkey: inviter.sharePublicKey,
        password: 'smoke-onboard-pass',
      });

      // Inviter: load the share and confirm its signer runtime is live on the relay
      // before the recipient starts, so the handshake can't race an unsubscribed peer.
      await seedPwaState(page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(page, 'Inviter Smoke Device');
      // Assert the dashboard + live runtime, not the profile label — label
      // placement is a render/@visual concern, orthogonal to this behavioral smoke.
      await expectPwaDashboard(page);
      await expectPwaRuntimeConnected(page);

      // Recipient: a fresh, isolated device completes the bfonboard handshake over
      // the relay and lands on its own dashboard.
      const secondary = await openFreshPwaPage(browser);
      secondaryContext = secondary.context;
      await onboardPwaDevice(secondary.page, {
        onboardPackage,
        packagePassword: 'smoke-onboard-pass',
        label: 'Onboarded Smoke Device',
        localPassword: 'playwright-passphrase',
      });
      await expectPwaDashboard(secondary.page);

      // Both devices hold a share of the same group and are online — confirm each
      // reaches a genuine sign-ready state.
      await expectPwaSignerSignReady(secondary.page, 1);
      await expectPwaSignerSignReady(page, 1);
    } finally {
      await secondaryContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
