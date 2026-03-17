import { defineConfig } from '@playwright/test';
import path from 'node:path';
import { TEST_ROOT_DIR } from '../shared/repo-paths';

export default defineConfig({
  testDir: path.join(TEST_ROOT_DIR, 'igloo-home', 'specs'),
  timeout: 120_000,
  fullyParallel: false,
  workers: 1,
  reporter: 'list',
});
