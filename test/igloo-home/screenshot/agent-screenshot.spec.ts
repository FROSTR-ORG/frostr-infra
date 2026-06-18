import { test } from '@playwright/test';

import { captureAgentArtifact } from '../../shared/visual-harness';

// Agent/human "render + see a screen" tool for the igloo-home desktop frontend.
// `make screenshot CLIENT=home STATE=<scenario>` loads the home web frontend with
// `?__igloo_visual=<scenario>` (the resolveVisualScenario seam in
// repos/igloo-home/src/test/visualMode.ts) and writes a full-page PNG + a
// visible-text dump + screenshot.json to .tmp/agent/ (via the shared
// visual-harness). The running dashboard renders via the scenario's
// sampleRuntimeSnapshot — no live daemon or Tauri host required.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

// Home scenarios differ from pwa/chrome; map the shared `dashboard-running`
// default (and an empty value) onto home's `dashboard-signer`.
const RAW = process.env.FROSTR_SCREENSHOT_STATE;
const STATE = !RAW || RAW === 'dashboard-running' ? 'dashboard-signer' : RAW;

test('@agent capture', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1080 });
  await page.goto(`/?__igloo_visual=${encodeURIComponent(STATE)}`);

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByRole('tab', { name: /Signer/i }).first().waitFor({ state: 'visible', timeout: 20_000 });
  } else {
    await page.getByRole('heading', { name: 'Igloo' }).first().waitFor({ state: 'visible', timeout: 20_000 });
  }

  const { png } = await captureAgentArtifact(page, { client: 'home', state: STATE });

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${png}`);
});
