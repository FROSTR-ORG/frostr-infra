import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { IGLOO_HOME_DIR, REPO_ROOT_DIR } from './repo-paths';

export function runTestPrebuild(targets: string[]) {
  if (process.env.FROSTR_TEST_PREPARED === '1') {
    if (targets.includes('home')) {
      process.env.IGLOO_HOME_TEST_SKIP_BUILD = '1';
      process.env.IGLOO_HOME_TEST_BINARY ??= path.join(
        IGLOO_HOME_DIR,
        'src-tauri',
        'target',
        'debug',
        'igloo-home',
      );
    }
    return;
  }

  execFileSync('bash', [path.join(REPO_ROOT_DIR, 'scripts', 'test-prebuild.sh'), ...targets], {
    cwd: REPO_ROOT_DIR,
    stdio: 'inherit',
    env: process.env,
  });

  process.env.FROSTR_TEST_PREPARED = '1';
  if (targets.includes('home')) {
    process.env.IGLOO_HOME_TEST_SKIP_BUILD = '1';
    process.env.IGLOO_HOME_TEST_BINARY ??= path.join(
      IGLOO_HOME_DIR,
      'src-tauri',
      'target',
      'debug',
      'igloo-home',
    );
  }
}
