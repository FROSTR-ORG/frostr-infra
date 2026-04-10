import { expect } from '@playwright/test';

import { test } from '../fixtures/extension';
import { assertNoncePoolHydrated, type RuntimeSnapshotResult } from '../support/runtime';
import { createGeneratedBrowserArtifacts } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { launchIglooHome } from '../../igloo-home/fixtures/app';

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
  runtime_diagnostics?: unknown;
  daemon_log_lines?: string[];
};

function assertHomeRuntimeHydrated(label: string, snapshot: HomeRuntimeSnapshot, expectedPeers: number) {
  if (!snapshot.active) {
    throw new Error(`${label}: home runtime is not active`);
  }
  if (!snapshot.readiness?.restore_complete || !snapshot.readiness?.sign_ready) {
    throw new Error(`${label}: home runtime is not sign-ready\n${JSON.stringify(snapshot, null, 2)}`);
  }
  const peers = snapshot.runtime_status?.peers ?? [];
  if (peers.length !== expectedPeers) {
    throw new Error(`${label}: expected ${expectedPeers} peers, got ${peers.length}\n${JSON.stringify(peers, null, 2)}`);
  }
  if (!peers.some((peer) => peer.can_sign || (peer.incoming_available ?? 0) > 0 || (peer.outgoing_available ?? 0) > 0)) {
    throw new Error(`${label}: nonce pool never hydrated\n${JSON.stringify(peers, null, 2)}`);
  }
}

test.describe('chrome <-> home pairing', () => {
  test.setTimeout(120_000);

  test('hydrates nonce pools between a chrome device and an igloo-home device over a local relay', async ({
    activateProfile,
    fetchRuntimeSnapshot,
    seedProfile,
  }) => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const relay = await startLocalRelay();
    const home = await launchIglooHome();

    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Chrome Home Pairing',
        labelPrefix: 'Host Pair',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const chromeArtifact = generated.shares[0];
      const homeArtifact = generated.shares[1];

      await seedProfile({
        id: chromeArtifact.profileId,
        groupName: 'Chrome Pairing Device',
        publicKey: generated.groupPublicKey,
        groupPublicKey: generated.groupPublicKey,
        sharePublicKey: chromeArtifact.sharePublicKey,
        peerPubkey: undefined,
        relays: [relay.url],
        profilePayload: {
          ...chromeArtifact.profilePayload,
          device: {
            ...chromeArtifact.profilePayload.device,
            name: 'Chrome Pairing Device',
          },
          groupPackage: {
            ...chromeArtifact.profilePayload.groupPackage,
            groupName: 'Chrome Home Pairing',
          },
        },
      });
      await activateProfile(chromeArtifact.profileId);

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

      await expect
        .poll(async () => await fetchRuntimeSnapshot<RuntimeSnapshotResult>(), {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toEqual(expect.objectContaining({
          runtime: expect.stringMatching(/ready|degraded/),
        }));

      await expect
        .poll(async () => {
          const snapshot = await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
          try {
            assertNoncePoolHydrated('chrome runtime snapshot', snapshot, 1, 1);
            return 'hydrated';
          } catch {
            return 'waiting';
          }
        }, {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toBe('hydrated');

      let lastHomeSnapshot: HomeRuntimeSnapshot | null = null;
      await expect
        .poll(async () => {
          lastHomeSnapshot = await home.request<HomeRuntimeSnapshot>('profile_runtime_snapshot', {
            profile_id: homeProfileId,
          });
          try {
            assertHomeRuntimeHydrated('home runtime snapshot', lastHomeSnapshot, 1);
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
