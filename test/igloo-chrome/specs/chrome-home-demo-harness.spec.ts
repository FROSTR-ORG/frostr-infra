import { expect } from '@playwright/test';
import { COMMAND_TYPE } from '../../../repos/igloo-chrome/src/extension/messages';

import { test } from '../fixtures/extension';
import { onboardLiveSignerProfile } from '../support/onboarding';
import { launchIglooHome } from '../../igloo-home/fixtures/app';
import {
  aliceRuntimeDiagnostics,
  ensureDemoHarness,
} from '../../igloo-home/fixtures/harness';

type RuntimePeer = {
  pubkey: string;
  incoming_available?: number;
  outgoing_available?: number;
  can_sign?: boolean;
  online?: boolean;
};

type ChromeRuntimeStatus = {
  runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
  status: {
    readiness?: {
      restore_complete?: boolean;
    } | null;
    status?: {
      pending_ops?: number;
    } | null;
    peers?: RuntimePeer[];
  } | null;
};

type HomeRuntimeSnapshot = {
  active: boolean;
  runtime_status?: {
    peers?: RuntimePeer[];
  } | null;
  readiness?: {
    restore_complete?: boolean;
    sign_ready?: boolean;
  } | null;
  runtime_diagnostics?: unknown;
  daemon_log_lines?: string[];
};

async function refreshChromePeers(openExtensionPage: (path: string) => Promise<import('@playwright/test').Page>) {
  const page = await openExtensionPage('options.html');
  try {
    await page.evaluate(async (messageType) => {
      const response = (await chrome.runtime.sendMessage({
        type: messageType,
      })) as { ok?: boolean; error?: string } | undefined;
      if (!response?.ok) {
        throw new Error(response?.error || 'Failed to refresh extension peers');
      }
    }, COMMAND_TYPE.RUNTIME_REFRESH_PEERS);
  } finally {
    await page.close().catch(() => undefined);
  }
}

function assertPeerNonceReady(label: string, peers: RuntimePeer[] | undefined, peerPubkey: string) {
  const peer = peers?.find(entry => entry.pubkey === peerPubkey);
  if (!peer) {
    throw new Error(`${label}: missing peer ${peerPubkey}\n${JSON.stringify(peers ?? [], null, 2)}`);
  }
  if (!peer.online) {
    throw new Error(`${label}: peer ${peerPubkey} is not online\n${JSON.stringify(peer, null, 2)}`);
  }
  if (!peer.can_sign || (peer.incoming_available ?? 0) <= 0) {
    throw new Error(`${label}: peer ${peerPubkey} is online but not nonce-ready\n${JSON.stringify(peer, null, 2)}`);
  }
}

