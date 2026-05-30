import { expect, test } from '@playwright/test';

import {
  completeDistributionCard,
  markDistributionCardDistributed,
  prepareDistributionPackage,
} from '../support/ui';

const STORAGE_KEY = 'igloo-pwa.state.v1';

test.describe('igloo-pwa ui-first shell', () => {
  test('creates a generated profile, distributes shares, and finishes setup to the locked welcome', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByText('Split your Nostr key. Sign from anywhere.')).toBeVisible();
    await page.getByRole('button', { name: 'Generate' }).click();
    await page.getByLabel('Group Name').fill('Playwright Treasury');
    await page.getByRole('button', { name: 'Next Step' }).click();
    await expect(page.getByRole('heading', { name: 'Select Share' })).toBeVisible();
    await expect(page.getByText('Choose Local Share')).toBeVisible();
    await page.getByRole('button', { name: 'Next Step' }).click();

    await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
    await page.getByLabel('Device Profile Name').fill('Primary Browser Device');
    await page.getByLabel('Device Password').fill('playwright-browser-pass');
    await page.getByLabel('Confirm Password').fill('playwright-browser-pass');
    await page.getByRole('button', { name: 'Next Step' }).click();
    await expect(page.getByText('Remote Shares')).toBeVisible();
    await expect(page.getByText('Distribution Completion')).toHaveCount(0);

    // Locate positionally: once packaged, the card no longer renders a password
    // field, so filtering by it would stop matching after Create Package.
    const shareCard = page
      .locator('section.igloo-create-distribution-card')
      .first();
    await prepareDistributionPackage(shareCard, 'remote-tablet-pass');
    await shareCard.getByRole('button', { name: 'QR code' }).click();
    await expect(page.getByText('Onboarding Package QR')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByText('Onboarding Package QR')).not.toBeVisible();
    await markDistributionCardDistributed(shareCard);

    const remainingCard = page
      .locator('section.igloo-create-distribution-card')
      .filter({ has: page.getByRole('heading', { name: /Playwright Treasury Device 3/ }) })
      .first();
    await completeDistributionCard(remainingCard, 'remote-tablet-pass');

    // Finish Setup persists the profile, stops the runtime, purges setup secrets,
    // and returns to the locked returning Welcome (all shares delivered, so no
    // undelivered-shares confirmation fires).
    await page.getByRole('button', { name: 'Finish Setup' }).click();
    await expect(page.getByText('Primary Browser Device')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Unlock' })).toBeVisible();
    await expect(page.getByText('Device Dashboard')).toHaveCount(0);
    await expect(page.getByRole('tab', { name: /Signer\s+runtime console/i })).toHaveCount(0);
  });

  test('persists settings across reloads', async ({ page }) => {
    await page.addInitScript(([storageKey]) => {
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
                share_package_json: '{"share":"demo"}',
                source: 'bfprofile',
                relay_profile: 'browser',
                group_ref: 'group-ref',
                encrypted_profile_ref: 'encrypted-profile-ref',
                state_path: '/tmp/igloo-pwa/profile-1',
                created_at: 1700000000000,
                stored_password: 'pw',
                profile_string: 'bfprofile1demo',
                share_string: 'bfshare1demo',
                signer_settings: {
                  sign_timeout_secs: 30,
                  ping_timeout_secs: 15,
                  request_ttl_secs: 300,
                  state_save_interval_secs: 30,
                  peer_selection_strategy: 'deterministic_sorted',
                },
                onboarding_package: null,
              },
            ],
            peerPolicies: [],
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
    }, [STORAGE_KEY]);

    await page.goto('/');
    await expect(page.getByRole('tab', { name: /Settings\s+operator controls/i })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Browser Settings', exact: true })).toBeVisible();

    const toggle = page.getByLabel(/Open signer after import/i);
    await toggle.uncheck();
    await page.reload();
    await expect(page.getByRole('tab', { name: /Settings\s+operator controls/i })).toBeVisible();
    await expect(toggle).not.toBeChecked();
  });

  test('settings expose the unified actions and logout returns to landing while preserving saved profiles', async ({ page }) => {
    await page.addInitScript(([storageKey]) => {
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
                share_package_json: '{"share":"demo"}',
                source: 'bfprofile',
                relay_profile: 'wss://relay.primal.net',
                group_ref: 'group-ref',
                encrypted_profile_ref: 'encrypted-profile-ref',
                state_path: '/tmp/igloo-pwa/profile-1',
                created_at: 1700000000000,
                stored_password: 'pw',
                profile_string: 'bfprofile1demo',
                share_string: 'bfshare1demo',
                signer_settings: {
                  sign_timeout_secs: 30,
                  ping_timeout_secs: 15,
                  request_ttl_secs: 300,
                  state_save_interval_secs: 30,
                  peer_selection_strategy: 'deterministic_sorted',
                },
                onboarding_package: null,
              },
            ],
            peerPolicies: [],
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
    }, [STORAGE_KEY]);

    await page.goto('/');
    await expect(page.getByText('Device Dashboard')).toBeVisible();
    await expect(page.getByText('Choose one path to initialize this browser workspace.')).toHaveCount(0);

    await page.getByRole('tab', { name: /Settings\s+operator controls/i }).click();
    await expect(page.getByRole('button', { name: 'copy profile' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'copy share' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'rotate share' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'logout' })).toBeVisible();
    await expect(page.getByRole('button', { name: /reset browser workspace/i })).toHaveCount(0);
    await page.getByRole('button', { name: 'logout' }).click();
    await expect(page.getByText('Welcome back.')).toBeVisible();
    const profileRow = page.locator('.igloo-welcome-profile-row').filter({ hasText: 'Primary Browser Device' }).first();
    await expect(profileRow).toBeVisible();
    await expect(profileRow.getByRole('button', { name: 'Unlock' })).toBeVisible();
  });
});
