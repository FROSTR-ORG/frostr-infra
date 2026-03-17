import { verifyEvent } from 'nostr-tools/pure';

import type { Page } from '@playwright/test';

import { test, expect } from '../fixtures/extension';
import { logE2E, withLoggedStep } from '../../shared/observability';
import {
  assertNoncePoolHydrated,
  type RuntimeDiagnosticEvent,
  type RuntimeSnapshotResult
} from '../support/runtime';
import { onboardLiveSignerProfile } from '../support/onboarding';

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

test.describe('demo harness onboarding @live', () => {
  test.setTimeout(360_000);

  test('onboards from igloo-demo and signs through the live demo node', async ({
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

    const storedProfile = await withLoggedStep(
      'chrome.demo-harness.spec',
      'onboard-via-helper',
      {
        recipient: demoHarness.recipient,
        relayUrl: demoHarness.relayUrl,
        onboardLength: demoHarness.onboardPackage.length
      },
      async () =>
        await onboardLiveSignerProfile(
          async (targetPath: string) => {
            const page = await openExtensionPage(targetPath);
            attachPageConsoleLogging(page, 'options');
            return page;
          },
          {
            keysetName: `Demo Harness ${demoHarness.recipient}`,
            onboardPackage: demoHarness.onboardPackage,
            onboardPassword: demoHarness.onboardPassword,
            publicKey: '',
            peerPubkey: ''
          },
          `Demo Harness ${demoHarness.recipient}`
        )
    );

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
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
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
