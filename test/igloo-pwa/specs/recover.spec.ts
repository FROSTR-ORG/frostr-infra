import { expect, test } from '@playwright/test';
import { schnorr } from '@noble/curves/secp256k1.js';
import { nip19 } from 'nostr-tools';

import { DEFAULT_BROWSER_PASSWORD, createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { pages } from '../support/pages';
import { expectPwaDashboard, importPwaProfile } from '../support/ui';

// @live — exercises a GENUINE private-key recovery: reconstruct the group secret
// from a threshold of real shares in WASM and assert the recovered nsec actually
// corresponds to the group public key. The prior recover-visual spec injects a
// FAKE key via window.__IGLOO_TEST_RECOVERED_KEY__ and only screenshots the
// success screen — it never reconstructs anything.
//
// The recovering device is a group member: its own profile supplies the group
// package and contributes its share (unlocked with the device passphrase), so for
// a 2-of-3 the operator only pastes ONE more share. Recovery is fully local — the
// removed relay-backup fetch is gone.

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

test.describe('igloo-pwa private key recovery @live', () => {
  test('reconstructs the real nsec from the device share plus a pasted share', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    try {
      // Real 2-of-3 keyset (WASM keygen). bfshare packages are sealed with the
      // default browser password; groupPublicKey is the x-only key we must recover.
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Recover Keyset',
        labelPrefix: 'Recover Device',
        threshold: 2,
        count: 3,
        relays: [relay.url],
      });
      const groupXOnly = (
        generated.groupPublicKey.length === 66 ? generated.groupPublicKey.slice(2) : generated.groupPublicKey
      ).toLowerCase();

      const p = pages(page);

      // Import share #3 as the recovering device's stored profile (recovery is
      // entered from a welcome profile row), then log out to the locked welcome.
      await importPwaProfile(page, generated.shares[2].bfprofile, DEFAULT_BROWSER_PASSWORD);
      await expectPwaDashboard(page);
      await p.dashboard.openTab('settings');
      await p.dashboard.logout();
      await p.welcome.expectReturning();

      // Recover: the device contributes share #3 (via its passphrase); paste share
      // #1 to reach the threshold of 2, then reconstruct.
      await p.welcome.recover();
      await p.recover.fillDevicePassphrase(DEFAULT_BROWSER_PASSWORD);
      await p.recover.fillSource(0, {
        packageText: generated.shares[0].bfshare,
        password: DEFAULT_BROWSER_PASSWORD,
      });
      await p.recover.next();

      // Reveal and read the genuinely reconstructed nsec.
      await p.recover.expectRecovered();
      await p.recover.revealKey();
      const nsec = await p.recover.readRecoveredKey();
      expect(nsec.startsWith('nsec1')).toBe(true);

      // Cryptographic proof: the recovered secret's x-only public key must equal the
      // group key. A stub or wrong reconstruction can't satisfy this.
      const decoded = nip19.decode(nsec);
      expect(decoded.type).toBe('nsec');
      const recoveredXOnly = bytesToHex(schnorr.getPublicKey(decoded.data as Uint8Array));
      expect(recoveredXOnly).toBe(groupXOnly);
    } finally {
      await relay.close();
    }
  });
});
