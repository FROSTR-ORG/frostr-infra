import { expect, type Page } from '@playwright/test';
import { logE2E } from '../../shared/observability';
import { fetchExtensionAppStateFromPage, fetchExtensionStatusFromPage } from './extension-status';

const ONBOARDING_UI_TIMEOUT_MS = 35_000;

type LiveOnboardingProfile = {
  keysetName?: string;
  onboardPackage?: string;
  onboardPassword?: string;
  publicKey: string;
  peerPubkey: string;
};

export type StoredProfile = {
  keysetName?: string;
  relays: string[];
  publicKey?: string;
  groupPublicKey?: string;
  peerPubkey?: string;
  runtimeSnapshotJson?: string;
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

async function waitForSignerUi(page: Page, keysetName: string) {
  const errorBanner = page.locator('div').filter({
    hasText: /Connection timed out|Failed to connect onboarding|Failed during onboard|error/i
  });

  await expect
    .poll(async () => {
      const status = await fetchLifecycleStatus(page);
      logE2E('chrome.support.onboarding', 'status-poll', {
        onboarding_stage: status.lifecycle.onboarding.stage,
        activation_stage: status.lifecycle.activation.stage,
        runtime: status.runtime
      });
      if (status.lifecycle.onboarding.lastError) {
        return `onboarding_failed:${status.lifecycle.onboarding.lastError.message}`;
      }
      if (status.lifecycle.activation.lastError) {
        return `activation_failed:${status.lifecycle.activation.lastError.message}`;
      }
      if (
        status.configured &&
        (status.lifecycle.activation.stage === 'ready' || status.lifecycle.activation.stage === 'degraded')
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
        sawWelcome: false,
        sawSetup: false,
        connectDisabled: null as boolean | null,
        lifecycle: status,
        appRoute: null as string | null,
        appHydrating: null as string | null,
        appState: null as unknown
      };
      await Promise.all([
        page.locator('body').textContent().then((text) => {
          diagnostics.body = (text ?? '').replace(/\s+/g, ' ').trim().slice(0, 1000);
        }),
        page
          .getByText('Welcome to igloo chrome')
          .isVisible()
          .then((visible) => {
            diagnostics.sawWelcome = visible;
          })
          .catch(() => {}),
        page
          .getByPlaceholder('e.g. Laptop Signer, Browser Node A')
          .isVisible()
          .then((visible) => {
            diagnostics.sawSetup = visible;
          })
          .catch(() => {}),
        page
          .getByRole('button', { name: 'Connect and Continue' })
          .isDisabled()
          .then((disabled) => {
            diagnostics.connectDisabled = disabled;
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
          .catch(() => {})
      ]);
      throw new Error(
        `Onboarding did not reach signer UI: ${error instanceof Error ? error.message : String(error)} | url=${diagnostics.url} | welcome=${diagnostics.sawWelcome} | setup=${diagnostics.sawSetup} | connectDisabled=${diagnostics.connectDisabled} | route=${diagnostics.appRoute} | hydrating=${diagnostics.appHydrating} | lifecycle=${JSON.stringify(diagnostics.lifecycle)} | appState=${JSON.stringify(diagnostics.appState)} | body=${diagnostics.body}`
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
  keysetName = profile.keysetName ?? 'Playwright Live'
): Promise<StoredProfile> {
  if (!profile.onboardPackage || !profile.onboardPassword) {
    throw new Error('Live signer profile is missing onboarding package material');
  }

  const page = await openExtensionPage('options.html');
  try {
    logE2E('chrome.support.onboarding', 'open-options');
    await expect(page.getByText('Welcome to igloo chrome')).toBeVisible();
    await page.getByRole('button', { name: 'Continue to Setup' }).click();
    logE2E('chrome.support.onboarding', 'continue-to-setup-clicked');
    await expect(page.getByPlaceholder('e.g. Laptop Signer, Browser Node A')).toBeVisible();
    logE2E('chrome.support.onboarding', 'setup-form-visible');
    await page.getByPlaceholder('e.g. Laptop Signer, Browser Node A').fill(keysetName);
    await page.getByPlaceholder('bfonboard1...').fill(profile.onboardPackage);
    await page.getByPlaceholder('Minimum 8 characters').fill(profile.onboardPassword);
    logE2E('chrome.support.onboarding', 'setup-inputs-filled', {
      keysetName
    });
    await page.getByRole('button', { name: 'Connect and Continue' }).click();
    logE2E('chrome.support.onboarding', 'submit-clicked');

    await waitForSignerUi(page, keysetName);
    logE2E('chrome.support.onboarding', 'signer-ui-ready');

    const appState = await fetchExtensionAppStateFromPage<{ profile: StoredProfile | null }>(page);
    if (!appState.profile) {
      throw new Error('missing stored profile after onboarding');
    }
    return appState.profile;
  } finally {
    if (!page.isClosed()) {
      await page.close();
    }
  }
}
