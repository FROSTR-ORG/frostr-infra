import { generateSecretKey, getPublicKey, nip44 } from 'nostr-tools';

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

  // The gold-standard interop check for the raw-X ECDH + padded-base64 fixes: drive
  // the real provider end-to-end and prove FROSTR's NIP-44 ciphertext round-trips
  // with a standard nostr-tools client (and vice versa). The counterparty is an
  // external, non-member nostr user — the threshold group does ECDH(group,
  // counterparty); the standard client does the mirror ECDH(counterparty, group),
  // and the raw-X shared secret is identical, so the conversation keys match.
  test('nip44 ciphertext interoperates with a standard nostr-tools client', async ({
    activateProfile,
    context,
    prepareRuntimeReadiness,
    server,
    onboardedLiveSignerProfile,
    seedProfile
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);
    await waitForLiveEcdhReady(prepareRuntimeReadiness, 'nip44 interop pre-ecdh readiness');

    const counterpartyPriv = generateSecretKey();
    const counterpartyPub = getPublicKey(counterpartyPriv); // x-only hex
    const groupPub = onboardedLiveSignerProfile.groupPublicKey;
    const groupXOnly = groupPub.length === 66 ? groupPub.slice(2) : groupPub;
    const conversationKey = nip44.v2.utils.getConversationKey(counterpartyPriv, groupXOnly);

    // Direction A: FROSTR encrypts via the live provider -> standard client decrypts.
    const fromFrostr = 'gm from a frostr threshold signer';
    const frostrCiphertext = await runProviderActionWithApproval(
      context,
      server.origin,
      'wants to encrypt a NIP-44 message',
      async (page) =>
        await page.evaluate(
          async ({ pubkey, value }) => await window.nostr!.nip44.encrypt(pubkey, value),
          { pubkey: counterpartyPub, value: fromFrostr }
        )
    );
    expect(typeof frostrCiphertext).toBe('string');
    expect(nip44.v2.decrypt(frostrCiphertext, conversationKey)).toBe(fromFrostr);

    // Direction B: standard client encrypts -> FROSTR decrypts via the live provider.
    const fromStandard = 'gm from a standard nostr client';
    const standardCiphertext = nip44.v2.encrypt(fromStandard, conversationKey);
    await expect(
      runProviderActionWithApproval(
        context,
        server.origin,
        'wants to decrypt a NIP-44 message',
        async (page) =>
          await page.evaluate(
            async ({ pubkey, value }) => await window.nostr!.nip44.decrypt(pubkey, value),
            { pubkey: counterpartyPub, value: standardCiphertext }
          )
      )
    ).resolves.toBe(fromStandard);
  });
});
