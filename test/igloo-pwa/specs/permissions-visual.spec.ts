import { expect, test, type Page } from '@playwright/test';

import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';
import { DETERMINISTIC_GROUP_KEY, DETERMINISTIC_SHARE_KEY } from '../support/deterministic-keys';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

function buildPermissionsProfile() {
  return {
    id: 'permissions-visual-profile',
    label: 'My Signing Key',
    share_public_key: DETERMINISTIC_SHARE_KEY.pubHex,
    group_public_key: DETERMINISTIC_GROUP_KEY.pubHex,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
    group_package_json: JSON.stringify({
      group_name: 'My Signing Key',
      group_pk: DETERMINISTIC_GROUP_KEY.pubHex,
      threshold: 2,
      members: [{ idx: 1, pubkey: DETERMINISTIC_SHARE_KEY.pubHex }],
    }),
    share_package_json: JSON.stringify({ idx: 1, seckey: DETERMINISTIC_SHARE_KEY.secretHex }),
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
    source: 'generated' as const,
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'group-ref',
    encrypted_profile_ref: 'enc-ref',
    state_path: 'state-path',
    created_at: 1_700_000_000_000,
    stored_password: 'paper-permissions-pass',
    profile_string: 'bfprofile1paperperms',
    share_string: 'bfshare1paperperms',
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted' as const,
    },
    manual_peer_policy_overrides: [] as [],
    peer_pubkey: null,
    runtime_snapshot_json: null,
    onboarding_package: null,
  };
}

function buildRunningSnapshot() {
  return {
    active: true,
    readiness: { runtime_ready: true, restore_complete: true, sign_ready: true, ecdh_ready: true, threshold: 2 },
    runtime_status: { metadata: { peers: ['02'.repeat(32), '04'.repeat(32)] } },
    runtime_log_lines: [],
  };
}

function peerState(pubkey: string) {
  const all = { ping: true, onboard: true, sign: true, ecdh: true };
  const unset = { ping: 'unset', onboard: 'unset', sign: 'unset', ecdh: 'unset' } as const;
  return {
    pubkey,
    manual_override: { request: { ...unset }, respond: { ...unset } },
    remote_observation: null,
    effective_policy: { request: { ...all }, respond: { ...all } },
  };
}

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}


test.describe('igloo-pwa Paper Permissions visual harness @visual', () => {
  test('captures the peer-only permissions page', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildPermissionsProfile();
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'permissions',
        runtimeSnapshot: buildRunningSnapshot(),
        peerPermissionStates: [peerState('02'.repeat(32)), peerState('04'.repeat(32))],
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    // PWA Permissions is peer-only: Peer Permissions renders; the chrome-only
    // website/origin "Signer Permissions" section must not appear.
    await dashboard.expectPeerPermissions();
    await dashboard.expectNoSignerPermissions();

    await capture(page, '02-permissions.png');
  });
});
