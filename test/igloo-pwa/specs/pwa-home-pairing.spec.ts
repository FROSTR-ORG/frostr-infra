import { expect, test } from '@playwright/test';

import { createGeneratedBrowserArtifacts, createPwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { launchIglooHome } from '../../igloo-home/fixtures/app';
import { buildPwaPersistedState } from '../support/state';
import { expectPwaDashboard, loadStoredPwaProfile, seedPwaState } from '../support/ui';

type HomeRuntimeSnapshot = {
  active: boolean;
  readiness?: {
    runtime_ready?: boolean;
    restore_complete?: boolean;
    sign_ready?: boolean;
    ecdh_ready?: boolean;
  } | null;
  runtime_status?: {
    peers?: Array<{
      pubkey: string;
      incoming_available?: number;
      outgoing_available?: number;
      can_sign?: boolean;
      online?: boolean;
    }>;
  } | null;
};

function assertPwaRuntimeHydrated(state: unknown, expectedPeers: number) {
  const runtime = (state as {
    runtimeSnapshot?: {
      active?: boolean;
      readiness?: { sign_ready?: boolean; restore_complete?: boolean };
      runtime_status?: {
        peers?: Array<{
          pubkey: string;
          incoming_available: number;
          outgoing_available: number;
          can_sign: boolean;
        }>;
      };
    } | null;
  } | null)?.runtimeSnapshot;
  if (!runtime?.active || !runtime.readiness?.restore_complete || !runtime.readiness?.sign_ready) {
    throw new Error(`pwa runtime is not sign-ready\n${JSON.stringify(state, null, 2)}`);
  }
  const peers = runtime.runtime_status?.peers ?? [];
  if (peers.length !== expectedPeers) {
    throw new Error(`expected ${expectedPeers} pwa peers, got ${peers.length}\n${JSON.stringify(peers, null, 2)}`);
  }
  if (!peers.some((peer) => peer.can_sign || peer.incoming_available > 0 || peer.outgoing_available > 0)) {
    throw new Error(`pwa nonce pool never hydrated\n${JSON.stringify(peers, null, 2)}`);
  }
}

function assertHomeRuntimeHydrated(snapshot: HomeRuntimeSnapshot, expectedPeers: number) {
  if (!snapshot.active || !snapshot.readiness?.restore_complete || !snapshot.readiness?.sign_ready) {
    throw new Error(`home runtime is not sign-ready\n${JSON.stringify(snapshot, null, 2)}`);
  }
  const peers = snapshot.runtime_status?.peers ?? [];
  if (peers.length !== expectedPeers) {
    throw new Error(`expected ${expectedPeers} home peers, got ${peers.length}\n${JSON.stringify(peers, null, 2)}`);
  }
  if (!peers.some((peer) => peer.can_sign || (peer.incoming_available ?? 0) > 0 || (peer.outgoing_available ?? 0) > 0)) {
    throw new Error(`home nonce pool never hydrated\n${JSON.stringify(peers, null, 2)}`);
  }
}

async function readPwaRuntimeState(page: import('@playwright/test').Page) {
  return await page.evaluate(() => {
    const raw = window.localStorage.getItem('igloo-pwa.state.v1');
    return raw ? JSON.parse(raw) : null;
  });
}

test.describe('pwa <-> home pairing', () => {
  test.setTimeout(120_000);

  test('hydrates nonce pools between a pwa device and an igloo-home device over a local relay', async ({ page }) => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const relay = await startLocalRelay();
    const home = await launchIglooHome();

    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'PWA Home Pairing',
        labelPrefix: 'Host Pair',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const pwaArtifact = generated.shares[0];
      const homeArtifact = generated.shares[1];
      const pwaSeed = createPwaStoredProfileSeed({
        artifact: pwaArtifact,
        groupPackageJson: generated.groupPackageJson,
        label: 'PWA Pairing Device',
      });

      await seedPwaState(page, buildPwaPersistedState({ profiles: [pwaSeed] }));
      await loadStoredPwaProfile(page, 'PWA Pairing Device');
      await expectPwaDashboard(page, 'PWA Pairing Device');

      const imported = await home.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Home Pairing Device',
        relay_urls: [relay.url],
        relay_profile: null,
        passphrase: 'playwright-password',
        group_package_json: generated.groupPackageJson,
        share_package_json: homeArtifact.sharePackageJson,
      });
      expect(imported.status).toBe('profile_created');
      expect(imported.profile?.id).toBeTruthy();

      const homeProfileId = imported.profile!.id;
      const started = await home.request<{ active: boolean }>('start_profile_session', {
        profile_id: homeProfileId,
        passphrase: 'playwright-password',
      });
      expect(started.active).toBe(true);

      let lastPwaState: unknown = null;
      await expect
        .poll(async () => {
          lastPwaState = await readPwaRuntimeState(page);
          try {
            assertPwaRuntimeHydrated(lastPwaState, 1);
            return 'hydrated';
          } catch {
            return 'waiting';
          }
        }, {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toBe('hydrated')
        .catch(() => {
          throw new Error(`PWA runtime never became sign-ready: ${JSON.stringify(lastPwaState, null, 2)}`);
        });

      let lastHomeSnapshot: HomeRuntimeSnapshot | null = null;
      await expect
        .poll(async () => {
          lastHomeSnapshot = await home.request<HomeRuntimeSnapshot>('profile_runtime_snapshot', {
            profile_id: homeProfileId,
          });
          try {
            assertHomeRuntimeHydrated(lastHomeSnapshot, 1);
            return 'hydrated';
          } catch {
            return 'waiting';
          }
        }, {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toBe('hydrated')
        .catch(() => {
          throw new Error(`Home runtime never became sign-ready: ${JSON.stringify(lastHomeSnapshot, null, 2)}`);
        });
    } finally {
      await home.request('stop_signer').catch(() => undefined);
      await home.close().catch(() => undefined);
      await relay.close();
    }
  });
});
