import path from 'node:path';

import { expect, test as base } from '@playwright/test';
import { getPublicKey } from 'nostr-tools';

import { clearE2EEvents, logE2E, withLoggedStep } from '../../shared/observability';
import { IGLOO_CHROME_DIST_DIR } from '../../shared/repo-paths';
import { TEST_PEER_PUBLIC_KEY, TEST_PROFILE, TEST_PUBLIC_KEY } from './constants';
import {
  buildExtensionOnce,
  attachPageDiagnostics,
  disposeExtensionContext,
  gotoExtensionPage,
  isExpectedConsoleNoise,
  launchExtensionContext,
  waitForServiceWorker,
} from './helpers/context';
import { startDemoHarnessFixture } from './helpers/demo-harness';
import { writeFailureBundle } from './helpers/failure-bundle';
import { clearFixtureDiagnostics } from './helpers/fixture-state';
import {
  activateProfileViaExtension,
  fetchRuntimeDiagnosticsViaExtension,
  fetchRuntimeSnapshotViaExtension,
  fetchRuntimeStatusViaExtension,
  openPageForStorage,
  reloadExtensionViaPage,
  runRuntimeControlViaExtension,
  sendRuntimePrepare,
} from './helpers/transport';
import {
  clearExtensionStorageState,
  clearSessionUnlocksInExtension,
  seedPermissionPoliciesIntoExtension,
  seedProfileIntoExtension,
} from './helpers/storage';
import { startLiveSignerFixture } from './live-signer';
import { startTestServer } from './server';
import type { DemoHarnessFixture, ExtensionFixtures, WorkerFixtures } from './types';

const extensionPath = IGLOO_CHROME_DIST_DIR;

