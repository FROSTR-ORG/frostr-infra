import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { buildPwaPersistedState, PWA_STORAGE_KEY } from '../support/state';
import {
  DETERMINISTIC_GROUP_KEY,
  DETERMINISTIC_SHARE_KEY,
  npubDisplay,
} from '../support/deterministic-keys';

const DASHBOARD_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'dashboard');

// A seeded stored profile carrying the deterministic keys, so the merged
// identity/runtime card renders byte-stable npub displays.
function buildDashboardProfile() {
  const groupPackageJson = JSON.stringify({
    group_name: 'My Signing Key',
    group_pk: DETERMINISTIC_GROUP_KEY.pubHex,
    threshold: 2,
    members: [
      { idx: 0, pubkey: '02'.repeat(32) },
      { idx: 1, pubkey: DETERMINISTIC_SHARE_KEY.pubHex },
      { idx: 2, pubkey: '04'.repeat(32) },
    ],
  });
  return {
    id: 'dashboard-visual-profile',
    label: 'My Signing Key',
    share_public_key: DETERMINISTIC_SHARE_KEY.pubHex,
    group_public_key: DETERMINISTIC_GROUP_KEY.pubHex,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
    group_package_json: groupPackageJson,
    share_package_json: JSON.stringify({ idx: 1, seckey: DETERMINISTIC_SHARE_KEY.secretHex }),
    source: 'generated' as const,
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'group-ref',
    encrypted_profile_ref: 'enc-ref',
    state_path: 'state-path',
    created_at: 1_700_000_000_000,
    stored_password: 'paper-dashboard-pass',
    profile_string: 'bfprofile1paperdashboard',
    share_string: 'bfshare1paperdashboard',
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

// A running runtime snapshot so the merged card shows "Signer Running".
function buildRunningSnapshot() {
  return {
    active: true,
    readiness: {
      runtime_ready: true,
      restore_complete: true,
      sign_ready: true,
      ecdh_ready: true,
      threshold: 2,
    },
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
  await mkdir(DASHBOARD_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(DASHBOARD_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Dashboard visual harness @visual', () => {
  test('captures the signer dashboard with the merged identity card', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildDashboardProfile();
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot: buildRunningSnapshot(),
      }),
    );

    const dashboard = pages(page).dashboard;
    // Header nav: Dashboard active (pill), Permissions, Settings.
    await dashboard.expectNavLinks();
    // Merged card: both keys shown as deterministic npub displays, split copy present.
    await dashboard.expectKeyDisplays(
      npubDisplay(DETERMINISTIC_GROUP_KEY.npub),
      npubDisplay(DETERMINISTIC_SHARE_KEY.npub),
    );
    await dashboard.expectKeyCopyControls();
    // Pending Approvals empty-state shell (deferred behavior).
    await dashboard.expectPendingApprovalsEmpty();

    await capture(page, '01-signer-dashboard.png');
  });
});
