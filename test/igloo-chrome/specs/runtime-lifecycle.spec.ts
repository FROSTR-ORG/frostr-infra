import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';

import { chromium, expect as pwExpect, type BrowserContext, type Page } from '@playwright/test';

import { IGLOO_CHROME_DIST_DIR } from '../../shared/repo-paths';
import { test, expect } from '../fixtures/extension';
import { onboardLiveSignerProfile } from '../support/onboarding';
import {
  assertNoncePoolHydrated,
  assertRuntimeReadiness,
  type RuntimeReadinessResult,
  type RuntimeDiagnosticEvent,
  type RuntimeSnapshotResult
} from '../support/runtime';
import { fetchExtensionStatusFromPage } from '../support/extension-status';

type ExtensionStatusSnapshot = {
  runtime: string;
  runtimeDetails?: {
    summary?: {
      metadata?: {
        group_public_key?: string | null;
      } | null;
      readiness?: {
        sign_ready?: boolean;
      } | null;
    } | null;
  } | null;
};

const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_000,
  tags: [],
  content: 'playwright restored signEvent'
};

async function prepareSignReady(
  callOffscreenRpc: <T>(rpcType: string, payload?: Record<string, unknown>) => Promise<T>,
  label: string
) {
  const readiness = await callOffscreenRpc<RuntimeReadinessResult>('runtime.prepare_sign');
  assertRuntimeReadiness(label, readiness, 'sign');
}

async function ensureRuntimeReady(
  activateProfile: (profileId: string) => Promise<void>,
  profileId: string
) {
  await expect
    .poll(async () => {
      try {
        await activateProfile(profileId);
        return 'ready';
      } catch {
        return 'pending';
      }
    }, {
      timeout: 10_000,
      intervals: [250, 500, 1_000]
    })
    .toBe('ready');
}

async function approvePromptOnce(prompt: import('@playwright/test').Page) {
  await prompt.waitForLoadState('domcontentloaded');
  await prompt
    .getByRole('button', { name: 'Allow once' })
    .evaluate((button: HTMLButtonElement) => button.click())
    .catch(() => {
      // The background closes the prompt as part of successful approval.
    });
}

const extensionPath = IGLOO_CHROME_DIST_DIR;
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

async function fetchExtensionStatus(page: Page) {
  return await fetchExtensionStatusFromPage<Record<string, unknown>>(page);
}

