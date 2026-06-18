import { expect, test } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { gotoCreateDistribute } from '../support/flows';
import { pages } from '../support/pages';
import {
  applyPwaSeed,
  buildPwaPersistedState,
  PWA_GLOBAL_STORE_KEY,
  pwaSeedPayload,
} from '../support/state';

function seededDashboardProfile(): PwaStoredProfileSeed {
  return {
    id: 'guard-profile',
    label: 'Guard Device',
    share_public_key: '33'.repeat(32),
    group_public_key: '22'.repeat(32),
    relays: ['wss://relay.primal.net'],
    group_package_json: '{"group_name":"Guard Group","group_pk":"22","threshold":2,"members":[]}',
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
    source: 'bfprofile',
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'g',
    encrypted_profile_ref: 'e',
    state_path: '/tmp/guard',
    created_at: 1_700_000_000_000,
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted',
    },
    manual_peer_policy_overrides: [],
    peer_pubkey: null,
  };
}

test.describe('igloo-pwa ui-first shell @fast', () => {
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
    const profile = seededDashboardProfile();
    // ifAbsent: this spec reloads, and addInitScript re-runs on every load — only
    // seed when the store is absent so the reload keeps the toggle this test
    // persists, instead of clobbering it back to the seed default.
    const seed = pwaSeedPayload(
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'settings',
      }),
    );
    seed.ifAbsent = true;
    await page.addInitScript(applyPwaSeed, seed);

    await page.goto('/');
    const dashboard = pages(page).dashboard;
    await dashboard.expectDashboard();
    await dashboard.openTab('settings');
    await expect(page.getByRole('heading', { name: 'Device Profile', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Browser Settings', exact: true })).toBeVisible();

    await dashboard.autoOpenToggle.uncheck();
    // The reconciled store persists via a debounced writer (250ms/500ms), so wait
    // for the toggle change to land in the global store (settings live there, not
    // in the per-tab session partition) before reloading — otherwise the reload
    // races the pending save and reverts.
    await expect
      .poll(() =>
        page.evaluate((key) => {
          const raw = window.localStorage.getItem(key);
          return raw ? (JSON.parse(raw).settings?.auto_open_signer ?? null) : null;
        }, PWA_GLOBAL_STORE_KEY),
      )
      .toBe(false);
    await page.reload();
    await dashboard.expectDashboard();
    await expect(dashboard.autoOpenToggle).not.toBeChecked();
  });

  test('settings expose the unified actions and logout returns to landing while preserving saved profiles', async ({ page }) => {
    const profile = { ...seededDashboardProfile(), id: 'profile-1', label: 'Primary Browser Device' };
    await page.addInitScript(
      applyPwaSeed,
      pwaSeedPayload(
        buildPwaPersistedState({
          profiles: [profile],
          selectedProfileId: profile.id,
          activeView: 'dashboard',
        }),
      ),
    );

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
