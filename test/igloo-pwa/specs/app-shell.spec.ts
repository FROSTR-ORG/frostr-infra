import { expect, test } from '@playwright/test';

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

function seededDashboardProfile() {
  return {
    id: 'guard-profile',
    label: 'Guard Device',
    share_public_key: '33'.repeat(32),
    group_public_key: '22'.repeat(32),
    relays: ['wss://relay.primal.net'],
    group_package_json: '{"group_name":"Guard Group","group_pk":"22","threshold":2,"members":[]}',
    share_package_json: '{"idx":1,"seckey":"11"}',
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
    await p.welcome.expectReturning();
    await expect(p.welcome.row().getByText('Primary Browser Device')).toBeVisible();
    await expect(page.getByText('Device Dashboard')).toHaveCount(0);
  });

  test('persists settings across reloads', async ({ page }) => {
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
                  '{"group_name":"Playwright Group","group_pk":"group-pub-1","threshold":2,"members":[]}',
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
    const dashboard = pages(page).dashboard;
    await dashboard.expectDashboard();
    await dashboard.openTab('settings');
    await expect(page.getByRole('heading', { name: 'Device Profile', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Browser Settings', exact: true })).toBeVisible();

    await dashboard.autoOpenToggle.uncheck();
    // The reconciled store persists via a debounced writer (250ms/500ms), so wait
    // for the toggle change to land in localStorage before reloading — otherwise
    // the reload races the pending save and reverts.
    await expect
      .poll(() =>
        page.evaluate((key) => {
          const raw = window.localStorage.getItem(key);
          return raw ? (JSON.parse(raw).settings?.auto_open_signer ?? null) : null;
        }, STORAGE_KEY),
      )
      .toBe(false);
    await page.reload();
    await dashboard.expectDashboard();
    await expect(dashboard.autoOpenToggle).not.toBeChecked();
  });

  test('settings expose the unified actions and logout returns to landing while preserving saved profiles', async ({ page }) => {
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
                  '{"group_name":"Playwright Group","group_pk":"group-pub-1","threshold":2,"members":[]}',
                // v2 schema (Bucket D): stored_password / share_package_json /
                // profile_string / share_string are no longer persisted; the
                // share reconstructs in-memory from encrypted_bfshare_artifact.
                encrypted_bfshare_artifact: 'bfshare1demo',
                member_idx: 1,
                source: 'bfprofile',
                relay_profile: 'wss://relay.primal.net',
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
            activeDashboardTab: 'signer',
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
    await p.dashboard.expectDashboard();
    await expect(page.getByText('Choose one path to initialize this browser workspace.')).toHaveCount(0);

    await p.dashboard.openTab('settings');
    await p.dashboard.expectSettingsActions();
    await expect(page.getByText(/reset browser workspace/i)).toHaveCount(0);
    await p.dashboard.logout();
    await expect(page.getByText('Welcome back.')).toBeVisible();
    await p.welcome.expectReturning();
    await expect(p.welcome.row('profile-1').getByText('Primary Browser Device')).toBeVisible();
  });

  test('guards unsaved Settings edits when navigating away', async ({ page }) => {
    const profile = seededDashboardProfile();
    await page.addInitScript(
      applyPwaSeed,
      pwaSeedPayload(
        buildPwaPersistedState({
          profiles: [profile],
          selectedProfileId: profile.id,
          activeView: 'dashboard',
          activeDashboardTab: 'settings',
        }),
      ),
    );

    await page.goto('/');
    const dashboard = pages(page).dashboard;
    await dashboard.expectDashboard();
    await dashboard.editSignerName('Edited Name');

    // Leaving Settings with unsaved edits opens the guard; Keep editing stays put.
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
});
