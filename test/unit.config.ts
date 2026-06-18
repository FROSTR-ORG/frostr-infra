import { defineConfig } from '@playwright/test';

// Pure-node unit tests for the shared harness helpers (no browser, no relay, no
// webServer). Matched by `*.unit.ts` so the lane-tag guard (which scans
// `*.spec.ts`) and the e2e client configs ignore them. Run via
// `npm run test:unit:shared`.
export default defineConfig({
  testDir: './shared',
  testMatch: '**/*.unit.ts',
  fullyParallel: false,
  workers: 1,
  reporter: [['line']],
  timeout: 30_000,
});
