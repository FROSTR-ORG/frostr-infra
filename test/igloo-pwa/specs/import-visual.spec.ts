import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

const IMPORT_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'import');

const IMPORT_SAVE_VISUAL_STATE = {
  confirmation: {
    kind: 'bfprofile',
    preview: {
      label: 'My Imported Key',
      share_public_key: '33'.repeat(32),
      group_public_key: '22'.repeat(32),
      relays: ['ws://127.0.0.1:4848'],
      group_package_json: JSON.stringify({
        group_name: 'My Imported Key',
        group_pk: '22'.repeat(32),
        threshold: 2,
        members: [
          { idx: 0, pubkey: '02'.repeat(32) },
          { idx: 1, pubkey: '03'.repeat(32) },
          { idx: 2, pubkey: '04'.repeat(32) },
        ],
      }),
      share_package_json: JSON.stringify({ idx: 0, seckey: '11'.repeat(32) }),
      member_idx: 0,
      source: 'bfprofile',
    },
    passphrase: 'paper-import-pass',
    profile_string: `bfprofile1${'q'.repeat(96)}`,
    share_string: `bfshare1${'q'.repeat(96)}`,
  },
  draft: {
    label: 'My Imported Key',
    relayUrls: 'ws://127.0.0.1:4848',
    password: 'paper-browser-pass',
    confirmPassword: 'paper-browser-pass',
  },
};

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await mkdir(IMPORT_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(IMPORT_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Import visual harness @visual', () => {
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
    await expect(page.getByRole('heading', { name: 'Import Existing Device' })).toBeVisible();
    await capture(page, '01-import-existing-device.png');

    // The passphrase-bearing Save Profile step is captured separately through a
    // DEV-only non-persisted visual seam.
  });

  test('captures the imported profile save step through the visual seam', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.addInitScript((visualState) => {
      (window as unknown as { __IGLOO_TEST_IMPORT_SAVE_STATE__?: unknown }).__IGLOO_TEST_IMPORT_SAVE_STATE__ =
        visualState;
    }, IMPORT_SAVE_VISUAL_STATE);

    await seedState(page, buildPwaPersistedState({ activeView: 'load-import' }));

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
    await expect(page.getByRole('heading', { name: 'Import Existing Device' })).toBeVisible();
    await pages(page).import.next();
    await expect(page.getByRole('heading', { name: 'Import Error' })).toBeVisible();
    await capture(page, '03-error.png');
  });
});
