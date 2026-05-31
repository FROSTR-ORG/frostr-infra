import { expect, type Browser, type BrowserContext, type Locator, type Page } from '@playwright/test';
import { CRITICAL_E2E_TEST_IDS, type CriticalE2ETestId } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';
import { DEFAULT_BROWSER_PASSWORD } from '../../shared/browser-artifacts';

import { PWA_STORAGE_KEY } from './state';

// The e2e test-id registry must be imported only here (enforced by
// check-e2e-selector-contracts.sh). Page objects consume it via this re-export.
export { CRITICAL_E2E_TEST_IDS as TID } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';
export type { CriticalE2ETestId } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';

export function byTestId(scope: Page | Locator, id: CriticalE2ETestId): Locator {
  return scope.getByTestId(id);
}

export async function seedPwaState(page: Page, state: unknown) {
  await page.addInitScript(
    ({ storageKey, payload }: { storageKey: string; payload: unknown }) => {
      window.localStorage.setItem(storageKey, JSON.stringify(payload));
    },
    { storageKey: PWA_STORAGE_KEY, payload: state },
  );
}

export async function openPwaLoadProfile(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Load Profile' }).first().click();
}

export async function getPwaStoredProfilesCard(page: Page) {
  const storedProfilesCard = page
    .getByRole('heading', { name: 'Stored Profiles' })
    .locator('xpath=ancestor::div[contains(@class, "igloo-card")]')
    .first();
  await expect(storedProfilesCard).toBeVisible();
  return storedProfilesCard;
}

export async function selectPwaStoredProfile(page: Page, label: string) {
  const storedProfilesCard = await getPwaStoredProfilesCard(page);
  const selector = storedProfilesCard.locator('button[aria-pressed]').filter({ hasText: label }).first();
  await selector.click();
  return selector.locator(`xpath=ancestor::*[@data-testid="${CRITICAL_E2E_TEST_IDS.storedProfileEntry}"][1]`);
}

export async function loadSelectedPwaStoredProfile(page: Page) {
  const storedProfilesCard = await getPwaStoredProfilesCard(page);
  const selectedEntry = storedProfilesCard
    .locator('button[aria-pressed="true"]')
    .first()
    .locator(`xpath=ancestor::*[@data-testid="${CRITICAL_E2E_TEST_IDS.storedProfileEntry}"][1]`);
  await selectedEntry.getByTestId(CRITICAL_E2E_TEST_IDS.storedProfileLoad).click();
}

export async function importPwaProfile(page: Page, profileText: string, password: string) {
  await openPwaLoadProfile(page);
  await page.getByRole('button', { name: 'Import Profile' }).click();
  await page.getByPlaceholder('Paste bfprofile1...').fill(profileText);
  await page.getByLabel('Decryption Password').fill(password);
  await page.getByRole('button', { name: 'Inspect Profile' }).click();
  await expect(page.getByText('Review Loaded Profile')).toBeVisible();
  await page.getByRole('button', { name: 'Accept and Load Device' }).click();
}


export async function onboardPwaDevice(
  page: Page,
  input: {
    onboardPackage: string;
    packagePassword: string;
    label: string;
    localPassword: string;
  },
) {
  await page.goto('/');
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeEntryOnboard).click();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardPackageInput).fill(input.onboardPackage);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardPasswordInput).fill(input.packagePassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardConnectSubmit).click();
  // The onboard handshake negotiates with the inviter over the relay, which can
  // take well over the default expect timeout.
  await expect(page.getByText('Onboarding Complete')).toBeVisible({ timeout: 60_000 });
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardSaveName).fill(input.label);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardSavePassword).fill(input.localPassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardSaveConfirm).fill(input.localPassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.onboardSaveSubmit).click();
}

export async function prepareDistributionPackage(card: Locator, password: string, label?: string) {
  if (label !== undefined) {
    await card.getByLabel('Share label').fill(label);
  }
  await card.getByLabel('Package password').fill(password);
  await card.getByRole('button', { name: 'Create Package' }).click();
}

export async function markDistributionCardDistributed(card: Locator) {
  await card.getByRole('button', { name: 'Mark Delivered' }).click();
}

export async function completeDistributionCard(card: Locator, password: string, label?: string) {
  await prepareDistributionPackage(card, password, label);
  await markDistributionCardDistributed(card);
}

export async function loadStoredPwaProfile(page: Page, label: string) {
  await page.goto('/');
  const profileRow = page.locator('.igloo-welcome-profile-row').filter({ hasText: label }).first();
  await expect(profileRow).toBeVisible();
  await profileRow.getByRole('button', { name: 'Unlock' }).click();
  await page.getByLabel('Profile Password').fill(DEFAULT_BROWSER_PASSWORD);
  await page.getByRole('button', { name: 'Unlock' }).click();
}

export async function openPwaRotateShare(page: Page) {
  await page.getByRole('tab', { name: /Settings\s+operator controls/i }).click();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.maintenanceRotateShare).click();
}

export async function connectPwaRotationPackage(
  page: Page,
  input: { packageText: string; packagePassword: string },
) {
  await openPwaRotateShare(page);
  await page.getByPlaceholder('Paste bfonboard1...').fill(input.packageText);
  await page.getByLabel('Package Password').fill(input.packagePassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConnectSubmit).click();
}

export async function confirmPwaRotationPackage(page: Page) {
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConfirmSubmit).click();
}

export async function expectPwaDashboard(page: Page, profileLabel?: string) {
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardRoot)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabSigner)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabPermissions)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabSettings)).toBeVisible();
  if (profileLabel) {
    await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardRoot)).toContainText(profileLabel);
  }
}

export async function openFreshPwaPage(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  // Explicit empty storage state: a second device must start from a clean
  // entry-hero (no profiles), independent of any state seeded into the primary
  // context or any future global storageState default.
  const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  return { context, page };
}
