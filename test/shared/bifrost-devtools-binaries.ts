import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

import { BIFROST_RS_DIR } from './repo-paths';

export const BIFROST_DEVTOOLS_BINARY_PATH = path.join(
  BIFROST_RS_DIR,
  'target',
  'debug',
  'bifrost-devtools',
);

let devtoolsPrepared = false;

export function ensureBifrostDevtoolsBinary() {
  if (devtoolsPrepared) return BIFROST_DEVTOOLS_BINARY_PATH;
  if (process.env.FROSTR_TEST_PREPARED === '1' && existsSync(BIFROST_DEVTOOLS_BINARY_PATH)) {
    devtoolsPrepared = true;
    return BIFROST_DEVTOOLS_BINARY_PATH;
  }
  execFileSync(
    'cargo',
    ['build', '--offline', '--locked', '-p', 'bifrost-devtools', '--bin', 'bifrost-devtools'],
    {
      cwd: BIFROST_RS_DIR,
      stdio: 'inherit',
      env: process.env,
    },
  );
  devtoolsPrepared = true;
  return BIFROST_DEVTOOLS_BINARY_PATH;
}
