import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { IGLOO_PWA_DIR } from '../shared/repo-paths';
import {
  defineFrostrPlaywrightConfig,
  frostrPlaywrightOutputDir,
} from '../shared/playwright-config';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webServerEnv = { ...process.env };

delete webServerEnv.NO_COLOR;
delete webServerEnv.FORCE_COLOR;

export default defineFrostrPlaywrightConfig({
  testDir: path.join(__dirname, 'specs'),
  globalSetup: path.join(__dirname, 'global-setup.ts'),
  outputDir: frostrPlaywrightOutputDir('igloo-pwa'),
  use: {
    baseURL: `http://127.0.0.1:${process.env.IGLOO_PWA_TEST_PORT ?? '4174'}`,
    // Keep the PWA signer's runtime pump alive: headless Chromium throttles
    // timers and the renderer in backgrounded/occluded tabs, which can stall the
    // websocket/relay loop in long @live flows. (General hardening — note it did
    // NOT resolve the sign-shell partial-sign round-trip, which is a browser
    // responder gap, not throttling; see dev/BACKLOG.md.)
    launchOptions: {
      args: [
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding',
      ],
    },
  },
  webServer: {
    command: `npx vite --host 127.0.0.1 --port ${process.env.IGLOO_PWA_TEST_PORT ?? '4174'} --strictPort`,
    cwd: IGLOO_PWA_DIR,
    env: webServerEnv,
    url: `http://127.0.0.1:${process.env.IGLOO_PWA_TEST_PORT ?? '4174'}`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
