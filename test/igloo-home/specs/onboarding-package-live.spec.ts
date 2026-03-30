import { test, expect } from '@playwright/test';

import { launchIglooHome } from '../fixtures/app';
import {
  aliceReadiness,
  aliceRuntimeDiagnostics,
  ensureDemoHarness,
  signWithBob,
  waitForAliceSignReady,
} from '../fixtures/harness';

test.describe('igloo-home onboarding package', () => {
  test('accepts Bob onboarding package and responds to live ping/sign', async () => {
    test.skip(!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY, 'desktop display is required');

    const harness = await ensureDemoHarness();
    const app = await launchIglooHome();
    try {
      const connected = await app.request<{
        preview: {
          label: string;
          share_public_key: string;
          group_public_key: string;
        };
      }>('connect_onboarding_package', {
        onboarding_password: harness.onboardPassword,
        package: harness.onboardPackage,
      });
      expect(connected.preview.label).toBeTruthy();

      const imported = await app.request<{
        status: string;
        profile?: { id: string };
        diagnostics?: unknown;
      }>('finalize_connected_onboarding', {
        label: 'Bob Onboarding Import',
        relay_profile: null,
        vault_passphrase: 'playwright-password',
      });
      expect(imported.status).toBe('profile_created');

      try {
        const snapshot = await app.request<{ active: boolean }>('start_profile_session', {
          profile_id: imported.profile!.id,
          vault_passphrase: 'playwright-password',
        });
        expect(snapshot.active).toBe(true);

        await waitForAliceSignReady(harness);
        const sign = await signWithBob(harness);
        expect(sign.ok, JSON.stringify(sign, null, 2)).toBe(true);
      } catch (error) {
        const [runtimeSnapshot, sessionLogs, aliceReady, aliceDiagnostics] = await Promise.all([
          app
            .request('profile_runtime_snapshot', { profile_id: imported.profile!.id })
            .catch(cause => ({ snapshot_error: String(cause) })),
          app
            .request('list_session_logs', {})
            .catch(cause => ({ logs_error: String(cause) })),
          aliceReadiness(harness).catch(cause => ({ ok: false, error: String(cause) })),
          aliceRuntimeDiagnostics(harness).catch(cause => ({ ok: false, error: String(cause) })),
        ]);
        throw new Error(
          [
            error instanceof Error ? error.message : String(error),
            `import diagnostics: ${JSON.stringify(imported.diagnostics ?? null, null, 2)}`,
            `bob runtime snapshot: ${JSON.stringify(runtimeSnapshot, null, 2)}`,
            `bob session logs: ${JSON.stringify(sessionLogs, null, 2)}`,
            `alice readiness: ${JSON.stringify(aliceReady, null, 2)}`,
            `alice runtime diagnostics: ${JSON.stringify(aliceDiagnostics, null, 2)}`,
          ].join('\n\n'),
        );
      }
    } finally {
      await app.request('stop_signer').catch(() => undefined);
      await app.close();
      await harness.cleanup();
    }
  });
});
