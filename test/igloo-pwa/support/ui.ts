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

export async function openPwaImportProfile(page: Page) {
  await page.goto('/');
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeEntryImport).click();
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
  // Welcome -> Import Device (connect) -> Review Device -> Save Profile -> dashboard.
  // The save screen derives the device name from the package (lockIdentity), so we
  // only set a local profile password — reuse the package password for the test.
  await openPwaImportProfile(page);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importProfileInput).fill(profileText);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importPasswordInput).fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importNext).click();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importAccept).click();
  const saveName = page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileName);
  await expect(saveName).toBeVisible({ timeout: 30_000 });
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfilePassword).fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileConfirm).fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileNext).click();
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
  // The onboard handshake negotiates nonces with the inviter over the relay (a few
  // ms locally, but allow ample margin for CI), then the PWA advances to the
  // "Save Profile" screen — which renders CreateFlowProfileSetup, so the form carries
  // the saveProfile* ids, not onboardSave*. A failed handshake instead shows the
  // "Onboarding Failed" panel; surface that fast rather than waiting out the timeout.
  const saveName = page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileName);
  const onboardFailed = page.getByText('Onboarding Failed');
  await expect(saveName.or(onboardFailed)).toBeVisible({ timeout: 30_000 });
  if (await onboardFailed.isVisible()) {
    throw new Error(
      'Onboarding failed: the recipient reached the "Onboarding Failed" panel (handshake did not complete).',
    );
  }
  // The onboard-save screen pre-fills a default device name but lets the recipient
  // name their own device (relays stay locked). Set the requested name explicitly.
  await saveName.fill(input.label);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfilePassword).fill(input.localPassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileConfirm).fill(input.localPassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.saveProfileNext).click();
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
  const profileRow = page
    .getByTestId(CRITICAL_E2E_TEST_IDS.welcomeProfileRow)
    .filter({ hasText: label })
    .first();
  await expect(profileRow).toBeVisible();
  // Use test-ids: the row "Unlock" trigger and the modal "Unlock" submit share the
  // same accessible name, so role-by-name is ambiguous once the modal opens.
  await profileRow.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeProfileUnlock).click();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeUnlockPassword).fill(DEFAULT_BROWSER_PASSWORD);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeUnlockSubmit).click();
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

export async function expectPwaRuntimeConnected(page: Page) {
  // The dashboard reports the live browser signer runtime once it has connected to
  // its relays; gate cross-device flows on this so a peer can't race an unsubscribed
  // inviter. (Deliberate copy assertion — the runtime-status line has no test-id.)
  await expect(page.getByText('Browser runtime connected')).toBeVisible({ timeout: 30_000 });
}

export async function openFreshPwaPage(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  // Explicit empty storage state: a second device must start from a clean
  // entry-hero (no profiles), independent of any state seeded into the primary
  // context or any future global storageState default.
  const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  return { context, page };
}
