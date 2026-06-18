import { test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';
import { DETERMINISTIC_GROUP_KEY, DETERMINISTIC_SHARE_KEY } from '../support/deterministic-keys';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

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
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
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
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
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

    // Export Profile opens the password-modal entry state.
    await dashboard.openExportProfile();
    await dashboard.expectExportModalEntry();
    await capture(page, '04-export-profile-modal.png');
  });
});
