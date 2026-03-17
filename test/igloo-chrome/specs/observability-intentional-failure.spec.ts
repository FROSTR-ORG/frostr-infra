import { expect } from '@playwright/test';

import { test } from '../fixtures/extension';
import { onboardLiveSignerProfile } from '../support/onboarding';

test.describe('observability intentional failure @live', () => {
  test.skip(process.env.OBS_BUNDLE_INNER !== '1', 'helper spec for observability bundle smoke test');

  test('writes an observability bundle on failure', async ({
    callOffscreenRpc,
    liveSigner,
    openExtensionPage
  }) => {
    const storedProfile = await onboardLiveSignerProfile(openExtensionPage, liveSigner.profile);
    await callOffscreenRpc('runtime.ensure', {
      profile: storedProfile
    });

    expect(false, 'intentional failure for observability bundle smoke test').toBe(true);
  });
});
