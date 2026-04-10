import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import type net from 'node:net';

import { expect } from '@playwright/test';

import { test } from '../fixtures/extension';
import { assertNoncePoolHydrated, type RuntimeSnapshotResult } from '../support/runtime';
import { createGeneratedBrowserArtifacts, createPwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { IGLOO_PWA_DIR } from '../../shared/repo-paths';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../../igloo-pwa/support/state';
import { expectPwaDashboard, seedPwaState } from '../../igloo-pwa/support/ui';

type StaticServer = {
  origin: string;
  close: () => Promise<void>;
};

async function startPwaDistServer(): Promise<StaticServer> {
  const distDir = path.join(IGLOO_PWA_DIR, 'dist');
  const sockets = new Set<net.Socket>();
  const mimeTypes = new Map<string, string>([
    ['.html', 'text/html; charset=utf-8'],
    ['.js', 'text/javascript; charset=utf-8'],
    ['.css', 'text/css; charset=utf-8'],
    ['.json', 'application/json; charset=utf-8'],
    ['.svg', 'image/svg+xml'],
    ['.wasm', 'application/wasm'],
    ['.txt', 'text/plain; charset=utf-8'],
  ]);

  const server = http.createServer(async (req, res) => {
    try {
      const requestPath = req.url ? new URL(req.url, 'http://127.0.0.1').pathname : '/';
      const normalizedPath = requestPath === '/' ? '/index.html' : requestPath;
      const targetPath = path.join(distDir, normalizedPath.replace(/^\/+/, ''));
      const safePath = path.normalize(targetPath);
      if (!safePath.startsWith(path.normalize(distDir))) {
        res.writeHead(403, { 'content-type': 'text/plain; charset=utf-8' });
        res.end('forbidden');
        return;
      }

      let filePath = safePath;
      try {
        const stat = await fs.stat(filePath);
        if (stat.isDirectory()) {
          filePath = path.join(filePath, 'index.html');
        }
      } catch {
        filePath = path.join(distDir, 'index.html');
      }

      const ext = path.extname(filePath);
      const body = await fs.readFile(filePath);
      res.writeHead(200, {
        'content-type': mimeTypes.get(ext) ?? 'application/octet-stream',
        'cache-control': 'no-store',
      });
      res.end(body);
    } catch (error) {
      res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
      res.end(error instanceof Error ? error.message : String(error));
    }
  });

  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });

  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve());
  });

  const address = server.address();
  if (!address || typeof address === 'string') {
    throw new Error('Failed to resolve PWA dist server address');
  }

  return {
    origin: `http://127.0.0.1:${address.port}`,
    close: async () => {
      for (const socket of sockets) {
        socket.destroy();
      }
      await new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error) reject(error);
          else resolve();
        });
      });
    },
  };
}

async function readPwaRuntimeState(page: import('@playwright/test').Page) {
  return await page.evaluate((storageKey) => {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) return null;
    return JSON.parse(raw) as {
      runtimeSnapshot?: {
        active?: boolean;
        readiness?: { sign_ready?: boolean };
        runtime_status?: {
          peers?: Array<{
            pubkey: string;
            can_sign: boolean;
            incoming_available: number;
            outgoing_available: number;
          }>;
        };
      } | null;
    };
  }, PWA_STORAGE_KEY);
}

async function loadStoredPwaProfileAtOrigin(
  page: import('@playwright/test').Page,
  origin: string,
  label: string,
) {
  await page.goto(origin);
  const storedProfilesCard = page
    .getByRole('heading', { name: 'Stored Profiles' })
    .locator('xpath=ancestor::div[contains(@class, "igloo-card")]')
    .first();
  await expect(storedProfilesCard).toBeVisible();
  await storedProfilesCard.locator('button[aria-pressed]').filter({ hasText: label }).click();
  await storedProfilesCard.getByRole('button', { name: /Load Profile|Open Dashboard/ }).first().click();
}

test.describe('chrome <-> pwa browser pairing', () => {
  test.setTimeout(120_000);

  test('hydrates nonce pools between a chrome device and a pwa device over a local relay', async ({
    activateProfile,
    context,
    fetchRuntimeSnapshot,
    openExtensionPage,
    seedProfile,
  }) => {
    const relay = await startLocalRelay();
    const pwaServer = await startPwaDistServer();
    const pwaPage = await context.newPage();

    try {
      const generated = await createGeneratedBrowserArtifacts({
        groupName: 'Chrome PWA Pairing',
        labelPrefix: 'Browser Peer',
        threshold: 2,
        count: 2,
        relays: [relay.url],
      });
      const chromeArtifact = generated.shares[0];
      const pwaArtifact = generated.shares[1];
      const pwaSeed = createPwaStoredProfileSeed({
        artifact: pwaArtifact,
        groupPackageJson: generated.groupPackageJson,
        label: 'PWA Pairing Device',
      });

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
            groupName: 'Chrome PWA Pairing',
          },
        },
      });
      await activateProfile(chromeArtifact.profileId);

      await seedPwaState(
        pwaPage,
        buildPwaPersistedState({
          profiles: [pwaSeed],
        }),
      );
      await loadStoredPwaProfileAtOrigin(pwaPage, pwaServer.origin, 'PWA Pairing Device');
      await expectPwaDashboard(pwaPage, 'PWA Pairing Device');

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

      await expect
        .poll(async () => await readPwaRuntimeState(pwaPage), {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toEqual(expect.objectContaining({
          runtimeSnapshot: expect.objectContaining({
            active: true,
          }),
        }));

      let lastPwaState: Awaited<ReturnType<typeof readPwaRuntimeState>> = null;
      await expect
        .poll(async () => {
          lastPwaState = await readPwaRuntimeState(pwaPage);
          const runtime = lastPwaState?.runtimeSnapshot;
          if (!runtime?.active || !runtime.readiness?.sign_ready) {
            return 'waiting';
          }
          const peers = runtime.runtime_status?.peers ?? [];
          return peers.length === 1 && peers.some((peer) => peer.can_sign) ? 'hydrated' : 'waiting';
        }, {
          timeout: 20_000,
          intervals: [250, 500, 1_000],
        })
        .toBe('hydrated')
        .catch(() => {
          throw new Error(`PWA runtime never became sign-ready: ${JSON.stringify(lastPwaState, null, 2)}`);
        });

      const chromeOptions = await openExtensionPage('options.html');
      await expect(chromeOptions.getByText('sign-ready').first()).toBeVisible();
      await expect(pwaPage.getByText('sign-ready').first()).toBeVisible();

      await chromeOptions.close();
    } finally {
      await pwaPage.close().catch(() => undefined);
      await pwaServer.close().catch(() => undefined);
      await relay.close();
    }
  });
});
