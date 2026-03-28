import { test, expect } from '@playwright/test';

import { launchIglooHome } from '../fixtures/app';
import { ensureDemoHarness } from '../fixtures/harness';

test.describe('igloo-home rotation update', () => {
  test('replaces an existing profile in place using a rotated bfonboard package', async () => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const harness = await ensureDemoHarness();
    const app = await launchIglooHome();
    try {
      const generated = await app.request<{
        group_package_json: string;
        group_public_key: string;
        shares: Array<{
          member_idx: number;
          share_public_key: string;
          share_package_json: string;
        }>;
      }>('create_generated_keyset', {
        group_name: 'Rotation Update Group',
        threshold: 2,
        count: 3,
      });

      const sourceA = generated.shares[0];
      const sourceB = generated.shares[1];

      const importedA = await app.request<{
        status: string;
        profile?: { id: string; label?: string };
      }>('import_profile_from_raw', {
        label: 'Rotation Target Device',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: generated.group_package_json,
        share_package_json: sourceA.share_package_json,
      });
      expect(importedA.status).toBe('profile_created');
      expect(importedA.profile?.id).toBeTruthy();

      const importedB = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Rotation Source B',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: generated.group_package_json,
        share_package_json: sourceB.share_package_json,
      });
      expect(importedB.status).toBe('profile_created');
      expect(importedB.profile?.id).toBeTruthy();

      await app.request('publish_profile_backup', {
        profile_id: importedA.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      await app.request('publish_profile_backup', {
        profile_id: importedB.profile!.id,
        vault_passphrase: 'playwright-password',
      });

      const exportedA = await app.request<{ package: string }>('export_profile_package', {
        profile_id: importedA.profile!.id,
        format: 'bfshare',
        package_password: 'rotation-source-a',
        vault_passphrase: 'playwright-password',
      });
      const exportedB = await app.request<{ package: string }>('export_profile_package', {
        profile_id: importedB.profile!.id,
        format: 'bfshare',
        package_password: 'rotation-source-b',
        vault_passphrase: 'playwright-password',
      });

      const rotated = await app.request<{
        source: string;
        group_public_key: string;
        group_package_json: string;
        shares: Array<{
          member_idx: number;
          share_public_key: string;
          share_package_json: string;
        }>;
      }>('create_rotated_keyset', {
        threshold: 2,
        count: 3,
        sources: [
          { package: exportedA.package, package_password: 'rotation-source-a' },
          { package: exportedB.package, package_password: 'rotation-source-b' },
        ],
      });

      expect(rotated.source).toBe('rotated');
      expect(rotated.group_public_key).toBe(generated.group_public_key);

      const rotatedInviter = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Rotated Inviter Device',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: rotated.group_package_json,
        share_package_json: rotated.shares[1].share_package_json,
      });
      expect(rotatedInviter.status).toBe('profile_created');
      expect(rotatedInviter.profile?.id).toBeTruthy();

      const started = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: rotatedInviter.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      expect(started.active).toBe(true);

      const rotatePackage = await app.request<string>('create_generated_onboarding_package', {
        share_package_json: rotated.shares[0].share_package_json,
        relay_urls: [harness.relayUrl],
        peer_pubkey: rotated.shares[1].share_public_key,
        package_password: 'rotation-update-password',
      });
      expect(rotatePackage.startsWith('bfonboard1')).toBe(true);

      const updated = await app.request<{
        status: string;
        profile?: { id: string; label?: string };
      }>('apply_rotation_update', {
        target_profile_id: importedA.profile!.id,
        vault_passphrase: 'playwright-password',
        onboarding_password: 'rotation-update-password',
        onboarding_package: rotatePackage,
      });

      expect(updated.status).toBe('profile_created');
      expect(updated.profile?.id).toBeTruthy();
      expect(updated.profile?.id).not.toBe(importedA.profile?.id);
      expect(updated.profile?.label).toBe('Rotation Target Device');

      const profiles = await app.request<Array<{ id: string; label: string }>>('list_profiles');
      const ids = profiles.map(profile => profile.id);
      expect(ids).not.toContain(importedA.profile!.id);
      expect(ids).toContain(importedB.profile!.id);
      expect(ids).toContain(rotatedInviter.profile!.id);
      expect(ids).toContain(updated.profile!.id);

      const updatedEntry = profiles.find(profile => profile.id === updated.profile!.id);
      expect(updatedEntry?.label).toBe('Rotation Target Device');

      await app.request('stop_signer');
      const restarted = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: updated.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      expect(restarted.active).toBe(true);
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await harness.cleanup();
    }
  });
});
