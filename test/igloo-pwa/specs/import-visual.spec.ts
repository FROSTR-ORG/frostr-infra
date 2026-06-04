import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';

const IMPORT_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'import');

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
    await expect(page.getByRole('heading', { name: 'Import Device Profile' })).toBeVisible();
    await capture(page, '01-import-device-profile.png');

    // NOTE (Paper<->security reconcile): the load-confirm "Save Profile" capture
    // was dropped. It seeded `pendingLoadConfirmation` + reloaded, but the
    // reconciled (security) store resets pending confirmations on load — they
    // carry the passphrase (secret-segregation) — so that screen is not reachable
    // via seed-and-reload. The save step is exercised functionally by app-shell.spec.
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
    await pages(page).import.next();
    await expect(page.getByRole('heading', { name: 'Import Error' })).toBeVisible();
    await capture(page, '03-error.png');
  });
});
