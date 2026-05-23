import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';

const ONBOARD_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'onboard');

function buildPendingOnboardConnection() {
  return {
    preview: {
      label: 'Onboarded Device',
      share_public_key: '33'.repeat(32),
      group_public_key: '22'.repeat(32),
      relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
      group_package_json: '{"group_name":"Paper Onboard","group_pk":"22","threshold":2,"members":[]}',
      share_package_json: '{"idx":1,"seckey":"11"}',
      source: 'bfonboard',
    },
    stored_password: 'paper-onboard-pass',
    package_text: `bfonboard1${'q'.repeat(96)}`,
    profile_string: 'bfprofile1paperdemo',
    share_string: 'bfshare1paperdemo',
  };
}

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(
    ([storageKey, payload]) => {
      window.localStorage.setItem(storageKey, JSON.stringify(payload));
    },
    [PWA_STORAGE_KEY, state] as const,
  );
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await mkdir(ONBOARD_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(ONBOARD_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Onboard visual harness', () => {
  test('captures recipient onboarding states', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'onboard-connect',
        drafts: {
          onboardConnectForm: {
            packageText: `bfonboard1${'q'.repeat(96)}`,
            password: 'paper-onboard-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Enter Onboarding Package' })).toBeVisible();
    await capture(page, '01-enter-package.png');

    await page.getByRole('button', { name: 'Apply Onboarding Package' }).click();
    await expect(page.getByRole('heading', { name: 'Onboarding...' })).toBeVisible();
    await capture(page, '02-handshake.png');

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'onboard-failed',
        drafts: {
          onboardConnectForm: {
            packageText: `bfonboard1${'q'.repeat(96)}`,
            password: 'paper-onboard-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Package Did Not Apply' })).toBeVisible();
    await capture(page, '03-onboarding-failed.png');

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'onboard-save',
        pendingOnboardConnection: buildPendingOnboardConnection(),
        drafts: {
          onboardSaveForm: {
            label: 'Onboarded Device',
            password: 'paper-onboard-pass',
            confirmPassword: 'paper-onboard-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Onboarding Complete' })).toBeVisible();
    await capture(page, '04-onboarding-complete.png');
  });
});
