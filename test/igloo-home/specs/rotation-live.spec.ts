import { test, expect } from '@playwright/test';

import { launchIglooHome } from '../fixtures/app';
import { ensureDemoHarness } from '../fixtures/harness';

test.describe('igloo-home rotation', () => {
  test('rotates from threshold bfshare sources and distributes rotated shares via bfonboard', async () => {
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
        group_name: 'Rotation Live Group',
        threshold: 2,
        count: 3,
      });

      const sourceA = generated.shares[0];
      const sourceB = generated.shares[1];

      const importedA = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Rotation Source A',
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

      const exportedA = await app.request<{ format: string; package: string }>('export_profile_package', {
        profile_id: importedA.profile!.id,
        format: 'bfshare',
        package_password: 'rotation-source-a',
        vault_passphrase: 'playwright-password',
      });
      const exportedB = await app.request<{ format: string; package: string }>('export_profile_package', {
        profile_id: importedB.profile!.id,
        format: 'bfshare',
        package_password: 'rotation-source-b',
        vault_passphrase: 'playwright-password',
      });

      expect(exportedA.format).toBe('bfshare');
      expect(exportedB.format).toBe('bfshare');

      const rotated = await app.request<{
        source: string;
        group_package_json: string;
        group_public_key: string;
        shares: Array<{
          member_idx: number;
          share_public_key: string;
          share_package_json: string;
        }>;
      }>('create_rotated_keyset', {
        threshold: 2,
        count: 3,
        sources: [
          {
            package: exportedA.package,
            package_password: 'rotation-source-a',
          },
          {
            package: exportedB.package,
            package_password: 'rotation-source-b',
          },
        ],
      });

      expect(rotated.source).toBe('rotated');
      expect(rotated.group_public_key).toBe(generated.group_public_key);
      expect(rotated.shares).toHaveLength(3);
      expect(rotated.shares[0].share_public_key).not.toBe(sourceA.share_public_key);

      const rotatedLocal = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_raw', {
        label: 'Rotated Local Device',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: rotated.group_package_json,
        share_package_json: rotated.shares[0].share_package_json,
      });
      expect(rotatedLocal.status).toBe('profile_created');
      expect(rotatedLocal.profile?.id).toBeTruthy();
      expect(rotatedLocal.profile?.id).not.toBe(importedA.profile?.id);
      expect(rotatedLocal.profile?.id).not.toBe(importedB.profile?.id);

      const started = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: rotatedLocal.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      expect(started.active).toBe(true);

      const rotatePackage = await app.request<string>('create_generated_onboarding_package', {
        share_package_json: rotated.shares[1].share_package_json,
        relay_urls: [harness.relayUrl],
        peer_pubkey: rotated.shares[0].share_public_key,
        package_password: 'rotation-onboard-password',
      });
      expect(rotatePackage.startsWith('bfonboard1')).toBe(true);

      const rotatedRemote = await app.request<{
        status: string;
        profile?: { id: string };
      }>('import_profile_from_onboarding', {
        label: 'Rotated Remote Device',
        vault_passphrase: 'playwright-password',
        onboarding_password: 'rotation-onboard-password',
        relay_profile: null,
        package: rotatePackage,
      });

      expect(rotatedRemote.status).toBe('profile_created');
      expect(rotatedRemote.profile?.id).toBeTruthy();
      expect(rotatedRemote.profile?.id).not.toBe(rotatedLocal.profile?.id);
      expect(rotatedRemote.profile?.id).not.toBe(importedA.profile?.id);
      expect(rotatedRemote.profile?.id).not.toBe(importedB.profile?.id);

      const profiles = await app.request<Array<{ id: string }>>('list_profiles');
      const ids = profiles.map(profile => profile.id);
      expect(ids).toContain(importedB.profile!.id);
      expect(ids).toContain(rotatedLocal.profile!.id);
      expect(ids).toContain(rotatedRemote.profile!.id!);
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await harness.cleanup();
    }
  });
});
