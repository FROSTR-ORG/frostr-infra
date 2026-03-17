import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
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
import { onboardLiveSignerProfile, type StoredProfile as OnboardedStoredProfile } from '../support/onboarding';
import {
  fetchExtensionStatusFromPage,
  fetchRuntimeDiagnosticsFromPage,
  fetchWorkerStorageSnapshot
} from '../support/extension-status';
import { TEST_PEER_PUBLIC_KEY, TEST_PROFILE, TEST_PUBLIC_KEY } from './constants';
import {
  startLiveSignerFixture,
  type LiveSignerController,
  type LiveSignerFixture
} from './live-signer';
import { startTestServer, type TestServer } from './server';

type ExtensionFixtures = {
  context: BrowserContext;
  extensionId: string;
  serviceWorker: Worker;
  server: TestServer;
  liveSigner: LiveSignerFixture;
  stableLiveSigner: LiveSignerFixture;
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

type WorkerFixtures = {
  liveSignerWorker: LiveSignerController;
  onboardedLiveSignerProfile: OnboardedStoredProfile;
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
  cleanup: () => Promise<void>;
};

const extensionPath = IGLOO_CHROME_DIST_DIR;
const DEMO_HARNESS_BUILD_SCRIPT = path.join(REPO_ROOT_DIR, 'scripts', 'build-demo-harness-binaries.sh');
const EXTENSION_MANIFEST_PATH = path.join(IGLOO_CHROME_DIST_DIR, 'manifest.json');
const DEMO_RELAY_HOST = process.env.DEV_RELAY_EXTERNAL_HOST ?? 'localhost';
const DEMO_RELAY_PORT = Number(process.env.IGLOO_DEMO_RELAY_PORT ?? '43194');
let buildPrepared = false;
let workerOnboardingFailureBundle: Record<string, unknown> | null = null;
const extensionPageErrors = new Map<string, string[]>();

function extensionLaunchArgs() {
  const secureOrigins = [
    `http://127.0.0.1:${DEMO_RELAY_PORT}`,
    `http://localhost:${DEMO_RELAY_PORT}`
  ];
  return [
    `--unsafely-treat-insecure-origin-as-secure=${secureOrigins.join(',')}`,
    `--disable-extensions-except=${extensionPath}`,
    `--load-extension=${extensionPath}`
  ];
}

function recordPageDiagnostic(page: Page, message: string) {
  const existing = extensionPageErrors.get(page.url()) ?? [];
  existing.push(message);
  if (existing.length > 25) {
    existing.splice(0, existing.length - 25);
  }
  extensionPageErrors.set(page.url(), existing);
}

async function waitForHarnessArtifact(filePath: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const info = await stat(filePath);
      if (info.size > 0) {
        return await readFile(filePath, 'utf8');
      }
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for harness artifact ${filePath}`);
}

async function waitForHarnessSocket(socketPath: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      await stat(socketPath);
      return;
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

function readHarnessLogs(projectName: string, env: NodeJS.ProcessEnv) {
  try {
    return execFileSync(
      'docker',
      ['compose', '-p', projectName, '-f', 'compose.test.yml', 'logs', '--tail=200', 'dev-relay', 'igloo-demo'],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8',
        env
      }
    );
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

async function startDemoHarnessFixture(): Promise<DemoHarnessFixture> {
  const projectName = `igloo-chrome-${process.pid}-${randomBytes(4).toString('hex')}`;
  const hostArtifactDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-demo-'));
  const demoMember = process.env.IGLOO_SHELL_DEMO_MEMBER ?? 'alice';
  const inviteMembers = process.env.IGLOO_SHELL_DEMO_INVITE_MEMBERS ?? 'bob,carol';
  const containerArtifactDir = `/workspace/test-harness/${projectName}`;
  const relayPortNumber = DEMO_RELAY_PORT;
  const relayHost = DEMO_RELAY_HOST;
  const relayPort = String(relayPortNumber);
  const relayUrl = `ws://${relayHost}:${relayPort}`;
  const recipient = process.env.IGLOO_SHELL_DEMO_E2E_MEMBER ?? 'bob';
  const composeEnv = {
    ...process.env,
    DEV_RELAY_PORT: relayPort,
    DEV_RELAY_EXTERNAL_HOST: relayHost,
    IGLOO_TRACE: process.env.IGLOO_TRACE ?? '',
    IGLOO_TRACE_LEVEL: process.env.IGLOO_TRACE_LEVEL ?? '',
    IGLOO_SHELL_DEMO_MEMBER: demoMember,
    IGLOO_SHELL_DEMO_INVITE_MEMBERS: inviteMembers,
    IGLOO_SHELL_DEMO_HOST_ARTIFACT_DIR: hostArtifactDir,
    IGLOO_SHELL_DEMO_ARTIFACT_DIR: containerArtifactDir,
    IGLOO_SHELL_DEMO_DIR: `${containerArtifactDir}/demo-2of3`,
    IGLOO_SHELL_DEMO_CONTROL_SOCKET: `${containerArtifactDir}/igloo-shell-${demoMember}.sock`,
    IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE: `${containerArtifactDir}/igloo-shell-${demoMember}.token`
  };
  const packagePath = path.join(hostArtifactDir, `onboard-${recipient}.txt`);
  const passwordPath = path.join(hostArtifactDir, `onboard-${recipient}.password.txt`);
  const socketPath = path.join(hostArtifactDir, `igloo-shell-${demoMember}.sock`);

  const cleanup = async () => {
    await withLoggedStep('chrome.demo-harness', 'compose-down', { projectName }, async () => {
      try {
        execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', 'down', '-v'], {
          cwd: REPO_ROOT_DIR,
          stdio: 'inherit',
          env: composeEnv
        });
      } catch {
        // Best-effort cleanup only.
      }
    });
    await cleanupArtifactDir(hostArtifactDir);
  };

  await withLoggedStep('chrome.demo-harness', 'build-binaries', undefined, async () => {
    execFileSync(DEMO_HARNESS_BUILD_SCRIPT, {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit'
    });
  });

  await withLoggedStep('chrome.demo-harness', 'compose-up-relay', { relayUrl }, async () => {
    execCompose(projectName, composeEnv, ['up', '-d', '--build', 'dev-relay']);
  });

  try {
    await withLoggedStep(
      'chrome.demo-harness',
      'wait-relay-port',
      { relayUrl },
      async () => await waitForRelayPort(relayHost, relayPortNumber, 300_000)
    );
    await withLoggedStep('chrome.demo-harness', 'compose-up-demo', { recipient }, async () => {
      execCompose(projectName, composeEnv, ['up', '-d', '--build', '--no-deps', 'igloo-demo']);
    });
    const [onboardPackage, onboardPassword] = await Promise.all([
      withLoggedStep(
        'chrome.demo-harness',
        'wait-onboard-package',
        { packagePath, recipient },
        async () => await waitForHarnessArtifact(packagePath, 300_000)
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
        async () => await waitForHarnessSocket(socketPath, 300_000)
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
      onboardPassword: onboardPassword.trim(),
      cleanup
    };
  } catch (error) {
    try {
      await cleanup();
    } catch {
      // Preserve the original startup error.
    }
    throw new Error(
      `Failed to start demo harness: ${error instanceof Error ? error.message : String(error)}\n${readHarnessLogs(projectName, composeEnv)}`
    );
  }
}

function execCompose(projectName: string, env: NodeJS.ProcessEnv, args: string[]) {
  execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', ...args], {
    cwd: REPO_ROOT_DIR,
    stdio: 'inherit',
    env
  });
}

