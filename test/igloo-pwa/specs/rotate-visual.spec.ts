import { expect, test, type Page } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'rotate', name });

function buildRotateProfile(): PwaStoredProfileSeed {
  const id = 'rotate-profile-1';
  const groupPublicKey = '44'.repeat(32);
  return {
    id,
    label: 'My Signing Key',
    share_public_key: '55'.repeat(32),
    group_public_key: groupPublicKey,
    relays: ['ws://127.0.0.1:4848'],
    group_package_json: JSON.stringify({
      group_name: 'My Signing Key',
      group_pk: groupPublicKey,
      threshold: 2,
      members: [
        { idx: 1, pubkey: '05'.repeat(32) },
        { idx: 2, pubkey: '06'.repeat(32) },
        { idx: 3, pubkey: '07'.repeat(32) },
      ],
    }),
    encrypted_bfshare_artifact: `bfshare1${id}`,
    member_idx: 2,
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

async function setPwaState(page: Page, profiles: PwaStoredProfileSeed[]) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(buildPwaPersistedState({ profiles })));
  await page.reload();
}

test.describe('igloo-pwa Paper Rotate visual harness @visual', () => {
  test('captures the rotate-keyset collect-shares step', async ({ page }) => {
    const profile = buildRotateProfile();
    await page.setViewportSize({ width: 1440, height: 1306 });

    await setPwaState(page, [profile]);
    await pages(page).welcome.rotate(profile.id);

    await expect(page.getByRole('heading', { name: 'Collect Shares' })).toBeVisible();
    await expect(page.getByText('This Device Share (#2)')).toBeVisible();
    await capture(page, '01-collect-shares.png');
  });
});
