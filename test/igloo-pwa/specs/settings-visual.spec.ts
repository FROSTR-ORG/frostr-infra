import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { test, type Page } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';
import { DETERMINISTIC_GROUP_KEY, DETERMINISTIC_SHARE_KEY } from '../support/deterministic-keys';

const SETTINGS_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'dashboard');

function buildSettingsProfile() {
  return {
    id: 'settings-visual-profile',
    label: 'Igloo Web',
    share_public_key: DETERMINISTIC_SHARE_KEY.pubHex,
    group_public_key: DETERMINISTIC_GROUP_KEY.pubHex,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io', 'wss://nos.lol'],
    group_package_json: JSON.stringify({
      group_name: 'My Signing Key',
      group_pk: DETERMINISTIC_GROUP_KEY.pubHex,
      threshold: 2,
      members: [
        { idx: 1, pubkey: DETERMINISTIC_SHARE_KEY.pubHex },
        { idx: 2, pubkey: '33'.repeat(32) },
        { idx: 3, pubkey: '44'.repeat(32) },
      ],
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
    updated_at: 1_700_086_400_000,
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

function buildRunningSnapshot(profile: ReturnType<typeof buildSettingsProfile>) {
  return {
    active: true,
    profile,
    readiness: { runtime_ready: true, restore_complete: true, sign_ready: true, ecdh_ready: true, threshold: 2 },
    runtime_status: { metadata: { peers: ['02'.repeat(32), '04'.repeat(32)] } },
    runtime_log_lines: [],
    runtime_host: {
      profile_id: profile.id,
      mode: 'browser',
      log_source: 'Visual seed session',
      started_at: 1_700_086_400_000,
      signer_pubkey: profile.share_public_key,
    },
  };
}

function buildReplaceShareVisualConnection(profile: ReturnType<typeof buildSettingsProfile>) {
  const replacementShareSecret = '55'.repeat(32);
  const replacementSharePublicKey = '66'.repeat(32);
  const groupPackage = {
    groupName: 'My Signing Key',
    groupPk: profile.group_public_key,
    threshold: 2,
    members: [
      { idx: 1, pubkey: `02${replacementSharePublicKey}` },
      { idx: 2, pubkey: `02${'33'.repeat(32)}` },
      { idx: 3, pubkey: `02${'44'.repeat(32)}` },
    ],
  };
  const groupPackageJson = JSON.stringify({
    group_name: groupPackage.groupName,
    group_pk: groupPackage.groupPk,
    threshold: groupPackage.threshold,
    members: groupPackage.members,
  });
  const sharePackageJson = JSON.stringify({ idx: 1, seckey: replacementShareSecret });
  return {
    preview: {
      label: 'Igloo Web Replacement',
      share_public_key: replacementSharePublicKey,
      group_public_key: profile.group_public_key,
      relays: profile.relays,
      group_package_json: groupPackageJson,
      share_package_json: sharePackageJson,
      source: 'bfonboard',
    },
    passphrase: 'paper-replacement-pass',
    package_text: `bfonboard1${'z'.repeat(96)}`,
    profile_string: 'bfprofile1replacement',
    share_string: 'bfshare1replacement',
    profile_payload: {
      profileId: 'replacement-profile-id',
      version: 1,
      device: {
        name: 'Igloo Web Replacement',
        shareSecret: replacementShareSecret,
        manualPeerPolicyOverrides: [],
        relays: profile.relays,
      },
      groupPackage,
    },
    manual_peer_policy_overrides: [],
    peer_pubkey: null,
    runtime_snapshot_json: null,
  };
}

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}

async function injectReplaceShareVisualState(page: Page, state: unknown) {
  await page.addInitScript((visualState) => {
    (window as unknown as { __IGLOO_TEST_REPLACE_SHARE_STATE__?: unknown }).__IGLOO_TEST_REPLACE_SHARE_STATE__ =
      visualState;
  }, state);
}

async function injectDashboardVisualState(page: Page, profile: ReturnType<typeof buildSettingsProfile>) {
  await page.addInitScript((visualState) => {
    (window as unknown as { __IGLOO_TEST_PERMISSION_STATE__?: unknown }).__IGLOO_TEST_PERMISSION_STATE__ =
      visualState;
  }, {
    runtimeSnapshot: buildRunningSnapshot(profile),
    peerPermissionStates: [],
  });
}

async function injectSettingsOnboardVisualState(page: Page) {
  await page.addInitScript((visualState) => {
    (window as unknown as { __IGLOO_TEST_SETTINGS_ONBOARD_STATE__?: unknown }).__IGLOO_TEST_SETTINGS_ONBOARD_STATE__ =
      visualState;
  }, {
    result: {
      label: 'Remote Device',
      memberLabel: 'Share #2',
      sharePublicKeyLabel: 'npub1zfd...3k9p',
      sharePublicKey: '33'.repeat(32),
      packageText: `bfonboard1${'z'.repeat(96)}`,
    },
  });
}

async function capture(page: Page, fileName: string) {
  await mkdir(SETTINGS_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SETTINGS_CAPTURE_DIR, fileName), fullPage: true });
}

async function captureViewport(page: Page, fileName: string) {
  await mkdir(SETTINGS_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SETTINGS_CAPTURE_DIR, fileName), fullPage: false });
}

