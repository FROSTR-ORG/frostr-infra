import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { test } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';

// Agent/human "render + see a screen" tool for the igloo-home desktop frontend.
// `make screenshot CLIENT=home STATE=<scenario>` loads the home web frontend with
// `?__igloo_visual=<scenario>` (the resolveVisualScenario seam in
// repos/igloo-home/src/test/visualMode.ts) and writes a full-page PNG + a
// visible-text dump to .tmp/agent/. The running dashboard renders via the
// scenario's sampleRuntimeSnapshot — no live daemon or Tauri host required.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

// Home scenarios differ from pwa/chrome; map the shared `dashboard-running`
// default (and an empty value) onto home's `dashboard-signer`.
const RAW = process.env.FROSTR_SCREENSHOT_STATE;
const STATE = !RAW || RAW === 'dashboard-running' ? 'dashboard-signer' : RAW;
const OUT_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'agent');

test('@agent capture', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1080 });
  await page.goto(`/?__igloo_visual=${encodeURIComponent(STATE)}`);

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByRole('tab', { name: /Signer/i }).first().waitFor({ state: 'visible', timeout: 20_000 });
  } else {
    await page.getByRole('heading', { name: 'Igloo' }).first().waitFor({ state: 'visible', timeout: 20_000 });
  }

  await mkdir(OUT_DIR, { recursive: true });
  const pngPath = path.join(OUT_DIR, `home-${STATE}.png`);
  const txtPath = path.join(OUT_DIR, `home-${STATE}.txt`);
  await page.screenshot({ path: pngPath, fullPage: true });
  const text = await page.locator('body').innerText();
  await writeFile(txtPath, text, 'utf8');

  // Machine-readable result so an agent can locate the artifacts without
  // scraping stdout. Reaching this point means the target surface rendered;
  // a failed render fails the test (non-zero exit) and this is not rewritten.
  await writeFile(
    path.join(OUT_DIR, 'screenshot.json'),
    `${JSON.stringify({ ok: true, client: 'home', state: STATE, png: pngPath, txt: txtPath }, null, 2)}\n`,
    'utf8',
  );

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${pngPath}`);
});
