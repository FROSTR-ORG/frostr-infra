import path from 'node:path';

import { defineConfig, type PlaywrightTestConfig } from '@playwright/test';

import { TEST_ROOT_DIR } from './repo-paths';

export function frostrPlaywrightOutputDir(name: string) {
  return path.join(TEST_ROOT_DIR, 'test-results', name);
}

// Centralized timeouts for slow/live specs (two-device relay handshakes, desktop
// app startup). Live specs opt in with `test.setTimeout(LIVE_TEST_TIMEOUT_MS)`
// rather than scattering magic numbers / `test.slow()`.
export const LIVE_TEST_TIMEOUT_MS = 240_000;
export const LIVE_EXPECT_TIMEOUT_MS = 20_000;

export function defineFrostrPlaywrightConfig(config: PlaywrightTestConfig) {
  return defineConfig({
    timeout: 60_000,
    reporter: [['line']],
    reportSlowTests: {
      max: 10,
      threshold: 15_000,
    },
    fullyParallel: false,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 1 : 0,
    workers: 1,
    // Reap any registered helper processes (local relays, native signer relay)
    // that outlived their spec after a mid-test crash. A client config may
    // override this; today none do.
    globalTeardown: path.join(TEST_ROOT_DIR, 'shared', 'global-teardown.ts'),
    ...config,
    expect: {
      timeout: 10_000,
      ...config.expect,
    },
    use: {
      headless: true,
      trace: 'retain-on-failure',
      screenshot: 'only-on-failure',
      ...config.use,
    },
  });
}
