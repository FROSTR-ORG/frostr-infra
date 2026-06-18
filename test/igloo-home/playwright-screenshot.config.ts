import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { IGLOO_HOME_DIR } from '../shared/repo-paths';
import {
  defineFrostrPlaywrightConfig,
  frostrPlaywrightOutputDir,
} from '../shared/playwright-config';

// Headless render config for the `make screenshot CLIENT=home` @agent capture
// ONLY. The home desktop e2e suite runs through ./igloo-home/run-e2e.sh
// (tauri-driver, playwright.config.ts). This config keeps a separate testDir so
// it never sweeps the live specs, and serves the home web frontend (vite) so the
// dashboard renders via the `?__igloo_visual=<scenario>` seam in a plain browser
// (Tauri calls are guarded under a visual scenario). `npm run dev` handles the
// workspace prep (igloo-ui build) before serving on :1420.

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webServerEnv = { ...process.env };

delete webServerEnv.NO_COLOR;
delete webServerEnv.FORCE_COLOR;

const PORT = process.env.IGLOO_HOME_TEST_PORT ?? '1420';

export default defineFrostrPlaywrightConfig({
  testDir: path.join(__dirname, 'screenshot'),
  outputDir: frostrPlaywrightOutputDir('igloo-home'),
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
  },
  webServer: {
    command: 'npm run dev',
    cwd: IGLOO_HOME_DIR,
    env: webServerEnv,
    url: `http://127.0.0.1:${PORT}`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
