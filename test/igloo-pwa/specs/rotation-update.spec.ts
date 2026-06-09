import { expect, test } from '@playwright/test';
import { nip19 } from 'nostr-tools';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createPwaStoredProfileSeed,
  createRotatedBrowserArtifacts,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import { buildPwaPersistedState } from '../support/state';
import {
  connectPwaRotationPackage,
  confirmPwaRotationPackage,
  expectPwaDashboard,
  importPwaProfile,
  loadStoredPwaProfile,
  openFreshPwaPage,
  seedPwaState,
} from '../support/ui';

// The redesigned dashboard identifies a device by its share public key,
// rendered as a truncated npub (`${npub.slice(0,8)}...${npub.slice(-4)}`, see
// igloo-pwa dashboard-view.ts). Rotation keeps the device label, so the share
// npub is the discriminator between the pre- and post-rotation identities.
function shareKeyDisplay(hexPubkey: string) {
  const npub = nip19.npubEncode(hexPubkey);
  return `${npub.slice(0, 8)}...${npub.slice(-4)}`;
}

test.describe('igloo-pwa rotate key @live', () => {
  test('replaces the active device with a rotated bfonboard package', async ({ browser, page }) => {
    test.slow();
    const relay = await startLocalRelay();
    let inviterContext;
    try {
      const current = await createGeneratedBrowserArtifacts({
        groupName: 'Rotation Update',
        labelPrefix: 'Rotation Device',
        relays: [relay.url],
      });
      const rotated = await createRotatedBrowserArtifacts({
        current,
        sourceMemberIndices: [1, 2],
        groupName: 'Rotation Update',
        labelPrefix: 'Rotated Device',
        relays: [relay.url],
      });
      const rotationPackage = await createOnboardingPackage({
        shareSecret: rotated.shares[0].shareSecret,
        relays: [relay.url],
        peerPubkey: rotated.shares[1].sharePublicKey,
        password: 'rotate-package-pass',
      });
      const inviterSeed = createPwaStoredProfileSeed({
        artifact: rotated.shares[1],
        groupPackageJson: rotated.groupPackageJson,
        label: 'Rotation Inviter',
      });

      const inviter = await openFreshPwaPage(browser);
      inviterContext = inviter.context;
      await seedPwaState(inviter.page, buildPwaPersistedState({ profiles: [inviterSeed] }));
      await loadStoredPwaProfile(inviter.page, 'Rotation Inviter');
      await expectPwaDashboard(inviter.page, 'Rotation Inviter');

      await importPwaProfile(page, current.shares[0].bfprofile, 'playwright-passphrase');
      await expectPwaDashboard(page, 'Rotation Device 1');

      await connectPwaRotationPackage(page, {
        packageText: rotationPackage,
        packagePassword: 'rotate-package-pass',
      });
      await expect(page.getByText('Replacement Preview')).toBeVisible({ timeout: 20_000 });
      await confirmPwaRotationPackage(page);
      await expectPwaDashboard(page, 'Rotation Device 1');
      await expect(page.getByText(shareKeyDisplay(rotated.shares[0].sharePublicKey))).toBeVisible();
      await expect(page.getByText(shareKeyDisplay(current.shares[0].sharePublicKey))).toHaveCount(0);
    } finally {
      await inviterContext?.close().catch(() => undefined);
      await relay.close();
    }
  });
});
