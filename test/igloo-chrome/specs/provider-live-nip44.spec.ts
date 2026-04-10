import { test, expect } from '../fixtures/extension';
import {
  runProviderActionWithApproval
} from '../support/provider-live';
import { waitForLiveEcdhReady } from '../support/live-runtime';

test.describe('provider bridge live signer nip44 flow @live', () => {
  test.setTimeout(180_000);

  test('nip44 encrypt fails cleanly when the relay disconnects mid-session', async ({
    activateProfile,
    context,
    server,
    stableLiveSigner,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);
    await stableLiveSigner.stopRelay();

    await expect(
      runProviderActionWithApproval(
        context,
        server.origin,
        'wants to encrypt a NIP-44 message',
        async (page) =>
          await page.evaluate(
            async ({ pubkey, value }) => {
              try {
                await window.nostr!.nip44.encrypt(pubkey, value);
                return { ok: true, message: null };
              } catch (error) {
                return {
                  ok: false,
                  message: error instanceof Error ? error.message : String(error)
                };
              }
            },
            {
              pubkey: stableLiveSigner.profile.peerPubkey,
              value: 'playwright live nip44 relay disconnect'
            }
          )
      )
    ).resolves.toMatchObject({
      ok: false,
      message: expect.any(String)
    });
  });

  test('nip44 encrypt and decrypt succeed against a live responder', async ({
    activateProfile,
    context,
    prepareRuntimeReadiness,
    server,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);
    await waitForLiveEcdhReady(prepareRuntimeReadiness, 'provider-live pre-ecdh readiness');
    const plaintext = 'playwright live nip44 message';
    const ciphertext = await runProviderActionWithApproval(
      context,
      server.origin,
      'wants to encrypt a NIP-44 message',
      async (page) =>
        await page.evaluate(
          async ({ pubkey, value }) => await window.nostr!.nip44.encrypt(pubkey, value),
          {
            pubkey: stableLiveSigner.profile.peerPubkey,
            value: plaintext
          }
        )
    );
    expect(typeof ciphertext).toBe('string');
    expect(ciphertext.length).toBeGreaterThan(32);

    await expect(
      runProviderActionWithApproval(
        context,
        server.origin,
        'wants to decrypt a NIP-44 message',
        async (page) =>
          await page.evaluate(
            async ({ pubkey, value }) => await window.nostr!.nip44.decrypt(pubkey, value),
            {
              pubkey: stableLiveSigner.profile.peerPubkey,
              value: ciphertext
            }
          )
      )
    ).resolves.toBe(plaintext);
  });
});
