import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  defineFrostrPlaywrightConfig,
  frostrPlaywrightOutputDir,
} from '../shared/playwright-config';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default defineFrostrPlaywrightConfig({
  testDir: path.join(__dirname, 'specs'),
  globalSetup: path.join(__dirname, 'global-setup.ts'),
  outputDir: frostrPlaywrightOutputDir('igloo-chrome'),
  use: {
    video: 'retain-on-failure'
  }
});
