import { expect, type Page } from '@playwright/test';
import { logE2E } from '../../shared/observability';
import {
  fetchExtensionAppStateFromPage,
  fetchRuntimeDiagnosticsFromPage,
  fetchExtensionStatusFromPage,
  fetchWorkerStorageSnapshot
} from './extension-status';

const ONBOARDING_UI_TIMEOUT_MS = 10_000;

type LiveOnboardingProfile = {
  groupName?: string;
  onboardPackage?: string;
  onboardPassword?: string;
  publicKey: string;
  peerPubkey: string;
};

export type StoredProfile = {
  id?: string;
  groupName?: string;
  relays: string[];
  publicKey?: string;
  groupPublicKey?: string;
  sharePublicKey?: string;
  peerPubkey?: string;
  runtimeSnapshotJson?: string;
  storedBlobRecord?: {
    id: string;
    label: string;
    blob: unknown;
    createdAt: number;
    updatedAt: number;
  };
  sessionKeyB64?: string;
};

type WorkerStorageSnapshot = {
  chromeStorage?: Record<string, unknown> | null;
  chromeSession?: Record<string, unknown> | null;
};

type LifecycleStatus = {
  configured: boolean;
  runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
  lifecycle: {
    onboarding: {
      stage: string;
      lastError: { message: string } | null;
    };
    activation: {
      stage: string;
      lastError: { message: string } | null;
    };
  };
};

async function fetchLifecycleStatus(page: Page): Promise<LifecycleStatus> {
  return await fetchExtensionStatusFromPage<LifecycleStatus>(page);
}

