import { expect, test } from '@playwright/test';

import {
  DEFAULT_BROWSER_PASSWORD,
  createGeneratedBrowserArtifacts,
  createPwaStoredProfileSeed,
} from '../../shared/browser-artifacts';
import { gotoCreateDistribute } from '../support/flows';
import { pages } from '../support/pages';
import {
  applyPwaSeed,
  buildPwaPersistedState,
  PWA_INSTANCE_ID_KEY,
  PWA_TEST_INSTANCE_ID,
  pwaPartitionKey,
  pwaSeedPayload,
} from '../support/state';

// igloo-pwa partitions persisted state per tab; tests pin the `e2e` instance id
// and read/write its partition (`igloo-pwa.state.v2::e2e`).
const STORAGE_KEY = pwaPartitionKey();

async function seedLockedGeneratedDashboard(page: Parameters<typeof pages>[0]) {
  const artifacts = await createGeneratedBrowserArtifacts({
    groupName: 'Guard Group',
    labelPrefix: 'Guard Device',
    relays: ['wss://relay.primal.net'],
  });
  const profile = createPwaStoredProfileSeed({
    artifact: artifacts.shares[0],
    groupPackageJson: artifacts.groupPackageJson,
    label: 'Guard Device',
  });
  await page.addInitScript(
    (payload) => {
      window.sessionStorage.setItem(payload.instanceIdKey, payload.instanceId);
      if (window.localStorage.getItem(payload.partitionKey)) return;
      window.localStorage.setItem(payload.partitionKey, JSON.stringify(payload.state));
      const profiles = (payload.state as { profiles?: unknown[] } | null)?.profiles;
      const profileCount = Array.isArray(profiles) ? profiles.length : 0;
      const now = Date.now();
      window.localStorage.setItem(
        payload.registryKey,
        JSON.stringify([
          { id: payload.instanceId, label: null, createdAt: now, updatedAt: now, profileCount },
        ]),
      );
    },
    pwaSeedPayload(
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'landing',
        activeDashboardTab: 'signer',
      }),
    ),
  );
  return profile;
}

async function openUnlockedDashboard(page: Parameters<typeof pages>[0]) {
  const profile = await seedLockedGeneratedDashboard(page);
  const p = pages(page);
  await p.welcome.goto();
  await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
  await p.dashboard.expectDashboard();
  return { profile, p };
}

