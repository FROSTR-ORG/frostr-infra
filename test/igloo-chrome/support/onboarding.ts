import { expect, type Page } from '@playwright/test';
import { logE2E } from '../../shared/observability';
import { COMMAND_TYPE } from '../../../repos/igloo-chrome/src/extension/messages';
import {
  fetchExtensionAppStateFromPage,
  fetchRuntimeDiagnosticsFromPage,
  fetchWorkerStorageSnapshot
} from './extension-status';

const ONBOARDING_UI_TIMEOUT_MS = 10_000;

type LiveOnboardingProfile = {
  groupName?: string;
  onboardPackage?: string;
  onboardPassword?: string;
  publicKey: string;
  peerPubkey: string;
  profilePayload?: {
    profileId: string;
    version: number;
    device: {
      name: string;
      shareSecret: string;
      manualPeerPolicyOverrides: Array<{
        pubkey: string;
        policy: {
          request: {
            echo: 'unset' | 'allow' | 'deny';
            ping: 'unset' | 'allow' | 'deny';
            onboard: 'unset' | 'allow' | 'deny';
            sign: 'unset' | 'allow' | 'deny';
            ecdh: 'unset' | 'allow' | 'deny';
          };
          respond: {
            echo: 'unset' | 'allow' | 'deny';
            ping: 'unset' | 'allow' | 'deny';
            onboard: 'unset' | 'allow' | 'deny';
            sign: 'unset' | 'allow' | 'deny';
            ecdh: 'unset' | 'allow' | 'deny';
          };
        };
      }>;
      relays: string[];
    };
    groupPackage: {
      groupName: string;
      groupPk: string;
      threshold: number;
      members: Array<{ idx: number; pubkey: string }>;
    };
  };
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
  profilePayload?: LiveOnboardingProfile['profilePayload'];
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
  const state = await fetchExtensionAppStateFromPage<{
    configured: boolean;
    runtime: { phase: 'cold' | 'restoring' | 'ready' | 'degraded' };
    lifecycle: LifecycleStatus['lifecycle'];
  }>(page);
  return {
    configured: state.configured,
    runtime: state.runtime.phase,
    lifecycle: state.lifecycle,
  };
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, fallback: T): Promise<T> {
  return await Promise.race([
    promise,
    new Promise<T>((resolve) => setTimeout(() => resolve(fallback), timeoutMs))
  ]);
}

async function captureOnboardingDiagnostics(page: Page) {
  const status = await withTimeout(fetchLifecycleStatus(page).catch(() => null), 1_000, null);
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
    storageSnapshot: null as unknown,
    runtimeDiagnostics: null as unknown,
    errorText: null as string | null,
  };
  const errorBanner = page.locator('div').filter({
    hasText: /Connection timed out|Failed to connect onboarding|Failed during onboard|error/i,
  });
  await Promise.all([
    page.locator('body').textContent().then((text) => {
      diagnostics.body = (text ?? '').replace(/\s+/g, ' ').trim().slice(0, 1500);
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
        appHydrating: document.body.dataset.appHydrating ?? null,
      }))
      .then((result) => {
        diagnostics.appRoute = result.appRoute;
        diagnostics.appHydrating = result.appHydrating;
      })
      .catch(() => {}),
    withTimeout(fetchExtensionAppStateFromPage(page), 1_000, { error: 'timeout' })
      .then((result) => {
        diagnostics.appState = result;
      })
      .catch(() => {}),
    withTimeout(fetchWorkerStorageSnapshot(page), 1_000, { error: 'timeout' })
      .then((result) => {
        diagnostics.storageSnapshot = result;
      })
      .catch(() => {}),
    withTimeout(fetchRuntimeDiagnosticsFromPage(page), 1_000, { error: 'timeout' })
      .then((result) => {
        diagnostics.runtimeDiagnostics = result;
      })
      .catch(() => {}),
    errorBanner
      .first()
      .textContent()
      .then((text) => {
        diagnostics.errorText = text?.trim() || null;
      })
      .catch(() => {}),
  ]);
  return diagnostics;
}

