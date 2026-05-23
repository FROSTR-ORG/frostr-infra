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
  outputDir: frostrPlaywrightOutputDir('igloo-ui-showcase'),
  use: {
    viewport: { width: 1440, height: 1080 },
  },
});
