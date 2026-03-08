import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import net from 'node:net';
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';

import {
  chromium,
  expect,
  test as base,
  type BrowserContext,
  type Page,
  type TestInfo,
  type Worker
} from '@playwright/test';

import { clearE2EEvents, getE2EEvents, logE2E, withLoggedStep } from '../../shared/observability';
import { IGLOO_CHROME_DIR, IGLOO_CHROME_DIST_DIR, REPO_ROOT_DIR } from '../../shared/repo-paths';
import { TEST_PEER_PUBLIC_KEY, TEST_PROFILE, TEST_PUBLIC_KEY } from './constants';
import { startLiveSignerFixture, type LiveSignerFixture } from './live-signer';
import { startTestServer, type TestServer } from './server';

type ExtensionFixtures = {
  context: BrowserContext;
  extensionId: string;
  serviceWorker: Worker;
  server: TestServer;
  liveSigner: LiveSignerFixture;
  demoHarness: DemoHarnessFixture;
  openExtensionPage: (path: string) => Promise<Page>;
  callOffscreenRpc: <T>(rpcType: string, payload?: Record<string, unknown>) => Promise<T>;
  runRuntimeControl: (action: 'closeOffscreen' | 'reloadExtension') => Promise<void>;
  reloadExtension: () => Promise<void>;
  seedProfile: (
    overrides?: Partial<typeof TEST_PROFILE> & {
      publicKey?: string;
      groupPublicKey?: string;
      peerPubkey?: string;
      onboardPackage?: string;
      onboardPassword?: string;
    }
  ) => Promise<void>;
  seedPermissionPolicies: (policies: SeedPermissionPolicy[]) => Promise<void>;
  seedPeerPolicies: (policies: SeedPeerPolicy[]) => Promise<void>;
  clearExtensionStorage: () => Promise<void>;
};

type SeedPermissionPolicy = {
  host: string;
  type: string;
  allow: boolean;
  createdAt?: number;
  kind?: number;
};

type SeedPeerPolicy = {
  pubkey: string;
  send: boolean;
  receive: boolean;
};

type DemoHarnessFixture = {
  relayUrl: string;
  recipient: string;
  onboardPackage: string;
  onboardPassword: string;
};

const extensionPath = IGLOO_CHROME_DIST_DIR;
const DEMO_HARNESS_DIR = path.join(REPO_ROOT_DIR, 'data', 'test-harness');
const DEMO_HARNESS_BUILD_SCRIPT = path.join(REPO_ROOT_DIR, 'scripts', 'build-demo-harness-binaries.sh');
let buildPrepared = false;

async function waitForHarnessArtifact(
  filePath: string,
  timeoutMs: number,
  minMtimeMs?: number
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const info = await stat(filePath);
      const freshEnough = typeof minMtimeMs !== 'number' || info.mtimeMs >= minMtimeMs;
      if (info.size > 0 && freshEnough) {
        return await readFile(filePath, 'utf8');
      }
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for harness artifact ${filePath}`);
}

async function waitForHarnessSocket(socketPath: string, minMtimeMs: number, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const info = await stat(socketPath);
      if (info.mtimeMs >= minMtimeMs) {
        return;
      }
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for harness socket ${socketPath}`);
}