async function waitForSignerUi(page: Page, groupName: string) {
  const errorBanner = page.locator('div').filter({
    hasText: /Connection timed out|Failed to connect onboarding|Failed during onboard|error/i
  });

  await expect
    .poll(async () => {
      const status = await fetchLifecycleStatus(page);
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
      const diagnostics = await captureOnboardingDiagnostics(page);
      throw new Error(
        `Onboarding did not reach signer UI: ${error instanceof Error ? error.message : String(error)} | url=${diagnostics.url} | connect=${diagnostics.sawConnect} | save=${diagnostics.sawSave} | actionDisabled=${diagnostics.actionDisabled} | route=${diagnostics.appRoute} | hydrating=${diagnostics.appHydrating} | lifecycle=${JSON.stringify(diagnostics.lifecycle)} | appState=${JSON.stringify(diagnostics.appState)} | storage=${JSON.stringify(diagnostics.storageSnapshot)} | runtimeDiagnostics=${JSON.stringify(diagnostics.runtimeDiagnostics)} | errorText=${JSON.stringify(diagnostics.errorText)} | body=${diagnostics.body}`
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
    const pendingProfile = await page.evaluate(
      async ({ onboardingStartType, onboardPackage, onboardPassword }) => {
        const response = (await Promise.race([
          chrome.runtime.sendMessage({
            type: onboardingStartType,
            input: {
              onboardPackage,
              onboardPassword
            }
          }),
          new Promise((resolve) =>
            setTimeout(() => resolve({ ok: false, error: `${onboardingStartType} timed out` }), 25_000)
          )
        ])) as { ok?: boolean; result?: unknown; error?: string } | undefined;

        if (!response?.ok || response.result === undefined) {
          throw new Error(response?.error || `${onboardingStartType} failed`);
        }

        return response.result;
      },
      {
        onboardingStartType: COMMAND_TYPE.ONBOARDING_START,
        onboardPackage: profile.onboardPackage,
        onboardPassword: profile.onboardPassword
      }
    ).catch(async (error) => {
      const diagnostics = await captureOnboardingDiagnostics(page);
      throw new Error(
        `Onboarding start request failed: ${error instanceof Error ? error.message : String(error)} | url=${diagnostics.url} | connect=${diagnostics.sawConnect} | save=${diagnostics.sawSave} | actionDisabled=${diagnostics.actionDisabled} | route=${diagnostics.appRoute} | hydrating=${diagnostics.appHydrating} | lifecycle=${JSON.stringify(diagnostics.lifecycle)} | appState=${JSON.stringify(diagnostics.appState)} | storage=${JSON.stringify(diagnostics.storageSnapshot)} | runtimeDiagnostics=${JSON.stringify(diagnostics.runtimeDiagnostics)} | errorText=${JSON.stringify(diagnostics.errorText)} | body=${diagnostics.body}`
      );
    });

    await page.evaluate(
      async ({ onboardingCompleteType, nextPendingProfile, label, password }) => {
        const response = (await Promise.race([
          chrome.runtime.sendMessage({
            type: onboardingCompleteType,
            pendingProfile: nextPendingProfile,
            label,
            password
          }),
          new Promise((resolve) =>
            setTimeout(() => resolve({ ok: false, error: `${onboardingCompleteType} timed out` }), 25_000)
          )
        ])) as { ok?: boolean; result?: unknown; error?: string } | undefined;

        if (!response?.ok || response.result === undefined) {
          throw new Error(response?.error || `${onboardingCompleteType} failed`);
        }
      },
      {
        onboardingCompleteType: COMMAND_TYPE.ONBOARDING_COMPLETE,
        nextPendingProfile: pendingProfile,
        label: groupName,
        password: profile.onboardPassword
      }
    ).catch(async (error) => {
      const diagnostics = await captureOnboardingDiagnostics(page);
      throw new Error(
        `Onboarding completion request failed: ${error instanceof Error ? error.message : String(error)} | url=${diagnostics.url} | connect=${diagnostics.sawConnect} | save=${diagnostics.sawSave} | actionDisabled=${diagnostics.actionDisabled} | route=${diagnostics.appRoute} | hydrating=${diagnostics.appHydrating} | lifecycle=${JSON.stringify(diagnostics.lifecycle)} | appState=${JSON.stringify(diagnostics.appState)} | storage=${JSON.stringify(diagnostics.storageSnapshot)} | runtimeDiagnostics=${JSON.stringify(diagnostics.runtimeDiagnostics)} | errorText=${JSON.stringify(diagnostics.errorText)} | body=${diagnostics.body}`
      );
    });

    await waitForSignerUi(page, groupName);

    const appState = await fetchExtensionAppStateFromPage<{ profile: StoredProfile | null }>(page);
    const [runtimeDiagnostics, storageSnapshot] = await Promise.all([
      fetchRuntimeDiagnosticsFromPage<{
        runtimeStatus?: {
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
      Array.isArray((storageSnapshot as WorkerStorageSnapshot | null)?.chromeStorage?.['igloo.v3.ext.profiles'])
        ? (
            (storageSnapshot as WorkerStorageSnapshot).chromeStorage?.['igloo.v3.ext.profiles'] as Array<Record<string, unknown>>
          ).find((entry) => entry.id === appState.profile?.id) ?? null
        : null;
    const sessionUnlocks = (storageSnapshot as WorkerStorageSnapshot | null)?.chromeSession?.['igloo.v3.ext.sessionUnlocks'];
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
      ...(typeof runtimeDiagnostics?.runtimeStatus?.metadata?.group_public_key === 'string' &&
      runtimeDiagnostics.runtimeStatus.metadata.group_public_key.trim().length > 0
          ? {
              publicKey: runtimeDiagnostics.runtimeStatus.metadata.group_public_key.trim().toLowerCase(),
              groupPublicKey: runtimeDiagnostics.runtimeStatus.metadata.group_public_key.trim().toLowerCase()
            }
          : {}),
      ...(typeof runtimeDiagnostics?.runtimeStatus?.metadata?.share_public_key === 'string' &&
      runtimeDiagnostics.runtimeStatus.metadata.share_public_key.trim().length > 0
          ? { sharePublicKey: runtimeDiagnostics.runtimeStatus.metadata.share_public_key.trim().toLowerCase() }
          : {}),
      ...(Array.isArray(runtimeDiagnostics?.runtimeStatus?.metadata?.peers) &&
      typeof runtimeDiagnostics.runtimeStatus.metadata.peers[0] === 'string' &&
      runtimeDiagnostics.runtimeStatus.metadata.peers[0].trim().length > 0
        ? { peerPubkey: runtimeDiagnostics.runtimeStatus.metadata.peers[0].trim().toLowerCase() }
        : {})
    };
  } finally {
    if (!page.isClosed()) {
      await page.close();
    }
  }
}
