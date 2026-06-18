import { test, expect } from '@playwright/test';

import { startLocalRelay } from '../../shared/local-relay';
import { launchIglooHome } from '../fixtures/app';

// @live @smoke — the Chrome/PWA per-PR smoke gate runs in client-scoped CI; the
// desktop host needs tauri + webkit2gtk + xvfb, which only the nightly
// release-validation job provides, so this home smoke is wired there (the per-PR
// home lane stays render/typecheck-only by design after the lean-CI cut).
//
// One onboarding round-trip over an in-process relay (no Docker / external infra):
// a live inviter session invites a fresh recipient, the bfonboard handshake
// crosses the relay, and finalize persists a distinct second profile. Home has no
// sign-initiate test RPC (one active session at a time), so the completed
// handshake against a live signer is the achievable signing-round-trip proof —
// the same flow generated-onboarding-live exercises, trimmed to a tripwire and
// de-coupled from the Docker demo harness.
test.describe('igloo-home onboarding smoke @live @smoke', () => {
  test('completes a bfonboard handshake against a live inviter session', async () => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const relay = await startLocalRelay();
    const app = await launchIglooHome();
    try {
      const generated = await app.request<{
        group_package_json: string;
        shares: Array<{
          member_idx: number;
          share_public_key: string;
          share_package_json: string;
        }>;
      }>('create_generated_keyset', {
        group_name: 'Home Smoke Group',
        threshold: 2,
        count: 3,
      });

      const localShare = generated.shares[0];
      const remoteShare = generated.shares[1];

      // Inviter: import the local share and bring its signer session live on the relay.
      const imported = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Home Smoke Local Device',
        relay_urls: [relay.url],
        relay_profile: null,
        passphrase: 'playwright-password',
        group_package_json: generated.group_package_json,
        share_package_json: localShare.share_package_json,
      });
      expect(imported.status).toBe('profile_created');
      expect(imported.profile?.id).toBeTruthy();

      const session = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: imported.profile!.id,
        passphrase: 'playwright-password',
      });
      expect(session.active).toBe(true);

      // Recipient: mint an onboarding package for the remote share and complete the
      // handshake against the running inviter — the bfonboard exchange crosses the relay.
      const onboardPackage = await app.request<string>('create_generated_onboarding_package', {
        share_package_json: remoteShare.share_package_json,
        relay_urls: [relay.url],
        peer_pubkey: localShare.share_public_key,
        package_password: 'home-smoke-package-password',
      });
      expect(onboardPackage.startsWith('bfonboard1')).toBe(true);

      const connected = await app.request<{
        preview: { label: string; share_public_key: string };
      }>('connect_onboarding_package', {
        onboarding_password: 'home-smoke-package-password',
        package: onboardPackage,
      });
      expect(connected.preview.label).toBeTruthy();

      const onboarded = await app.request<{
        status: string;
        profile?: { id: string };
      }>('finalize_connected_onboarding', {
        label: 'Home Smoke Remote Device',
        relay_profile: null,
        passphrase: 'playwright-password',
      });
      expect(onboarded.status).toBe('profile_created');
      expect(onboarded.profile?.id).toBeTruthy();
      expect(onboarded.profile?.id).not.toBe(imported.profile?.id);
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await relay.close();
    }
  });
});
