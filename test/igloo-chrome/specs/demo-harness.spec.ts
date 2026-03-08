import { verifyEvent } from 'nostr-tools/pure';

import type { Page } from '@playwright/test';

import { test, expect } from '../fixtures/extension';
import { logE2E, withLoggedStep } from '../../shared/observability';
import {
  assertNoncePoolHydrated,
  type RuntimeDiagnosticEvent,
  type RuntimeSnapshotResult
} from '../support/runtime';

const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_100,
  tags: [],
  content: 'playwright demo-harness signEvent'
};

type ProviderSignResult = {
  ok: boolean;
  event: unknown;
  message: string | null;
};

type StoredProfile = {
  keysetName?: string;
  relays: string[];
  publicKey?: string;
  groupPublicKey?: string;
  peerPubkey?: string;
};

async function approvePromptOnce(prompt: import('@playwright/test').Page) {
  await withLoggedStep('chrome.demo-harness.spec', 'prompt-approve', undefined, async () => {
    await prompt.waitForLoadState('domcontentloaded');
    await prompt
      .getByRole('button', { name: 'Allow once' })
      .evaluate((button: HTMLButtonElement) => button.click())
      .catch(() => {
        // The background closes the prompt as part of successful approval.
      });
  });
}

function attachPageConsoleLogging(page: Page, label: string) {
  page.on('console', (message) => {
    const text = message.text();
    try {
      const parsed = JSON.parse(text) as Record<string, unknown>;
      logE2E(`chrome.page.${label}`, 'console', {
        console_type: message.type(),
        ...parsed
      });
      return;
    } catch {
      // Fall through to raw console capture.
    }

    logE2E(`chrome.page.${label}`, 'console', {
      console_type: message.type(),
      message: text
    });
  });
}

async function requestProviderSign(
  context: import('@playwright/test').BrowserContext,
  providerPage: Page
): Promise<ProviderSignResult> {
  const promptPromise = withLoggedStep(
    'chrome.demo-harness.spec',
    'wait-provider-prompt',
    undefined,
    async () =>
      await context.waitForEvent(
        'page',
        (candidate) => candidate.url().includes('/prompt.html')
      )
  );
  const resultPromise = withLoggedStep(
    'chrome.demo-harness.spec',
    'provider-sign-event',
    undefined,
    async () =>
      await providerPage.evaluate(async (event) => {
        try {
          return { ok: true, event: await window.nostr!.signEvent(event), message: null };
        } catch (error) {
          return {
            ok: false,
            event: null,
            message: error instanceof Error ? error.message : String(error)
          };
        }
      }, SIGN_EVENT_PAYLOAD)
  );

  const prompt = await promptPromise;
  await withLoggedStep('chrome.demo-harness.spec', 'assert-provider-prompt', undefined, async () => {
    await expect(prompt.getByText('wants to sign a Nostr event')).toBeVisible();
  });
  await approvePromptOnce(prompt);
  return await resultPromise;
}

async function waitForSignerUiOrError(page: Page, recipient: string) {
  const signerName = `Demo Harness ${recipient}`;
  const errorBanner = page.locator('div').filter({
    hasText: /Connection timed out|Failed to connect onboarding|Failed during onboard|error/i
  });
  let outcome: 'signer' | 'error';
  try {
    outcome = await Promise.race([
      page
        .getByText(signerName)
        .waitFor({ state: 'visible', timeout: 10_000 })
        .then(() => 'signer' as const),
      errorBanner
        .first()
        .waitFor({ state: 'visible', timeout: 10_000 })
        .then(() => 'error' as const)
    ]);
  } catch (error) {
    const bodyText = ((await page.locator('body').textContent()) ?? '').replace(/\s+/g, ' ').trim();
    throw new Error(
      `Onboarding did not reach signer UI: ${error instanceof Error ? error.message : String(error)} | page=${bodyText.slice(0, 600)}`
    );
  }

  if (outcome === 'error') {
    const errorText = (await errorBanner.first().textContent())?.trim() || 'unknown onboarding error';
    throw new Error(`Onboarding did not reach signer UI: ${errorText}`);
  }

  await expect(page.getByRole('button', { name: /Signer runtime console/i })).toBeVisible();
}

