import path from 'node:path';
import { TEST_ROOT_DIR } from '../shared/repo-paths';
import {
  defineFrostrPlaywrightConfig,
  frostrPlaywrightOutputDir,
} from '../shared/playwright-config';

export default defineFrostrPlaywrightConfig({
  testDir: path.join(TEST_ROOT_DIR, 'igloo-home', 'specs'),
  globalSetup: path.join(TEST_ROOT_DIR, 'igloo-home', 'global-setup.ts'),
  timeout: 120_000,
  reporter: 'list',
  outputDir: frostrPlaywrightOutputDir('igloo-home'),
});
