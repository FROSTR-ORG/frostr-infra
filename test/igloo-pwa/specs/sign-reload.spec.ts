import { expect, test } from '@playwright/test';
import { schnorr } from '@noble/curves/secp256k1.js';

import { DEFAULT_BROWSER_PASSWORD, createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { pages } from '../support/pages';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { expectPwaDashboard, expectPwaSignerSignReady, importPwaProfile } from '../support/ui';

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// @live — validates the per-pool nonce-generation self-heal END TO END (until now
// only unit-tested in bifrost-signer). A 2-of-2 group signs once over a relay: a
// headless igloo-shell co-signer (share #1) and the PWA (share #2, imported and
// started independently) converge their nonce pools and the shell-initiated sign
// completes. Then the PWA tab is RELOADED, dropping its in-memory nonce pool and
// booting a signer with a fresh generation id. The shell still holds the dead
// generation's nonces; the reloaded PWA's pings carry the new generation, the shell
// discards the stale nonces and re-syncs, and a SECOND signature completes — proof
// the reload path recovers without re-importing or re-onboarding.
//
// The PWA is imported (not onboarded) so its profile persists across the reload and
// each runtime starts with its own fresh pool — the resync is genuinely exercised.
test.describe('igloo-pwa sign after reload (generation self-heal) @live', () => {
  test('signs, reloads the tab, and signs again after the runtime re-syncs', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;
    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Reload Sign',
        labelPrefix: 'Reload Sign Device',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const shellShare = generated.shares[0];
      const pwaShare = generated.shares[1];
      const groupXOnly =
        generated.groupPublicKey.length === 66 ? generated.groupPublicKey.slice(2) : generated.groupPublicKey;
      const groupKeyBytes = hexToBytes(groupXOnly);

      shell = await startShellSigner({
        bfprofile: shellShare.bfprofile,
        packageSecret: DEFAULT_BROWSER_PASSWORD,
        relayUrl: relay.url,
        label: 'Reload Sign Shell',
      });
      await shell.waitConnected();

      // Import the PWA share as a persisted profile and boot its runtime. Unlike the
      // onboard path, import persists the profile so it survives the reload below.
      await importPwaProfile(page, pwaShare.bfprofile, DEFAULT_BROWSER_PASSWORD);
      await expectPwaDashboard(page);

      const p = pages(page);

      // Wait for both sides to be sign-ready, request a signature over `messageHex`,
      // and assert it verifies against the group key.
      const signAndVerify = async (messageHex: string) => {
        try {
          await expectPwaSignerSignReady(page, 1);
          await shell!.signReady(60_000);
        } catch (error) {
          console.log('SHELL RUNTIME STATUS:', JSON.stringify(shell!.status(), null, 2));
          throw error;
        }
        const signatures = await shell!.requestSign(messageHex);
        expect(signatures.length, 'shell sign returned no signatures').toBeGreaterThan(0);
        const messageBytes = hexToBytes(messageHex);
        const verified = signatures.some((sig) => {
          try {
            return schnorr.verify(hexToBytes(sig), messageBytes, groupKeyBytes);
          } catch {
            return false;
          }
        });
        expect(verified, `no returned signature verified against group key ${groupXOnly}`).toBe(true);
      };

      // First signature: the two independently-started runtimes converge their pools.
      await signAndVerify('ab'.repeat(32));

      // Reload the PWA tab: the in-memory nonce pool (and its generation id) is gone.
      // remember_browser_state restores the stopped dashboard; re-boot a fresh signer
      // via logout -> unlock. The shell stays online throughout.
      await page.reload();
      await p.dashboard.openTab('settings');
      await p.dashboard.logout();
      await p.welcome.expectReturning();
      await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD);
      await expectPwaDashboard(page);

      // Second signature over a DIFFERENT message: only succeeds if the shell detected
      // the reloaded PWA's new generation, discarded the stale nonces, and re-synced.
      await signAndVerify('cd'.repeat(32));
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
