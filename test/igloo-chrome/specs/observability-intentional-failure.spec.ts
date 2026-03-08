import { expect } from '@playwright/test';

import { test } from '../fixtures/extension';

test.describe('observability intentional failure', () => {
  test.skip(process.env.OBS_BUNDLE_INNER !== '1', 'helper spec for observability bundle smoke test');

  test('writes an observability bundle on failure', async ({
    callOffscreenRpc,
    liveSigner,
    seedProfile
  }) => {
    await seedProfile(liveSigner.profile);
    await callOffscreenRpc('runtime.ensure', {
      profile: liveSigner.profile
    });

    expect(false, 'intentional failure for observability bundle smoke test').toBe(true);
  });
});
