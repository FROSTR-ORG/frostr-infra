import { expect, test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

test.describe('igloo-pwa Paper Permissions visual harness @visual', () => {
  test('captures the peer-only permissions page', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.goto('/?__frostr_dev=dashboard-permissions');

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    // PWA Permissions is peer-only: Peer Permissions renders; the chrome-only
    // website/origin "Signer Permissions" section must not appear.
    await dashboard.expectPeerPermissions();
    await dashboard.expectNoSignerPermissions();

    await capture(page, '02-permissions.png');
  });
});
