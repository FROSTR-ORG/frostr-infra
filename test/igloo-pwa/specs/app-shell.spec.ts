import { expect, test } from '@playwright/test';

import { gotoCreateDistribute } from '../support/flows';
import { pages } from '../support/pages';
import { PWA_GLOBAL_STORE_KEY } from '../support/state';

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
    await page.goto('/?__frostr_dev=dashboard-settings');
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
    await dashboard.openTab('settings');
    await expect(dashboard.autoOpenToggle).not.toBeChecked();
  });

  test('settings expose the unified actions and logout returns to landing while preserving saved profiles', async ({ page }) => {
    await page.goto('/?__frostr_dev=dashboard-settings');
    const p = pages(page);
    await p.dashboard.expectDashboard();
    await expect(page.getByText('Choose one path to initialize this browser workspace.')).toHaveCount(0);

    await p.dashboard.expectSettingsActions();
    await expect(page.getByText(/reset browser workspace/i)).toHaveCount(0);
    await p.dashboard.logout();
    await expect(page.getByText('Welcome back.')).toBeVisible();
    await p.welcome.expectReturning();
    await expect(page.getByText('Dev Signing Key')).toBeVisible();
  });

  test('guards unsaved Settings edits when navigating away', async ({ page }) => {
    await page.goto('/?__frostr_dev=dashboard-settings');
    const dashboard = pages(page).dashboard;
    await dashboard.expectDashboard();
    await dashboard.editSignerName('Edited Name');

    // Closing Settings with unsaved edits opens the guard; Keep editing stays put.
    await dashboard.closeSettings();
    await dashboard.expectUnsavedGuard();
    await dashboard.keepEditing();
    await dashboard.expectSettingsSections();

    // Discard closes Settings and resets the draft; another tab can be opened after
    // the modal drawer is gone.
    await dashboard.closeSettings();
    await dashboard.expectUnsavedGuard();
    await dashboard.discardChanges();
    await dashboard.openTab('permissions');
    await dashboard.expectPeerPermissions();
  });
});
