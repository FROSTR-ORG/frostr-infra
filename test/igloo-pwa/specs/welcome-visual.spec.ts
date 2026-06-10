import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

const WELCOME_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'welcome');
const CREATE_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'create');
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
    encrypted_bfshare_artifact: `bfshare1${id}`,
    member_idx: memberIdx,
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
  await page.evaluate(applyPwaSeed, pwaSeedPayload(buildPwaPersistedState({ profiles })));
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await captureIn(page, WELCOME_CAPTURE_DIR, fileName);
}

async function captureIn(page: Page, directory: string, fileName: string) {
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: path.join(directory, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Welcome visual harness @visual', () => {
  test('captures first-launch and returning Welcome states', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, []);
    await expect(page.getByRole('heading', { name: 'Igloo Web' })).toBeVisible();
    await expect(page.getByText('Split your Nostr key. Sign from anywhere.')).toBeVisible();
    await capture(page, '01-first-launch.png');

    const singleProfiles = [buildPaperProfile(1, 'My Signing Key', 2, 3)];
    await setPwaState(page, singleProfiles);
    await expect(page.getByText('Welcome back.')).toBeVisible();
    await pages(page).welcome.expectRowCount(1);
    await capture(page, '02-returning-single.png');

    const multiProfiles = [
      buildPaperProfile(1, 'My Signing Key', 2, 3),
      buildPaperProfile(2, 'Work Key', 2, 3),
      buildPaperProfile(3, 'Travel Key', 2, 3),
    ];
    await setPwaState(page, multiProfiles);
    await pages(page).welcome.expectRowCount(3);
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
    await pages(page).welcome.expectRowCount(6);
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
    const welcome = pages(page).welcome;
    await welcome.openUnlock('paper-profile-1');
    await expect(page.getByText('Unlock Profile')).toBeVisible();
    await capture(page, '05-unlock-modal.png');

    await welcome.fillUnlockPassword('incorrect-password');
    await welcome.submitUnlock();
    await expect(page.getByText('Incorrect password. Please try again.')).toBeVisible();
    await capture(page, '06-unlock-modal-error.png');
  });

  test('captures the returning card action menu open', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, [buildPaperProfile(1, 'My Signing Key', 2, 3)]);
    const welcome = pages(page).welcome;
    await welcome.expectRowCount(1);
    await welcome.openMenu('paper-profile-1');
    await welcome.expectMenuOpen();
    await capture(page, '07-returning-menu-open.png');
  });

  test('captures the Create Keyset flow screens', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await setPwaState(page, []);
    const p = pages(page);
    await p.welcome.startGenerate();

    await expect(p.create.backButton).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Create Keyset' })).toBeVisible();
    await expect(p.create.generateNextButton).toBeVisible();
    await captureIn(page, CREATE_CAPTURE_DIR, '01-create-keyset.png');

    await p.create.fillGenerate({ groupName: 'My Signing Key' });
    await p.create.generateNext();
    await expect(page.getByRole('heading', { name: 'Select Share' })).toBeVisible();
    await expect(page.getByText('Choose Local Share')).toBeVisible();
    await page.setViewportSize({ width: 1440, height: 1861 });
    await p.create.selectShareByName('My Signing Key Device 2');
    await captureIn(page, CREATE_CAPTURE_DIR, '02-select-share.png');

    await p.create.selectShareNext();
    await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
    await p.create.fillSaveProfile({ password: 'paper-browser-pass' });

    await page.setViewportSize({ width: 1440, height: 1861 });
    await captureIn(page, CREATE_CAPTURE_DIR, '03-save-profile.png');

    await p.create.saveProfileNext();
    await expect(page.getByText('Distribute Shares')).toBeVisible();
    await expect(page.getByText('Remote Shares')).toBeVisible();
    await p.distribute.preparePackage(p.distribute.cards().nth(1), 'remote-device-pass');
    await captureIn(page, CREATE_CAPTURE_DIR, '04-distribute-shares.png');
  });
});
