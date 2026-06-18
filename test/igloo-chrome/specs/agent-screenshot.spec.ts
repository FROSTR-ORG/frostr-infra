import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { test } from '../fixtures/extension';

// Agent/human "render + see a screen" tool for the Chrome extension options page.
// `make screenshot CLIENT=chrome STATE=<scenario>` loads
// options.html?__frostr_dev=<scenario> (the in-memory dev-scenario seam in
// repos/igloo-chrome/src/lib/dev-scenario.ts) and writes a full-page PNG + a
// visible-text dump to .tmp/agent/. Unlike the storage-only seedProfile fixture,
// this can render the *running* dashboard (peers / status) without a live signer.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

const STATE = process.env.FROSTR_SCREENSHOT_STATE || 'dashboard-running';
const OUT_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'agent');

test('@agent capture', async ({ openExtensionPage }) => {
  const page = await openExtensionPage(`options.html?__frostr_dev=${encodeURIComponent(STATE)}`);
  await page.setViewportSize({ width: 1440, height: 1080 });

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByRole('tab', { name: /Signer/i }).first().waitFor({ state: 'visible', timeout: 15_000 });
  } else {
    await page.getByRole('heading', { name: 'Onboard Device' }).waitFor({ state: 'visible', timeout: 15_000 });
  }

  await mkdir(OUT_DIR, { recursive: true });
  const pngPath = path.join(OUT_DIR, `chrome-${STATE}.png`);
  const txtPath = path.join(OUT_DIR, `chrome-${STATE}.txt`);
  await page.screenshot({ path: pngPath, fullPage: true });
  const text = await page.locator('body').innerText();
  await writeFile(txtPath, text, 'utf8');

  // Machine-readable result so an agent can locate the artifacts without
  // scraping stdout. Reaching this point means the target surface rendered;
  // a failed render fails the test (non-zero exit) and this is not rewritten.
  await writeFile(
    path.join(OUT_DIR, 'screenshot.json'),
    `${JSON.stringify({ ok: true, client: 'chrome', state: STATE, png: pngPath, txt: txtPath }, null, 2)}\n`,
    'utf8',
  );

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${pngPath}`);
});
