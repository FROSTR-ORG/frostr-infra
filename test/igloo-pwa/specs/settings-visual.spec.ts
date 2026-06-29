import { test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

test.describe('igloo-pwa Paper Settings visual harness @visual', () => {
  test('captures the settings drawer over the running dashboard', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.goto('/?__frostr_dev=dashboard-settings');

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.expectSettingsSections();

    await capture(page, '03-settings.png');

    // Export Profile opens the password-modal entry state.
    await dashboard.openExportProfile();
    await dashboard.expectExportModalEntry();
    await capture(page, '04-export-profile-modal.png');

    await dashboard.closeExportModalEntry();
    await dashboard.editSignerName('Edited Name');
    await dashboard.closeSettings();
    await dashboard.expectUnsavedGuard();
    await capture(page, '05-unsaved-changes-modal.png');

    await dashboard.keepEditing();
    await dashboard.openClearCredentialsDialog();
    await dashboard.expectClearCredentialsDialog();
    await capture(page, '06-clear-credentials-modal.png');
  });
});
