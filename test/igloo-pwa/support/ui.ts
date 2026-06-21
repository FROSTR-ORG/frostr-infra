import { expect, type Browser, type BrowserContext, type Locator, type Page } from '@playwright/test';
import { CRITICAL_E2E_TEST_IDS, type CriticalE2ETestId } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';
import { DEFAULT_BROWSER_PASSWORD } from '../../shared/browser-artifacts';

import { applyPwaSeed, pwaSeedPayload } from './state';

// The e2e test-id registry must be imported only here (enforced by
// check-e2e-selector-contracts.sh). Page objects consume it via this re-export.
export { CRITICAL_E2E_TEST_IDS as TID } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';
export type { CriticalE2ETestId } from '../../../repos/igloo-ui/src/lib/e2e-test-ids';

export function byTestId(scope: Page | Locator, id: CriticalE2ETestId): Locator {
  return scope.getByTestId(id);
}

export async function seedPwaState(page: Page, state: unknown) {
  await page.addInitScript(applyPwaSeed, pwaSeedPayload(state));
}

export async function openPwaImportProfile(page: Page) {
  await page.goto('/');
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.welcomeEntryImport).click();
}

export async function importPwaProfile(page: Page, profileText: string, password: string) {
  // Welcome -> Import Device (paste + decrypt) -> Save Profile -> dashboard. The save
  // screen derives the device name from the package backup (lockIdentity), so we only
  // set a local profile password — reuse the package password for the test.
  await openPwaImportProfile(page);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importProfileInput).fill(profileText);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importPasswordInput).fill(password);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.importNext).click();
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

export async function loadStoredPwaProfile(page: Page, label: string, options?: { url?: string }) {
  // Defaults to the Playwright baseURL ('/'); cross-client specs that serve the
  // pwa dist on an ad-hoc origin pass that URL explicitly.
  await page.goto(options?.url ?? '/');
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
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabSettings).click();
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.maintenanceRotateShare).click();
}

export async function connectPwaRotationPackage(
  page: Page,
  input: { packageText: string; packagePassword: string },
) {
  await openPwaRotateShare(page);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationPackageInput).fill(input.packageText);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationPasswordInput).fill(input.packagePassword);
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConnectSubmit).click();
}

export async function confirmPwaRotationPackage(page: Page) {
  await page.getByTestId(CRITICAL_E2E_TEST_IDS.rotationConfirmSubmit).click();
}

// `_profileLabel` is accepted (callers still pass the expected device name for
// readability) but no longer asserted: post-Paper-redesign the pwa dashboard does
// not render the device label anywhere (the banner shows the generic app header;
// dashboard-root holds only the signer panel). The correct profile is already
// guaranteed by the load step — loadStoredPwaProfile selects the welcome row by
// label — so a dashboard-level label check is both impossible and redundant.
export async function expectPwaDashboard(page: Page, _profileLabel?: string) {
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardRoot)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabSigner)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabPermissions)).toBeVisible();
  await expect(page.getByTestId(CRITICAL_E2E_TEST_IDS.dashboardTabSettings)).toBeVisible();
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

// Tier-2 readiness gate, observed via the LIVE dashboard. The runtime snapshot is
// intentionally never persisted to localStorage (see igloo-pwa persist-allowlist),
// so readiness has to be read from the rendered signer panel. Post-Paper-redesign
// the panel no longer renders a literal "sign-ready" label per peer; sign-readiness
// now surfaces in the peers summary as a hydrated nonce pool ("N ready", N≥1)
// alongside at least one online peer, whereas the degraded/no-peer state shows
// "0 online … 0 ready" under a "Signing unavailable" banner. Gate on a nonzero
// ready count — the modern equivalent of "the nonce pool has hydrated and the
// signer can participate in a signature". Use this where a cooperating signer is
// online; for a single device with no peers use the lighter
// expectPwaRuntimeConnected. (The `expectedPeers` arg is advisory — a hydrated
// nonce pool is the meaningful, race-free signal.)
export async function expectPwaSignerSignReady(page: Page, _expectedPeers = 1): Promise<void> {
  await expect(page.getByText(/[1-9]\d*\s+ready\b/).first()).toBeVisible({ timeout: 45_000 });
}