async function cleanupArtifactDir(dir: string) {
  try {
    await rm(dir, { recursive: true, force: true });
    return;
  } catch {
    try {
      execFileSync(
        'docker',
        [
          'run',
          '--rm',
          '-v',
          `${dir}:/target`,
          'ubuntu:24.04',
          'bash',
          '-lc',
          'chmod -R a+rwX /target || true; rm -rf /target/* /target/.[!.]* /target/..?* || true'
        ],
        {
          cwd: REPO_ROOT_DIR,
          stdio: 'ignore'
        }
      );
    } catch {
      // Best-effort only.
    }
    await rm(dir, { recursive: true, force: true }).catch(() => undefined);
  }
}

function buildExtensionOnce() {
  if (buildPrepared) return;
  if (!existsSync(EXTENSION_MANIFEST_PATH)) {
    throw new Error(
      `Missing built extension at ${EXTENSION_MANIFEST_PATH}. Run the Playwright global setup or npm run build in repos/igloo-chrome first.`
    );
  }
  logE2E('chrome.fixture', 'build-extension:ready', {
    manifestPath: EXTENSION_MANIFEST_PATH
  });
  buildPrepared = true;
}

async function waitForServiceWorker(context: BrowserContext) {
  const existing = context.serviceWorkers();
  if (existing.length > 0) return existing[0];
  return await context.waitForEvent('serviceworker');
}

