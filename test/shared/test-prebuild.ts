import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

import { IGLOO_HOME_DIR, REPO_ROOT_DIR, TEST_ROOT_DIR } from './repo-paths';
import { setDefaultTestBrowserWasmDir } from './browser-wasm-paths';

const PREPARED_TARGETS_ENV = 'FROSTR_TEST_PREPARED_TARGETS';

interface TestTargetsManifest {
  clients: Record<string, { paths: string[]; prebuild: string[]; fastPrebuild?: string[] }>;
}

// Single source of truth shared with scripts/test-affected.sh — the per-client
// prebuild target set. Used by the per-client global-setup.ts files so they can
// never drift from the affected-lane wiring. When FROSTR_TEST_LANE=fast (set by the
// :fast npm scripts, which exclude @live and @cross-client specs), the leaner
// `fastPrebuild` set is used so the fast lane does not require cross-client clients
// (e.g. igloo-home/Tauri) that its specs never exercise.
export function targetsForClient(client: string): string[] {
  const manifestPath = path.join(TEST_ROOT_DIR, 'shared', 'test-targets.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as TestTargetsManifest;
  const entry = manifest.clients[client];
  if (!entry) {
    throw new Error(`No test-targets manifest entry for client "${client}"`);
  }
  if (process.env.FROSTR_TEST_LANE === 'fast' && entry.fastPrebuild) {
    return entry.fastPrebuild;
  }
  return entry.prebuild;
}

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
    setDefaultTestBrowserWasmDir();
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
  setDefaultTestBrowserWasmDir();
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
