import path from 'node:path';

import { defineConfig, type PlaywrightTestConfig } from '@playwright/test';

import { TEST_ROOT_DIR } from './repo-paths';

export function frostrPlaywrightOutputDir(name: string) {
  return path.join(TEST_ROOT_DIR, 'test-results', name);
}

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
