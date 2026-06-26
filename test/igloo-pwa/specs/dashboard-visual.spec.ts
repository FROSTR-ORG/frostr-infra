import { mkdir } from 'node:fs/promises';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';
import { nip19 } from 'nostr-tools';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { pages } from '../support/pages';
import { applyPwaSeed, buildPwaPersistedState, pwaSeedPayload } from '../support/state';
import {
  DETERMINISTIC_SHARE_KEY,
  npubDisplay,
} from '../support/deterministic-keys';

const DASHBOARD_CAPTURE_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'visual', 'igloo-pwa', 'dashboard');
const PAPER_GROUP_KEY_HEX = `${'03'.repeat(29)}7a7b7c`;
const PAPER_LOCAL_SHARE_KEY_HEX = `02d7e1b9f3${'0'.repeat(48)}3b9e7d`;
const PAPER_REMOTE_PEER_KEYS = [
  `02a3f8c2d1${'0'.repeat(48)}8f2c4a`,
  `029c4a8e2f${'0'.repeat(48)}6a1f5e`,
];
const PAPER_EVENT_BASE_TS = 1_699_994_055;

function paperNpubDisplay(pubkey: string) {
  return npubDisplay(nip19.npubEncode(pubkey));
}

// A seeded stored profile carrying the deterministic keys, so the merged
// identity/runtime card renders byte-stable npub displays.
function buildDashboardProfile() {
  const groupPackageJson = JSON.stringify({
    group_name: 'My Signing Key',
    group_pk: PAPER_GROUP_KEY_HEX,
    threshold: 2,
    members: [
      { idx: 0, pubkey: PAPER_REMOTE_PEER_KEYS[0] },
      { idx: 1, pubkey: PAPER_LOCAL_SHARE_KEY_HEX },
      { idx: 2, pubkey: PAPER_REMOTE_PEER_KEYS[1] },
    ],
  });
  return {
    id: 'dashboard-visual-profile',
    label: 'My Signing Key',
    share_public_key: PAPER_LOCAL_SHARE_KEY_HEX,
    group_public_key: PAPER_GROUP_KEY_HEX,
    relays: ['wss://relay.primal.net', 'wss://relay.damus.io'],
    group_package_json: groupPackageJson,
    share_package_json: JSON.stringify({ idx: 1, seckey: DETERMINISTIC_SHARE_KEY.secretHex }),
    encrypted_bfshare_artifact: 'bfshare1seed',
    member_idx: 1,
    source: 'generated' as const,
    relay_profile: 'wss://relay.primal.net',
    group_ref: 'group-ref',
    encrypted_profile_ref: 'enc-ref',
    state_path: 'state-path',
    created_at: 1_700_000_000_000,
    stored_password: 'paper-dashboard-pass',
    profile_string: 'bfprofile1paperdashboard',
    share_string: 'bfshare1paperdashboard',
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

function peerState(
  pubkey: string,
  policy: Partial<Record<'sign' | 'ecdh' | 'ping' | 'onboard', boolean>> = {},
) {
  const all = { ping: false, onboard: false, sign: true, ecdh: true, ...policy };
  const unset = { ping: 'unset', onboard: 'unset', sign: 'unset', ecdh: 'unset' } as const;
  return {
    pubkey,
    manual_override: { request: { ...unset }, respond: { ...unset } },
    remote_observation: null,
    effective_policy: { request: { ...all }, respond: { ...all } },
  };
}

// A running runtime snapshot so the merged card shows "Signer Running".
function buildRunningSnapshot(peerPermissionStates: ReturnType<typeof peerState>[]) {
  const localPeerPolicy = peerState(PAPER_LOCAL_SHARE_KEY_HEX, { ecdh: false, ping: true });
  return {
    active: true,
    readiness: {
      runtime_ready: true,
      restore_complete: true,
      sign_ready: true,
      ecdh_ready: true,
      threshold: 2,
    },
    runtime_status: {
      metadata: { peers: peerPermissionStates.map((peer) => peer.pubkey) },
      peer_permission_states: [
        peerPermissionStates[0],
        localPeerPolicy,
        peerPermissionStates[1],
      ].filter(Boolean),
      peers: [
        {
          idx: 0,
          pubkey: peerPermissionStates[0]?.pubkey ?? '02'.repeat(32),
          known: true,
          online: true,
          can_sign: true,
          last_seen: 1_700_000_000,
          incoming_available: 93,
          outgoing_available: 78,
          outgoing_spent: 7,
          latency_ms: 24,
          should_send_nonces: true,
        },
        {
          idx: 1,
          pubkey: PAPER_LOCAL_SHARE_KEY_HEX,
          known: true,
          online: true,
          can_sign: true,
          last_seen: 1_700_000_038,
          incoming_available: 18,
          outgoing_available: 12,
          outgoing_spent: 8,
          latency_ms: 38,
          should_send_nonces: true,
        },
        {
          idx: 2,
          pubkey: peerPermissionStates[1]?.pubkey ?? '04'.repeat(32),
          known: false,
          online: false,
          can_sign: false,
          last_seen: 1_700_000_024,
          incoming_available: 0,
          outgoing_available: 0,
          outgoing_spent: 0,
          should_send_nonces: false,
        },
      ],
      pending_operations: [
        {
          request_id: 'pending-sign-peer-2',
          op_type: 'sign',
          threshold: 2,
          started_at: 1_700_000_115,
          timeout_at: 1_700_000_157,
          collected_responses: [],
          target_peers: [peerPermissionStates[1]?.pubkey ?? '04'.repeat(32)],
          context: {
            method_label: 'SIGN',
            peer_label: 'Peer #2',
            detail_label: 'kind:1 Short Text Note',
          },
        },
        {
          request_id: 'pending-ecdh-peer-1',
          op_type: 'ecdh',
          threshold: 2,
          started_at: 1_700_000_112,
          timeout_at: 1_700_000_184,
          collected_responses: [],
          target_peers: [PAPER_LOCAL_SHARE_KEY_HEX],
          context: {
            method_label: 'ECDH',
            peer_label: 'Peer #1',
            detail_label: 'NIP-44 key exchange',
          },
        },
        {
          request_id: 'pending-sign-peer-0',
          op_type: 'sign',
          threshold: 2,
          started_at: 1_700_000_110,
          timeout_at: 1_700_000_295,
          collected_responses: [{}],
          target_peers: [peerPermissionStates[0]?.pubkey ?? '02'.repeat(32)],
          context: {
            method_label: 'SIGN',
            peer_label: 'Peer #0',
            detail_label: 'kind:4 Encrypted DM',
          },
        },
      ],
    },
    events: [
      {
        ts: PAPER_EVENT_BASE_TS,
        level: 'info',
        component: 'pwa',
        domain: 'sync',
        event: 'pool_sync',
        message: 'Pool sync with peer #0 — 50 received · 50 sent',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 3,
        level: 'info',
        component: 'pwa',
        domain: 'sign',
        event: 'sign_request',
        message: 'Signature request received from 02a3f8...8f2c',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 3,
        level: 'info',
        component: 'pwa',
        domain: 'sign',
        event: 'partial_signature',
        message: 'Partial signature sent — aggregation complete',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 27,
        level: 'info',
        component: 'pwa',
        domain: 'ecdh',
        event: 'ecdh_request',
        message: 'ECDH request processed for 02d7e1...3b9e',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 30,
        level: 'warn',
        component: 'pwa',
        domain: 'signer policy',
        event: 'policy_required',
        message: 'ECDH request from peer #2 — signer policy required',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 134,
        level: 'info',
        component: 'pwa',
        domain: 'ping',
        event: 'ping_sweep',
        message: 'Ping sweep — 2/3 online (avg 31ms) · pools balanced',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 150,
        level: 'info',
        component: 'pwa',
        domain: 'echo',
        event: 'presence_published',
        message: 'Echo published — announced presence on 2 relays',
      },
      {
        ts: PAPER_EVENT_BASE_TS - 155,
        level: 'info',
        component: 'pwa',
        domain: 'sync',
        event: 'pool_refresh',
        message: 'Pool refresh queued — next health check in 30s',
      },
    ],
    runtime_log_lines: [],
  };
}

function buildStoppedSnapshot(peerPermissionStates: ReturnType<typeof peerState>[]) {
  return {
    active: false,
    readiness: {
      runtime_ready: false,
      restore_complete: false,
      sign_ready: false,
      ecdh_ready: false,
      threshold: 2,
    },
    runtime_status: {
      metadata: { peers: peerPermissionStates.map((peer) => peer.pubkey) },
      peer_permission_states: peerPermissionStates,
      peers: [],
      pending_operations: [],
    },
    events: [],
    runtime_log_lines: [],
  };
}

function buildAllRelaysOfflineSnapshot(peerPermissionStates: ReturnType<typeof peerState>[]) {
  return {
    active: true,
    readiness: {
      runtime_ready: true,
      restore_complete: false,
      sign_ready: false,
      ecdh_ready: false,
      threshold: 2,
      signing_peer_count: 0,
      ecdh_peer_count: 0,
      degraded_reasons: ['No connected relays available (wss://relay.primal.net; wss://relay.damus.io)'],
    },
    runtime_status: {
      metadata: { peers: peerPermissionStates.map((peer) => peer.pubkey) },
      peer_permission_states: peerPermissionStates,
      peers: [],
      pending_operations: [],
    },
    events: [],
    runtime_log_lines: [],
  };
}

function buildSigningBlockedSnapshot(peerPermissionStates: ReturnType<typeof peerState>[]) {
  return {
    active: true,
    readiness: {
      runtime_ready: true,
      restore_complete: true,
      sign_ready: false,
      ecdh_ready: true,
      threshold: 2,
      signing_peer_count: 1,
      ecdh_peer_count: 2,
      degraded_reasons: ['insufficient_signing_peers'],
    },
    runtime_status: {
      metadata: { peers: peerPermissionStates.map((peer) => peer.pubkey) },
      peer_permission_states: peerPermissionStates,
      peers: [],
      pending_operations: [],
    },
    events: [],
    runtime_log_lines: [],
  };
}

function buildSigningFailedSnapshot(peerPermissionStates: ReturnType<typeof peerState>[]) {
  const runningSnapshot = buildRunningSnapshot(peerPermissionStates);
  return {
    ...runningSnapshot,
    events: [
      ...runningSnapshot.events,
      {
        ts: 1_700_000_007_000,
        level: 'warn',
        component: 'runtime',
        domain: 'runtime',
        event: 'failure',
        op_type: 'sign',
        request_id: 'r-0x4f2a',
        event_kind: 1,
        retry_attempts: 3,
        peers_responded: 1,
        peers_required: 2,
        message: 'insufficient partial signatures',
      },
    ],
  };
}

async function seedState(page: Page, state: unknown) {
  await page.goto('/');
  await page.evaluate(applyPwaSeed, pwaSeedPayload(state));
  await page.reload();
}

async function injectDashboardVisualState(page: Page, state: unknown) {
  await page.addInitScript((visualState) => {
    (window as unknown as { __IGLOO_TEST_PERMISSION_STATE__?: unknown }).__IGLOO_TEST_PERMISSION_STATE__ =
      visualState;
  }, state);
}

async function capture(page: Page, fileName: string) {
  await mkdir(DASHBOARD_CAPTURE_DIR, { recursive: true });
  await page.screenshot({ path: path.join(DASHBOARD_CAPTURE_DIR, fileName), fullPage: true });
}

test.describe('igloo-pwa Paper Dashboard visual harness @visual', () => {
  test('captures the signer dashboard with the merged identity card', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1080 });

    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildRunningSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    const dashboard = pages(page).dashboard;
    // Header nav: Dashboard active (pill), Permissions routed, Settings opens the Paper sidebar.
    await dashboard.expectNavLinks();
    // Merged card: group key shown with split copy; share public key hidden.
    await dashboard.expectKeyDisplays(
      paperNpubDisplay(PAPER_GROUP_KEY_HEX),
      paperNpubDisplay(PAPER_LOCAL_SHARE_KEY_HEX),
    );
    await dashboard.expectKeyCopyControls();
    await dashboard.expectPeerSummary('~186 ready', 'Avg: 31ms');
    // Pending Approvals shell mirrors the Paper signer dashboard rows.
    await dashboard.expectPendingApprovals(3);
    await dashboard.expectEventLogSummary('8 events', '4 types');

    await capture(page, '01-signer-dashboard.png');
  });

  test('captures the stopped signer dashboard state', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 571 });

    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildStoppedSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.expectNoRuntimeRecoverAction();
    await dashboard.expectKeyDisplays(
      paperNpubDisplay(PAPER_GROUP_KEY_HEX),
      paperNpubDisplay(PAPER_LOCAL_SHARE_KEY_HEX),
    );
    await dashboard.expectKeyCopyControls();
    await dashboard.expectStoppedSignerDashboard();

    await capture(page, '01b-stopped-dashboard.png');
  });

  test('captures the all-relays-offline dashboard state', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 533 });

    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildAllRelaysOfflineSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.expectNoRuntimeRecoverAction();
    await dashboard.expectKeyDisplays(
      paperNpubDisplay(PAPER_GROUP_KEY_HEX),
      paperNpubDisplay(PAPER_LOCAL_SHARE_KEY_HEX),
    );
    await dashboard.expectKeyCopyControls();
    await dashboard.expectAllRelaysOfflineDashboard();

    await capture(page, '01c-all-relays-offline.png');
  });

  test('captures the signing-blocked dashboard state', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 569 });

    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildSigningBlockedSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.expectNoRuntimeRecoverAction();
    await dashboard.expectKeyDisplays(
      paperNpubDisplay(PAPER_GROUP_KEY_HEX),
      paperNpubDisplay(PAPER_LOCAL_SHARE_KEY_HEX),
    );
    await dashboard.expectKeyCopyControls();
    await dashboard.expectSigningBlockedDashboard();

    await capture(page, '01d-signing-blocked.png');
  });

  test('captures the signing-failed dashboard modal', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1284 });

    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildSigningFailedSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    const dashboard = pages(page).dashboard;
    await dashboard.expectNavLinks();
    await dashboard.expectKeyDisplays(
      paperNpubDisplay(PAPER_GROUP_KEY_HEX),
      paperNpubDisplay(PAPER_LOCAL_SHARE_KEY_HEX),
    );
    await dashboard.expectPeerSummary('~186 ready', 'Avg: 31ms');
    await dashboard.expectPendingApprovals(3);
    await dashboard.expectEventLogSummary('9 events', '4 types');
    await dashboard.expectSigningFailedModal();

    await capture(page, '06-signing-failed.png');
  });

  test('keeps the signer dashboard lane aligned with the header across breakpoints', async ({ page }) => {
    const profile = buildDashboardProfile();
    const peerPermissionStates = [
      peerState(PAPER_REMOTE_PEER_KEYS[0], { onboard: false }),
      peerState(PAPER_REMOTE_PEER_KEYS[1], { ecdh: false, ping: true }),
    ];
    const runtimeSnapshot = buildRunningSnapshot(peerPermissionStates);
    await injectDashboardVisualState(page, {
      runtimeSnapshot,
      peerPermissionStates,
    });
    await seedState(
      page,
      buildPwaPersistedState({
        profiles: [profile],
        selectedProfileId: profile.id,
        activeView: 'dashboard',
        activeDashboardTab: 'signer',
        runtimeSnapshot,
        peerPermissionStates,
      }),
    );

    for (const width of [1440, 1024, 768, 430, 375]) {
      await page.setViewportSize({ width, height: 900 });
      const metrics = await page.evaluate(() => {
        const header = document.querySelector('header > div')?.getBoundingClientRect();
        const dashboard = document.querySelector('[data-testid="dashboard-root"]')?.getBoundingClientRect();
        return {
          overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          header: header ? { x: header.x, width: header.width } : null,
          dashboard: dashboard ? { x: dashboard.x, width: dashboard.width } : null,
        };
      });

      expect(metrics.header, `header missing at ${width}px`).not.toBeNull();
      expect(metrics.dashboard, `dashboard missing at ${width}px`).not.toBeNull();
      expect(metrics.overflowX, `horizontal overflow at ${width}px`).toBe(0);
      expect(
        Math.abs((metrics.header?.x ?? 0) - (metrics.dashboard?.x ?? 0)),
        `header/dashboard x drift at ${width}px`,
      ).toBeLessThanOrEqual(1);
      expect(
        Math.abs((metrics.header?.width ?? 0) - (metrics.dashboard?.width ?? 0)),
        `header/dashboard width drift at ${width}px`,
      ).toBeLessThanOrEqual(1);
    }
  });
});
