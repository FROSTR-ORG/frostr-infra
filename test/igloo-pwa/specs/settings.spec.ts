import { expect, test, type Page } from '@playwright/test';

import { startLocalRelay } from '../../shared/local-relay';
import { LIVE_TEST_TIMEOUT_MS } from '../../shared/playwright-config';
import { pages } from '../support/pages';
import { expectPwaRuntimeConnected } from '../support/ui';

// @live — genuine behavioral coverage of the operator Settings form: edit the
// signer name, add a relay, and change a numeric setting, then SAVE against a
// real running runtime (Save is gated on an active signer) and prove the change
// survives a full browser reload through the real persistence store. The prior
// settings-visual spec only seeds fake state and screenshots — it never drives a
// save or asserts persistence.
//
// A freshly-created keyset (no peer) is enough here: Save only requires the
// runtime to be active, which a solo signer satisfies (see create-keyset.spec).

const RELAY_TO_ADD = 'wss://relay.settings-persist.test';
const NEW_SIGNER_NAME = 'Renamed Operator Device';
const NEW_SIGN_TIMEOUT = 45; // default is 30

// Scan every per-instance partition for a persisted profile carrying `label`.
// Confirms the debounced persistor has flushed the saved settings to localStorage
// before we reload — decoupled from the exact partition key (storage.ts namespaces
// by sessionStorage instance id).
async function persistedHasSignerName(page: Page, label: string): Promise<boolean> {
  return page.evaluate((wanted) => {
    for (let i = 0; i < window.localStorage.length; i += 1) {
      const key = window.localStorage.key(i);
      if (!key || !key.startsWith('igloo-pwa.state.v2')) continue;
      try {
        const parsed = JSON.parse(window.localStorage.getItem(key) ?? 'null');
        const profiles = parsed?.profiles;
        if (Array.isArray(profiles) && profiles.some((profile) => profile?.label === wanted)) {
          return true;
        }
      } catch {
        // ignore unparsable partitions
      }
    }
    return false;
  }, label);
}

test.describe('igloo-pwa operator settings persistence @live', () => {
  test('saves signer name, relay, and a timeout, and persists them across a reload', async ({ page }) => {
    test.setTimeout(LIVE_TEST_TIMEOUT_MS);
    const relay = await startLocalRelay();
    try {
      const p = pages(page);

      // Create a brand-new keyset and bring up a live solo runtime (Save needs it).
      await page.goto('/');
      await p.welcome.startGenerate();
      await p.create.fillGenerate({ groupName: 'Settings Keyset' });
      await p.create.generateNext();
      await expect(page.getByRole('heading', { name: 'Select Share' })).toBeVisible({ timeout: 30_000 });
      await p.create.selectShare(1);
      await p.create.selectShareNext();

      await expect(page.getByRole('heading', { name: 'Save Profile' })).toBeVisible();
      await p.create.fillSaveProfile({ name: 'Settings Device', password: 'playwright-passphrase' });
      await p.create.addRelay(relay.url);
      await p.create.expectRelay(relay.url);
      await p.create.saveProfileNext();

      await expect(page.getByRole('heading', { name: 'Remote Shares', exact: true })).toBeVisible();
      const remoteCount = await p.distribute.cards().count();
      expect(remoteCount).toBeGreaterThan(0);
      for (let i = 0; i < remoteCount; i += 1) {
        const card = p.distribute.cards().nth(i);
        await p.distribute.preparePackage(card, 'settings-remote-pass');
        await p.distribute.markDelivered(card);
      }
      await p.distribute.finish();
      await p.welcome.expectReturning();

      await p.welcome.unlock('playwright-passphrase');
      await p.dashboard.expectDashboard('Settings Device');
      await expectPwaRuntimeConnected(page);

      // Edit the settings form, then Save against the running runtime.
      await p.dashboard.openTab('settings');
      await p.dashboard.expectSignerName('Settings Device');
      await p.dashboard.setSignerName(NEW_SIGNER_NAME);
      await p.dashboard.addSettingsRelay(RELAY_TO_ADD);
      await p.dashboard.expectSettingsRelay(RELAY_TO_ADD);
      await p.dashboard.setNumberSetting('sign_timeout_secs', NEW_SIGN_TIMEOUT);
      await expect(p.dashboard.settingsSaveButton).toBeEnabled();
      await p.dashboard.saveSettings();

      // The save is async (applies to the live runtime, then persists the updated
      // profile). Gate the reload on the debounced persistor actually flushing the
      // new label to localStorage.
      await expect.poll(() => persistedHasSignerName(page, NEW_SIGNER_NAME), {
        timeout: 15_000,
      }).toBe(true);

      // Full browser reload wipes all in-memory state. remember_browser_state
      // restores the dashboard directly (same tab → same instance partition); the
      // runtime stays stopped (its snapshot is never persisted), but the Settings
      // form rehydrates its public fields purely from the persisted profile — so
      // reading them back proves the save round-tripped through localStorage.
      await page.reload();
      await p.dashboard.expectDashboard();

      await p.dashboard.openTab('settings');
      await p.dashboard.expectSignerName(NEW_SIGNER_NAME);
      await p.dashboard.expectSettingsRelay(relay.url);
      await p.dashboard.expectSettingsRelay(RELAY_TO_ADD);
      await p.dashboard.expectNumberSetting('sign_timeout_secs', NEW_SIGN_TIMEOUT);
    } finally {
      await relay.close();
    }
  });
});
