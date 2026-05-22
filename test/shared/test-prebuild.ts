import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { IGLOO_HOME_DIR, REPO_ROOT_DIR } from './repo-paths';

const PREPARED_TARGETS_ENV = 'FROSTR_TEST_PREPARED_TARGETS';

function normalizedTargets(targets: string[]) {
  return Array.from(new Set(targets)).sort();
}

function preparedTargets() {
  return new Set(
    (process.env[PREPARED_TARGETS_ENV] ?? '')
      .split(',')
      .map((target) => target.trim())
      .filter(Boolean),
  );
}

function markPrepared(targets: string[]) {
  const prepared = preparedTargets();
  for (const target of targets) {
    prepared.add(target);
  }
  process.env[PREPARED_TARGETS_ENV] = Array.from(prepared).sort().join(',');
}

function targetsPrepared(targets: string[]) {
  const prepared = preparedTargets();
  return targets.every((target) => prepared.has(target));
}

export function runTestPrebuild(targets: string[]) {
  const requestedTargets = normalizedTargets(targets);
  const includesHome = requestedTargets.includes('home');
  const includesDemo = requestedTargets.includes('demo');

  if (process.env.FROSTR_TEST_PREPARED === '1' || targetsPrepared(requestedTargets)) {
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
    execFileSync('bash', [scriptPath, 'check', ...requestedTargets], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit',
      env: process.env,
    });
  } catch {
    execFileSync('bash', [scriptPath, 'sync', ...requestedTargets], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit',
      env: process.env,
    });
  }

  markPrepared(requestedTargets);
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