async function waitForRelayPort(host: string, port: number, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ready = await new Promise<boolean>((resolve) => {
      const socket = net.createConnection({ host, port });
      socket.once('connect', () => {
        socket.destroy();
        resolve(true);
      });
      socket.once('error', () => {
        socket.destroy();
        resolve(false);
      });
    });
    if (ready) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for relay ${host}:${port}`);
}

function readHarnessLogs() {
  try {
    return execFileSync(
      'docker',
      ['compose', '-f', 'compose.test.yml', 'logs', '--tail=200', 'dev-relay', 'bifrost-demo'],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8'
      }
    );
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

async function startDemoHarnessFixture(): Promise<DemoHarnessFixture> {
  const relayHost = process.env.DEV_RELAY_EXTERNAL_HOST ?? '127.0.0.1';
  const relayPort = process.env.DEV_RELAY_PORT ?? '8194';
  const relayPortNumber = Number.parseInt(relayPort, 10);
  const relayUrl = `ws://${relayHost}:${relayPort}`;
  const recipient = process.env.BIFROST_DEMO_E2E_MEMBER ?? 'bob';
  const startedAt = Date.now();
  const packagePath = path.join(DEMO_HARNESS_DIR, `onboard-${recipient}.txt`);
  const passwordPath = path.join(DEMO_HARNESS_DIR, `onboard-${recipient}.password.txt`);
  const socketPath = path.join(
    DEMO_HARNESS_DIR,
    `bifrost-${process.env.BIFROST_DEMO_MEMBER ?? 'alice'}.sock`
  );

  await withLoggedStep('chrome.demo-harness', 'build-binaries', undefined, async () => {
    execFileSync(DEMO_HARNESS_BUILD_SCRIPT, {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit'
    });
  });

  await withLoggedStep('chrome.demo-harness', 'compose-up-relay', { relayUrl }, async () => {
    execFileSync(
      'docker',
      ['compose', '-f', 'compose.test.yml', 'up', '-d', '--build', 'dev-relay'],
      {
        cwd: REPO_ROOT_DIR,
        stdio: 'inherit'
      }
    );
  });

  try {
    await withLoggedStep(
      'chrome.demo-harness',
      'wait-relay-port',
      { relayUrl },
      async () => await waitForRelayPort(relayHost, relayPortNumber, 300_000)
    );
    await withLoggedStep('chrome.demo-harness', 'compose-up-demo', { recipient }, async () => {
      execFileSync(
        'docker',
        ['compose', '-f', 'compose.test.yml', 'up', '-d', '--build', '--no-deps', 'bifrost-demo'],
        {
          cwd: REPO_ROOT_DIR,
          stdio: 'inherit'
        }
      );
    });
    const [onboardPackage, onboardPassword] = await Promise.all([
      withLoggedStep(
        'chrome.demo-harness',
        'wait-onboard-package',
        { packagePath, recipient },
        async () => await waitForHarnessArtifact(packagePath, 300_000, startedAt)
      ),
      withLoggedStep(
        'chrome.demo-harness',
        'wait-onboard-password',
        { passwordPath, recipient },
        async () => await waitForHarnessArtifact(passwordPath, 300_000)
      ),
      withLoggedStep(
        'chrome.demo-harness',
        'wait-control-socket',
        { socketPath },
        async () => await waitForHarnessSocket(socketPath, startedAt, 300_000)
      )
    ]);

    logE2E('chrome.demo-harness', 'fixture-ready', {
      recipient,
      relayUrl,
      onboardLength: onboardPackage.trim().length
    });

    return {
      relayUrl,
      recipient,
      onboardPackage: onboardPackage.trim(),
      onboardPassword: onboardPassword.trim()
    };
  } catch (error) {
    try {
      await stopDemoHarnessFixture();
    } catch {
      // Preserve the original startup error.
    }
    throw new Error(
      `Failed to start demo harness: ${error instanceof Error ? error.message : String(error)}\n${readHarnessLogs()}`
    );
  }
}

async function stopDemoHarnessFixture() {
  await withLoggedStep('chrome.demo-harness', 'compose-down', undefined, async () => {
    execFileSync('docker', ['compose', '-f', 'compose.test.yml', 'down'], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit'
    });
  });
}

function buildExtensionOnce() {
  if (buildPrepared) return;
  logE2E('chrome.fixture', 'build-extension:start');
  execFileSync('npm', ['run', 'build'], {
    cwd: IGLOO_CHROME_DIR,
    stdio: 'inherit',
    env: {
      ...process.env,
      VITE_IGLOO_VERBOSE: process.env.VITE_IGLOO_VERBOSE ?? '1',
      VITE_IGLOO_DEBUG: process.env.VITE_IGLOO_DEBUG ?? '0'
    }
  });
  logE2E('chrome.fixture', 'build-extension:ok');
  buildPrepared = true;
}

async function waitForServiceWorker(context: BrowserContext) {
  const existing = context.serviceWorkers();
  if (existing.length > 0) return existing[0];
  return await context.waitForEvent('serviceworker');
}

async function gotoExtensionPage(page: Page, extensionId: string, targetPath: string) {
  const url = `chrome-extension://${extensionId}/${targetPath}`;
  await page.goto(url).catch(async (error) => {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes('interrupted by another navigation')) {
      throw error;
    }
  });
  await page.waitForURL(url);
}

async function openPageForStorage(context: BrowserContext, extensionId: string) {
  const page = await context.newPage();
  await gotoExtensionPage(page, extensionId, 'options.html');
  await expect(page.getByText('igloo-chrome')).toBeVisible();
  return page;
}

