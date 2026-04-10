import { test, expect } from '../fixtures/extension';
import {
  assertNoncePoolHydrated,
  type RuntimeDiagnosticEvent,
  type RuntimeSnapshotResult
} from '../support/runtime';
import {
  approvePromptOnce,
  ensureRuntimeReady,
  fetchExtensionStatus,
  getProviderPublicKeyWithApproval,
  signProviderEventWithApproval,
  waitForNonceHydration,
  withUnlockedRelaunchContext,
} from '../support/runtime-lifecycle';
import { seedAndActivateLiveProfile } from '../support/live-runtime';

const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_000,
  tags: [],
  content: 'playwright restored signEvent'
};

test.describe('runtime lifecycle @live', () => {
  test.setTimeout(180_000);

  test('recreates the runtime after explicit teardown', async ({
    activateProfile,
    context,
    fetchRuntimeSnapshot,
    fetchRuntimeStatus,
    onboardedLiveSignerProfile,
    runRuntimeControl,
    server,
    seedProfile
  }) => {
    await seedAndActivateLiveProfile({
      seedProfile,
      activateProfile,
      profile: onboardedLiveSignerProfile,
    });
    const preTeardownSnapshot = await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
    assertNoncePoolHydrated(
      'runtime-lifecycle restored pre-sign snapshot',
      preTeardownSnapshot,
      2,
      1
    );

    await runRuntimeControl('stopRuntime');
    await activateProfile(onboardedLiveSignerProfile.id!);
    assertNoncePoolHydrated(
      'runtime-lifecycle restored post-teardown snapshot',
      await fetchRuntimeSnapshot<RuntimeSnapshotResult>(),
      2,
      1
    );

    await expect(
      getProviderPublicKeyWithApproval(context, server.origin)
    ).resolves.toBe(onboardedLiveSignerProfile.publicKey);
    await expect(fetchRuntimeStatus<{ runtime: 'cold' | 'restoring' | 'ready' | 'degraded'; status: unknown }>()).resolves.toMatchObject({
      runtime: expect.stringMatching(/^(ready|degraded)$/)
    });
  });

  test('provider getPublicKey prompts still complete while the runtime stays cold after explicit teardown', async ({
    activateProfile,
    context,
    fetchRuntimeStatus,
    onboardedLiveSignerProfile,
    openExtensionPage,
    runRuntimeControl,
    server,
    seedProfile
  }) => {
    await seedAndActivateLiveProfile({
      seedProfile,
      activateProfile,
      profile: onboardedLiveSignerProfile,
    });

    await runRuntimeControl('stopRuntime');

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

    await expect(
      getProviderPublicKeyWithApproval(context, server.origin)
    ).resolves.toBe(onboardedLiveSignerProfile.publicKey);

    await expect(fetchRuntimeStatus<{ runtime: 'cold' | 'restoring' | 'ready' | 'degraded'; status: unknown }>()).resolves.toMatchObject({
      runtime: 'cold'
    });
  });

  test('restores signer nonce state after runtime teardown so signEvent still succeeds', async ({
    activateProfile,
    context,
    fetchRuntimeDiagnostics,
    fetchRuntimeSnapshot,
    onboardedLiveSignerProfile,
    runRuntimeControl,
    server,
    seedProfile,
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await ensureRuntimeReady(activateProfile, onboardedLiveSignerProfile.id!);

    await runRuntimeControl('stopRuntime');
    await ensureRuntimeReady(activateProfile, onboardedLiveSignerProfile.id!);
    await waitForNonceHydration(
      fetchRuntimeSnapshot,
      'runtime-lifecycle restored sign snapshot',
      2,
      1
    );

    const result = await signProviderEventWithApproval(context, server.origin, SIGN_EVENT_PAYLOAD);
    if (!result.ok) {
      const snapshot = await fetchRuntimeSnapshot<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        status: unknown;
        snapshot: unknown;
        snapshotError: string | null;
      }>();
      const diagnostics = await fetchRuntimeDiagnostics<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        diagnostics: RuntimeDiagnosticEvent[];
        dropped: number;
      }>();
      throw new Error(
        `restored signEvent failed: ${result.message}\n${JSON.stringify({ snapshot, diagnostics }, null, 2)}`
      );
    }

    expect(result.event).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      created_at: SIGN_EVENT_PAYLOAD.created_at,
      content: SIGN_EVENT_PAYLOAD.content,
      pubkey: onboardedLiveSignerProfile.publicKey
    });
  });

  test('recovers provider access after extension context relaunch', async ({
    server,
    stableLiveSigner
  }) => {
    await withUnlockedRelaunchContext({
      profile: stableLiveSigner.profile,
      callback: async ({ context: secondContext }) => {
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

        await expect(resultPromise).resolves.toBe(stableLiveSigner.profile.publicKey);
        await page.close();
      },
    });
  });

  test('restores signEvent capability after a full browser-context relaunch', async ({
    server,
    stableLiveSigner
  }) => {
    await withUnlockedRelaunchContext({
      profile: stableLiveSigner.profile,
      callback: async ({ context: secondContext, extensionId: secondExtensionId }) => {
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
          pubkey: stableLiveSigner.profile.publicKey
        });

        const statusPage = await secondContext.newPage();
        await statusPage.goto(`chrome-extension://${secondExtensionId}/options.html`);
        const status = await fetchExtensionStatus(statusPage);
        expect(status.runtime).toMatch(/^(ready|degraded)$/);
        expect(status.runtimeDetails?.summary?.metadata?.group_public_key).toBe(
          stableLiveSigner.profile.publicKey
        );
        expect(status.runtimeDetails?.summary?.readiness?.sign_ready).toBe(true);

        await statusPage.close();
        await page.close();
      },
    });
  });
});
