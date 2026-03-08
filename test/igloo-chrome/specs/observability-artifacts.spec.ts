import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { promisify } from 'node:util';

import { test, expect } from '@playwright/test';

import { TEST_ROOT_DIR } from '../../shared/repo-paths';

const execFileAsync = promisify(execFile);

async function collectFiles(rootDir: string): Promise<string[]> {
  const entries = await readdir(rootDir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    const nextPath = path.join(rootDir, entry.name);
    if (entry.isDirectory()) {
      results.push(...(await collectFiles(nextPath)));
    } else {
      results.push(nextPath);
    }
  }
  return results;
}

test.describe('observability artifacts', () => {
  test.setTimeout(180_000);

  test('writes a failure-only observability bundle', async () => {
    const outputDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-observability-'));

    try {
      let failed = false;
      try {
        await execFileAsync(
          'npx',
          [
            'playwright',
            'test',
            '-c',
            './igloo-chrome/playwright.config.ts',
            './igloo-chrome/specs/observability-intentional-failure.spec.ts',
            '--output',
            outputDir
          ],
          {
            cwd: TEST_ROOT_DIR,
            env: {
              ...process.env,
              OBS_BUNDLE_INNER: '1',
              VITE_IGLOO_VERBOSE: process.env.VITE_IGLOO_VERBOSE ?? '1',
              VITE_IGLOO_DEBUG: process.env.VITE_IGLOO_DEBUG ?? '0'
            }
          }
        );
      } catch (error) {
        failed = true;
        const output =
          error && typeof error === 'object'
            ? `${'stdout' in error ? String(error.stdout) : ''}\n${
                'stderr' in error ? String(error.stderr) : ''
              }`
            : '';
        expect(output).toContain('intentional failure for observability bundle smoke test');
      }

      expect(failed).toBe(true);

      const files = await collectFiles(outputDir);
      const bundlePath = files.find((filePath) => filePath.endsWith('observability-bundle.json'));
      expect(bundlePath).toBeTruthy();

      const bundleRaw = await readFile(bundlePath!, 'utf8');
      const bundle = JSON.parse(bundleRaw) as Record<string, unknown>;
      expect(bundle).toHaveProperty('e2eEvents');
      expect(bundle).toHaveProperty('runtimeDiagnostics');
      expect(bundle).toHaveProperty('status');
    } finally {
      await rm(outputDir, { recursive: true, force: true });
    }
  });
});