async function gotoExtensionPage(
  page: Page,
  extensionId: string,
  targetPath: string,
  options?: { waitForAppReady?: boolean }
) {
  const url = `chrome-extension://${extensionId}/${targetPath}`;
  await page.goto(url).catch(async (error) => {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes('interrupted by another navigation')) {
      throw error;
    }
  });
  await page.waitForURL(url);
  await page.waitForLoadState('domcontentloaded');
  if (options?.waitForAppReady && targetPath === 'options.html') {
    await page
      .waitForFunction(() => document.body.dataset.appHydrating === 'false', undefined, {
        timeout: 3_000
      })
      .catch((error) => {
        recordPageDiagnostic(
          page,
          `app-ready-timeout: ${error instanceof Error ? error.message : String(error)}`
        );
      });
  }
}

async function openPageForStorage(context: BrowserContext, extensionId: string) {
  const page = await context.newPage();
  await gotoExtensionPage(page, extensionId, 'options.html', { waitForAppReady: false });
  return page;
}

async function collectFailureBundle(context: BrowserContext, extensionId: string) {
  const page = await openPageForStorage(context, extensionId).catch(() => null);
  if (!page) {
    return {
      e2eEvents: getE2EEvents(),
      extensionDiagnosticsError: 'failed to open extension storage page',
      workerOnboardingFailureBundle
    };
  }

  try {
    const runtimeDiagnostics = await fetchRuntimeDiagnosticsFromPage(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error)
    }));
    const status = await fetchExtensionStatusFromPage(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error)
    }));
    const storageSnapshot = await fetchWorkerStorageSnapshot(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error)
    }));
    return {
      e2eEvents: getE2EEvents(),
      runtimeDiagnostics,
      status,
      storageSnapshot,
      pageDiagnostics: Object.fromEntries(extensionPageErrors),
      workerOnboardingFailureBundle
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

function isIgnorableContextCloseError(error: unknown) {
  if (!(error instanceof Error)) {
    return false;
  }

  return (
    error.message.includes('ENOENT: no such file or directory') &&
    (error.message.includes('.playwright-artifacts-') ||
      error.message.includes('recording') ||
      error.message.includes('.zip'))
  );
}

async function closeContextSafely(context: BrowserContext) {
  try {
    await context.close();
  } catch (error) {
    if (!isIgnorableContextCloseError(error)) {
      throw error;
    }
    logE2E('chrome.fixture', 'close-context:ignoring-playwright-artifact-error', {
      error_message: error.message
    });
  }
}

export const test = base.extend<ExtensionFixtures, WorkerFixtures>({
  context: async ({}, use, testInfo) => {
    clearE2EEvents();
    workerOnboardingFailureBundle = null;
    extensionPageErrors.clear();
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
          args: extensionLaunchArgs()
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
      await closeContextSafely(context);
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

  liveSignerWorker: [async ({}, use) => {
    const controller = await withLoggedStep(
      'chrome.fixture',
      'start-live-signer-worker',
      undefined,
      async () => await startLiveSignerFixture()
    );
    try {
      await use(controller);
    } finally {
      logE2E('chrome.fixture', 'stop-live-signer-worker:start');
      await controller.close();
      logE2E('chrome.fixture', 'stop-live-signer-worker:ok');
    }
  }, { scope: 'worker', timeout: 180_000 }],

  onboardedLiveSignerProfile: [async ({ liveSignerWorker }, use) => {
    buildExtensionOnce();
    const fixture = await withLoggedStep(
      'chrome.fixture',
      'prepare-onboarded-live-profile',
      undefined,
      async () => await liveSignerWorker.resetForTest()
    );
    const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-pw-worker-onboard-'));
    const context = await chromium.launchPersistentContext(userDataDir, {
      channel: 'chromium',
      headless: true,
      args: extensionLaunchArgs()
    });

    try {
      const serviceWorker = await waitForServiceWorker(context);
      const extensionId = new URL(serviceWorker.url()).host;
      let lastOnboardingPage: Page | null = null;
      const profile = await onboardLiveSignerProfile(async (targetPath: string) => {
        const page = await context.newPage();
        lastOnboardingPage = page;
        await gotoExtensionPage(page, extensionId, targetPath, {
          waitForAppReady: targetPath === 'options.html'
        });
        return page;
      }, fixture.profile, `${fixture.profile.keysetName} Seed`).catch(async (error) => {
        const status = lastOnboardingPage
          ? await fetchExtensionStatusFromPage(lastOnboardingPage).catch((inner) => ({
              error: inner instanceof Error ? inner.message : String(inner)
            }))
          : null;
        const runtimeDiagnostics = lastOnboardingPage
          ? await fetchRuntimeDiagnosticsFromPage(lastOnboardingPage).catch((inner) => ({
              error: inner instanceof Error ? inner.message : String(inner)
            }))
          : null;
        const storageSnapshot = lastOnboardingPage
          ? await fetchWorkerStorageSnapshot(lastOnboardingPage).catch((inner) => ({
              error: inner instanceof Error ? inner.message : String(inner)
            }))
          : null;
        workerOnboardingFailureBundle = {
          error: error instanceof Error ? error.message : String(error),
          status,
          runtimeDiagnostics,
          storageSnapshot
        };
        throw error;
      });
      await use(profile);
    } finally {
      await context.close();
      await rm(userDataDir, { recursive: true, force: true });
    }
  }, { scope: 'worker', timeout: 180_000 }],

  stableLiveSigner: async ({ liveSignerWorker, onboardedLiveSignerProfile }, use) => {
    void onboardedLiveSignerProfile;
    const fixture = await withLoggedStep(
      'chrome.fixture',
      'prepare-stable-live-signer',
      undefined,
      async () => await liveSignerWorker.currentForTest()
    );
    await use(fixture);
  },

  liveSigner: async ({ liveSignerWorker }, use) => {
    const fixture = await withLoggedStep(
      'chrome.fixture',
      'start-isolated-live-signer',
      undefined,
      async () => await liveSignerWorker.resetForTest()
    );
    try {
      await use(fixture);
    } finally {
      logE2E('chrome.fixture', 'release-isolated-live-signer:ok');
    }
  },

  demoHarness: async ({}, use) => {
    const fixture = await startDemoHarnessFixture();
    try {
      await use(fixture);
    } finally {
      await fixture.cleanup();
    }
  },

  openExtensionPage: async ({ context, extensionId }, use) => {
    await use(async (targetPath: string) => {
      const page = await context.newPage();
      page.on('pageerror', (error) => {
        recordPageDiagnostic(page, `pageerror: ${error.message}`);
      });
      page.on('console', (message) => {
        if (message.type() === 'error' || message.type() === 'warning') {
          recordPageDiagnostic(page, `console.${message.type()}: ${message.text()}`);
        }
      });
      await gotoExtensionPage(page, extensionId, targetPath, {
        waitForAppReady: targetPath === 'options.html'
      });
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
