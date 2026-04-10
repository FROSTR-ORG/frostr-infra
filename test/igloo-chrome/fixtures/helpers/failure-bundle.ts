import { writeFile } from 'node:fs/promises';

import type { BrowserContext, TestInfo } from '@playwright/test';

import { getE2EEvents } from '../../../shared/observability';
import {
  fetchExtensionAppStateFromPage,
  fetchRuntimeDiagnosticsFromPage,
  fetchWorkerStorageSnapshot,
} from '../../support/extension-status';
import {
  getPageDiagnostics,
  getWorkerOnboardingFailureBundle,
} from './fixture-state';
import { openPageForStorage } from './transport';

export async function collectFailureBundle(context: BrowserContext, extensionId: string) {
  const page = await openPageForStorage(context, extensionId).catch(() => null);
  if (!page) {
    return {
      e2eEvents: getE2EEvents(),
      extensionDiagnosticsError: 'failed to open extension storage page',
      workerOnboardingFailureBundle: getWorkerOnboardingFailureBundle(),
    };
  }

  try {
    const runtimeDiagnostics = await fetchRuntimeDiagnosticsFromPage(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error),
    }));
    const state = await fetchExtensionAppStateFromPage(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error),
    }));
    const storageSnapshot = await fetchWorkerStorageSnapshot(page).catch((error) => ({
      error: error instanceof Error ? error.message : String(error),
    }));
    return {
      e2eEvents: getE2EEvents(),
      runtimeDiagnostics,
      state,
      storageSnapshot,
      pageDiagnostics: getPageDiagnostics(),
      workerOnboardingFailureBundle: getWorkerOnboardingFailureBundle(),
    };
  } finally {
    await page.close().catch(() => undefined);
  }
}

export async function writeFailureBundle(
  testInfo: TestInfo,
  context: BrowserContext,
  extensionId: string
) {
  const filePath = testInfo.outputPath('observability-bundle.json');
  const bundle = await collectFailureBundle(context, extensionId);
  await writeFile(filePath, JSON.stringify(bundle, null, 2), 'utf8');
  await testInfo.attach('observability-bundle', {
    path: filePath,
    contentType: 'application/json',
  });
}