async function collectFailureBundle(context: BrowserContext, extensionId: string) {
  const page = await openPageForStorage(context, extensionId).catch(() => null);
  if (!page) {
    return {
      e2eEvents: getE2EEvents(),
      extensionDiagnosticsError: 'failed to open extension storage page'
    };
  }

  try {
    const runtimeDiagnostics = await page.evaluate(async () => {
      const response = await chrome.runtime.sendMessage({
        type: 'ext.offscreenRpc',
        rpcType: 'runtime.diagnostics'
      });
      return response?.ok ? response.result : { error: response?.error || 'runtime diagnostics unavailable' };
    });
    const status = await page.evaluate(async () => {
      const response = await chrome.runtime.sendMessage({ type: 'ext.getStatus' });
      return response?.ok ? response.result : { error: response?.error || 'status unavailable' };
    });
    return {
      e2eEvents: getE2EEvents(),
      runtimeDiagnostics,
      status
    };
  } finally {
    await page.close().catch(() => undefined);
  }
}

async function writeFailureBundle(
  testInfo: TestInfo,
  context: BrowserContext,
  extensionId: string
) {
  const filePath = testInfo.outputPath('observability-bundle.json');
  const bundle = await collectFailureBundle(context, extensionId);
  await writeFile(filePath, JSON.stringify(bundle, null, 2), 'utf8');
  await testInfo.attach('observability-bundle', {
    path: filePath,
    contentType: 'application/json'
  });
}

