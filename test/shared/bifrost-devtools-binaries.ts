import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';

import { BIFROST_RS_DIR } from './repo-paths';

export const BIFROST_DEVTOOLS_BINARY_PATH = path.join(
  BIFROST_RS_DIR,
  'target',
  'debug',
  'bifrost-devtools',
);

let devtoolsPrepared = false;

function resolveCargoBinary() {
  if (process.env.CARGO && existsSync(process.env.CARGO)) return process.env.CARGO;

  for (const entry of (process.env.PATH ?? '').split(path.delimiter)) {
    if (!entry) continue;
    const candidate = path.join(entry, 'cargo');
    if (existsSync(candidate)) return candidate;
  }

  const rustupCargo = path.join(homedir(), '.cargo', 'bin', 'cargo');
  if (existsSync(rustupCargo)) return rustupCargo;

  return 'cargo';
}

export function ensureBifrostDevtoolsBinary() {
  if (devtoolsPrepared) return BIFROST_DEVTOOLS_BINARY_PATH;
  if (process.env.FROSTR_TEST_PREPARED === '1' && existsSync(BIFROST_DEVTOOLS_BINARY_PATH)) {
    devtoolsPrepared = true;
    return BIFROST_DEVTOOLS_BINARY_PATH;
  }
  if (process.env.FROSTR_TEST_PREPARED === '1') {
    throw new Error(
      `FROSTR_TEST_PREPARED=1 but missing prepared bifrost-devtools binary at ${BIFROST_DEVTOOLS_BINARY_PATH}. Run make test-prep before this spec.`,
    );
  }
  execFileSync(
    resolveCargoBinary(),
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
