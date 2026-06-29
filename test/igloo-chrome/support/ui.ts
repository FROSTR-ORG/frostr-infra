import { expect, type Locator, type Page } from '@playwright/test';
import { CRITICAL_E2E_TEST_IDS } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';

/**
 * Returns the welcome returning-hero section that lists stored profiles.
 * This replaces the old StoredProfilesLandingCard anchor.
 */
export async function getChromeStoredProfilesCard(page: Page) {
  const hero = page
    .locator('[aria-labelledby="igloo-welcome-returning-title"]')
    .first();
  await expect(hero).toBeVisible();
  return hero;
}

export async function selectChromeStoredProfile(page: Page, label: string) {
  const hero = await getChromeStoredProfilesCard(page);
  return hero
    .locator(`[data-testid="${CRITICAL_E2E_TEST_IDS.welcomeProfileRow}"]`)
    .filter({ hasText: label })
    .first();
}

export async function getChromeStoredProfileRow(page: Page, profileId: string) {
  const hero = await getChromeStoredProfilesCard(page);
  return hero
    .locator(`[data-testid="${CRITICAL_E2E_TEST_IDS.welcomeProfileRow}"][data-profile-id="${profileId}"]`)
    .first();
}

/**
 * Clicks the "Unlock" button on the first profile row in the returning hero,
 * opening the WelcomeUnlockModal.
 */
export async function loadSelectedChromeStoredProfile(page: Page) {
  const hero = await getChromeStoredProfilesCard(page);
  await hero
    .getByTestId(CRITICAL_E2E_TEST_IDS.welcomeProfileUnlock)
    .first()
    .click();
}

/**
 * Fills the WelcomeUnlockModal password field and submits.
 */
export async function unlockChromeStoredProfile(page: Page, password: string) {
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeUnlockPassword)).toBeVisible();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeUnlockPassword).fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeUnlockSubmit).click();
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