test.describe('demo harness onboarding', () => {
  test.setTimeout(360_000);

  test('onboards from bifrost-demo and signs through the live demo node', async ({
    callOffscreenRpc,
    clearExtensionStorage,
    context,
    demoHarness,
    openExtensionPage,
    server
  }) => {
    await withLoggedStep('chrome.demo-harness.spec', 'clear-storage', undefined, async () => {
      await clearExtensionStorage();
    });

    const page = await withLoggedStep(
      'chrome.demo-harness.spec',
      'open-options',
      undefined,
      async () => await openExtensionPage('options.html')
    );
    attachPageConsoleLogging(page, 'options');

    await withLoggedStep('chrome.demo-harness.spec', 'fill-onboarding', {
      recipient: demoHarness.recipient,
      relayUrl: demoHarness.relayUrl,
      onboardLength: demoHarness.onboardPackage.length
    }, async () => {
      await expect(page.getByText('Welcome to igloo web')).toBeVisible();
      await page.getByRole('button', { name: 'Continue to Setup' }).click();
      await page.getByPlaceholder('e.g. Laptop Signer, Browser Node A').fill(
        `Demo Harness ${demoHarness.recipient}`
      );
      await page.getByPlaceholder('bfonboard1...').fill(demoHarness.onboardPackage);
      await page.getByPlaceholder('Minimum 8 characters').fill(demoHarness.onboardPassword);
      await page.locator('textarea').nth(1).fill(demoHarness.relayUrl);
    });

    await withLoggedStep('chrome.demo-harness.spec', 'submit-onboarding', undefined, async () => {
      await page.getByRole('button', { name: 'Connect and Continue' }).click();
    });

    await withLoggedStep('chrome.demo-harness.spec', 'wait-signer-ui', undefined, async () => {
      await waitForSignerUiOrError(page, demoHarness.recipient);
    });

    const storedProfile = await withLoggedStep(
      'chrome.demo-harness.spec',
      'read-stored-profile',
      undefined,
      async () =>
        await page.evaluate(() => {
          const raw = window.localStorage.getItem('igloo.v2.profile');
          if (!raw) {
            throw new Error('missing stored profile after onboarding');
          }
          return JSON.parse(raw) as StoredProfile;
        })
    );

    const localSnapshot = await withLoggedStep(
      'chrome.demo-harness.spec',
      'read-local-runtime-snapshot',
      undefined,
      async () =>
        await page.evaluate(() => {
          const raw = window.localStorage.getItem('igloo.ext.runtimeSnapshot');
          if (!raw) {
            throw new Error('missing local runtime snapshot after onboarding');
          }
          return {
            runtime: 'ready' as const,
            status: null,
            snapshot: JSON.parse(raw),
            snapshotError: null
          } satisfies RuntimeSnapshotResult;
        })
    );

    await withLoggedStep(
      'chrome.demo-harness.spec',
      'assert-local-nonce-hydration',
      undefined,
      async () => {
        assertNoncePoolHydrated('local onboarding snapshot', localSnapshot, 2, 1);
      }
    );

    await withLoggedStep('chrome.demo-harness.spec', 'close-options-after-onboarding', undefined, async () => {
      await page.close();
    });

    await withLoggedStep(
      'chrome.demo-harness.spec',
      'ensure-offscreen-runtime',
      undefined,
      async () => {
        await callOffscreenRpc('runtime.ensure', {
          profile: storedProfile
        });
      }
    );

    const offscreenSnapshot = await withLoggedStep(
      'chrome.demo-harness.spec',
      'read-offscreen-runtime-snapshot',
      undefined,
      async () =>
        await callOffscreenRpc<RuntimeSnapshotResult>('runtime.snapshot')
    );

    await withLoggedStep(
      'chrome.demo-harness.spec',
      'assert-offscreen-nonce-hydration',
      undefined,
      async () => {
        assertNoncePoolHydrated('offscreen restored snapshot', offscreenSnapshot, 2, 1);
      }
    );

    const providerPage = await withLoggedStep(
      'chrome.demo-harness.spec',
      'open-provider-page',
      { origin: server.origin },
      async () => {
        const nextPage = await context.newPage();
        attachPageConsoleLogging(nextPage, 'provider');
        await nextPage.goto(`${server.origin}/provider`);
        return nextPage;
      }
    );

    const result = await requestProviderSign(context, providerPage);

    if (!result.ok) {
      const diagnostics = await callOffscreenRpc<{
        runtime: 'cold' | 'ready';
        diagnostics: RuntimeDiagnosticEvent[];
        dropped: number;
      }>('runtime.diagnostics');
      throw new Error(
        `demo harness signEvent failed: ${result.message}\n${JSON.stringify(diagnostics.diagnostics.slice(-12), null, 2)}`
      );
    }

    expect(result.ok).toBe(true);
    expect(result.message).toBeNull();
    const signedEvent = result.event as Record<string, unknown>;
    expect(signedEvent).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      content: SIGN_EVENT_PAYLOAD.content,
      created_at: SIGN_EVENT_PAYLOAD.created_at
    });
    expect(typeof signedEvent.pubkey).toBe('string');
    expect(typeof signedEvent.id).toBe('string');
    expect(typeof signedEvent.sig).toBe('string');
    expect(verifyEvent(signedEvent as Parameters<typeof verifyEvent>[0])).toBe(true);

    await providerPage.close();
  });
});
