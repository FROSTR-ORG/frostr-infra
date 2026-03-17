import { test, expect } from '@playwright/test';

import { launchIglooHome } from '../fixtures/app';
import { ensureDemoHarness, onboardBobFromAlice, pingBob, signWithBob, waitForAliceSignReady } from '../fixtures/harness';

test.describe('igloo-home live raw import', () => {
  test('imports Bob raw artifacts and responds to live ping/sign', async () => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const harness = await ensureDemoHarness();
    const app = await launchIglooHome();
    try {
      const imported = await app.request<{ status: string; profile?: { id: string } }>('import_profile_from_raw', {
        label: 'Bob Raw Import',
        relay_urls: [harness.relayUrl],
        relay_profile: null,
        vault_passphrase: 'playwright-password',
        group_package_json: harness.bobGroupJson,
        share_package_json: harness.bobShareJson,
      });
      expect(imported.status).toBe('profile_created');
      expect(imported.profile?.id).toBeTruthy();

      const snapshot = await app.request<{ active: boolean }>('start_profile_session', {
        profile_id: imported.profile!.id,
        vault_passphrase: 'playwright-password',
      });
      expect(snapshot.active).toBe(true);

      const ping = await pingBob(harness);
      expect(ping.ok, JSON.stringify(ping, null, 2)).toBe(true);

      const onboard = await onboardBobFromAlice(harness);
      expect(onboard.ok, JSON.stringify(onboard, null, 2)).toBe(true);

      await waitForAliceSignReady(harness);
      const sign = await signWithBob(harness);
      expect(sign.ok, JSON.stringify(sign, null, 2)).toBe(true);
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await harness.cleanup();
    }
  });
});