function seededDashboardProfile() {
  return {
    id: 'guard-profile',
    label: 'Guard Device',
    share_public_key: '33'.repeat(32),
    group_public_key: '22'.repeat(32),
    relays: ['wss://relay.primal.net'],
    group_package_json:
      '{"group_name":"Guard Group","group_pk":"22","threshold":2,"members":[{"idx":1},{"idx":2},{"idx":3}]}',
    share_package_json: '{"idx":1,"seckey":"11"}',
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
    source: 'bfprofile' as const,
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'g',
    encrypted_profile_ref: 'e',
    state_path: '/tmp/guard',
    created_at: 1_700_000_000_000,
    stored_password: 'pw',
    profile_string: 'bfprofile1guard',
    share_string: 'bfshare1guard',
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

test.describe('igloo-pwa ui-first shell', () => {
  test('creates a generated profile, distributes shares, and finishes setup to the locked welcome', async ({ page }) => {
    const p = pages(page);
    await p.welcome.goto();
    await p.welcome.expectEntryHero();

    await gotoCreateDistribute(page, {
      groupName: 'Playwright Treasury',
      profileName: 'Primary Browser Device',
      password: 'playwright-browser-pass',
    });
    await expect(page.getByText('Remote Shares')).toBeVisible();

    // First remote share: package → QR → mark delivered.
    const first = p.distribute.cards().nth(0);
    await p.distribute.preparePackage(first, 'remote-tablet-pass');
    await p.distribute.showQr(first);
    await expect(page.getByText('Onboarding Package QR')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByText('Onboarding Package QR')).not.toBeVisible();
    await p.distribute.markDelivered(first);

    // Second remote share: package + mark delivered.
    const second = p.distribute.cards().nth(1);
    await p.distribute.preparePackage(second, 'remote-tablet-pass');
    await p.distribute.markDelivered(second);

    // Finish Setup persists the profile, stops the runtime, purges setup secrets,
    // and returns to the locked returning Welcome (all shares delivered, so no
    // undelivered-shares confirmation fires) — matching the reconciled pwa
    // finishSetup, which navigates back to the landing/welcome surface.
    await p.distribute.finish();
    await expect(page).toHaveURL(/\/$/);
    await p.welcome.expectReturning();
    await expect(p.welcome.row().getByText('Primary Browser Device')).toBeVisible();
    await expect(page.getByText('Device Dashboard')).toHaveCount(0);
  });

  test('recovers a reloaded create setup state to the first create form', async ({ page }) => {
    await page.addInitScript(
      applyPwaSeed,
      pwaSeedPayload(
        buildPwaPersistedState({
          activeView: 'create-select-share',
          drafts: {
            createForm: {
              mode: 'new',
              groupName: 'Recovered Treasury',
              threshold: '2',
              count: '3',
            },
          },
        }),
      ),
    );

    const p = pages(page);
    await page.goto('/');
    await p.create.expectGenerateForm({ groupName: 'Recovered Treasury' });
    await expect(p.create.generateNextButton).toBeVisible();
    await p.create.expectSelectShareHidden();

    await page.reload();
    await p.create.expectGenerateForm({ groupName: 'Recovered Treasury' });
  });

  test('keeps focus in the Export Share password field while typing', async ({ page }) => {
    const { p } = await openUnlockedDashboard(page);

    await p.dashboard.openTab('settings');
    await p.dashboard.scrollSettingsSidebarToBottom();
    await p.dashboard.openExportShare();

    const dialog = page.getByRole('dialog', { name: 'Export Share' });
    const password = p.dashboard.exportPasswordInput;
    const passwordShell = p.dashboard.exportPasswordFieldShell;
    await expect(dialog).toBeVisible();
    await p.dashboard.expectSettingsSidebarClosed();
    await passwordShell.click({ position: { x: 8, y: 8 } });
    for (const character of ['a', 'b', 'c']) {
      await page.keyboard.type(character, { delay: 75 });
      await expect.poll(() => password.evaluate((node) => node === document.activeElement)).toBe(true);
    }

    await expect(password).toHaveValue('abc');
    await expect.poll(() => password.evaluate((node) => node === document.activeElement)).toBe(true);
  });

  test('keeps focus in Settings sidebar profile and relay inputs while typing', async ({ page }) => {
    const { p } = await openUnlockedDashboard(page);

    await p.dashboard.openTab('settings');

    const selectAll = process.platform === 'darwin' ? 'Meta+A' : 'Control+A';
    const profileName = p.dashboard.settingsProfileNameInput;
    await expect(profileName).toBeVisible();
    await profileName.click({ position: { x: 10, y: 10 } });
    await page.keyboard.press(selectAll);
    for (const character of 'Smoke Device') {
      await page.keyboard.type(character, { delay: 35 });
      await expect.poll(() => profileName.evaluate((node) => node === document.activeElement)).toBe(true);
    }
    await expect(profileName).toHaveValue('Smoke Device');

    const relayUrl = 'wss://relay-smoke.example';
    const relayInput = p.dashboard.settingsRelayInput;
    await relayInput.click({ position: { x: 10, y: 10 } });
    for (const character of relayUrl) {
      await page.keyboard.type(character, { delay: 20 });
      await expect.poll(() => relayInput.evaluate((node) => node === document.activeElement)).toBe(true);
    }
    await expect(relayInput).toHaveValue(relayUrl);
    await page.keyboard.press('Enter');
    await p.dashboard.expectSettingsRelay(relayUrl);
  });

  test('returns persisted dashboard routes to the locked landing screen on reload', async ({ page }) => {
    await page.addInitScript(({ storageKey, instanceIdKey, instanceId }) => {
      window.sessionStorage.setItem(instanceIdKey, instanceId);
      if (!window.localStorage.getItem(storageKey)) {
        window.localStorage.setItem(
          storageKey,
          JSON.stringify({
            profiles: [
              {
                id: 'profile-1',
                label: 'Primary Browser Device',
                share_public_key: 'share-pub-1',
                group_public_key: 'group-pub-1',
                relays: ['wss://relay.primal.net'],
                group_package_json:
                  '{"group_name":"Playwright Group","group_pk":"group-pub-1","threshold":2,"members":[{"idx":1},{"idx":2},{"idx":3}]}',
                // v2 schema (Bucket D): stored_password / share_package_json /
                // profile_string / share_string are no longer persisted; the
                // share reconstructs in-memory from encrypted_bfshare_artifact.
                encrypted_bfshare_artifact: 'bfshare1demo',
                member_idx: 1,
                source: 'bfprofile',
                relay_profile: 'browser',
                group_ref: 'group-ref',
                encrypted_profile_ref: 'encrypted-profile-ref',
                state_path: '/tmp/igloo-pwa/profile-1',
                created_at: 1700000000000,
                signer_settings: {
                  sign_timeout_secs: 30,
                  ping_timeout_secs: 15,
                  request_ttl_secs: 300,
                  state_save_interval_secs: 30,
                  peer_selection_strategy: 'deterministic_sorted',
                },
              },
            ],
            peerPermissionStates: [],
            selectedProfileId: 'profile-1',
            activeView: 'dashboard',
            activeDashboardTab: 'settings',
            activeSignerTab: 'signer',
            unlockPhrase: '',
            generatedKeyset: null,
            selectedGeneratedShareIdx: null,
            pendingLoadConfirmation: null,
            pendingOnboardConnection: null,
            distributionSession: null,
            recoveredKey: null,
            runtimeSnapshot: null,
            settings: {
              remember_browser_state: true,
              auto_open_signer: true,
              prefer_install_prompt: true,
            },
            drafts: {
              createForm: {
                groupName: '',
                secretKey: '',
                detectedFormat: null,
                threshold: '2',
                count: '3',
              },
              profileForm: {
                label: '',
                password: '',
                confirmPassword: '',
                relayUrls: 'wss://relay.primal.net',
              },
              distributionForms: {},
              importProfileForm: { profileString: '', password: '' },
              onboardConnectForm: { packageText: '', password: '' },
              onboardSaveForm: { label: '', password: '', confirmPassword: '' },
            },
          }),
        );
      }
    }, { storageKey: STORAGE_KEY, instanceIdKey: PWA_INSTANCE_ID_KEY, instanceId: PWA_TEST_INSTANCE_ID });

    await page.goto('/');
    const p = pages(page);
    await p.welcome.expectReturning(1);
    await expect(page.getByText('Primary Browser Device')).toBeVisible();
    await p.dashboard.expectNoDashboard();

    await page.reload();
    await p.welcome.expectReturning(1);
    await expect(page.getByText('Primary Browser Device')).toBeVisible();
    await expect(page.getByText('Enter the device passphrase to start the signer.')).toHaveCount(0);
  });

  test('opens dashboard deep links after unlock and records tab history', async ({ page }) => {
    const profile = await seedLockedGeneratedDashboard(page);
    const p = pages(page);

    await page.goto('/dashboard/permissions');
    await p.welcome.expectReturning(1);
    await p.dashboard.expectNoDashboard();

    await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
    await p.dashboard.expectPeerPermissions();
    await p.dashboard.expectDashboardActionActive('permissions');
    await p.dashboard.expectRoute('permissions');

    await p.dashboard.openTab('signer');
    await p.dashboard.expectDashboard();
    await p.dashboard.expectDashboardActionActive('dashboard');
    await p.dashboard.expectRoute('signer');

    await page.goBack();
    await p.dashboard.expectPeerPermissions();
    await p.dashboard.expectDashboardActionActive('permissions');
    await p.dashboard.expectRoute('permissions');
  });

  test('opens dashboard recover deep links after unlock', async ({ page }) => {
    const profile = await seedLockedGeneratedDashboard(page);
    const p = pages(page);

    await page.goto('/dashboard/recover');
    await p.welcome.expectReturning(1);
    await p.dashboard.expectNoDashboard();

    await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
    await p.dashboard.expectRecoverCollect('dashboard');
    await expect(page).toHaveURL(/\/dashboard\/recover\/?$/);
  });

  test('opens dashboard settings deep links after unlock', async ({ page }) => {
    const profile = await seedLockedGeneratedDashboard(page);
    const p = pages(page);

    await page.goto('/dashboard/settings');
    await p.welcome.expectReturning(1);
    await p.dashboard.expectNoDashboard();

    await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
    await p.dashboard.expectSettingsSections();
    await p.dashboard.expectDashboardActionActive('settings');
    await p.dashboard.expectRoute('settings');
  });

  test('settings expose the unified actions and logout returns to landing while preserving saved profiles', async ({ page }) => {
    const { profile, p } = await openUnlockedDashboard(page);
    await p.dashboard.expectDashboard();
    await expect(page.getByText('Choose one path to initialize this browser workspace.')).toHaveCount(0);

    await p.dashboard.openTab('settings');
    await p.dashboard.expectSettingsActions();
    await expect(page.getByText(/reset browser workspace/i)).toHaveCount(0);
    await p.dashboard.logout();
    await expect(page.getByText('Welcome back.')).toBeVisible();
    await p.welcome.expectReturning();
    await expect(p.welcome.row(profile.id).getByText('Guard Device')).toBeVisible();
  });

  test('saves Settings profile changes through reload and unlock', async ({ page }) => {
    const { profile, p } = await openUnlockedDashboard(page);
    const dashboard = p.dashboard;
    const savedName = 'Saved Browser Signer';
    const savedRelay = 'wss://relay.damus.io';

    await dashboard.openTab('settings');
    await dashboard.expectSettingsSections();
    await dashboard.editSignerName(savedName);
    await dashboard.addSettingsRelay(savedRelay);
    await dashboard.saveSettings();
    await dashboard.expectDashboard();
    await dashboard.expectDashboardActionActive('dashboard');

    await page.reload();
    await p.welcome.expectReturning(1);
    await expect(p.welcome.row(profile.id).getByText(savedName)).toBeVisible();

    await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
    await dashboard.expectDashboard();
    await dashboard.openTab('settings');
    await dashboard.expectSignerName(savedName);
    await dashboard.expectSettingsRelay(savedRelay);
  });

  test('saves Permissions peer overrides through reload and unlock', async ({ page }) => {
    const { profile, p } = await openUnlockedDashboard(page);
    const dashboard = p.dashboard;

    await dashboard.openTab('permissions');
    await dashboard.expectPeerPermissions();
    await dashboard.expectPeerPermission('request', 'sign', 'allow');
    await dashboard.toggleFirstPeerPermission('request', 'sign', 'allow');
    await dashboard.expectPeerPermission('request', 'sign', 'deny');

    await page.reload();
    await p.welcome.expectReturning(1);
    await expect(p.welcome.row(profile.id).getByText('Guard Device')).toBeVisible();

    await p.welcome.unlock(DEFAULT_BROWSER_PASSWORD, profile.id);
    await dashboard.expectDashboard();
    await dashboard.openTab('permissions');
    await dashboard.expectPeerPermission('request', 'sign', 'deny');
  });

  test('guards unsaved Settings edits when navigating away', async ({ page }) => {
    const { p } = await openUnlockedDashboard(page);
    const dashboard = p.dashboard;
    await dashboard.expectDashboard();
    await dashboard.openTab('settings');
    await dashboard.expectRoute('settings');
    await dashboard.editSignerName('Edited Name');

    // Browser Back out of dirty Settings opens the guard; Keep editing restores Settings.
    await page.goBack();
    await dashboard.expectUnsavedGuard();
    await dashboard.keepEditing();
    await dashboard.expectSettingsSections();
    await dashboard.expectRoute('settings');

    // Leaving Settings via app nav with unsaved edits opens the same guard.
    await dashboard.openTab('permissions');
    await dashboard.expectUnsavedGuard();
    await dashboard.keepEditing();
    await dashboard.expectSettingsSections();

    // Discard navigates away and resets the draft.
    await dashboard.openTab('permissions');
    await dashboard.expectUnsavedGuard();
    await dashboard.discardChanges();
    await dashboard.expectPeerPermissions();
  });

  test('keeps dashboard navigation aligned with Paper header actions', async ({ page }) => {
    const { p } = await openUnlockedDashboard(page);
    const dashboard = p.dashboard;
    await dashboard.expectDashboard();
    await dashboard.expectDashboardActionActive('dashboard');
    await dashboard.expectNoRuntimeRecoverAction();

    await dashboard.openTab('permissions');
    await dashboard.expectPeerPermissions();
    await dashboard.expectDashboardActionActive('permissions');

    await dashboard.openTab('signer');
    await dashboard.expectDashboard();
    await dashboard.expectDashboardActionActive('dashboard');
  });
});
