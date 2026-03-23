import { expect, type Browser, type BrowserContext, type Page } from '@playwright/test';

import { PWA_STORAGE_KEY } from './state';

export async function seedPwaState(page: Page, state: unknown) {
  await page.addInitScript(
    ([storageKey, payload]: [string, unknown]) => {
      window.localStorage.setItem(storageKey, JSON.stringify(payload));
    },
    [PWA_STORAGE_KEY, state],
  );
}

export async function openPwaLoadProfile(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Load Profile' }).first().click();
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

export async function recoverPwaProfile(page: Page, shareText: string, password: string) {
  await openPwaLoadProfile(page);
  await page.getByRole('button', { name: 'Recover from Share' }).click();
  await page.getByPlaceholder('Paste bfshare1...').fill(shareText);
  await page.getByLabel('Decryption Password').fill(password);
  await page.getByRole('button', { name: 'Recover Profile' }).click();
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
  await page.getByRole('button', { name: 'Continue Onboarding' }).click();
  await page.getByPlaceholder('Paste bfonboard1...').fill(input.onboardPackage);
  await page.getByLabel('Decryption Password').fill(input.packagePassword);
  await page.getByRole('button', { name: 'Connect' }).click();
  await expect(page.getByText('Review Onboarded Profile')).toBeVisible();
  await page.getByLabel('Device Name').fill(input.label);
  await page.getByLabel('Password', { exact: true }).fill(input.localPassword);
  await page.getByLabel('Confirm Password').fill(input.localPassword);
  await page.getByRole('button', { name: 'Save Device' }).click();
}

export async function loadStoredPwaProfile(page: Page, label: string) {
  await page.goto('/');
  await expect(page.getByText('Stored Profiles')).toBeVisible();
  await page.locator('.igloo-flow-card').filter({ hasText: label }).getByRole('button', { name: 'Load Profile' }).click();
}

export async function expectPwaDashboard(page: Page, profileLabel?: string) {
  await expect(page.getByText('Device Dashboard')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Stop Signer' })).toBeVisible();
  if (profileLabel) {
    await expect(page.getByRole('heading', { name: new RegExp(profileLabel) })).toBeVisible();
  }
}

export async function openFreshPwaPage(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  return { context, page };
}
