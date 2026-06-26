import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

const ONBOARD_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'onboard');

const ONBOARD_SAVE_VISUAL_STATE = {
  connection: {
    preview: {
      label: 'My Onboarded Device',
      share_public_key: '44'.repeat(32),
      group_public_key: '22'.repeat(32),
      relays: ['ws://127.0.0.1:4848'],
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
      share_package_json: JSON.stringify({ idx: 1, seckey: '11'.repeat(32) }),
      member_idx: 1,
      source: 'bfonboard',
    },
    passphrase: 'paper-onboard-pass',
    package_text: `bfonboard1${'q'.repeat(96)}`,
    profile_string: `bfprofile1${'q'.repeat(96)}`,
    share_string: `bfshare1${'q'.repeat(96)}`,
    runtime_snapshot_json: null,
  },
  draft: {
    label: 'My Onboarded Device',
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
  await mkdir(ONBOARD_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(ONBOARD_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Onboard visual harness @visual', () => {
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
    await expect(page.getByRole('heading', { name: 'Input Package' })).toBeVisible();
    await capture(page, '01-input-package.png');

    // The `onboard-handshake` view is transient/runtime-only (normalized away on load),
    // but the store holds it for a guaranteed minimum window after Next Step, so drive it.
    await pages(page).onboard.submitConnect();
    await expect(page.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    await capture(page, '02-onboard-device.png');

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
    await expect(page.getByRole('heading', { name: 'Onboarding Failed' })).toBeVisible();
    await capture(page, '03-onboarding-failed.png');

    // The passphrase-bearing Save Profile step is captured separately through a
    // DEV-only non-persisted visual seam.
  });

  test('captures the onboarded profile save step through the visual seam', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.addInitScript((visualState) => {
      (window as unknown as { __IGLOO_TEST_ONBOARD_SAVE_STATE__?: unknown }).__IGLOO_TEST_ONBOARD_SAVE_STATE__ =
        visualState;
    }, ONBOARD_SAVE_VISUAL_STATE);

    await seedState(page, buildPwaPersistedState({ activeView: 'onboard-connect' }));

    await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
    await capture(page, '04-save-profile.png');
  });
});
