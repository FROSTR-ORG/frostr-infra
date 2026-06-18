import { expect, test, type Page } from '@playwright/test';

import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';
import { captureVisual } from '../../shared/visual-harness';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';
import {
  DETERMINISTIC_GROUP_KEY,
  DETERMINISTIC_SHARE_KEY,
  npubDisplay,
} from '../support/deterministic-keys';

const capture = (page: Page, name: string) =>
  captureVisual(page, { client: 'igloo-pwa', section: 'dashboard', name });

// A seeded stored profile carrying the deterministic keys, so the merged
// identity/runtime card renders byte-stable npub displays.
function buildDashboardProfile(): PwaStoredProfileSeed {
  const groupPackageJson = JSON.stringify({
    group_name: 'My Signing Key',
    group_pk: DETERMINISTIC_GROUP_KEY.pubHex,
    threshold: 2,
    members: [
      { idx: 0, pubkey: '02'.repeat(32) },
      { idx: 1, pubkey: DETERMINISTIC_SHARE_KEY.pubHex },
      { idx: 2, pubkey: '04'.repeat(32) },
    ],
  });
  return {
    id: 'dashboard-visual-profile',
    label: 'My Signing Key',
    share_public_key: DETERMINISTIC_SHARE_KEY.pubHex,
    group_public_key: DETERMINISTIC_GROUP_KEY.pubHex,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
    group_package_json: groupPackageJson,
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
    source: 'generated',
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'group-ref',
    encrypted_profile_ref: 'enc-ref',
    state_path: 'state-path',
    created_at: 1_700_000_000_000,
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

test.describe('igloo-pwa Paper Dashboard visual harness @visual', () => {
  // The runtime snapshot is in-memory only (never persisted), so a storage-seeded
  // dashboard renders the Paper "stopped" layout: the merged identity/status card
  // plus the Readiness + Next Step cards. Capturing the running layout (peers /
  // approvals / event log) needs a runtime-injection seam (tracked follow-up).
  test('captures the stopped signer dashboard with the merged identity card', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildDashboardProfile();
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
      }),
    );

    const dashboard = pages(page).dashboard;
    // Header nav: Dashboard active (pill), Permissions, Settings.
    await dashboard.expectNavLinks();
    // Merged status card: both keys shown as deterministic npub displays, split copy present.
    await dashboard.expectKeyDisplays(
      npubDisplay(DETERMINISTIC_GROUP_KEY.npub),
      npubDisplay(DETERMINISTIC_SHARE_KEY.npub),
    );
    await dashboard.expectKeyCopyControls();
    // Stopped state: Readiness + Next Step cards.
    await dashboard.expectStopped();

    await capture(page, '01-signer-dashboard.png');
  });
});
