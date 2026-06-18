import { test, expect } from '../fixtures/extension';
import { prepareLiveProfileForSigning } from '../support/live-runtime';
import { signProviderEventWithApproval } from '../support/runtime-lifecycle';

const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_000,
  tags: [],
  content: 'chrome smoke signEvent',
};

// @live @smoke — the per-PR-tier Chrome integration tripwire (ADR-013 §(b)): one
// onboarded live signer + one real signing round-trip. The onboarded live-signer
// profile (paired with the headless co-signer worker) is activated, driven to
// sign-ready, and then a provider `signEvent` is approved and completed end to
// end — the returned event must carry the group pubkey, proving the threshold
// signature actually crossed the relay. Minimal subset of the full @live suite
// (runtime-lifecycle adds teardown/relaunch recovery on top of this path).
test.describe('igloo-chrome onboarding + signing smoke @live @smoke', () => {
  test.setTimeout(180_000);

  test('an onboarded live signer completes a provider signEvent round-trip', async ({
    activateProfile,
    context,
    fetchRuntimeSnapshot,
    onboardedLiveSignerProfile,
    seedProfile,
    server,
  }) => {
    await prepareLiveProfileForSigning({
      seedProfile,
      activateProfile,
      fetchRuntimeSnapshot,
      profile: onboardedLiveSignerProfile,
      label: 'chrome smoke sign snapshot',
    });

    const result = await signProviderEventWithApproval(context, server.origin, SIGN_EVENT_PAYLOAD);
    expect(result.ok, `smoke signEvent failed: ${result.message}`).toBe(true);
    expect(result.event).toMatchObject({
      kind: SIGN_EVENT_PAYLOAD.kind,
      created_at: SIGN_EVENT_PAYLOAD.created_at,
      content: SIGN_EVENT_PAYLOAD.content,
      pubkey: onboardedLiveSignerProfile.publicKey,
    });
  });
});