test.describe('demo harness chrome <-> home pairing @live', () => {
  test.setTimeout(360_000);

  test('onboards chrome and home from igloo-demo and reaches symmetric nonce readiness after refresh', async ({
    activateProfile,
    clearExtensionStorage,
    fetchRuntimeDiagnostics,
    fetchRuntimeStatus,
    openExtensionPage,
  }) => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');
    test.skip(!process.env.IGLOO_DEMO_LIVE_REPRO, 'set IGLOO_DEMO_LIVE_REPRO=1 to run the unresolved live demo repro');

    const harness = await ensureDemoHarness();
    const home = await launchIglooHome();
    let homeProfileId: string | null = null;
    let lastChromeStatus: ChromeRuntimeStatus | null = null;
    let lastHomeSnapshot: HomeRuntimeSnapshot | null = null;

    try {
      const bobInvitee = harness.invitees.bob;
      const carolInvitee = harness.invitees.carol;
      if (!bobInvitee || !carolInvitee) {
        throw new Error(`expected bob and carol onboarding artifacts\n${JSON.stringify(harness.invitees, null, 2)}`);
      }

      await clearExtensionStorage();
      const storedProfile = await onboardLiveSignerProfile(
        async (targetPath: string) => await openExtensionPage(targetPath),
        {
          groupName: 'Demo Harness Bob',
          onboardPackage: bobInvitee.onboardPackage,
          onboardPassword: bobInvitee.onboardPassword,
          publicKey: '',
          peerPubkey: '',
        },
        'Demo Harness Bob'
      );
      await activateProfile(storedProfile.id!);

      await expect
        .poll(async () => {
          lastChromeStatus = await fetchRuntimeStatus<ChromeRuntimeStatus>();
          return lastChromeStatus.runtime;
        }, {
          timeout: 30_000,
          intervals: [250, 500, 1_000],
        })
        .toMatch(/ready|degraded/);

      const connected = await home.request<{
        preview: {
          label: string;
          share_public_key: string;
        };
      }>('connect_onboarding_package', {
        onboarding_password: carolInvitee.onboardPassword,
        package: carolInvitee.onboardPackage,
      });
      expect(connected.preview.label).toBeTruthy();

      const imported = await home.request<{
        status: string;
        profile?: { id: string };
        diagnostics?: unknown;
      }>('finalize_connected_onboarding', {
        label: 'Demo Harness Carol',
        relay_profile: null,
        passphrase: 'playwright-password',
      });
      expect(imported.status).toBe('profile_created');
      homeProfileId = imported.profile?.id ?? null;
      expect(homeProfileId).toBeTruthy();

      const started = await home.request<{ active: boolean }>('start_profile_session', {
        profile_id: homeProfileId,
        passphrase: 'playwright-password',
      });
      expect(started.active).toBe(true);

      await expect
        .poll(async () => {
          lastChromeStatus = await fetchRuntimeStatus<ChromeRuntimeStatus>();
          return {
            runtime: lastChromeStatus.runtime,
            restoreComplete: lastChromeStatus.status?.readiness?.restore_complete ?? false,
            pendingOps: lastChromeStatus.status?.status?.pending_ops ?? null,
          };
        }, {
          timeout: 45_000,
          intervals: [250, 500, 1_000],
        })
        .toEqual({
          runtime: 'ready',
          restoreComplete: true,
          pendingOps: 0,
        });

      await refreshChromePeers(openExtensionPage);
      await home.request<{
        attempted: number;
        refreshed: number;
        failures: Array<{ peer: string; error: string }>;
      }>('refresh_runtime_peers');

      await expect
        .poll(async () => {
          lastChromeStatus = await fetchRuntimeStatus<ChromeRuntimeStatus>();
          lastHomeSnapshot = await home.request<HomeRuntimeSnapshot>('profile_runtime_snapshot', {
            profile_id: homeProfileId,
          });
          assertPeerNonceReady('chrome runtime status', lastChromeStatus.status?.peers, carolInvitee.pubkeyXOnly);
          assertPeerNonceReady('home runtime snapshot', lastHomeSnapshot.runtime_status?.peers, bobInvitee.pubkeyXOnly);
          return 'ready';
        }, {
          timeout: 45_000,
          intervals: [250, 500, 1_000],
        })
        .toBe('ready');
    } catch (error) {
      const [chromeDiagnostics, homeSnapshot, aliceDiagnostics] = await Promise.all([
        fetchRuntimeDiagnostics<unknown>().catch(cause => ({ diagnostics_error: String(cause) })),
        homeProfileId
          ? home.request<HomeRuntimeSnapshot>('profile_runtime_snapshot', { profile_id: homeProfileId }).catch(cause => ({
              snapshot_error: String(cause),
            }))
          : Promise.resolve({ snapshot_error: 'home profile not created' }),
        aliceRuntimeDiagnostics(harness).catch(cause => ({ diagnostics_error: String(cause) })),
      ]);
      throw new Error(
        [
          error instanceof Error ? error.message : String(error),
          `last chrome status: ${JSON.stringify(lastChromeStatus, null, 2)}`,
          `last home snapshot: ${JSON.stringify(lastHomeSnapshot, null, 2)}`,
          `chrome diagnostics: ${JSON.stringify(chromeDiagnostics, null, 2)}`,
          `home snapshot: ${JSON.stringify(homeSnapshot, null, 2)}`,
          `alice diagnostics: ${JSON.stringify(aliceDiagnostics, null, 2)}`,
        ].join('\n\n')
      );
    } finally {
      await home.request('stop_signer').catch(() => undefined);
      await home.close().catch(() => undefined);
      await harness.cleanup();
    }
  });
});
