import os from 'node:os';
import path from 'node:path';
import { existsSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';

import { chromium, type BrowserContext, type Page } from '@playwright/test';

import { logE2E } from '../../../shared/observability';
import { IGLOO_CHROME_DIST_DIR } from '../../../shared/repo-paths';
import { recordPageDiagnostic } from './fixture-state';

const DEMO_RELAY_PORT = Number(
  process.env.IGLOO_DEMO_RELAY_PORT ?? String(43000 + (process.pid % 1000))
);
const EXTENSION_MANIFEST_PATH = path.join(IGLOO_CHROME_DIST_DIR, 'manifest.json');

let buildPrepared = false;

const EXPECTED_CONSOLE_WARNING_EVENTS = [
  '"event":"load_module_begin"',
  '"event":"subscription_closed"',
  '"event":"probe_failed"',
  '"event":"command_timeout"',
];

function extensionLaunchArgs(extensionPath: string) {
  const secureOrigins = [
    `http://127.0.0.1:${DEMO_RELAY_PORT}`,
    `http://localhost:${DEMO_RELAY_PORT}`,
  ];
  return [
    `--unsafely-treat-insecure-origin-as-secure=${secureOrigins.join(',')}`,
    `--disable-extensions-except=${extensionPath}`,
    `--load-extension=${extensionPath}`,
  ];
}

export function buildExtensionOnce(extensionPath: string) {
  if (buildPrepared) return;
  if (!existsSync(EXTENSION_MANIFEST_PATH)) {
    throw new Error(
      `Missing built extension at ${EXTENSION_MANIFEST_PATH}. Run the Playwright global setup or npm run build in repos/igloo-chrome first.`
    );
  }
  logE2E('chrome.fixture', 'build-extension:ready', {
    manifestPath: EXTENSION_MANIFEST_PATH,
  });
  buildPrepared = true;
}

export async function launchExtensionContext(extensionPath: string) {
  buildExtensionOnce(extensionPath);
  const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-pw-'));
  const context = await chromium.launchPersistentContext(userDataDir, {
    channel: 'chromium',
    headless: true,
    args: extensionLaunchArgs(extensionPath),
  });
  return { context, userDataDir };
}

export async function disposeExtensionContext(context: BrowserContext, userDataDir: string) {
  try {
    await context.close();
  } catch (error) {
    if (
      !(error instanceof Error) ||
      !error.message.includes('ENOENT: no such file or directory') ||
      (!error.message.includes('.playwright-artifacts-') &&
        !error.message.includes('recording') &&
        !error.message.includes('.zip'))
    ) {
      throw error;
    }
    logE2E('chrome.fixture', 'close-context:ignoring-playwright-artifact-error', {
      error_message: error.message,
    });
  }
  await rm(userDataDir, { recursive: true, force: true });
}

export async function waitForServiceWorker(context: BrowserContext) {
  const existing = context.serviceWorkers();
  if (existing.length > 0) return existing[0];
  return await context.waitForEvent('serviceworker');
}

export async function gotoExtensionPage(
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
        timeout: 3_000,
      })
      .catch((error) => {
        recordPageDiagnostic(
          page.url(),
          `app-ready-timeout: ${error instanceof Error ? error.message : String(error)}`
        );
      });
  }
}

export function isExpectedConsoleNoise(type: string, text: string) {
  if (
    type === 'error' &&
    text.includes('Failed to load resource: the server responded with a status of 404')
  ) {
    return true;
  }
  if (type !== 'warning') {
    return false;
  }
  if (EXPECTED_CONSOLE_WARNING_EVENTS.some((event) => text.includes(event))) {
    return true;
  }
  return (
    text.includes('"event":"persist_snapshot_failed"') &&
    text.includes('Stored profile') &&
    text.includes('was not found')
  );
}

export function attachPageDiagnostics(page: Page) {
  page.on('pageerror', (error) => {
    recordPageDiagnostic(page.url(), `pageerror: ${error.message}`);
  });
  page.on('console', (message) => {
    if (isExpectedConsoleNoise(message.type(), message.text())) {
      return;
    }
    recordPageDiagnostic(page.url(), `console.${message.type()}: ${message.text()}`);
    logE2E('chrome.page', 'console', {
      url: page.url(),
      console_type: message.type(),
      text: message.text(),
    });
  });
}
