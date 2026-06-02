import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';
import { DETERMINISTIC_GROUP_KEY, DETERMINISTIC_SHARE_KEY } from '../support/deterministic-keys';

const SETTINGS_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'dashboard');

function buildSettingsProfile() {
  return {
    id: 'settings-visual-profile',
    label: 'My Signing Key',
    share_public_key: DETERMINISTIC_SHARE_KEY.pubHex,
    group_public_key: DETERMINISTIC_GROUP_KEY.pubHex,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
    group_package_json: JSON.stringify({
      group_name: 'My Signing Key',
      group_pk: DETERMINISTIC_GROUP_KEY.pubHex,
      threshold: 2,
      members: [{ idx: 1, pubkey: DETERMINISTIC_SHARE_KEY.pubHex }],
    }),
    share_package_json: JSON.stringify({ idx: 1, seckey: DETERMINISTIC_SHARE_KEY.secretHex }),
    source: 'generated' as const,
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'group-ref',
    encrypted_profile_ref: 'enc-ref',
    state_path: 'state-path',
    created_at: 1_700_000_000_000,
    stored_password: 'paper-settings-pass',
    profile_string: 'bfprofile1paperset',
    share_string: 'bfshare1paperset',
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted' as const,
    },
    manual_peer_policy_overrides: [] as [],
    peer_pubkey: null,
    runtime_snapshot_json: null,
    onboarding_package: null,
  };
}

function buildRunningSnapshot() {
  return {
    active: true,
    readiness: { runtime_ready: true, restore_complete: true, sign_ready: true, ecdh_ready: true, threshold: 2 },
    runtime_status: { metadata: { peers: ['02'.repeat(32), '04'.repeat(32)] } },
    runtime_log_lines: [],
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
  await mkdir(SETTINGS_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SETTINGS_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Settings visual harness @visual', () => {
  test('captures the settings page section layout', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildSettingsProfile();
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'settings',
        runtimeSnapshot: buildRunningSnapshot(),
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    // Paper-aligned section layout: Device Profile, Replace Share, Export Profile,
    // Export Share, Logout (Advanced + Browser Settings render below).
    await dashboard.expectSettingsSections();

    await capture(page, '03-settings.png');
  });
});
