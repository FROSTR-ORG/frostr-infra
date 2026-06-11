import { expect, test } from '@playwright/test';
import { schnorr } from '@noble/curves/secp256k1.js';

import {
  DEFAULT_BROWSER_PASSWORD,
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { buildPwaPersistedState } from '../support/state';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { expectPwaDashboard, expectPwaSignerSignReady, loadStoredPwaProfile, seedPwaState } from '../support/ui';

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// @live — a genuine end-to-end threshold SIGNATURE across two runtimes. A browser
// PWA signer (share #2, loaded from a stored profile) and a headless native
// igloo-shell signer (share #1) discover each other over a relay and hydrate their
// nonce pools; the shell — the PWA is responder-only and can't self-initiate —
// INITIATES the sign, the PWA contributes its partial, and we schnorr-verify the
// returned aggregate against the group key. Proof the browser signer really signs.
//
// The PWA loads its share from a seeded stored profile rather than onboarding,
// because the onboard → save → relaunch flow currently resets the nonce pool so the
// re-launched signer can't serve a partial (tracked separately in dev/BACKLOG.md).
// Onboarding itself is covered behaviorally by onboarding.spec.ts.
//
// CI: tagged @live so release-validation (make test-live) runs it; igloo-shell is
// prebuilt in test-prep. The multi-PWA-tab variant is a documented manual demo
// (make pwa-multisig-demo).
test.describe('igloo-pwa + igloo-shell threshold signature @live', () => {
  test('produces a verifiable threshold signature with a headless igloo-shell co-signer', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    // Build the igloo-shell CLI (the `shared` prebuild target → build/igloo-shell-target);
    // a no-op when `make test-prep` already prepared it in CI.
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;
    try {
      // A 2-of-2 group: share #1 → igloo-shell (initiator), share #2 → the PWA. Both
      // are required, so a completed signature proves the PWA genuinely co-signed.
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Shell Sign',
        labelPrefix: 'Shell Sign Device',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const shellShare = generated.shares[0];
      const pwaShare = generated.shares[1];

      // igloo-shell: import the initiator share and start its daemon (connected to
      // the relay) so it can exchange nonces with the PWA.
      shell = await startShellSigner({
        bfprofile: shellShare.bfprofile,
        packageSecret: DEFAULT_BROWSER_PASSWORD,
        relayUrl: relay.url,
        label: 'Shell Signing Device',
      });
      await shell.waitConnected();

      // PWA: load share #2 from a seeded stored profile and bring up its signer.
      const pwaSeed = createPwaStoredProfileSeed({
        artifact: pwaShare,
        groupPackageJson: generated.groupPackageJson,
        label: 'PWA Signing Device',
      });
      await seedPwaState(page, buildPwaPersistedState({ profiles: [pwaSeed] }));
      await loadStoredPwaProfile(page, 'PWA Signing Device');
      await expectPwaDashboard(page, 'PWA Signing Device');

      // Both sides must reach a mutual can-sign state (nonce pools hydrated) before
      // the 2-of-2 sign can complete. Dump the shell's view if either stalls.
      try {
        await expectPwaSignerSignReady(page, 1);
        await shell.signReady(60_000);
      } catch (error) {
        console.log('SHELL RUNTIME STATUS:', JSON.stringify(shell.status(), null, 2));
        throw error;
      }

      // The shell initiates a real signature over a fixed 32-byte message; the PWA
      // contributes its partial over the relay.
      const messageHex = 'ab'.repeat(32);
      const signatures = await shell.requestSign(messageHex);
      expect(signatures.length, 'shell sign returned no signatures').toBeGreaterThan(0);

      // The aggregate schnorr signature must verify against the group x-only key —
      // the cryptographic proof that the threshold sign actually succeeded.
      const groupXOnly =
        generated.groupPublicKey.length === 66 ? generated.groupPublicKey.slice(2) : generated.groupPublicKey;
      const messageBytes = hexToBytes(messageHex);
      const groupKeyBytes = hexToBytes(groupXOnly);
      const verified = signatures.some((sig) => {
        try {
          return schnorr.verify(hexToBytes(sig), messageBytes, groupKeyBytes);
        } catch {
          return false;
        }
      });
      expect(
        verified,
        `no returned signature verified against group key ${groupXOnly}: ${JSON.stringify(signatures)}`,
      ).toBe(true);
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
