import { test, expect } from '../fixtures/extension';
import { verifyEvent } from 'nostr-tools/pure';
import type { RuntimeDiagnosticEvent, RuntimeSnapshotResult } from '../support/runtime';
import {
  approvePromptOnce,
  buildSignFailureMessage,
  prepareSignReady,
  SIGN_EVENT_PAYLOAD
} from '../support/provider-live';

test.describe('provider bridge live signer sign flow @live', () => {
  test.setTimeout(180_000);

  test('getPublicKey always returns the group public key', async ({
    context,
    server,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner
  }) => {
    await seedProfile(onboardedLiveSignerProfile);

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

    await expect(resultPromise).resolves.toBe(stableLiveSigner.profile.publicKey);
    await page.close();
  });

  test('signEvent succeeds against a live responder after bootstrap hydration', async ({
    callOffscreenRpc,
    context,
    server,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await callOffscreenRpc('runtime.ensure', {
      profile: onboardedLiveSignerProfile
    });
    await prepareSignReady(callOffscreenRpc, 'provider-live pre-sign readiness');

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
      const diagnostics = await callOffscreenRpc<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        diagnostics: RuntimeDiagnosticEvent[];
        dropped: number;
      }>('runtime.diagnostics');
      throw new Error(buildSignFailureMessage(result.message, diagnostics.diagnostics));
    }

    expect(result.event).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      content: SIGN_EVENT_PAYLOAD.content,
      created_at: SIGN_EVENT_PAYLOAD.created_at,
      pubkey: stableLiveSigner.profile.publicKey
    });
    expect(result.event?.tags).toEqual(SIGN_EVENT_PAYLOAD.tags);
    expect(typeof result.event?.id).toBe('string');
    expect(typeof result.event?.sig).toBe('string');
    expect(verifyEvent(result.event!)).toBe(true);
    await page.close();
  });

  test('signEvent fails cleanly when the live responder disappears mid-session', async ({
    callOffscreenRpc,
    context,
    server,
    stableLiveSigner,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await callOffscreenRpc('runtime.ensure', {
      profile: onboardedLiveSignerProfile
    });
    await callOffscreenRpc<RuntimeSnapshotResult>('runtime.snapshot');
    await stableLiveSigner.stopResponder();

    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = page.evaluate(async (event) => {
      try {
        await window.nostr!.signEvent(event);
        return { ok: true, message: null };
      } catch (error) {
        return {
          ok: false,
          message: error instanceof Error ? error.message : String(error)
        };
      }
    }, SIGN_EVENT_PAYLOAD);

    const prompt = await promptPromise;
    await expect(prompt.getByText('wants to sign a Nostr event')).toBeVisible();
    await approvePromptOnce(prompt);

    await expect(resultPromise).resolves.toMatchObject({
      ok: false,
      message: expect.any(String)
    });
    await page.close();
  });
});
