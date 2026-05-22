import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';

const WELCOME_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'igloo-pwa-welcome');
const CREATE_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'igloo-pwa-create');
const PAPER_PASSWORD = 'paper-pass';

function fixedHex(index: number, prefix: string) {
  return `${prefix}${index.toString(16).padStart(2, '0')}`.padEnd(64, '0').slice(0, 64);
}

function buildPaperProfile(index: number, label: string, threshold: number, memberCount: number): PwaStoredProfileSeed {
  const memberIdx = index - 1;
  const id = `paper-profile-${index}`;
  const sharePublicKey = fixedHex(index, 'ab');
  const groupPublicKey = fixedHex(index, 'cd');
  const members = Array.from({ length: memberCount }, (_, memberIndex) => ({
    idx: memberIndex,
    pubkey: fixedHex(memberIndex, 'ef'),
  }));

  return {
    id,
    label,
    share_public_key: sharePublicKey,
    group_public_key: groupPublicKey,
    relays: ['ws://127.0.0.1:4848'],
    group_package_json: JSON.stringify({
      group_name: 'Paper Welcome',
      group_pk: groupPublicKey,
      threshold,
      members,
    }),
    share_package_json: JSON.stringify({
      idx: memberIdx,
      seckey: fixedHex(index, '12'),
    }),
    source: 'generated',
    relay_profile: 'local',
    group_ref: `browser-profile:${id}:group`,
    encrypted_profile_ref: `browser-profile:${id}:encrypted-profile`,
    state_path: `/tmp/igloo-pwa/${id}`,
    created_at: Date.UTC(2026, 4, 21) + index,
    stored_password: PAPER_PASSWORD,
    profile_string: `bfprofile1${id}`,
    share_string: `bfshare1${id}`,
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted',
    },
    manual_peer_policy_overrides: [],
    peer_pubkey: null,
    runtime_snapshot_json: null,
    onboarding_package: null,
  };
}

async function setPwaState(page: Page, profiles: PwaStoredProfileSeed[]) {
  await page.goto('/');
  await page.evaluate(
    ([storageKey, payload]) => {
      window.localStorage.setItem(storageKey, JSON.stringify(payload));
    },
    [PWA_STORAGE_KEY, buildPwaPersistedState({ profiles })] as const,
  );
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await captureIn(page, WELCOME_CAPTURE_DIR, fileName);
}

async function captureIn(page: Page, directory: string, fileName: string) {
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: path.join(directory, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Welcome visual harness', () => {
  test('captures first-launch and returning Welcome states', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, []);
    await expect(page.getByRole('heading', { name: 'Igloo Web' })).toBeVisible();
    await expect(page.getByText('Split your Nostr key. Sign from anywhere.')).toBeVisible();
    await capture(page, '01-first-launch.png');

    const singleProfiles = [buildPaperProfile(1, 'My Signing Key', 2, 3)];
    await setPwaState(page, singleProfiles);
    await expect(page.getByText('Welcome back.')).toBeVisible();
    await expect(page.locator('.igloo-welcome-profile-row')).toHaveCount(1);
    await capture(page, '02-returning-single.png');

    const multiProfiles = [
      buildPaperProfile(1, 'My Signing Key', 2, 3),
      buildPaperProfile(2, 'Work Key', 2, 3),
      buildPaperProfile(3, 'Travel Key', 2, 3),
    ];
    await setPwaState(page, multiProfiles);
    await expect(page.locator('.igloo-welcome-profile-row')).toHaveCount(3);
    await capture(page, '03-returning-multi.png');

    const manyProfiles = [
      buildPaperProfile(1, 'My Signing Key', 3, 5),
      buildPaperProfile(2, 'Work Key', 3, 5),
      buildPaperProfile(3, 'Travel Key', 3, 5),
      buildPaperProfile(4, 'Archive Key', 3, 5),
      buildPaperProfile(5, 'Cold Key', 3, 5),
      buildPaperProfile(6, 'Family Key', 3, 5),
    ];
    await page.setViewportSize({ width: 1440, height: 1284 });
    await setPwaState(page, manyProfiles);
    await expect(page.locator('.igloo-welcome-profile-row')).toHaveCount(6);
    await capture(page, '04-returning-many.png');
  });

  test('captures unlock modal normal and error states', async ({ page }) => {
    const profiles = [
      buildPaperProfile(1, 'My Signing Key', 2, 3),
      buildPaperProfile(2, 'Work Key', 2, 3),
      buildPaperProfile(3, 'Travel Key', 2, 3),
    ];

    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, profiles);
    await page.locator('.igloo-welcome-profile-row').filter({ hasText: 'My Signing Key' }).getByRole('button', { name: 'Unlock' }).click();
    await expect(page.getByText('Unlock Profile')).toBeVisible();
    await capture(page, '05-unlock-modal.png');

    await page.getByLabel('Profile Password').fill('incorrect-password');
    await page.locator('form').getByRole('button', { name: 'Unlock' }).click();
    await expect(page.getByText('Incorrect password. Please try again.')).toBeVisible();
    await capture(page, '06-unlock-modal-error.png');
  });

  test('captures the Create Keyset and Create Profile screens', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, []);
    await page.getByRole('button', { name: 'New Keyset' }).click();

    await expect(page.getByText('Back to Welcome')).toBeVisible();
    await expect(page.getByText('Create New Keyset')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Create Keyset' })).toBeVisible();
    await captureIn(page, CREATE_CAPTURE_DIR, '01-create-keyset.png');

    await page.getByLabel('Group Name').fill('My Signing Key');
    await page.getByRole('button', { name: 'Create Keyset' }).click();
    await expect(page.getByRole('heading', { name: 'Create Profile' })).toBeVisible();
    await expect(page.getByText('Choose Local Share')).toBeVisible();

    await page.setViewportSize({ width: 1440, height: 1861 });
    await captureIn(page, CREATE_CAPTURE_DIR, '02-create-profile.png');

    await page.getByLabel('Device Password').fill('paper-browser-pass');
    await page.getByLabel('Confirm Password').fill('paper-browser-pass');
    await page.getByRole('button', { name: 'Continue to Review' }).click();
    await expect(page.getByRole('heading', { name: 'Review Device Profile', level: 2 })).toBeVisible();
    await captureIn(page, CREATE_CAPTURE_DIR, '03-create-confirm.png');

    await page.getByRole('button', { name: 'Accept and Continue' }).click();
    await expect(page.getByText('Distribute Shares')).toBeVisible();
    await expect(page.getByText('Remaining Shares')).toBeVisible();
    await captureIn(page, CREATE_CAPTURE_DIR, '04-distribute-shares.png');

    const distributionCards = page.locator('section.igloo-create-distribution-card');
    const cardCount = await distributionCards.count();
    for (let index = 0; index < cardCount; index += 1) {
      const card = distributionCards.nth(index);
      await card.getByLabel('Package password').fill('remote-device-pass');
      await card.getByLabel('Confirm Password').fill('remote-device-pass');
      await card.getByRole('button', { name: 'Create package' }).click();
    }
    await expect(page.getByText('Distribution Completion')).toBeVisible();
    await captureIn(page, CREATE_CAPTURE_DIR, '05-distribution-completion.png');
  });
});
