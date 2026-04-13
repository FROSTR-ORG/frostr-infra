import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { IGLOO_HOME_DIR, REPO_ROOT_DIR } from './repo-paths';

export function runTestPrebuild(targets: string[]) {
  const includesHome = targets.includes('home');
  const includesDemo = targets.includes('demo');

  if (process.env.FROSTR_TEST_PREPARED === '1') {
    if (includesHome) {
      process.env.IGLOO_HOME_TEST_SKIP_BUILD = '1';
      process.env.IGLOO_HOME_TEST_BINARY ??= path.join(
        IGLOO_HOME_DIR,
        'src-tauri',
        'target',
        'debug',
        'igloo-home',
      );
    }
    if (includesDemo) {
      process.env.FROSTR_DEMO_BINARIES_PREPARED = '1';
    }
    return;
  }

  const scriptPath = path.join(REPO_ROOT_DIR, 'scripts', 'test-prebuild.sh');
  try {
    execFileSync('bash', [scriptPath, 'check', ...targets], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit',
      env: process.env,
    });
  } catch {
    execFileSync('bash', [scriptPath, 'sync', ...targets], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit',
      env: process.env,
    });
  }

  process.env.FROSTR_TEST_PREPARED = '1';
  if (includesHome) {
    process.env.IGLOO_HOME_TEST_SKIP_BUILD = '1';
    process.env.IGLOO_HOME_TEST_BINARY ??= path.join(
      IGLOO_HOME_DIR,
      'src-tauri',
      'target',
      'debug',
      'igloo-home',
    );
  }
  if (includesDemo) {
    process.env.FROSTR_DEMO_BINARIES_PREPARED = '1';
  }
}
