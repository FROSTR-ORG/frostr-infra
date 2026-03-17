import { test, expect } from '../fixtures/extension';
import {
  approvePromptOnce
} from '../support/provider-live';

test.describe('provider bridge live signer nip44 flow @live', () => {
  test.setTimeout(180_000);

  test('nip44 encrypt fails cleanly when the relay disconnects mid-session', async ({
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
    await stableLiveSigner.stopRelay();

    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = page.evaluate(
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
    );

    const prompt = await promptPromise;
    await expect(prompt.getByText('wants to encrypt a NIP-44 message')).toBeVisible();
    await approvePromptOnce(prompt);

    await expect(resultPromise).resolves.toMatchObject({
      ok: false,
      message: expect.any(String)
    });
    await page.close();
  });

  test('nip44 encrypt and decrypt succeed against a live responder', async ({
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
    const page = await context.newPage();
    await page.goto(`${server.origin}/provider`);

    const plaintext = 'playwright live nip44 message';

    const encryptPromptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const encryptResultPromise = page.evaluate(
      async ({ pubkey, value }) => await window.nostr!.nip44.encrypt(pubkey, value),
      {
        pubkey: stableLiveSigner.profile.peerPubkey,
        value: plaintext
      }
    );

    const encryptPrompt = await encryptPromptPromise;
    await expect(encryptPrompt.getByText('wants to encrypt a NIP-44 message')).toBeVisible();
    await approvePromptOnce(encryptPrompt);

    const ciphertext = await encryptResultPromise;
    expect(typeof ciphertext).toBe('string');
    expect(ciphertext.length).toBeGreaterThan(32);

    const decryptPromptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const decryptResultPromise = page.evaluate(
      async ({ pubkey, value }) => await window.nostr!.nip44.decrypt(pubkey, value),
      {
        pubkey: stableLiveSigner.profile.peerPubkey,
        value: ciphertext
      }
    );

    const decryptPrompt = await decryptPromptPromise;
    await expect(decryptPrompt.getByText('wants to decrypt a NIP-44 message')).toBeVisible();
    await approvePromptOnce(decryptPrompt);

    await expect(decryptResultPromise).resolves.toBe(plaintext);
    await page.close();
  });
});