async function completeOnboardingInContext(
  context: BrowserContext,
  extensionId: string,
  profile: {
    groupName?: string;
    onboardPackage?: string;
    onboardPassword?: string;
    publicKey: string;
    peerPubkey: string;
  }
) {
  const page = await context.newPage();
  try {
    await gotoExtensionPage(page, extensionId, 'options.html');
    const onboardCard = page.locator('section').filter({
      has: page.getByRole('heading', { name: 'Onboard Device' })
    });
    await pwExpect(onboardCard.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    if (!profile.onboardPackage || !profile.onboardPassword) {
      throw new Error('profile is missing onboarding package data');
    }

    await onboardCard.getByPlaceholder('bfonboard1...').fill(profile.onboardPackage);
    await onboardCard.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    await onboardCard.getByRole('button', { name: 'Connect' }).click();
    const saveCard = page.locator('section').filter({
      has: page.getByRole('heading', { name: 'Save Onboarded Device' })
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
        const lifecycle = status.lifecycle as {
          onboarding: { stage: string; lastError: { message: string } | null };
          activation: { stage: string; lastError: { message: string } | null };
        };
        if (lifecycle.onboarding.lastError) {
          return `onboarding_failed:${lifecycle.onboarding.lastError.message}`;
        }
        if (lifecycle.activation.lastError) {
          return `activation_failed:${lifecycle.activation.lastError.message}`;
        }
        if (
          status.configured === true &&
          (status.runtime === 'ready' || status.runtime === 'degraded')
        ) {
          return 'ready';
        }
        return `${lifecycle.onboarding.stage}/${lifecycle.activation.stage}/${String(status.runtime)}`;
      }, {
        timeout: 35_000,
        intervals: [250, 500, 1_000]
      })
      .toBe('ready');
  } finally {
    await page.close();
  }
}

async function unlockStoredProfileInContext(
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

async function launchExtensionContext(userDataDir: string) {
  return await chromium.launchPersistentContext(userDataDir, {
    channel: 'chromium',
    headless: true,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`
    ]
  });
}

async function closeContextSafely(context: BrowserContext | null) {
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

test.describe('runtime lifecycle @live', () => {
  test.setTimeout(180_000);

  test('recreates the offscreen document after explicit teardown', async ({
    activateProfile,
    callOffscreenRpc,
    context,
    liveSigner,
    openExtensionPage,
    runRuntimeControl,
    server,
    seedProfile
  }) => {
    const currentProfile = await onboardLiveSignerProfile(
      async (targetPath: string) => await openExtensionPage(targetPath),
      liveSigner.profile,
      `${liveSigner.profile.groupName} Restore`
    );
    await seedProfile(currentProfile);
    await activateProfile(currentProfile.id!);
    const preTeardownSnapshot = await callOffscreenRpc<RuntimeSnapshotResult>('runtime.snapshot');
    assertNoncePoolHydrated(
      'runtime-lifecycle restored pre-sign snapshot',
      preTeardownSnapshot,
      2,
      1
    );

    await runRuntimeControl('closeOffscreen');
    await activateProfile(currentProfile.id!);
    assertNoncePoolHydrated(
      'runtime-lifecycle restored post-teardown snapshot',
      await callOffscreenRpc<RuntimeSnapshotResult>('runtime.snapshot'),
      2,
      1
    );

    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = page.evaluate(() => window.nostr!.getPublicKey());

    const prompt = await promptPromise;
    await expect(prompt.getByText('wants to read your public key')).toBeVisible();
    await approvePromptOnce(prompt);

    await expect(resultPromise).resolves.toBe(liveSigner.profile.publicKey);
    await expect(
      callOffscreenRpc<{ runtime: 'cold' | 'restoring' | 'ready' | 'degraded'; status: unknown }>(
        'runtime.status'
      )
    ).resolves.toMatchObject({
      runtime: expect.stringMatching(/^(ready|degraded)$/)
    });

    await page.close();
  });

  test('provider getPublicKey prompts still complete while the runtime stays cold after offscreen teardown', async ({
    activateProfile,
    callOffscreenRpc,
    context,
    liveSigner,
    openExtensionPage,
    runRuntimeControl,
    server,
    seedProfile
  }) => {
    const currentProfile = await onboardLiveSignerProfile(
      async (targetPath: string) => await openExtensionPage(targetPath),
      liveSigner.profile,
      `${liveSigner.profile.groupName} Cold Restore`
    );
    await seedProfile(currentProfile);
    await activateProfile(currentProfile.id!);

    await runRuntimeControl('closeOffscreen');

    const dashboard = await openExtensionPage('options.html');
    const status = await fetchExtensionStatus(dashboard);
    expect(status).toMatchObject({
      runtime: 'cold',
      runtimeDetails: {
        status: null,
        snapshot: null,
        snapshotError: null
      }
    });
    await dashboard.close();

    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = page.evaluate(() => window.nostr!.getPublicKey());

    const prompt = await promptPromise;
    await expect(prompt.getByText('wants to read your public key')).toBeVisible();
    await approvePromptOnce(prompt);

    await expect(resultPromise).resolves.toBe(liveSigner.profile.publicKey);

    await expect(
      callOffscreenRpc<{ runtime: 'cold' | 'restoring' | 'ready' | 'degraded'; status: unknown }>(
        'runtime.status'
      )
    ).resolves.toMatchObject({
      runtime: 'cold'
    });

    await page.close();
  });

  test('restores signer nonce state after offscreen teardown so signEvent still succeeds', async ({
    activateProfile,
    callOffscreenRpc,
    context,
    liveSigner,
    openExtensionPage,
    runRuntimeControl,
    server,
    seedProfile
  }) => {
    const currentProfile = await onboardLiveSignerProfile(
      async (targetPath: string) => await openExtensionPage(targetPath),
      liveSigner.profile,
      `${liveSigner.profile.groupName} Restored Sign`
    );
    await seedProfile(currentProfile);
    await ensureRuntimeReady(activateProfile, currentProfile.id!);

    await runRuntimeControl('closeOffscreen');
    await ensureRuntimeReady(activateProfile, currentProfile.id!);
    await prepareSignReady(callOffscreenRpc, 'runtime-lifecycle restored sign');

    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = page.evaluate(async (event) => {
      try {
        return { ok: true, event: await window.nostr!.signEvent(event), message: null };
      } catch (error) {
        return {
          ok: false,
          event: null,
          message: error instanceof Error ? error.message : String(error)
        };
      }
    }, SIGN_EVENT_PAYLOAD);

    const prompt = await promptPromise;
    await expect(prompt.getByText('wants to sign a Nostr event')).toBeVisible();
    await approvePromptOnce(prompt);

    const result = await resultPromise;
    if (!result.ok) {
      const snapshot = await callOffscreenRpc<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        status: unknown;
        snapshot: unknown;
        snapshotError: string | null;
      }>('runtime.snapshot');
      const diagnostics = await callOffscreenRpc<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        diagnostics: RuntimeDiagnosticEvent[];
        dropped: number;
      }>('runtime.diagnostics');
      throw new Error(
        `restored signEvent failed: ${result.message}\n${JSON.stringify({ snapshot, diagnostics }, null, 2)}`
      );
    }

    expect(result.event).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      created_at: SIGN_EVENT_PAYLOAD.created_at,
      content: SIGN_EVENT_PAYLOAD.content,
      pubkey: liveSigner.profile.publicKey
    });

    await page.close();
  });

  test('recovers provider access after extension context relaunch', async ({
    server,
    liveSigner
  }) => {
    const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-relaunch-'));
    let firstContext: BrowserContext | null = null;
    let secondContext: BrowserContext | null = null;

    try {
      firstContext = await launchExtensionContext(userDataDir);
      const firstWorker = await waitForServiceWorker(firstContext);
      const extensionId = new URL(firstWorker.url()).host;
      await completeOnboardingInContext(firstContext, extensionId, liveSigner.profile);
      await closeContextSafely(firstContext);
      firstContext = null;

      secondContext = await launchExtensionContext(userDataDir);
      await waitForServiceWorker(secondContext);
      await unlockStoredProfileInContext(secondContext, extensionId, liveSigner.profile.onboardPassword);

      const page = await secondContext.newPage();
      await page.goto(`${server.origin}/provider`);

      await expect
        .poll(async () => {
          return await page.evaluate(() => ({
            hasNostr: typeof window.nostr === 'object',
            hasGetPublicKey: typeof window.nostr?.getPublicKey === 'function'
          }));
        })
        .toEqual({
          hasNostr: true,
          hasGetPublicKey: true
        });

      const promptPromise = secondContext.waitForEvent(
        'page',
        (candidate) => candidate.url().includes('/prompt.html')
      );
      const resultPromise = page.evaluate(() => window.nostr!.getPublicKey());

      const prompt = await promptPromise;
      await expect(prompt.getByText('wants to read your public key')).toBeVisible();
      await approvePromptOnce(prompt);

      await expect(resultPromise).resolves.toBe(liveSigner.profile.publicKey);
      await page.close();
    } finally {
      await closeContextSafely(secondContext).catch(() => undefined);
      await closeContextSafely(firstContext).catch(() => undefined);
      await rm(userDataDir, { recursive: true, force: true });
    }
  });

  test('restores signEvent capability after a full browser-context relaunch', async ({
    server,
    liveSigner
  }) => {
    const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-relaunch-sign-'));
    let firstContext: BrowserContext | null = null;
    let secondContext: BrowserContext | null = null;

    try {
      firstContext = await launchExtensionContext(userDataDir);
      const firstWorker = await waitForServiceWorker(firstContext);
      const firstExtensionId = new URL(firstWorker.url()).host;
      await completeOnboardingInContext(firstContext, firstExtensionId, liveSigner.profile);
      await closeContextSafely(firstContext);
      firstContext = null;

      secondContext = await launchExtensionContext(userDataDir);
      const secondWorker = await waitForServiceWorker(secondContext);
      const secondExtensionId = new URL(secondWorker.url()).host;
      await unlockStoredProfileInContext(
        secondContext,
        secondExtensionId,
        liveSigner.profile.onboardPassword
      );

      const page = await secondContext.newPage();
      await page.goto(`${server.origin}/provider`);

      const promptPromise = secondContext.waitForEvent(
        'page',
        (candidate) => candidate.url().includes('/prompt.html')
      );
      const resultPromise = page.evaluate(async (event) => await window.nostr!.signEvent(event), SIGN_EVENT_PAYLOAD);

      const prompt = await promptPromise;
      await expect(prompt.getByText('wants to sign a Nostr event')).toBeVisible();
      await approvePromptOnce(prompt);

      await expect(resultPromise).resolves.toMatchObject({
        kind: SIGN_EVENT_PAYLOAD.kind,
        created_at: SIGN_EVENT_PAYLOAD.created_at,
        content: SIGN_EVENT_PAYLOAD.content,
        pubkey: liveSigner.profile.publicKey
      });

      const statusPage = await secondContext.newPage();
      await gotoExtensionPage(statusPage, secondExtensionId, 'options.html');
      const status = await fetchExtensionStatusFromPage<ExtensionStatusSnapshot>(statusPage);
      expect(status.runtime).toMatch(/^(ready|degraded)$/);
      expect(status.runtimeDetails?.summary?.metadata?.group_public_key).toBe(
        liveSigner.profile.publicKey
      );
      expect(status.runtimeDetails?.summary?.readiness?.sign_ready).toBe(true);

      await statusPage.close();
      await page.close();
    } finally {
      await closeContextSafely(secondContext).catch(() => undefined);
      await closeContextSafely(firstContext).catch(() => undefined);
      await rm(userDataDir, { recursive: true, force: true });
    }
  });
});
