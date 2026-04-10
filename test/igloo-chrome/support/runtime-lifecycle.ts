import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';

import { chromium, expect as pwExpect, type BrowserContext, type Page } from '@playwright/test';

import { IGLOO_CHROME_DIST_DIR } from '../../shared/repo-paths';
import { gotoExtensionPage, waitForServiceWorker } from '../fixtures/helpers/context';
import { fetchExtensionAppStateFromPage, fetchRuntimeDiagnosticsFromPage } from './extension-status';
import { waitForLiveSignReady } from './live-runtime';
import { approvePromptOnce, runProviderActionWithApproval } from './provider-live';

export { approvePromptOnce } from './provider-live';

export type ExtensionStatusSnapshot = {
  configured: boolean;
  runtime: string;
  lifecycle: {
    onboarding: { stage: string; lastError: { message: string } | null };
    activation: { stage: string; lastError: { message: string } | null };
  };
  runtimeDetails: {
    status: unknown;
    summary: {
      metadata?: {
        group_public_key?: string | null;
      } | null;
      readiness?: {
        sign_ready?: boolean;
      } | null;
    } | null;
    snapshot: unknown;
    snapshotError: string | null;
    metadata: {
      group_public_key?: string | null;
    } | null;
    readiness: {
      sign_ready?: boolean;
    } | null;
  };
};

const extensionPath = IGLOO_CHROME_DIST_DIR;

export async function ensureRuntimeReady(
  activateProfile: (profileId: string) => Promise<void>,
  profileId: string
) {
  await pwExpect
    .poll(async () => {
      try {
        await activateProfile(profileId);
        return 'ready';
      } catch {
        return 'pending';
      }
    }, {
      timeout: 10_000,
      intervals: [250, 500, 1_000],
    })
    .toBe('ready');
}

export async function waitForNonceHydration(
  fetchRuntimeSnapshot: <T>() => Promise<T>,
  label: string,
  expectedPeers: number,
  minSignReadyPeers: number
) {
  await waitForLiveSignReady(
    fetchRuntimeSnapshot,
    label,
    expectedPeers,
    minSignReadyPeers
  );
}

export async function getProviderPublicKeyWithApproval(
  context: BrowserContext,
  serverOrigin: string
) {
  return await runProviderActionWithApproval(
    context,
    serverOrigin,
    'wants to read your public key',
    async (page) => await page.evaluate(() => window.nostr!.getPublicKey())
  );
}

export async function signProviderEventWithApproval(
  context: BrowserContext,
  serverOrigin: string,
  event: Record<string, unknown>
) {
  return await runProviderActionWithApproval(
    context,
    serverOrigin,
    'wants to sign a Nostr event',
    async (page) => await page.evaluate(async (nextEvent) => {
      try {
        return { ok: true, event: await window.nostr!.signEvent(nextEvent), message: null };
      } catch (error) {
        return {
          ok: false,
          event: null,
          message: error instanceof Error ? error.message : String(error),
        };
      }
    }, event)
  );
}

export async function fetchExtensionStatus(page: Page): Promise<ExtensionStatusSnapshot> {
  const [state, diagnostics] = await Promise.all([
    fetchExtensionAppStateFromPage<{
      configured: boolean;
      runtime: { phase: string };
      lifecycle: ExtensionStatusSnapshot['lifecycle'];
    }>(page),
    fetchRuntimeDiagnosticsFromPage<{
      runtimeStatus?: ExtensionStatusSnapshot['runtimeDetails']['summary'];
      runtimeSnapshot?: unknown;
      runtimeSnapshotError?: string | null;
    }>(page),
  ]);
  return {
    configured: state.configured,
    runtime: state.runtime.phase,
    lifecycle: state.lifecycle,
    runtimeDetails: {
      status: diagnostics.runtimeStatus?.status ?? null,
      summary: diagnostics.runtimeStatus ?? null,
      snapshot: diagnostics.runtimeSnapshot ?? null,
      snapshotError: diagnostics.runtimeSnapshotError ?? null,
      metadata: diagnostics.runtimeStatus?.metadata ?? null,
      readiness: diagnostics.runtimeStatus?.readiness ?? null,
    },
  };
}