async function waitForSignerUi(page: Page, groupName: string) {
  const errorBanner = page.locator('div').filter({
    hasText: /Connection timed out|Failed to connect onboarding|Failed during onboard|error/i
  });

  await expect
    .poll(async () => {
      const status = await fetchLifecycleStatus(page);
      logE2E('chrome.support.onboarding', 'status-poll', {
        onboarding_stage: status.lifecycle.onboarding.stage,
        activation_stage: status.lifecycle.activation.stage,
        runtime: status.runtime,
        onboarding_error: status.lifecycle.onboarding.lastError?.message ?? null,
        activation_error: status.lifecycle.activation.lastError?.message ?? null
      });
      if (status.lifecycle.onboarding.lastError) {
        return `onboarding_failed:${status.lifecycle.onboarding.lastError.message}`;
      }
      if (status.lifecycle.activation.lastError) {
        return `activation_failed:${status.lifecycle.activation.lastError.message}`;
      }
      if (
        status.configured &&
        (
          status.runtime === 'ready' ||
          status.runtime === 'degraded' ||
          status.lifecycle.activation.stage === 'ready' ||
          status.lifecycle.activation.stage === 'degraded'
        )
      ) {
        return 'ready';
      }
      return `${status.lifecycle.onboarding.stage}/${status.lifecycle.activation.stage}/${status.runtime}`;
    }, {
      timeout: ONBOARDING_UI_TIMEOUT_MS,
      intervals: [250, 500, 1_000]
    })
    .toBe('ready')
    .catch(async (error) => {
      const status = await fetchLifecycleStatus(page).catch(() => null);
      const diagnostics = {
        url: page.url(),
        body: '',
        sawConnect: false,
        sawSave: false,
        actionDisabled: null as boolean | null,
        lifecycle: status,
        appRoute: null as string | null,
        appHydrating: null as string | null,
        appState: null as unknown,
        storageSnapshot: null as unknown
        ,
        runtimeDiagnostics: null as unknown
      };
      await Promise.all([
        page.locator('body').textContent().then((text) => {
          diagnostics.body = (text ?? '').replace(/\s+/g, ' ').trim().slice(0, 1000);
        }),
        page
          .getByRole('heading', { name: 'Onboard Device' })
          .isVisible()
          .then((visible) => {
            diagnostics.sawConnect = visible;
          })
          .catch(() => {}),
        page
          .getByRole('heading', { name: 'Save Onboarded Device' })
          .isVisible()
          .then((visible) => {
            diagnostics.sawSave = visible;
          })
          .catch(() => {}),
        page
          .getByRole('button', { name: /Connect|Save Device/ })
          .isDisabled()
          .then((disabled) => {
            diagnostics.actionDisabled = disabled;
          })
          .catch(() => {}),
        page
          .evaluate(() => ({
            appRoute: document.body.dataset.appRoute ?? null,
            appHydrating: document.body.dataset.appHydrating ?? null
          }))
          .then((result) => {
            diagnostics.appRoute = result.appRoute;
            diagnostics.appHydrating = result.appHydrating;
          })
          .catch(() => {}),
        fetchExtensionAppStateFromPage(page)
          .then((result) => {
            diagnostics.appState = result;
          })
          .catch(() => {}),
        fetchWorkerStorageSnapshot(page)
          .then((result) => {
            diagnostics.storageSnapshot = result;
          })
          .catch(() => {}),
        fetchRuntimeDiagnosticsFromPage(page)
          .then((result) => {
            diagnostics.runtimeDiagnostics = result;
          })
          .catch(() => {})
      ]);
      throw new Error(
        `Onboarding did not reach signer UI: ${error instanceof Error ? error.message : String(error)} | url=${diagnostics.url} | connect=${diagnostics.sawConnect} | save=${diagnostics.sawSave} | actionDisabled=${diagnostics.actionDisabled} | route=${diagnostics.appRoute} | hydrating=${diagnostics.appHydrating} | lifecycle=${JSON.stringify(diagnostics.lifecycle)} | appState=${JSON.stringify(diagnostics.appState)} | storage=${JSON.stringify(diagnostics.storageSnapshot)} | runtimeDiagnostics=${JSON.stringify(diagnostics.runtimeDiagnostics)} | body=${diagnostics.body}`
      );
    });

  if (await errorBanner.first().isVisible().catch(() => false)) {
    const errorText = (await errorBanner.first().textContent())?.trim() || 'unknown onboarding error';
    throw new Error(`Onboarding did not reach signer UI: ${errorText}`);
  }

  const appState = await fetchExtensionAppStateFromPage<{ configured: boolean }>(page).catch(
    () => null
  );
  if (!appState?.configured) {
    throw new Error('Onboarding finished without a configured app state');
  }
}

