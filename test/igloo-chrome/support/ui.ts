import { expect, type Locator, type Page } from '@playwright/test';
import { CRITICAL_E2E_TEST_IDS } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';

export async function getChromeStoredProfilesCard(page: Page) {
  const storedProfilesCard = page
    .getByRole('heading', { name: 'Stored Profiles' })
    .locator('xpath=ancestor::div[contains(@class, "igloo-card")]')
    .first();
  await expect(storedProfilesCard).toBeVisible();
  return storedProfilesCard;
}

export async function selectChromeStoredProfile(page: Page, label: string) {
  const storedProfilesCard = await getChromeStoredProfilesCard(page);
  const selector = storedProfilesCard.locator('button[aria-pressed]').filter({ hasText: label }).first();
  await selector.click();
  return selector.locator(`xpath=ancestor::*[@data-testid="${CRITICAL_E2E_TEST_IDS.storedProfileEntry}"][1]`);
}

export async function loadSelectedChromeStoredProfile(page: Page) {
  const storedProfilesCard = await getChromeStoredProfilesCard(page);
  const selectedEntry = storedProfilesCard
    .locator('button[aria-pressed="true"]')
    .first()
    .locator(`xpath=ancestor::*[@data-testid="${CRITICAL_E2E_TEST_IDS.storedProfileEntry}"][1]`);
  await selectedEntry.getByTestId(CRITICAL_E2E_TEST_IDS.storedProfileLoad).click();
}

export async function unlockChromeStoredProfile(page: Page, password: string) {
  await expect(page.getByText('Unlock Stored Profile')).toBeVisible();
  await page.getByPlaceholder('Enter profile password').fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.storedProfileUnlockSubmit).click();
}

export function getChromeRotateShareCard(page: Page): Locator {
  return page
    .getByRole('heading', { name: 'rotate share' })
    .locator('xpath=ancestor::section[contains(@class, "rounded-lg")]')
    .first();
}

export async function connectChromeRotationPackage(
  page: Page,
  input: { packageText: string; packagePassword: string },
) {
  const rotateCard = getChromeRotateShareCard(page);
  await expect(rotateCard).toBeVisible();
  await rotateCard.getByPlaceholder('bfonboard1...').fill(input.packageText);
  await rotateCard.getByLabel('Package Password').fill(input.packagePassword);
  await rotateCard.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConnectSubmit).click();
  return rotateCard;
}

export async function confirmChromeRotationPackage(page: Page) {
  const rotateCard = getChromeRotateShareCard(page);
  await rotateCard.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConfirmSubmit).click();
  return rotateCard;
}

export function getChromeRotationConfirmButton(page: Page) {
  return getChromeRotateShareCard(page).getByTestId(CRITICAL_E2E_TEST_IDS.rotationConfirmSubmit);
}
