import { execFileSync } from 'node:child_process';

import { ensureBifrostDevtoolsBinary } from '../shared/bifrost-devtools-binaries';
import { ensureIglooShellBinary } from '../shared/igloo-shell-binaries';
import { IGLOO_CHROME_DIR } from '../shared/repo-paths';

export default async function globalSetup() {
  ensureBifrostDevtoolsBinary();
  ensureIglooShellBinary();

  execFileSync('node', ['./scripts/ensure-bridge-wasm.mjs'], {
    cwd: IGLOO_CHROME_DIR,
    stdio: 'inherit',
    env: process.env
  });

  execFileSync('npm', ['run', 'build'], {
    cwd: IGLOO_CHROME_DIR,
    stdio: 'inherit',
    env: {
      ...process.env,
      VITE_IGLOO_VERBOSE: process.env.VITE_IGLOO_VERBOSE ?? '1',
      VITE_IGLOO_DEBUG: process.env.VITE_IGLOO_DEBUG ?? '0'
    }
  });
}