export async function onboardLiveSignerProfile(
  openExtensionPage: (targetPath: string) => Promise<Page>,
  profile: LiveOnboardingProfile,
  groupName = 'Playwright Live'
): Promise<StoredProfile> {
  if (!profile.onboardPackage || !profile.onboardPassword) {
    throw new Error('Live signer profile is missing onboarding package material');
  }

  const page = await openExtensionPage('options.html');
  try {
    logE2E('chrome.support.onboarding', 'open-options');
    const onboardCard = page.locator('section').filter({
      has: page.getByRole('heading', { name: 'Onboard Device' })
    });
    await expect(onboardCard.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    await onboardCard.getByPlaceholder('bfonboard1...').fill(profile.onboardPackage);
    await onboardCard.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    logE2E('chrome.support.onboarding', 'connect-inputs-filled');
    await onboardCard.getByRole('button', { name: 'Connect' }).click();
    await expect(page.getByRole('heading', { name: 'Save Onboarded Device' })).toBeVisible();
    await page.getByPlaceholder('e.g. Laptop Signer, Browser Node A').fill(groupName);
    await page.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    logE2E('chrome.support.onboarding', 'save-inputs-filled', { groupName });
    await page.getByRole('button', { name: 'Save Device' }).click();
    logE2E('chrome.support.onboarding', 'save-clicked');

    await waitForSignerUi(page, groupName);
    logE2E('chrome.support.onboarding', 'signer-ui-ready');

    const appState = await fetchExtensionAppStateFromPage<{ profile: StoredProfile | null }>(page);
    const [status, storageSnapshot] = await Promise.all([
      fetchExtensionStatusFromPage<{
        publicKey?: string | null;
        sharePublicKey?: string | null;
        runtimeDetails?: {
          metadata?: {
            group_public_key?: string | null;
            share_public_key?: string | null;
            peers?: string[] | null;
          } | null;
        } | null;
      }>(page).catch(() => null),
      fetchWorkerStorageSnapshot(page).catch(() => null)
    ]);
    if (!appState.profile) {
      throw new Error('missing stored profile after onboarding');
    }
    const storedRecord =
      Array.isArray((storageSnapshot as WorkerStorageSnapshot | null)?.chromeStorage?.['igloo.ext.profiles'])
        ? (
            (storageSnapshot as WorkerStorageSnapshot).chromeStorage?.['igloo.ext.profiles'] as Array<Record<string, unknown>>
          ).find((entry) => entry.id === appState.profile?.id) ?? null
        : null;
    const sessionUnlocks = (storageSnapshot as WorkerStorageSnapshot | null)?.chromeSession?.['igloo.ext.sessionUnlocks'];
    const sessionKeyB64 =
      sessionUnlocks &&
      typeof sessionUnlocks === 'object' &&
      appState.profile.id &&
      appState.profile.id in (sessionUnlocks as Record<string, unknown>) &&
      typeof (sessionUnlocks as Record<string, Record<string, unknown>>)[appState.profile.id]?.keyB64 === 'string'
        ? (sessionUnlocks as Record<string, Record<string, string>>)[appState.profile.id].keyB64
        : undefined;
    return {
      ...appState.profile,
      ...(storedRecord &&
      typeof storedRecord.id === 'string' &&
      typeof storedRecord.label === 'string' &&
      typeof storedRecord.createdAt === 'number' &&
      typeof storedRecord.updatedAt === 'number'
        ? {
            storedBlobRecord: {
              id: storedRecord.id,
              label: storedRecord.label,
              blob: storedRecord.blob,
              createdAt: storedRecord.createdAt,
              updatedAt: storedRecord.updatedAt
            }
          }
        : {}),
      ...(typeof sessionKeyB64 === 'string' && sessionKeyB64.trim().length > 0
        ? { sessionKeyB64: sessionKeyB64.trim() }
        : {}),
      ...(typeof status?.publicKey === 'string' && status.publicKey.trim().length > 0
        ? {
            publicKey: status.publicKey.trim().toLowerCase(),
            groupPublicKey: status.publicKey.trim().toLowerCase()
          }
        : typeof status?.runtimeDetails?.metadata?.group_public_key === 'string' &&
            status.runtimeDetails.metadata.group_public_key.trim().length > 0
          ? {
              publicKey: status.runtimeDetails.metadata.group_public_key.trim().toLowerCase(),
              groupPublicKey: status.runtimeDetails.metadata.group_public_key.trim().toLowerCase()
            }
          : {}),
      ...(typeof status?.sharePublicKey === 'string' && status.sharePublicKey.trim().length > 0
        ? { sharePublicKey: status.sharePublicKey.trim().toLowerCase() }
        : typeof status?.runtimeDetails?.metadata?.share_public_key === 'string' &&
            status.runtimeDetails.metadata.share_public_key.trim().length > 0
          ? { sharePublicKey: status.runtimeDetails.metadata.share_public_key.trim().toLowerCase() }
          : {}),
      ...(Array.isArray(status?.runtimeDetails?.metadata?.peers) &&
      typeof status.runtimeDetails.metadata.peers[0] === 'string' &&
      status.runtimeDetails.metadata.peers[0].trim().length > 0
        ? { peerPubkey: status.runtimeDetails.metadata.peers[0].trim().toLowerCase() }
        : {})
    };
  } finally {
    if (!page.isClosed()) {
      await page.close();
    }
  }
}
