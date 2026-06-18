import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

const RECOVER_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'recover');

function buildRecoverProfile(): PwaStoredProfileSeed {
  const id = 'recover-profile-1';
  const groupPublicKey = '22'.repeat(32);
  return {
    id,
    label: 'My Signing Key',
    share_public_key: '33'.repeat(32),
    group_public_key: groupPublicKey,
    relays: ['ws://127.0.0.1:4848'],
    group_package_json: JSON.stringify({
      group_name: 'My Signing Key',
      group_pk: groupPublicKey,
      threshold: 2,
      members: [
        { idx: 0, pubkey: '02'.repeat(32) },
        { idx: 1, pubkey: '03'.repeat(32) },
        { idx: 2, pubkey: '04'.repeat(32) },
      ],
    }),
    encrypted_bfshare_artifact: `bfshare1${id}`,
    member_idx: 0,
    source: 'generated',
    relay_profile: 'local',
    group_ref: `browser-profile:${id}:group`,
    encrypted_profile_ref: `browser-profile:${id}:encrypted-profile`,
    state_path: `/tmp/igloo-pwa/${id}`,
    created_at: Date.UTC(2026, 4, 21),
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted',
    },
    manual_peer_policy_overrides: [],
    peer_pubkey: null,
  };
}

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}

async function capture(page: Page, fileName: string) {
  await mkdir(RECOVER_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(RECOVER_CAPTURE_DIR, fileName), fullPage: true });
}

// The recover-key view is gated on App-local `recoveredKey` state (a reconstructed nsec
// that is never persisted). The app exposes a DEV-only window seam so the harness can
// render the success screen with a FAKE key without seeding any real secret.
const FAKE_RECOVERED_KEY = {
  nsec: 'nsec1qqqqqzpwk6m3ags7frv0j8dkwmxcf0klhfja3yd4rqlzgn64c4hq7y4ms9',
  signingKeyHex: '11'.repeat(32),
};

test.describe('igloo-pwa Paper Recover visual harness @visual', () => {
  test('captures the collect-shares recover step', async ({ page }) => {
    const profile = buildRecoverProfile();
    await page.setViewportSize({ width: 1440, height: 1080 });

    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'recover-collect',
        drafts: {
          recoverKeyForm: {
            sourceProfileId: profile.id,
            sources: [{ packageText: '', password: '' }],
          },
        },
      }),
    );
    await expect(page.getByRole('heading', { name: 'Collect Shares' })).toBeVisible();
    await capture(page, '01-collect-shares.png');
  });

  test('captures the recovered private key screen', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });
    // Inject the fake recovered key on every navigation (before app scripts run) so the
    // DEV-only seam can hydrate the recover-key view without seeding a real secret.
    await page.addInitScript((key) => {
      (window as unknown as { __IGLOO_TEST_RECOVERED_KEY__?: unknown }).__IGLOO_TEST_RECOVERED_KEY__ = key;
    }, FAKE_RECOVERED_KEY);
    await seedState(page, buildPwaPersistedState({ activeView: 'recover-key' }));
    await expect(page.getByRole('heading', { name: 'Recover Private Key' })).toBeVisible();
    await capture(page, '02-recover-success.png');
  });
});
