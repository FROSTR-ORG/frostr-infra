import { test, expect } from '../fixtures/extension';
import { verifyEvent } from 'nostr-tools/pure';
import type { RuntimeDiagnosticEvent, RuntimeSnapshotResult } from '../support/runtime';
import {
  buildSignFailureMessage,
  runProviderActionWithApproval,
  SIGN_EVENT_PAYLOAD,
} from '../support/provider-live';
import { prepareLiveProfileForSigning, seedAndActivateLiveProfile } from '../support/live-runtime';

test.describe('provider bridge live signer sign flow @live', () => {
  test.setTimeout(180_000);

  test('getPublicKey always returns the group public key', async ({
    context,
    server,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await seedProfile(onboardedLiveSignerProfile);

    await expect(
      runProviderActionWithApproval(
        context,
        server.origin,
        'wants to read your public key',
        async (page) => await page.evaluate(() => window.nostr!.getPublicKey())
      )
    ).resolves.toBe(onboardedLiveSignerProfile.publicKey);
  });

  test('signEvent succeeds against a live responder after bootstrap hydration', async ({
    activateProfile,
    fetchRuntimeDiagnostics,
    fetchRuntimeSnapshot,
    context,
    server,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await prepareLiveProfileForSigning({
      seedProfile,
      activateProfile,
      fetchRuntimeSnapshot,
      profile: onboardedLiveSignerProfile,
      label: 'provider-live pre-sign readiness',
      expectedPeers: 2,
      minSignReadyPeers: 1,
    });

    const result = await runProviderActionWithApproval(
      context,
      server.origin,
      'wants to sign a Nostr event',
      async (page) =>
        await page.evaluate(async (event) => {
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
    if (!result.ok) {
      const diagnostics = await fetchRuntimeDiagnostics<{
        runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
        diagnostics: RuntimeDiagnosticEvent[];
        dropped: number;
      }>();
      throw new Error(buildSignFailureMessage(result.message, diagnostics.diagnostics));
    }

    expect(result.event).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      content: SIGN_EVENT_PAYLOAD.content,
      created_at: SIGN_EVENT_PAYLOAD.created_at,
      pubkey: onboardedLiveSignerProfile.publicKey
    });
    expect(result.event?.tags).toEqual(SIGN_EVENT_PAYLOAD.tags);
    expect(typeof result.event?.id).toBe('string');
    expect(typeof result.event?.sig).toBe('string');
    expect(verifyEvent(result.event!)).toBe(true);
  });

  test('signEvent fails cleanly when the live responder disappears mid-session', async ({
    activateProfile,
    context,
    fetchRuntimeSnapshot,
    server,
    stableLiveSigner,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await seedAndActivateLiveProfile({
      seedProfile,
      activateProfile,
      profile: onboardedLiveSignerProfile,
    });
    await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
    await stableLiveSigner.stopResponder();

    await expect(
      runProviderActionWithApproval(
        context,
        server.origin,
        'wants to sign a Nostr event',
        async (page) =>
          await page.evaluate(async (event) => {
            try {
              await window.nostr!.signEvent(event);
              return { ok: true, message: null };
            } catch (error) {
              return {
                ok: false,
                message: error instanceof Error ? error.message : String(error)
              };
            }
          }, SIGN_EVENT_PAYLOAD)
      )
    ).resolves.toMatchObject({
      ok: false,
      message: expect.any(String)
    });
  });
});
