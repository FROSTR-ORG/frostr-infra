import { captureAgentArtifact } from '../../shared/visual-harness';
import { test } from '../fixtures/extension';

// Agent/human "render + see a screen" tool for the Chrome extension options page.
// `make screenshot CLIENT=chrome STATE=<scenario>` loads
// options.html?__frostr_dev=<scenario> (the in-memory dev-scenario seam in
// repos/igloo-chrome/src/lib/dev-scenario.ts) and writes a full-page PNG + a
// visible-text dump + screenshot.json to .tmp/agent/ (via the shared
// visual-harness). Unlike the storage-only seedProfile fixture, this can render
// the *running* dashboard (peers / status) without a live signer.
//
// Tagged @agent so it stays out of the normal test lanes; it is a tool, not a test.

const STATE = process.env.FROSTR_SCREENSHOT_STATE || 'dashboard-running';

test('@agent capture', async ({ openExtensionPage }) => {
  const page = await openExtensionPage(`options.html?__frostr_dev=${encodeURIComponent(STATE)}`);
  await page.setViewportSize({ width: 1440, height: 1080 });

  // Wait for the relevant surface to render before capturing.
  if (STATE.startsWith('dashboard')) {
    await page.getByRole('tab', { name: /Signer/i }).first().waitFor({ state: 'visible', timeout: 15_000 });
  } else {
    // Onboarding state: may show WelcomeEntryHero (no profiles) or
    // WelcomeReturningHero (stored profiles present) — wait for either.
    await Promise.race([
      page.locator('[aria-labelledby="igloo-welcome-returning-title"]').waitFor({ state: 'visible', timeout: 15_000 }),
      page.locator('[aria-labelledby="igloo-welcome-entry-title"]').waitFor({ state: 'visible', timeout: 15_000 }),
    ]);
  }

  const { png } = await captureAgentArtifact(page, { client: 'chrome', state: STATE });

  // eslint-disable-next-line no-console
  console.log(`screenshot: ${png}`);
});