test.describe('igloo-pwa Paper Settings visual harness @visual', () => {
  test('captures the settings sidebar section layout', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1210 });

    const profile = buildSettingsProfile();
    await injectDashboardVisualState(page, profile);
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot: buildRunningSnapshot(profile),
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.openTab('settings');
    // Paper-aligned sidebar layout: Device Profile, Group Profile, Onboard Device,
    // Replace Share, Export Profile, Export Share, Browser Settings, Logout,
    // Clear Credentials.
    await dashboard.expectSettingsSections();

    await capture(page, '03-settings.png');
    await dashboard.openOnboardDevice();
    await dashboard.expectOnboardDeviceConfigureForm();
    await capture(page, '03c-settings-onboard-device.png');
    await dashboard.closeOnboardDeviceConfigureForm();

    await dashboard.openProfilePassword();
    await dashboard.expectProfilePasswordModal();
    await capture(page, '03f-profile-password-modal.png');
    await dashboard.cancelProfilePassword();

    await dashboard.scrollSettingsSidebarToBottom();
    await capture(page, '03b-settings-security.png');
    await dashboard.openClearCredentials();
    await dashboard.expectClearCredentialsModal();
    await capture(page, '03d-clear-credentials-modal.png');
    await dashboard.cancelClearCredentials();

    await dashboard.editSignerName('Igloo Web Draft');
    await dashboard.closeSettingsSidebar();
    await dashboard.expectUnsavedGuard();
    await capture(page, '03e-unsaved-changes-modal.png');
    await dashboard.discardChanges();
    await dashboard.openTab('settings');

    // Export Profile opens the password-modal entry state.
    await dashboard.openExportProfile();
    await dashboard.expectExportModalEntry();
    await capture(page, '04-export-profile-modal.png');
  });

  test('captures the Settings Onboard Device package handoff modal', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1210 });

    const profile = buildSettingsProfile();
    await injectDashboardVisualState(page, profile);
    await injectSettingsOnboardVisualState(page);
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'settings',
        runtimeSnapshot: buildRunningSnapshot(profile),
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectOnboardDeviceHandoff();
    await capture(page, '03h-settings-onboard-handoff.png');
  });

  test('captures the settings sidebar narrow viewport layout', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });

    const profile = buildSettingsProfile();
    await injectDashboardVisualState(page, profile);
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot: buildRunningSnapshot(profile),
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.openTab('settings');
    await dashboard.expectSettingsSections();
    await dashboard.expectSettingsSidebarFitsViewport();
    await captureViewport(page, '03g-settings-mobile.png');
  });

  test('captures the Settings Replace Share package-entry screen', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildSettingsProfile();
    await injectDashboardVisualState(page, profile);
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot: buildRunningSnapshot(profile),
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.openTab('settings');
    await dashboard.openReplaceShare();
    await page.getByRole('heading', { name: 'Enter Replacement Package' }).waitFor();
    await capture(page, '05-replace-share-entry.png');
  });

  test('captures the Settings Replace Share transient states', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildSettingsProfile();
    const connection = buildReplaceShareVisualConnection(profile);
    const baseState = {
      profiles: [profile],
      selectedProfileId: profile.id,
      activeView: 'dashboard',
      activeDashboardTab: 'signer' as const,
      runtimeSnapshot: buildRunningSnapshot(profile),
    };
    const dashboard = pages(page).dashboard;

    await injectReplaceShareVisualState(page, {
      state: 'applying',
      connection,
      applying: true,
      unlockPassphrase: 'paper-active-device-pass',
    });
    await seedState(page, buildPwaPersistedState(baseState));
    await dashboard.expectReplaceShareApplying();
    await capture(page, '05b-replace-share-applying.png');

    await injectReplaceShareVisualState(page, {
      state: 'failed',
      connection,
      message: 'Check the package, password, group match, and current share state, then retry replacement.',
    });
    await seedState(page, buildPwaPersistedState(baseState));
    await dashboard.expectReplaceShareFailed();
    await capture(page, '05c-replace-share-failed.png');

    await injectReplaceShareVisualState(page, {
      state: 'success',
      result: {
        groupKeyLabel: 'npub1qe3...7k4m',
        oldShareKeyLabel: '02a3f8...8f2c',
        newShareKeyLabel: '03b7d9...2e5a',
      },
    });
    await seedState(page, buildPwaPersistedState(baseState));
    await dashboard.expectReplaceShareSuccess();
    await capture(page, '05d-replace-share-success.png');
  });
});
