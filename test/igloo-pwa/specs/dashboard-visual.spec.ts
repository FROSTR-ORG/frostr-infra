import { expect, test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

test.describe('igloo-pwa Paper Dashboard visual harness @visual', () => {
  test('captures the stopped signer dashboard with the merged identity card', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.goto('/?__frostr_dev=dashboard-stopped');

    const dashboard = pages(page).dashboard;
    // Header nav: Dashboard active (pill), Permissions, Settings.
    await dashboard.expectNavLinks();
    await dashboard.expectNavLink('signer');
    await expect(page.getByRole('tablist', { name: 'Operator dashboard sections' })).toHaveCount(0);
    // Merged status card: both keys shown as deterministic npub displays, split copy present.
    await dashboard.expectKeyDisplays(
      'npub1qgp...z0cn',
      'npub1zyg...sl3h',
    );
    await dashboard.expectKeyCopyControls();
    // Stopped state: Readiness + Next Step cards.
    await dashboard.expectStopped();

    await capture(page, '01-signer-dashboard.png');
  });
});
