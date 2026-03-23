import { expect, test } from '@playwright/test';

import { createGeneratedBrowserArtifacts, createPwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { buildPwaPersistedState } from '../support/state';
import { expectPwaDashboard, loadStoredPwaProfile, seedPwaState } from '../support/ui';

test.describe('igloo-pwa stored profiles', () => {
  test('lists stored profiles on the landing page and loads the selected profile', async ({ page }) => {
    const relay = await startLocalRelay();
    try {
      const generated = await createGeneratedBrowserArtifacts({
        keysetName: 'PWA Inventory',
        labelPrefix: 'Stored Browser Device',
        relays: [relay.url],
      });
      const seededProfile = createPwaStoredProfileSeed({
        artifact: generated.shares[0],
        groupPackageJson: generated.groupPackageJson,
        label: 'Stored Browser Device',
      });

      await seedPwaState(page, buildPwaPersistedState({ profiles: [seededProfile] }));
      await loadStoredPwaProfile(page, 'Stored Browser Device');
      await expectPwaDashboard(page, 'Stored Browser Device');
    } finally {
      await relay.close();
    }
  });
});