export const test = base.extend<ExtensionFixtures>({
  context: async ({}, use, testInfo) => {
    clearE2EEvents();
    buildExtensionOnce();
    const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-pw-'));
    const context = await withLoggedStep(
      'chrome.fixture',
      'launch-context',
      { userDataDir },
      async () =>
        await chromium.launchPersistentContext(userDataDir, {
          channel: 'chromium',
          headless: true,
          args: [
            `--disable-extensions-except=${extensionPath}`,
            `--load-extension=${extensionPath}`
          ]
        })
    );

    try {
      await use(context);
    } finally {
      const serviceWorkers = context.serviceWorkers();
      const extensionId =
        serviceWorkers.length > 0 ? new URL(serviceWorkers[0].url()).host : null;
      if (testInfo.status !== testInfo.expectedStatus && extensionId) {
        await writeFailureBundle(testInfo, context, extensionId).catch(() => undefined);
      }
      logE2E('chrome.fixture', 'close-context:start');
      await context.close();
      await rm(userDataDir, { recursive: true, force: true });
      logE2E('chrome.fixture', 'close-context:ok');
    }
  },

  serviceWorker: async ({ context }, use) => {
    const worker = await withLoggedStep('chrome.fixture', 'wait-service-worker', undefined, async () =>
      await waitForServiceWorker(context)
    );
    await use(worker);
  },

  extensionId: async ({ serviceWorker }, use) => {
    const extensionId = new URL(serviceWorker.url()).host;
    await use(extensionId);
  },

  server: async ({}, use) => {
    const server = await withLoggedStep('chrome.fixture', 'start-test-server', undefined, async () =>
      await startTestServer()
    );
    try {
      await use(server);
    } finally {
      logE2E('chrome.fixture', 'stop-test-server:start');
      await server.close();
      logE2E('chrome.fixture', 'stop-test-server:ok');
    }
  },

  liveSigner: async ({}, use) => {
    const fixture = await withLoggedStep('chrome.fixture', 'start-live-signer', undefined, async () =>
      await startLiveSignerFixture()
    );
    try {
      await use(fixture);
    } finally {
      logE2E('chrome.fixture', 'stop-live-signer:start');
      await fixture.close();
      logE2E('chrome.fixture', 'stop-live-signer:ok');
    }
  },

  demoHarness: async ({}, use) => {
    const fixture = await startDemoHarnessFixture();
    try {
      await use(fixture);
    } finally {
      await stopDemoHarnessFixture();
    }
  },

  openExtensionPage: async ({ context, extensionId }, use) => {
    await use(async (targetPath: string) => {
      const page = await context.newPage();
      await gotoExtensionPage(page, extensionId, targetPath);
      return page;
    });
  },

  callOffscreenRpc: async ({ context, extensionId }, use) => {
    await use(async <T>(rpcType: string, payload?: Record<string, unknown>) => {
      return await withLoggedStep(
        'chrome.fixture',
        'offscreen-rpc',
        { rpcType },
        async () => {
          const page = await openPageForStorage(context, extensionId);
          try {
            const result = await page.evaluate(
              async ({ nextRpcType, nextPayload }) => {
                await chrome.runtime.sendMessage({ type: 'ext.getStatus' });
                const response = await chrome.runtime.sendMessage({
                  type: 'ext.offscreenRpc',
                  rpcType: nextRpcType,
                  payload: nextPayload
                });
                if (!response?.ok) {
                  throw new Error(response?.error || 'Offscreen rpc failed');
                }
                return response.result;
              },
              { nextRpcType: rpcType, nextPayload: payload }
            );
            return result as T;
          } finally {
            await page.close();
          }
        }
      );
    });
  },

  runRuntimeControl: async ({ context, extensionId }, use) => {
    await use(async (action: 'closeOffscreen' | 'reloadExtension') => {
      await withLoggedStep(
        'chrome.fixture',
        'runtime-control',
        { action },
        async () => {
          const page = await openPageForStorage(context, extensionId);
          try {
            await page.evaluate(async (nextAction) => {
              const response = (await chrome.runtime.sendMessage({
                type: 'ext.runtimeControl',
                action: nextAction
              })) as { ok?: boolean; error?: string } | undefined;
              if (!response?.ok) {
                throw new Error(response?.error || 'Runtime control failed');
              }
            }, action);
          } finally {
            await page.close();
          }
        }
      );
    });
  },

  reloadExtension: async ({ context, extensionId }, use) => {
    await use(async () => {
      await withLoggedStep('chrome.fixture', 'reload-extension', undefined, async () => {
        const page = await openPageForStorage(context, extensionId);
        try {
          await page.evaluate(async () => {
            const response = (await chrome.runtime.sendMessage({
              type: 'ext.runtimeControl',
              action: 'reloadExtension'
            })) as { ok?: boolean; error?: string } | undefined;
            if (!response?.ok) {
              throw new Error(response?.error || 'Extension reload failed');
            }
          });
        } finally {
          await page.close().catch(() => undefined);
        }
        await context.waitForEvent('serviceworker', { timeout: 5_000 }).catch(() => undefined);
        await new Promise((resolve) => setTimeout(resolve, 500));
      });
    });
  },

  seedProfile: async ({ context, extensionId }, use) => {
    await use(async (overrides = {}) => {
      await withLoggedStep(
        'chrome.fixture',
        'seed-profile',
        {
          relays: overrides.relays ?? TEST_PROFILE.relays,
          hasOnboardPackage: typeof overrides.onboardPackage === 'string'
        },
        async () => {
          const page = await openPageForStorage(context, extensionId);
          await page.evaluate(
            async ({ profile, publicKey, groupPublicKey, peerPubkey }) => {
              const localProfile = {
                ...profile,
                ...(groupPublicKey
                  ? { groupPublicKey }
                  : publicKey
                    ? { groupPublicKey: publicKey }
                    : {}),
                ...(publicKey ? { publicKey } : {}),
                ...(peerPubkey ? { peerPubkey } : {})
              };
              localStorage.removeItem('igloo.ext.runtimeSnapshot');
              localStorage.setItem('igloo.v2.profile', JSON.stringify(localProfile));
              await chrome.storage.local.set({
                'igloo.ext.profile': {
                  ...localProfile
                }
              });
            },
            {
              profile: { ...TEST_PROFILE, ...overrides },
              publicKey: overrides.publicKey,
              groupPublicKey: overrides.groupPublicKey,
              peerPubkey: overrides.peerPubkey
            }
          );
          await page.close();
        }
      );
    });
  },

  seedPermissionPolicies: async ({ context, extensionId }, use) => {
    await use(async (policies) => {
      const page = await openPageForStorage(context, extensionId);
      await page.evaluate(async (entries) => {
        await chrome.storage.local.set({
          'igloo.ext.permissions': entries.map((entry) => ({
            ...entry,
            createdAt: entry.createdAt ?? Date.now()
          }))
        });
      }, policies);
      await page.close();
    });
  },

  seedPeerPolicies: async ({ context, extensionId }, use) => {
    await use(async (policies) => {
      const page = await openPageForStorage(context, extensionId);
      await page.evaluate(
        async (entries) => {
          localStorage.setItem('igloo.policies', JSON.stringify(entries));
          await chrome.storage.local.set({
            'igloo.ext.peerPolicies': entries
          });
        },
        policies
      );
      await page.close();
    });
  },

  clearExtensionStorage: async ({ context, extensionId }, use) => {
    await use(async () => {
      const page = await openPageForStorage(context, extensionId);
      await page.evaluate(async () => {
        localStorage.removeItem('igloo.v2.profile');
        localStorage.removeItem('igloo.policies');
        localStorage.removeItem('igloo.ext.runtimeSnapshot');
        await chrome.storage.local.clear();
      });
      await page.close();
    });
  }
});

export { expect, TEST_PEER_PUBLIC_KEY, TEST_PROFILE, TEST_PUBLIC_KEY };
