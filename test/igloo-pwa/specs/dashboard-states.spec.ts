import { expect, test } from '@playwright/test';

import {
  DEFAULT_BROWSER_PASSWORD,
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { pages, type PeerPolicySelector } from '../support/pages';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { expectPwaDashboard, expectPwaSignerSignReady, onboardPwaDevice } from '../support/ui';

// can_sign readiness counts peers whose request.sign is permitted, so denying
// the (only) peer's request.sign drops sign_ready and surfaces signing-blocked.
const SIGN_REQUEST: PeerPolicySelector = { direction: 'request', method: 'sign' };

// @live — behavioral coverage of the dashboard condition banners over a real
// signer. A headless igloo-shell co-signer (share #1) and the onboarded PWA
// (share #2) form a 2-of-2 group. We then drive two banners off real runtime
// state, exploiting their precedence (all-relays-offline supersedes
// signing-blocked) to cover both from one setup:
//   1. deny the peer's request.sign  → sign_ready false → signing-blocked banner
//   2. close the relay               → connected_relays empties on the next
//      background re-probe → the banner flips to all-relays-offline
//
// (loading is transient and load-failed is a start-failure state, neither
// cleanly drivable here; signing-failed needs a local node to record a Sign
// failure, which the responder-only PWA dashboard can't initiate — see BACKLOG.)
//
// CI: tagged @live so make test-live runs it; igloo-shell is prebuilt in test-prep.
test.describe('igloo-pwa dashboard condition banners @live', () => {
  test('shows signing-blocked on a denied peer policy, then all-relays-offline when the relay drops', async ({
    page,
  }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let relayClosed = false;
    let shell: ShellSigner | null = null;
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Dashboard States',
        labelPrefix: 'Dashboard States Device',
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
        label: 'Dashboard States Shell',
      });
      await shell.waitConnected();

      const onboardPackage = await createOnboardingPackage({
        shareSecret: pwaShare.shareSecret,
        relays: [relay.url],
        peerPubkey: shellShare.sharePublicKey,
        password: 'dashboard-states-onboard-pass',
      });
      await onboardPwaDevice(page, {
        onboardPackage,
        packagePassword: 'dashboard-states-onboard-pass',
        label: 'PWA Dashboard States Device',
        localPassword: DEFAULT_BROWSER_PASSWORD,
      });
      await expectPwaDashboard(page, 'PWA Dashboard States Device');
      console.error('STEP onboarded; awaiting sign-ready');
      await expectPwaSignerSignReady(page, 1);
      console.error('STEP sign-ready');

      const p = pages(page);

      // (1) signing-blocked: deny the peer's request.sign (unset → allow → ask →
      // deny) so sign_ready drops below threshold while the peer is still online.
      await p.dashboard.openTab('permissions');
      await p.dashboard.expectPeerPolicyVisible(SIGN_REQUEST);
      await p.dashboard.togglePeerPolicy(SIGN_REQUEST); // → allow
      await p.dashboard.togglePeerPolicy(SIGN_REQUEST); // → ask
      await p.dashboard.togglePeerPolicy(SIGN_REQUEST); // → deny
      await p.dashboard.expectPeerPolicyOverride(SIGN_REQUEST, 'deny');

      await p.dashboard.openTab('signer');
      await expect(page.getByTestId('dashboard-banner-signing-blocked')).toBeVisible({
        timeout: 15_000,
      });

      // Stop the co-signer cleanly while the relay is still up — a `daemon stop`
      // against a dead relay can hang.
      await shell.close();
      shell = null;

      // (2) all-relays-offline: drop the relay. The background relay-health
      // re-probe (~30s) recomputes connected_relays to empty, and the banner
      // flips (all-relays-offline supersedes signing-blocked).
      await relay.close();
      relayClosed = true;
      await expect(page.getByTestId('dashboard-banner-all-relays-offline')).toBeVisible({
        timeout: 45_000,
      });
      await expect(page.getByTestId('dashboard-banner-signing-blocked')).toHaveCount(0);
    } finally {
      await shell?.close();
      // The test closes the relay during the all-relays-offline step. Don't
      // re-close: the local relay is SIGKILLed (no clean SIGTERM exit), leaving
      // exitCode null, so a second close() awaits an 'exit' that never re-fires.
      if (!relayClosed) await relay.close();
    }
  });
});
