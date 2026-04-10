import { expect } from '@playwright/test';
import { COMMAND_TYPE } from '../../../repos/igloo-chrome/src/extension/messages';

import {
  createGeneratedBrowserArtifacts,
  createOnboardingPackage,
  createRotatedBrowserArtifacts,
} from '../../shared/browser-artifacts';
import { startLocalRelay } from '../../shared/local-relay';
import {
  startBrowserRuntimeSession,
  type BrowserRuntimeSession,
} from '../../../repos/igloo-pwa/src/lib/page-runtime-host';
import { test } from '../fixtures/extension';

function shortId(value: string) {
  return value.slice(0, 8);
}

test.describe('extension rotate key', () => {
  test('replaces the active device from settings using a rotated bfonboard package', async ({
    clearExtensionStorage,
    openExtensionPage,
  }) => {
    const relay = await startLocalRelay();
    let inviterSession: BrowserRuntimeSession | null = null;
    try {
      const current = await createGeneratedBrowserArtifacts({
        groupName: 'Chrome Rotation',
        labelPrefix: 'Chrome Rotation Device',
        relays: [relay.url],
      });
      const rotated = await createRotatedBrowserArtifacts({
        current,
        sourceMemberIndices: [1, 2],
        groupName: 'Chrome Rotation',
        labelPrefix: 'Chrome Rotated Device',
        relays: [relay.url],
      });
      const rotationPackage = await createOnboardingPackage({
        shareSecret: rotated.shares[0].shareSecret,
        relays: [relay.url],
        peerPubkey: rotated.shares[1].sharePublicKey,
        password: 'rotate-package-pass',
      });
      inviterSession = await startBrowserRuntimeSession({
        groupName: 'Chrome Rotation Inviter',
        relays: [relay.url],
        groupPublicKey: rotated.groupPublicKey,
        sharePublicKey: rotated.shares[1].sharePublicKey,
        groupPackageJson: rotated.groupPackageJson,
        sharePackageJson: rotated.shares[1].sharePackageJson,
      });
      await inviterSession.refreshPeers();

      await clearExtensionStorage();
      const page = await openExtensionPage('options.html');
      await expect(page.getByRole('heading', { name: 'Load bfprofile' })).toBeVisible();
      await page.evaluate(
        async ({ importType, packageText, password }) => {
          const response = (await chrome.runtime.sendMessage({
            type: importType,
            packageText,
            password,
          })) as { ok?: boolean; error?: string } | undefined;
          if (!response?.ok) {
            throw new Error(response?.error || 'Extension bfprofile import failed');
          }
        },
        {
          importType: COMMAND_TYPE.PROFILES_IMPORT,
          packageText: current.shares[0].bfprofile,
          password: 'playwright-passphrase',
        },
      );
      await expect(page.getByRole('tab', { name: /Settings/i }).first()).toBeVisible();

      await page.getByRole('tab', { name: /Settings operator controls/i }).click();
      const rotateCard = page
        .getByRole('heading', { name: 'rotate share' })
        .locator('xpath=ancestor::section[contains(@class, "rounded-lg")]')
        .first();
      await expect(rotateCard).toBeVisible();
      await rotateCard.getByPlaceholder('bfonboard1...').fill(rotationPackage);
      await rotateCard.getByLabel('Package Password').fill('rotate-package-pass');
      await rotateCard.getByRole('button', { name: 'rotate share' }).click();
      await expect(page.getByText('New Profile Id')).toBeVisible();
      await expect(page.getByText(rotated.shares[0].profileId)).toBeVisible();
      await rotateCard.getByRole('button', { name: 'rotate share' }).click();
      await expect(rotateCard.getByRole('button', { name: 'rotate share' })).toHaveCount(0);
      await expect(page.getByText(`${shortId(rotated.shares[0].profileId)})`)).toBeVisible();
      await page.getByRole('button', { name: 'logout' }).click();
      const storedProfilesCard = page
        .getByRole('heading', { name: 'Stored Profiles' })
        .locator('xpath=ancestor::div[contains(@class, "igloo-card")]')
        .first();
      await expect(storedProfilesCard).toBeVisible();
      await expect(
        storedProfilesCard.getByRole('button', { name: new RegExp(shortId(rotated.shares[0].profileId)) }),
      ).toBeVisible();
      await expect(
        storedProfilesCard.getByRole('button', { name: new RegExp(shortId(current.shares[0].profileId)) }),
      ).toHaveCount(0);
      await page.close();
    } finally {
      inviterSession?.stop();
      await relay.close();
    }
  });
});