export async function completeOnboardingInContext(
  context: BrowserContext,
  extensionId: string,
  profile: {
    groupName?: string;
    onboardPackage?: string;
    onboardPassword?: string;
  }
) {
  const page = await context.newPage();
  try {
    await gotoExtensionPage(page, extensionId, 'options.html');
    const onboardCard = page.locator('section').filter({
      has: page.getByRole('heading', { name: 'Onboard Device' }),
    });
    await pwExpect(onboardCard.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    if (!profile.onboardPackage || !profile.onboardPassword) {
      throw new Error('profile is missing onboarding package data');
    }

    await onboardCard.getByPlaceholder('bfonboard1...').fill(profile.onboardPackage);
    await onboardCard.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    await onboardCard.getByRole('button', { name: 'Connect' }).click();
    const saveCard = page.locator('section').filter({
      has: page.getByRole('heading', { name: 'Save Onboarded Device' }),
    });
    await pwExpect(saveCard.getByRole('heading', { name: 'Save Onboarded Device' })).toBeVisible();
    await saveCard
      .getByPlaceholder('e.g. Laptop Signer, Browser Node A')
      .fill(profile.groupName ?? 'Playwright Live');
    await saveCard.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    await saveCard.getByRole('button', { name: 'Save Device' }).click();
    await pwExpect
      .poll(async () => {
        const status = await fetchExtensionStatus(page);
        if (status.lifecycle.onboarding.lastError) {
          return `onboarding_failed:${status.lifecycle.onboarding.lastError.message}`;
        }
        if (status.lifecycle.activation.lastError) {
          return `activation_failed:${status.lifecycle.activation.lastError.message}`;
        }
        if (status.configured === true && (status.runtime === 'ready' || status.runtime === 'degraded')) {
          return 'ready';
        }
        return `${status.lifecycle.onboarding.stage}/${status.lifecycle.activation.stage}/${String(status.runtime)}`;
      }, {
        timeout: 35_000,
        intervals: [250, 500, 1_000],
      })
      .toBe('ready');
  } finally {
    await page.close();
  }
}

export async function unlockStoredProfileInContext(
  context: BrowserContext,
  extensionId: string,
  password: string
) {
  const page = await context.newPage();
  try {
    await gotoExtensionPage(page, extensionId, 'options.html');
    await pwExpect(page.getByText('Stored Profiles', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Unlock' }).click();
    await pwExpect(page.getByText('Unlock Stored Profile')).toBeVisible();
    await page.getByPlaceholder('Enter profile password').fill(password);
    await page.getByRole('button', { name: 'Unlock Profile' }).click();
    await pwExpect(page.getByRole('tab', { name: /Signer/i }).first()).toBeVisible();
  } finally {
    await page.close();
  }
}

export async function launchExtensionContext(userDataDir?: string) {
  const nextUserDataDir =
    userDataDir ?? (await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-relaunch-')));
  const context = await chromium.launchPersistentContext(nextUserDataDir, {
    channel: 'chromium',
    headless: true,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`,
    ],
  });
  return {
    context,
    userDataDir: nextUserDataDir,
  };
}

export async function closeContextSafely(context: BrowserContext | null) {
  if (!context) {
    return;
  }

  try {
    await context.close();
  } catch (error) {
    if (
      error instanceof Error &&
      error.message.includes('ENOENT: no such file or directory') &&
      (error.message.includes('.playwright-artifacts-') ||
        error.message.includes('recording') ||
        error.message.includes('.zip'))
    ) {
      return;
    }
    throw error;
  }
}

export async function withExtensionRelaunchContext<T>(
  callback: (input: {
    context: BrowserContext;
    extensionId: string;
  }) => Promise<T>
) {
  const { context, userDataDir } = await launchExtensionContext();
  try {
    const worker = await waitForServiceWorker(context);
    const extensionId = new URL(worker.url()).host;
    return await callback({ context, extensionId });
  } finally {
    await closeContextSafely(context).catch(() => undefined);
    await rm(userDataDir, { recursive: true, force: true });
  }
}

export async function withUnlockedRelaunchContext<T>(input: {
  profile: {
    groupName?: string;
    onboardPackage?: string;
    onboardPassword?: string;
  };
  callback: (state: {
    context: BrowserContext;
    extensionId: string;
  }) => Promise<T>;
}) {
  const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-relaunch-'));
  let firstContext: BrowserContext | null = null;
  let secondContext: BrowserContext | null = null;

  try {
    ({ context: firstContext } = await launchExtensionContext(userDataDir));
    const firstWorker = await waitForServiceWorker(firstContext);
    const firstExtensionId = new URL(firstWorker.url()).host;
    await completeOnboardingInContext(firstContext, firstExtensionId, input.profile);
    await closeContextSafely(firstContext);
    firstContext = null;

    ({ context: secondContext } = await launchExtensionContext(userDataDir));
    const secondWorker = await waitForServiceWorker(secondContext);
    const secondExtensionId = new URL(secondWorker.url()).host;
    if (!input.profile.onboardPassword) {
      throw new Error('profile is missing onboarding password');
    }
    await unlockStoredProfileInContext(secondContext, secondExtensionId, input.profile.onboardPassword);

    return await input.callback({
      context: secondContext,
      extensionId: secondExtensionId,
    });
  } finally {
    await closeContextSafely(secondContext).catch(() => undefined);
    await closeContextSafely(firstContext).catch(() => undefined);
    await rm(userDataDir, { recursive: true, force: true });
  }
}
