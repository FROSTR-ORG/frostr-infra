import { test, expect, TEST_PEER_PUBLIC_KEY, TEST_PUBLIC_KEY } from '../fixtures/extension';

const formatPeerPubkey = (value: string) => `${value.slice(0, 14)}...${value.slice(-8)}`;

test.describe('extension dashboard smoke', () => {
  test('renders onboarding flow on a fresh profile', async ({
    openExtensionPage,
    clearExtensionStorage
  }) => {
    await clearExtensionStorage();

    const page = await openExtensionPage('options.html');

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
    await expect(page.getByText('Pending Operations')).toBeVisible();

    await page.getByRole('tab', { name: /Permissions/i }).first().click();
    await expect(page.getByRole('heading', { name: 'Site Policies' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Peer Policies' })).toBeVisible();

    await page.getByRole('tab', { name: /Settings/i }).first().click();
    await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
    await expect(page.getByText('Maintenance')).toBeVisible();

    await page.close();
  });

  test('signer tab surfaces live nonce pool diagnostics @live', async ({
    activateProfile,
    callOffscreenRpc,
    openExtensionPage,
    onboardedLiveSignerProfile,
    seedProfile,
    stableLiveSigner,
  }) => {
    await seedProfile(onboardedLiveSignerProfile);
    await activateProfile(onboardedLiveSignerProfile.id!);

    const page = await openExtensionPage('options.html');

    await expect(page.getByRole('heading', { name: 'Pending Operations' })).toBeVisible();
    await expect(page.getByText('Share Public Key')).toBeVisible();
    await expect(page.getByText('Group Public Key')).toBeVisible();
    await expect(page.getByText(formatPeerPubkey(stableLiveSigner.profile.peerPubkey))).toBeVisible();
    await expect(page.getByText('sign-ready').first()).toBeVisible();

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

  test('settings page wipes stored state and resets the profile', async ({
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
    await page.getByRole('button', { name: 'Wipe All Data' }).click();
    await expect(page.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Connect' })).toBeVisible();

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

    await expect(page.getByText('Stored Profiles', { exact: true })).toBeVisible();
    await expect(page.getByText('Playwright Smoke')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Unlock' })).toBeVisible();

    await page.getByRole('button', { name: 'Unlock' }).click();
    await expect(page.getByText('Unlock Stored Profile')).toBeVisible();
    await page.getByPlaceholder('Enter profile password').fill('wrongpass');
    await page.getByRole('button', { name: 'Unlock Profile' }).click();
    await expect(page.getByText('Invalid profile password.')).toBeVisible();

    await page.getByPlaceholder('Enter profile password').fill('playwright-passphrase');
    await page.getByRole('button', { name: 'Unlock Profile' }).click();
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
    await page.getByRole('button', { name: 'Log Out' }).click();

    await expect(page.getByText('Stored Profiles', { exact: true })).toBeVisible();
    await expect(page.getByText('Playwright Smoke')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Unlock' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Onboard Device' })).toBeVisible();

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
