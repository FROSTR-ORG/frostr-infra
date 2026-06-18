import { test } from '@playwright/test';

import { captureAgentArtifact } from '../../shared/visual-harness';

// Agent/human "render + see a screen" tool. `make screenshot STATE=<scenario>`
// loads the PWA with `?__frostr_dev=<scenario>` (the in-memory dev-scenario seam
// in repos/igloo-pwa/src/lib/dev-scenario.ts) and writes a full-page PNG + a
// visible-text dump + screenshot.json to .tmp/agent/ (via the shared
// visual-harness). pwa is the default client, so its artifacts are bare
// `<state>.{png,txt}` (no client prefix). Unlike the storage-only seed, this can
// render the *running* dashboard (peers / event log) via a seeded runtimeSnapshot.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

const STATE = process.env.FROSTR_SCREENSHOT_STATE || 'dashboard-running';

test('@agent capture', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1080 });
  await page.goto(`/?__frostr_dev=${encodeURIComponent(STATE)}`);

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByTestId('dashboard-root').waitFor({ state: 'visible', timeout: 15_000 });
  } else {
    await page.getByRole('heading', { name: 'Igloo Web' }).waitFor({ state: 'visible', timeout: 15_000 });
  }

  const { png } = await captureAgentArtifact(page, { client: 'pwa', state: STATE, baseName: STATE });

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${png}`);
});
