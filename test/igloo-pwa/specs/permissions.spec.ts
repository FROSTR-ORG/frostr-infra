import { expect, test, type Page } from '@playwright/test';

import {
  DEFAULT_BROWSER_PASSWORD,
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { pages, type PeerPolicySelector } from '../support/pages';
import { PWA_GLOBAL_STORE_KEY } from '../support/state';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { expectPwaDashboard, expectPwaSignerSignReady, onboardPwaDevice } from '../support/ui';

// @live — genuine behavioral coverage of the peer-permission editor: bring up a
// real two-party runtime (a headless igloo-shell co-signer + the onboarded PWA),
// toggle a live peer policy in the PWA, and prove the manual override survives a
// full browser reload through the real persistence store. The prior
// permissions-visual spec only seeds fake peer rows and screenshots — it never
// drives a toggle or asserts that an override persists.
//
// We toggle respond/ecdh (deny inbound ECDH from this peer): a real, persisted
// policy change that does NOT interfere with the nonce re-sync the reloaded
// signer needs to re-establish its peer, keeping the reload half deterministic.

const TOGGLED_POLICY: PeerPolicySelector = { direction: 'respond', method: 'ecdh' };

// Scan every per-instance partition for a persisted manual peer-policy override
// matching the toggle. Confirms the debounced persistor flushed the override to
// localStorage before we reload (decoupled from the exact partition key).
async function persistedHasDenyOverride(page: Page, direction: string, method: string): Promise<boolean> {
  return page.evaluate(
    ({ wantDirection, wantMethod, storeKey }) => {
      // Profiles (with their manual peer-policy overrides) live in the GLOBAL store
      // (post-2026-06-16 split); read it directly, not the retired
      // `igloo-pwa.state.v2` partition.
      const parsed = JSON.parse(window.localStorage.getItem(storeKey) ?? 'null');
      const profiles = parsed?.profiles;
      if (!Array.isArray(profiles)) return false;
      for (const profile of profiles) {
        const overrides = profile?.manual_peer_policy_overrides;
        if (!Array.isArray(overrides)) continue;
        for (const override of overrides) {
          if (override?.policy?.[wantDirection]?.[wantMethod] === 'deny') return true;
        }
      }
      return false;
    },
    { wantDirection: direction, wantMethod: method, storeKey: PWA_GLOBAL_STORE_KEY },
  );
}

test.describe('igloo-pwa peer permission persistence @live', () => {
  test('toggles a live peer policy and persists the override across a reload', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;
    try {
      // 2-of-2: share #1 → headless igloo-shell (inviter), share #2 → the PWA.
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Permissions Sign',
        labelPrefix: 'Permissions Device',
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
        label: 'Permissions Shell Device',
      });
      await shell.waitConnected();

      const onboardPackage = await createOnboardingPackage({
        shareSecret: pwaShare.shareSecret,
        relays: [relay.url],
        peerPubkey: shellShare.sharePublicKey,
        password: 'permissions-onboard-pass',
      });
      await onboardPwaDevice(page, {
        onboardPackage,
        packagePassword: 'permissions-onboard-pass',
        label: 'PWA Permissions Device',
        localPassword: DEFAULT_BROWSER_PASSWORD,
      });
      await expectPwaDashboard(page, 'PWA Permissions Device');

      // Both sides reach a mutual can-sign state — guarantees the shell is a known,
      // live peer in the PWA's peer-policy view.
      try {
        await expectPwaSignerSignReady(page, 1);
        await shell.signReady(60_000);
      } catch (error) {
        console.log('SHELL RUNTIME STATUS:', JSON.stringify(shell.status(), null, 2));
        throw error;
      }

      const p = pages(page);
      await p.dashboard.openTab('permissions');

      // Exactly one peer (the shell); the (direction, method) pair is unambiguous.
      // Effective starts allowed with no manual override.
      await p.dashboard.expectPeerPolicyVisible(TOGGLED_POLICY);
      await p.dashboard.expectPeerPolicyAllowed(TOGGLED_POLICY, true);
      await p.dashboard.expectPeerPolicyOverride(TOGGLED_POLICY, 'unset');

      // The toggle cycles the manual override forward: unset → allow → ask → deny.
      // Click through to a 'deny' override (also exercises the new 'ask' state),
      // asserting the OVERRIDE (the operator's directly-edited, persisted tri-state)
      // at each step — not the effective capability, which tracks live negotiation.
      await p.dashboard.togglePeerPolicy(TOGGLED_POLICY);
      await p.dashboard.expectPeerPolicyOverride(TOGGLED_POLICY, 'allow');
      await p.dashboard.togglePeerPolicy(TOGGLED_POLICY);
      await p.dashboard.expectPeerPolicyOverride(TOGGLED_POLICY, 'ask');
      await p.dashboard.togglePeerPolicy(TOGGLED_POLICY);
      await p.dashboard.expectPeerPolicyOverride(TOGGLED_POLICY, 'deny');

      // The override applies to the live runtime, then persists onto the profile.
      // Gate the reload on the debounced persistor actually flushing it.
      await expect.poll(() => persistedHasDenyOverride(page, TOGGLED_POLICY.direction, TOGGLED_POLICY.method), {
        timeout: 15_000,
      }).toBe(true);

      // Full browser reload wipes all in-memory state and rebuilds it from
      // localStorage. remember_browser_state restores the (stopped) dashboard;
      // peer rows only render for an ACTIVE runtime, so boot a fresh signer:
      // log out to the welcome, then unlock. The shell stays online, so the
      // fresh signer re-syncs (generation self-heal) and the peer re-appears —
      // now carrying the 'deny' override restored from the persisted profile.
      await page.reload();
      await p.dashboard.openTab('settings');
      await p.dashboard.logout();
      await p.welcome.expectReturning();
      await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD);
      await expectPwaDashboard(page, 'PWA Permissions Device');

      await p.dashboard.openTab('permissions');
      await p.dashboard.expectPeerPolicyVisible(TOGGLED_POLICY);
      await p.dashboard.expectPeerPolicyOverride(TOGGLED_POLICY, 'deny');
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
