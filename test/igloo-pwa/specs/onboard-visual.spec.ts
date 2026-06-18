import { expect, test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'onboard', name });

test.describe('igloo-pwa Paper Onboard visual harness @visual', () => {
  test('captures recipient onboarding states', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'onboard-connect',
        drafts: {
          onboardConnectForm: {
            packageText: `bfonboard1${'q'.repeat(96)}`,
            password: 'paper-onboard-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Input Package' })).toBeVisible();
    await capture(page, '01-input-package.png');

    // The `onboard-handshake` view is transient/runtime-only (normalized away on load),
    // but the store holds it for a guaranteed minimum window after Next Step, so drive it.
    await pages(page).onboard.submitConnect();
    await expect(page.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    await capture(page, '02-onboard-device.png');

    await seedState(
      page,
      buildPwaPersistedState({
        activeView: 'onboard-failed',
        drafts: {
          onboardConnectForm: {
            packageText: `bfonboard1${'q'.repeat(96)}`,
            password: 'paper-onboard-pass',
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Onboarding Failed' })).toBeVisible();
    await capture(page, '03-onboarding-failed.png');

    // NOTE (Paper<->security reconcile): the onboard-save "Save Profile" capture
    // was dropped. It seeded `pendingOnboardConnection` + reloaded, but the
    // reconciled (security) store resets pending connections on load — they carry
    // the passphrase (secret-segregation) — so that screen is not reachable via
    // seed-and-reload. The save step is exercised functionally by app-shell.spec.
  });
});
