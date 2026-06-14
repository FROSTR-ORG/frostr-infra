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
import { pages, type PeerPolicySelector } from '../support/pages';
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

// The inbound SIGN method whose disposition we drive to `ask` (one peer, so the
// (direction, method) pair is unambiguous).
const SIGN_RESPOND: PeerPolicySelector = { direction: 'respond', method: 'sign' };

// @live — behavioral coverage of the interactive signing-approval queue (the `ask`
// disposition). A headless igloo-shell co-signer (share #1) and the onboarded PWA
// (share #2) form a 2-of-2 group. With the PWA's respond.sign set to `ask`, every
// sign request the shell INITIATES parks in the PWA's Pending Approvals card until
// the operator decides — so `shell.requestSign(...)` (kicked off un-awaited) is the
// inbound request that parks, and the operator's button decides whether it resolves
// (a verifiable signature) or rejects (no signature). Walks Deny → Allow once →
// still-parks → Always allow → auto-allowed, the full queue lifecycle.
//
// CI: tagged @live so make test-live runs it; igloo-shell is prebuilt in test-prep.
test.describe('igloo-pwa interactive approval queue @live', () => {
  test('parks ask-gated sign requests and resolves them via Deny / Allow once / Always allow', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    runTestPrebuild(['shared']);
    const relay = await startLocalRelay();
    let shell: ShellSigner | null = null;
    try {
      // 2-of-2: share #1 → igloo-shell (initiator), share #2 → the PWA (responder).
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Approval Queue',
        labelPrefix: 'Approval Device',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const shellShare = generated.shares[0];
      const pwaShare = generated.shares[1];
      const groupXOnly =
        generated.groupPublicKey.length === 66 ? generated.groupPublicKey.slice(2) : generated.groupPublicKey;
      const groupKeyBytes = hexToBytes(groupXOnly);

      const verifies = (signatures: string[], messageHex: string): boolean => {
        const messageBytes = hexToBytes(messageHex);
        return signatures.some((sig) => {
          try {
            return schnorr.verify(hexToBytes(sig), messageBytes, groupKeyBytes);
          } catch {
            return false;
          }
        });
      };

      shell = await startShellSigner({
        bfprofile: shellShare.bfprofile,
        packageSecret: DEFAULT_BROWSER_PASSWORD,
        relayUrl: relay.url,
        label: 'Approval Shell Device',
      });
      await shell.waitConnected();

      const onboardPackage = await createOnboardingPackage({
        shareSecret: pwaShare.shareSecret,
        relays: [relay.url],
        peerPubkey: shellShare.sharePublicKey,
        password: 'approval-onboard-pass',
      });
      await onboardPwaDevice(page, {
        onboardPackage,
        packagePassword: 'approval-onboard-pass',
        label: 'PWA Approval Device',
        localPassword: DEFAULT_BROWSER_PASSWORD,
      });
      await expectPwaDashboard(page, 'PWA Approval Device');

      const signReady = async () => {
        try {
          await expectPwaSignerSignReady(page, 1);
          await shell!.signReady(60_000);
        } catch (error) {
          console.log('SHELL RUNTIME STATUS:', JSON.stringify(shell!.status(), null, 2));
          throw error;
        }
      };
      await signReady();

      const p = pages(page);

      // Set the PWA's respond.sign disposition to `ask`. The toggle cycles
      // unset → allow → ask, so two clicks; `ask` is capability-allowed for
      // readiness, so the peer stays sign-ready.
      await p.dashboard.openTab('permissions');
      await p.dashboard.expectPeerPolicyVisible(SIGN_RESPOND);
      await p.dashboard.togglePeerPolicy(SIGN_RESPOND); // → allow
      await p.dashboard.togglePeerPolicy(SIGN_RESPOND); // → ask
      await p.dashboard.expectPeerPolicyOverride(SIGN_RESPOND, 'ask');
      await p.dashboard.openTab('signer');
      await p.dashboard.expectPendingApprovalsEmpty();

      // attempts:1 — the default 5 would retry and stack extra parked rows.

      // --- Deny: the parked request is rejected; the shell sign yields nothing. ---
      const denyMessage = 'ab'.repeat(32);
      const denied = shell.requestSign(denyMessage, 1).catch((error) => error);
      await p.dashboard.expectPendingApprovalVisible();
      await p.dashboard.denyPendingApproval();
      expect(await denied, 'a denied request must not produce a signature').toBeInstanceOf(Error);
      await p.dashboard.expectPendingApprovalsEmpty();

      // --- Allow once: the parked request is approved; a real signature returns. ---
      await signReady();
      const allowOnceMessage = 'cd'.repeat(32);
      const allowOnce = shell.requestSign(allowOnceMessage, 1);
      await p.dashboard.expectPendingApprovalVisible();
      await p.dashboard.approvePendingApprovalOnce();
      const allowOnceSigs = await allowOnce;
      expect(allowOnceSigs.length, 'allow-once must complete the signature').toBeGreaterThan(0);
      expect(verifies(allowOnceSigs, allowOnceMessage), 'allow-once signature must verify').toBe(true);
      await p.dashboard.expectPendingApprovalsEmpty();

      // --- Still ask: allow-once was one-shot, so the next request parks again. ---
      await signReady();
      const alwaysMessage = 'ef'.repeat(32);
      const always = shell.requestSign(alwaysMessage, 1);
      await p.dashboard.expectPendingApprovalVisible();
      // Always allow: approve this one AND persist a respond.sign Allow override.
      await p.dashboard.alwaysAllowPendingApproval();
      const alwaysSigs = await always;
      expect(alwaysSigs.length, 'always-allow must complete the signature').toBeGreaterThan(0);
      expect(verifies(alwaysSigs, alwaysMessage), 'always-allow signature must verify').toBe(true);

      // The override flipped to `allow` — verify on the permissions tab.
      await p.dashboard.openTab('permissions');
      await p.dashboard.expectPeerPolicyOverride(SIGN_RESPOND, 'allow');
      await p.dashboard.openTab('signer');

      // --- Auto-allowed: with the override now `allow`, the next request never parks. ---
      await signReady();
      const directMessage = '12'.repeat(32);
      const directSigs = await shell.requestSign(directMessage, 1);
      expect(directSigs.length, 'an allow-policy request must sign without parking').toBeGreaterThan(0);
      expect(verifies(directSigs, directMessage), 'auto-allowed signature must verify').toBe(true);
      await p.dashboard.expectPendingApprovalsEmpty();
    } finally {
      await shell?.close();
      await relay.close();
    }
  });
});
