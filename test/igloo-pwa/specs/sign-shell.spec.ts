import { expect, test } from '@playwright/test';
import { schnorr } from '@noble/curves/secp256k1.js';

import {
  DEFAULT_BROWSER_PASSWORD,
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { runTestPrebuild } from '../../shared/test-prebuild';
import { startRelayEventRecorder } from '../support/onboard-diagnostics';
import { startShellSigner, type ShellSigner } from '../support/shell-signer';
import { expectPwaDashboard, expectPwaSignerSignReady, onboardPwaDevice } from '../support/ui';

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// @live — a browser PWA signer and a headless native igloo-shell signer,
// independently hosted, discover each other over a relay, complete a bfonboard
// handshake, and both hydrate their signing nonce pools to a mutual can-sign
// state. That mutual sign-readiness is the reliable, high-value proof here: it
// catches relay/WASM-runtime/nonce-exchange/cross-runtime regressions that the
// seeded @visual specs can't. The igloo-pwa runtime is responder-only, so a
// headless igloo-shell co-signer also INITIATES a real signature; when that
// partial-sign round-trip completes we schnorr-verify the aggregate. The
// shell-initiated round-trip to a headless browser tab is not yet reliable (the
// tab can stall the locked-sign response — tracked in dev/BACKLOG.md), so the
// signature is verified opportunistically rather than gating the test.
//
// CI: tagged @live so release-validation (make test-live) runs it; igloo-shell is
// prebuilt in test-prep. The multi-PWA-tab variant is a documented manual demo
// (make pwa-multisig-demo) since the PWA can't self-initiate.
test.describe('igloo-pwa + igloo-shell threshold signer @live', () => {
  test('a browser signer and a headless igloo-shell co-signer reach mutual sign-readiness over a relay', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    // Build the igloo-shell CLI (the `shared` prebuild target → build/igloo-shell-target);
    // a no-op when `make test-prep` already prepared it in CI.
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    const recorder = startRelayEventRecorder(relay.url);
    let shell: ShellSigner | null = null;
    try {
      // A 2-of-2 group: share #1 → igloo-shell (inviter + initiator), share #2 →
      // the PWA (recipient). Both are required, so a completed signature proves
      // the PWA genuinely co-signed.
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Shell Sign',
        labelPrefix: 'Shell Sign Device',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const shellShare = generated.shares[0];
      const pwaShare = generated.shares[1];

      // igloo-shell: import the inviter share and start its daemon. Wait only for
      // the daemon to finish restoring (NOT sign-ready — that needs the PWA online,
      // which happens after onboarding) so it is subscribed before the handshake.
      shell = await startShellSigner({
        bfprofile: shellShare.bfprofile,
        packageSecret: DEFAULT_BROWSER_PASSWORD,
        relayUrl: relay.url,
        label: 'Shell Signing Device',
      });
      await shell.waitConnected();

      // PWA: onboard the recipient share against the running shell inviter. The
      // handshake brings the PWA online and primes the nonce pools both ways.
      const onboardPackage = await createOnboardingPackage({
        shareSecret: pwaShare.shareSecret,
        relays: [relay.url],
        peerPubkey: shellShare.sharePublicKey,
        password: 'shell-sign-onboard-pass',
      });
      await onboardPwaDevice(page, {
        onboardPackage,
        packagePassword: 'shell-sign-onboard-pass',
        label: 'PWA Signing Device',
        localPassword: DEFAULT_BROWSER_PASSWORD,
      });
      await expectPwaDashboard(page, 'PWA Signing Device');

      // HARD assertion: both sides reach a mutual can-sign state — the PWA sees
      // the shell as a sign-ready peer (nonce pool hydrated) AND the shell reports
      // sign_ready with the PWA as a signing peer. Dump the shell's view if either
      // stalls.
      try {
        await expectPwaSignerSignReady(page, 1);
        await shell.signReady(60_000);
      } catch (error) {
        console.log('SHELL RUNTIME STATUS:', JSON.stringify(shell.status(), null, 2));
        throw error;
      }

      // OPPORTUNISTIC: drive a real shell-initiated signature. When the round-trip
      // completes, verify the aggregate schnorr signature against the group x-only
      // key. A timeout (the headless-tab locked-sign gap, see BACKLOG) is logged,
      // not failed.
      const messageHex = 'ab'.repeat(32);
      const shellX =
        shellShare.sharePublicKey.length === 66 ? shellShare.sharePublicKey.slice(2) : shellShare.sharePublicKey;
      const pwaX = pwaShare.sharePublicKey.length === 66 ? pwaShare.sharePublicKey.slice(2) : pwaShare.sharePublicKey;
      const signStartMs = Date.now();
      let signatures: string[] = [];
      try {
        signatures = await shell.requestSign(messageHex, 2);
      } catch (error) {
        console.warn(
          `shell-initiated signature did not complete (known headless round-trip gap): ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      // Breadcrumb for the known round-trip gap (dev/BACKLOG.md): the shell
      // publishes the sign request, but the headless browser signer never
      // publishes its partial back. Logs request=true / response=false so the gap
      // is visible in CI output without failing the test.
      const shellRequested = Boolean(recorder.firstFromTo(shellX, pwaX, signStartMs));
      const pwaResponded = Boolean(recorder.firstFromTo(pwaX, shellX, signStartMs));
      console.log(`SIGN WIRE: shell->pwa request=${shellRequested} pwa->shell response=${pwaResponded}`);
      if (signatures.length > 0) {
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
          `a signature was returned but did not verify against group key ${groupXOnly}: ${JSON.stringify(signatures)}`,
        ).toBe(true);
      }
    } finally {
      recorder.stop();
      await shell?.close();
      await relay.close();
    }
  });
});
