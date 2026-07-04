import { expect, test } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { pages } from '../support/pages';
import { buildPwaPersistedState } from '../support/state';
import { seedPwaState } from '../support/ui';

function buildStoredProfile(): PwaStoredProfileSeed {
  const id = 'route-profile-1';
  const groupPublicKey = '55'.repeat(32);
  return {
    id,
    label: 'Route Check Key',
    share_public_key: '44'.repeat(32),
    group_public_key: groupPublicKey,
    relays: ['wss://relay.primal.net'],
    group_package_json: JSON.stringify({
      group_name: 'Route Check Key',
      group_pk: groupPublicKey,
      threshold: 2,
      members: [
        { idx: 0, pubkey: 'aa'.repeat(32) },
        { idx: 1, pubkey: 'bb'.repeat(32) },
        { idx: 2, pubkey: 'cc'.repeat(32) },
      ],
    }),
    encrypted_bfshare_artifact: 'bfshare1routecheck',
    member_idx: 0,
    source: 'generated',
    relay_profile: 'browser',
    group_ref: `browser-profile:${id}:group`,
    encrypted_profile_ref: `browser-profile:${id}:encrypted-profile`,
    state_path: `/tmp/igloo-pwa/${id}`,
    created_at: Date.UTC(2026, 6, 4),
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

function staleRotateDraft(profileId: string) {
  return {
    createForm: {
      mode: 'rotate',
      groupName: 'Stale Rotate Draft',
      threshold: '2',
      count: '3',
    },
    rotationForm: {
      sourceProfileId: profileId,
      sources: [{ packageText: 'bfshare1stale', password: 'stale-pass' }],
    },
  };
}

test.describe('igloo-pwa welcome routing @fast', () => {
  test('starts a new keyset from returning Welcome even when a rotate draft is persisted', async ({ page }) => {
    const profile = buildStoredProfile();
    await seedPwaState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        drafts: staleRotateDraft(profile.id),
      }),
    );

    const p = pages(page);
    await p.welcome.goto();
    await p.welcome.startGenerate();

    await expect(page.getByRole('heading', { name: 'Create Keyset' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Collect Shares' })).toBeHidden();
    await expect(page.getByLabel('Group Name')).toBeVisible();
  });

  test('keeps the explicit returning-profile Rotate action on the collect-shares route', async ({ page }) => {
    const profile = buildStoredProfile();
    await seedPwaState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
      }),
    );

    const p = pages(page);
    await p.welcome.goto();
    await p.welcome.rotate(profile.id);

    await expect(page.getByRole('heading', { name: 'Collect Shares' })).toBeVisible();
    await expect(page.getByText('Validate & Continue')).toBeVisible();
  });
});