export const test = base.extend<ExtensionFixtures, WorkerFixtures>({
  context: async ({}, use, testInfo) => {
    clearE2EEvents();
    clearFixtureDiagnostics();
    const { context, userDataDir } = await withLoggedStep(
      'chrome.fixture',
      'launch-context',
      { userDataDirPrefix: path.join('/tmp', 'igloo-chrome-pw-') },
      async () => await launchExtensionContext(extensionPath)
    );

    try {
      await use(context);
    } finally {
      const serviceWorkers = context.serviceWorkers();
      const extensionId = serviceWorkers.length > 0 ? new URL(serviceWorkers[0].url()).host : null;
      if (testInfo.status !== testInfo.expectedStatus && extensionId) {
        await writeFailureBundle(testInfo, context, extensionId).catch(() => undefined);
      }
      logE2E('chrome.fixture', 'close-context:start');
      await disposeExtensionContext(context, userDataDir);
      logE2E('chrome.fixture', 'close-context:ok');
    }
  },

  serviceWorker: async ({ context }, use) => {
    const worker = await withLoggedStep('chrome.fixture', 'wait-service-worker', undefined, async () =>
      await waitForServiceWorker(context)
    );
    worker.on('console', (message) => {
      if (isExpectedConsoleNoise(message.type(), message.text())) {
        return;
      }
      logE2E('chrome.worker', 'console', {
        console_type: message.type(),
        text: message.text(),
      });
    });
    worker.on('close', () => {
      logE2E('chrome.worker', 'close');
    });
    await use(worker);
  },

  extensionId: async ({ serviceWorker }, use) => {
    await use(new URL(serviceWorker.url()).host);
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
    buildExtensionOnce(extensionPath);
    const fixture = await withLoggedStep(
      'chrome.fixture',
      'prepare-onboarded-live-profile',
      undefined,
      async () => await liveSignerWorker.resetForTest()
    );
    const liveProfile = fixture.profile;
    const shareSecret = liveProfile.profilePayload?.device.shareSecret ?? null;
    const sharePublicKey =
      typeof shareSecret === 'string' && shareSecret.length > 0
        ? getPublicKey(Uint8Array.from(Buffer.from(shareSecret, 'hex'))).toLowerCase()
        : undefined;
    await use({
      id: liveProfile.profilePayload?.profileId,
      groupName: `${liveProfile.groupName} Seed`,
      relays: liveProfile.relays,
      publicKey: liveProfile.publicKey,
      groupPublicKey: liveProfile.publicKey,
      sharePublicKey,
      peerPubkey: liveProfile.peerPubkey,
      profilePayload:
        liveProfile.profilePayload
          ? {
              ...liveProfile.profilePayload,
              device: {
                ...liveProfile.profilePayload.device,
                name: `${liveProfile.groupName} Seed`,
              },
              groupPackage: {
                ...liveProfile.profilePayload.groupPackage,
                groupName: `${liveProfile.groupName} Seed`,
              },
            }
          : undefined,
    });
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
    const fixture: DemoHarnessFixture = await startDemoHarnessFixture();
    try {
      await use(fixture);
    } finally {
      await fixture.cleanup();
    }
  },

  openExtensionPage: async ({ context, extensionId }, use) => {
    await use(async (targetPath: string) => {
      const page = await context.newPage();
      attachPageDiagnostics(page);
      await gotoExtensionPage(page, extensionId, targetPath, {
        waitForAppReady: targetPath === 'options.html',
      });
      return page;
    });
  },

  fetchRuntimeSnapshot: async ({ context, extensionId }, use) => {
    await use(async <T>() =>
      await withLoggedStep('chrome.fixture', 'fetch-runtime-snapshot', undefined, async () =>
        await fetchRuntimeSnapshotViaExtension<T>(context, extensionId)
      )
    );
  },

  fetchRuntimeStatus: async ({ context, extensionId }, use) => {
    await use(async <T>() =>
      await withLoggedStep('chrome.fixture', 'fetch-runtime-status', undefined, async () =>
        await fetchRuntimeStatusViaExtension<T>(context, extensionId)
      )
    );
  },

  fetchRuntimeDiagnostics: async ({ context, extensionId }, use) => {
    await use(async <T>() =>
      await withLoggedStep('chrome.fixture', 'fetch-runtime-diagnostics', undefined, async () =>
        await fetchRuntimeDiagnosticsViaExtension<T>(context, extensionId)
      )
    );
  },

  prepareRuntimeReadiness: async ({ context, extensionId }, use) => {
    await use(async <T>(operation: 'sign' | 'ecdh') =>
      await withLoggedStep('chrome.fixture', 'prepare-runtime-readiness', { operation }, async () =>
        await sendRuntimePrepare<T>(context, extensionId, operation)
      )
    );
  },

  activateProfile: async ({ context, extensionId }, use) => {
    await use(async (profileId: string) => {
      await withLoggedStep('chrome.fixture', 'activate-profile', { profileId }, async () => {
        const page = await openPageForStorage(context, extensionId);
        try {
          await activateProfileViaExtension(page, profileId);
        } finally {
          await page.close().catch(() => undefined);
        }
      });
    });
  },

  runRuntimeControl: async ({ context, extensionId }, use) => {
    await use(async (action: 'stopRuntime' | 'reloadExtension') => {
      await withLoggedStep('chrome.fixture', 'runtime-control', { action }, async () => {
        const page = await openPageForStorage(context, extensionId);
        try {
          await runRuntimeControlViaExtension(page, action);
        } finally {
          await page.close().catch(() => undefined);
        }
      });
    });
  },

  reloadExtension: async ({ context, extensionId }, use) => {
    await use(async () => {
      await withLoggedStep('chrome.fixture', 'reload-extension', undefined, async () => {
        const page = await openPageForStorage(context, extensionId);
        try {
          await reloadExtensionViaPage(page);
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
          hasOnboardPackage: typeof overrides.onboardPackage === 'string',
        },
        async () => {
          await seedProfileIntoExtension(context, extensionId, overrides);
        }
      );
    });
  },

  seedPermissionPolicies: async ({ context, extensionId }, use) => {
    await use(async (policies) => {
      await seedPermissionPoliciesIntoExtension(context, extensionId, policies);
    });
  },

  clearSessionUnlocks: async ({ context, extensionId }, use) => {
    await use(async () => {
      await clearSessionUnlocksInExtension(context, extensionId);
    });
  },

  clearExtensionStorage: async ({ context, extensionId }, use) => {
    await use(async () => {
      await clearExtensionStorageState(context, extensionId);
    });
  },
});

export { expect, TEST_PEER_PUBLIC_KEY, TEST_PROFILE, TEST_PUBLIC_KEY };
