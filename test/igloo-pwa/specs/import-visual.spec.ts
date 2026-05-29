import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';

const IMPORT_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'import');

function buildPendingLoadConfirmation() {
  return {
    kind: 'bfprofile',
    preview: {
      label: 'My Signing Key',
      share_public_key: '33'.repeat(32),
      group_public_key: '22'.repeat(32),
      relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
      group_package_json: JSON.stringify({
        group_name: 'My Signing Key',
        group_pk: '22'.repeat(32),
        threshold: 2,
        members: [
          { idx: 0, pubkey: '02'.repeat(32) },
          { idx: 1, pubkey: '03'.repeat(32) },
          { idx: 2, pubkey: '04'.repeat(32) },
        ],
      }),
      share_package_json: JSON.stringify({ idx: 0, seckey: '11'.repeat(32) }),
      source: 'bfprofile',
    },
    stored_password: 'paper-import-pass',
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
  await mkdir(IMPORT_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(IMPORT_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Import visual harness', () => {
  test('captures the device-profile import flow screens', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'load-import',
        drafts: {
          importProfileForm: {
            profileString: `bfprofile1${'q'.repeat(96)}`,
            password: 'paper-import-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Import Device Profile' })).toBeVisible();
    await capture(page, '01-import-device-profile.png');

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'load-confirm',
        pendingLoadConfirmation: buildPendingLoadConfirmation(),
        drafts: {
          importSaveForm: {
            label: 'My Signing Key',
            password: 'paper-import-pass',
            confirmPassword: 'paper-import-pass',
            relayUrls: 'wss://relay.primal.net',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
    await capture(page, '02-save-profile.png');
  });

  test('captures the import error state', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'load-import',
        drafts: {
          importProfileForm: {
            profileString: 'not-a-valid-bfprofile-string',
            password: 'wrong-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Import Device Profile' })).toBeVisible();
    await page.getByRole('button', { name: 'Next Step' }).click();
    await expect(page.getByRole('heading', { name: 'Import Error' })).toBeVisible();
    await capture(page, '03-error.png');
  });
});
