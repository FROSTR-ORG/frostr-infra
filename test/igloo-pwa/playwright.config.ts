import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { defineConfig } from '@playwright/test';

import { IGLOO_PWA_DIR } from '../shared/repo-paths';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default defineConfig({
  testDir: path.join(__dirname, 'specs'),
  globalSetup: path.join(__dirname, 'global-setup.ts'),
  timeout: 60_000,
  expect: {
    timeout: 10_000,
  },
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  use: {
    baseURL: `http://127.0.0.1:${process.env.IGLOO_PWA_TEST_PORT ?? '4174'}`,
    headless: true,
  },
  webServer: {
    command: `npx vite --host 127.0.0.1 --port ${process.env.IGLOO_PWA_TEST_PORT ?? '4174'} --strictPort`,
    cwd: IGLOO_PWA_DIR,
    url: `http://127.0.0.1:${process.env.IGLOO_PWA_TEST_PORT ?? '4174'}`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
