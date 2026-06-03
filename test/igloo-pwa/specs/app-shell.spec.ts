import { expect, test } from '@playwright/test';

const STORAGE_KEY = 'igloo-pwa.state.v2';

test.describe('igloo-pwa ui-first shell', () => {
  test('creates a generated profile, distributes a share, and lands on the dashboard', async ({ page }) => {
    await page.goto('/');

    await expect(
      page.getByText('Choose one path to initialize this browser workspace.'),
    ).toBeVisible();
    await page.getByRole('button', { name: 'Start' }).first().click();
    await page.getByLabel('Group Name').fill('Playwright Treasury');
    await page.getByRole('button', { name: 'Generate Keyset' }).click();
    await expect(page.getByText('Select the Device Share')).toBeVisible();

    await page.getByLabel('Device Profile Name').fill('Primary Browser Device');
    await page.getByLabel('Device Password').fill('playwright-browser-pass');
    await page.getByLabel('Confirm Password').fill('playwright-browser-pass');
    await page.getByRole('button', { name: 'Continue to Review' }).click();
    await expect(page.getByText('Preview and Confirm')).toBeVisible();
    await page.getByRole('button', { name: 'Accept and Continue' }).click();
    await expect(page.getByRole('heading', { name: 'Remaining Shares', exact: true })).toBeVisible();

    const shareCard = page
      .locator('section.igloo-panel')
      .filter({ has: page.getByLabel('Share label') })
      .first();
    await shareCard.getByLabel('Share label').fill('Remote Tablet');
    await shareCard.getByLabel('Package password').fill('remote-tablet-pass');
    await shareCard.getByLabel('Confirm Password').fill('remote-tablet-pass');
    await shareCard.getByRole('button', { name: 'QR' }).click();
    await expect(page.getByText('Onboarding Package QR')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByText('Onboarding Package QR')).not.toBeVisible();

    await page.getByRole('button', { name: 'Finish' }).click();
    await expect(page.getByText('Device Dashboard')).toBeVisible();
    await expect(page.getByRole('tab', { name: /Signer\s+runtime console/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /Permissions\s+peer policies/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /Settings\s+operator controls/i })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Manage your signer runtime', exact: true })).toBeVisible();
    // Target the card heading by role: the OperatorSignerPanel help tooltip
    // (HelpHint, igloo-ui H.8) also contains the substring "pending operations",
    // so a loose getByText() now matches two elements.
    await expect(page.getByRole('heading', { name: 'Pending Operations' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Create Keyset' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Load Profile' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Onboard Device' })).toHaveCount(0);
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
              recoverProfileForm: { shareString: '', password: '' },
              onboardConnectForm: { packageText: '', password: '' },
              onboardSaveForm: { label: '', password: '', confirmPassword: '' },
              recoverForm: { groupPackageJson: '', sharePackageJsons: ['', ''] },
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
    // The store persists via a debounced writer (250ms wait / 500ms maxWait),
    // so wait for the toggle change to actually land in localStorage before
    // reloading — otherwise the reload races the pending save and reverts.
    await expect
      .poll(() =>
        page.evaluate((key) => {
          const raw = window.localStorage.getItem(key);
          return raw ? (JSON.parse(raw).settings?.auto_open_signer ?? null) : null;
        }, STORAGE_KEY),
      )
      .toBe(false);
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
              recoverProfileForm: { shareString: '', password: '' },
              onboardConnectForm: { packageText: '', password: '' },
              onboardSaveForm: { label: '', password: '', confirmPassword: '' },
              recoverForm: { groupPackageJson: '', sharePackageJsons: ['', ''] },
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
    await expect(page.getByText('Choose one path to initialize this browser workspace.')).toBeVisible();
    const storedProfilesCard = page
      .getByRole('heading', { name: 'Stored Profiles' })
      .locator('xpath=ancestor::div[contains(@class, "igloo-card")]')
      .first();
    await expect(storedProfilesCard.getByRole('button', { name: 'Primary Browser Device' })).toBeVisible();
    await expect(storedProfilesCard.getByRole('button', { name: 'Load Profile' })).toBeVisible();
  });
});
