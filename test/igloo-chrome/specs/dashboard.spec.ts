import { test, expect, TEST_PEER_PUBLIC_KEY, TEST_PUBLIC_KEY } from '../fixtures/extension';

import { loadSelectedChromeStoredProfile, unlockChromeStoredProfile } from '../support/ui';

test.describe('extension dashboard smoke', () => {
  test('renders onboarding flow on a fresh profile', async ({
    openExtensionPage,
    clearExtensionStorage
  }) => {
    await clearExtensionStorage();

    const page = await openExtensionPage('options.html');

    // No stored profiles → WelcomeEntryHero + Onboard Device form shown by default
    await expect(page.getByRole('heading', { name: 'Onboard New Device' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    await expect(page.getByPlaceholder('bfonboard1...')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Connect' })).toBeDisabled();
    await page.close();
  });

  test('popup shows configured profile status', async ({
    openExtensionPage,
    seedProfile
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });

    const popup = await openExtensionPage('popup.html');

    await expect(popup.getByText('Playwright Smoke')).toBeVisible();
    await expect(popup.getByText('cold')).toBeVisible();
    await expect(popup.getByText(TEST_PUBLIC_KEY)).toBeVisible();
    await popup.close();
  });

  test('configured options page exposes signer, permissions, and settings tabs', async ({
    openExtensionPage,
    seedProfile
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });

    const page = await openExtensionPage('options.html');

    await expect(page.getByRole('tab', { name: /Signer/i }).first()).toBeVisible();
    await expect(page.getByRole('tab', { name: /Permissions/i }).first()).toBeVisible();
    await expect(page.getByRole('tab', { name: /Settings/i }).first()).toBeVisible();

    await expect(page.getByText('Share Public Key')).toBeVisible();
    await expect(page.getByText('Group Public Key')).toBeVisible();
    // Cold seeded profile → the Paper-restructured signer panel renders the
    // stopped Readiness / Next-Step cards, not a live "Pending Operations"
    // section (that section only exists once the runtime is running). Assert the
    // stopped-state controls that prove the signer console rendered.
    await expect(page.getByRole('button', { name: 'Start Signer' })).toBeVisible();
    await expect(page.getByText('Start signer to restore connectivity.')).toBeVisible();

    await page.getByRole('tab', { name: /Permissions/i }).first().click();
    await expect(page.getByRole('heading', { name: 'Site Policies' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Peer Policies' })).toBeVisible();

    await page.getByRole('tab', { name: /Settings/i }).first().click();
    // Paper's OperatorSettingsPanel has no top-level "Settings" heading; it leads
    // with the "Device Profile" card and renders the maintenance actions as
    // labeled section cards (Export Profile / Export Share / Logout).
    await expect(page.getByRole('heading', { name: 'Device Profile' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Export Profile' })).toBeVisible();

    await page.close();
  });

  test('signer tab surfaces live nonce pool diagnostics @live', async ({
    activateProfile,
    openExtensionPage,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner,
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);

    const page = await openExtensionPage('options.html');

    // Live runtime is running → the panel renders the live sections, whose titles
    // are section-title spans (Paper restructure), not headings.
    await expect(
      page.locator('.igloo-dashboard-section-title', { hasText: 'Pending Operations' }),
    ).toBeVisible();
    await expect(page.getByText('Share Public Key')).toBeVisible();
    await expect(page.getByText('Group Public Key')).toBeVisible();
    // The Peers diagnostics panel renders the peer's full hex pubkey (not a
    // truncated/npub form), so assert the value verbatim.
    await expect(page.getByText(stableLiveSigner.profile.peerPubkey)).toBeVisible();
    // Nonce-pool diagnostics: the Peers header shows the aggregate "~N ready"
    // capacity and each peer a SIGN capability chip (Paper restructure replaced
    // the old "sign-ready" label).
    await expect(page.locator('.igloo-dashboard-count.is-ready')).toBeVisible();
    await expect(page.getByLabel('SIGN capable').first()).toBeVisible();

    await page.close();
  });

  test('permissions page lists stored site policies and shows live peer policy as unavailable while cold', async ({
    openExtensionPage,
    seedPermissionPolicies,
    seedProfile,
    server
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });
    await seedPermissionPolicies([
      {
        host: new URL(server.origin).host,
        type: 'nostr.getPublicKey',
        allow: true,
        createdAt: Date.UTC(2026, 2, 6, 12, 0, 0)
      }
    ]);

    const page = await openExtensionPage('options.html');
    await page.getByRole('tab', { name: /Permissions/i }).first().click();

    await expect(page.getByText(new URL(server.origin).host)).toBeVisible();
    await expect(page.getByText('Method: getPublicKey • all kinds')).toBeVisible();
    await expect(page.getByText('Start the signer to inspect and edit live peer policy state.')).toBeVisible();

    await page.getByRole('button', { name: 'Revoke' }).click();
    await expect(page.getByText('No website permissions have been granted yet.')).toBeVisible();
    await expect(page.getByText('Start the signer to inspect and edit live peer policy state.')).toBeVisible();

    await page.close();
  });

  test('settings page exposes the unified actions and no wipe/reset control', async ({
    openExtensionPage,
    seedPermissionPolicies,
    seedProfile,
    server
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });
    await seedPermissionPolicies([
      {
        host: new URL(server.origin).host,
        type: 'nostr.getPublicKey',
        allow: true
      }
    ]);

    const page = await openExtensionPage('options.html');

    await page.getByRole('tab', { name: /Permissions/i }).first().click();
    await expect(page.getByText(new URL(server.origin).host)).toBeVisible();
    await expect(page.getByText('Start the signer to inspect and edit live peer policy state.')).toBeVisible();

    await page.getByRole('tab', { name: /Settings/i }).first().click();
    await expect(page.getByRole('button', { name: 'Export Profile' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Export Share' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'rotate share' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Logout' })).toBeVisible();
    await expect(page.getByRole('button', { name: /wipe all data/i })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /reset/i })).toHaveCount(0);

    await page.close();
  });

  test('stored profiles relock after session clear and require unlock again', async ({
    clearSessionUnlocks,
    openExtensionPage,
    seedProfile
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });
    await clearSessionUnlocks();

    const page = await openExtensionPage('options.html');
    // Stored profiles → WelcomeReturningHero with profile rows
    const hero = page.locator('[aria-labelledby="igloo-welcome-returning-title"]').first();
    await expect(hero).toBeVisible();
    await expect(hero.getByRole('heading', { name: /Playwright Smoke/ })).toBeVisible();
    await expect(hero.getByRole('button', { name: 'Unlock' }).first()).toBeVisible();

    await loadSelectedChromeStoredProfile(page);
    await unlockChromeStoredProfile(page, 'wrongpass');
    await expect(page.getByText('Invalid profile password.')).toBeVisible();

    await unlockChromeStoredProfile(page, 'playwright-passphrase');
    await expect(page.getByRole('tab', { name: /Signer/i }).first()).toBeVisible();

    await page.close();
  });

  test('logout keeps stored profiles but clears the active unlocked session', async ({
    openExtensionPage,
    seedProfile
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });

    const page = await openExtensionPage('options.html');

    await expect(page.getByRole('tab', { name: /Settings/i }).first()).toBeVisible();
    await page.getByRole('tab', { name: /Settings/i }).first().click();
    await page.getByRole('button', { name: 'Logout' }).click();

    // After logout, WelcomeReturningHero shows with the stored profile
    const hero = page.locator('[aria-labelledby="igloo-welcome-returning-title"]').first();
    await expect(hero).toBeVisible();
    await expect(hero.getByRole('heading', { name: /Playwright Smoke/ })).toBeVisible();
    await expect(hero.getByRole('button', { name: 'Unlock' }).first()).toBeVisible();
    // Secondary action to onboard another device is still accessible
    await expect(hero.getByRole('button', { name: 'Onboard New Device' })).toBeVisible();

    await page.close();
  });

  test('provider approvals are surfaced in the permissions dashboard', async ({
    context,
    openExtensionPage,
    seedProfile,
    server
  }) => {
    await seedProfile({ publicKey: TEST_PUBLIC_KEY });

    const providerPage = await context.newPage();
    await providerPage.goto(`${server.origin}/provider`);

    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = providerPage.evaluate(() => window.nostr!.getRelays());

    const prompt = await promptPromise;
    await prompt.waitForLoadState('domcontentloaded');
    await prompt
      .getByRole('button', { name: 'Always allow this method' })
      .evaluate((button: HTMLButtonElement) => button.click())
      .catch(() => {
        // The background closes the prompt as part of successful approval.
      });

    await expect(resultPromise).resolves.toEqual({
      'ws://127.0.0.1:8194': {
        read: true,
        write: true
      }
    });

    const page = await openExtensionPage('options.html');
    await page.getByRole('tab', { name: /Permissions/i }).first().click();
    await expect(page.getByText(new URL(server.origin).host)).toBeVisible();
    await expect(page.getByText('Method: getRelays • all kinds')).toBeVisible();
    await expect(page.locator('span').filter({ hasText: /^allow$/ })).toHaveCount(1);

    await providerPage.close();
    await page.close();
  });

});
