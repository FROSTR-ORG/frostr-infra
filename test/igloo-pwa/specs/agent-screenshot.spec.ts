import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { test } from '@playwright/test';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';

// Agent/human "render + see a screen" tool. `make screenshot STATE=<scenario>`
// loads the PWA with `?__frostr_dev=<scenario>` (the in-memory dev-scenario seam
// in repos/igloo-pwa/src/lib/dev-scenario.ts) and writes a full-page PNG + a
// visible-text dump to .tmp/agent/. Unlike the storage-only seed, this can render
// the *running* dashboard (peers / event log) via a seeded runtimeSnapshot.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

const STATE = process.env.FROSTR_SCREENSHOT_STATE || 'dashboard-running';
const OUT_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'agent');

test('@agent capture', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1080 });
  await page.goto(`/?__frostr_dev=${encodeURIComponent(STATE)}`);

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByTestId('dashboard-root').waitFor({ state: 'visible', timeout: 15_000 });
  } else {
    await page.getByRole('heading', { name: 'Igloo Web' }).waitFor({ state: 'visible', timeout: 15_000 });
  }

  await mkdir(OUT_DIR, { recursive: true });
  await page.screenshot({ path: path.join(OUT_DIR, `${STATE}.png`), fullPage: true });
  const text = await page.locator('body').innerText();
  await writeFile(path.join(OUT_DIR, `${STATE}.txt`), text, 'utf8');

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${path.join(OUT_DIR, `${STATE}.png`)}`);
});
