import { test, expect } from '@playwright/test';

import { launchIglooHome } from '../fixtures/app';
import { ensureDemoHarness } from '../fixtures/harness';

test.describe('igloo-home generated onboarding', () => {
  test('creates a local share, distributes bfonboard, and imports the second device', async () => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const harness = await ensureDemoHarness();
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
        group_name: 'Generated Onboarding Group',
        threshold: 2,
        count: 3,
      });

      const localShare = generated.shares[0];
      const remoteShare = generated.shares[1];

      const imported = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Generated Local Device',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: generated.group_package_json,
        share_package_json: localShare.share_package_json,
      });
      expect(imported.status).toBe('profile_created');
      expect(imported.profile?.id).toBeTruthy();

      const snapshot = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: imported.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      expect(snapshot.active).toBe(true);

      const onboardPackage = await app.request<string>('create_generated_onboarding_package', {
        share_package_json: remoteShare.share_package_json,
        relay_urls: [harness.relayUrl],
        peer_pubkey: localShare.share_public_key,
        package_password: 'generated-package-password',
      });
      expect(onboardPackage.startsWith('bfonboard1')).toBe(true);

      const onboarded = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_onboarding', {
        label: 'Generated Remote Device',
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        onboarding_password: 'generated-package-password',
        package: onboardPackage,
      });

      expect(onboarded.status).toBe('profile_created');
      expect(onboarded.profile?.id).toBeTruthy();
      expect(onboarded.profile?.id).not.toBe(imported.profile?.id);
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await harness.cleanup();
    }
  });
});
