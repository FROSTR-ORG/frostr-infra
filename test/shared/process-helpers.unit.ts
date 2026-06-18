import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { expect, test } from '@playwright/test';

import { allocatePort } from './port-allocation';
import { closeChild } from './process-lifecycle';
import { registerProcess, reapRegisteredProcesses, unregisterProcess } from './process-registry';

// A node process that stays alive until signalled.
function spawnSleeper() {
  return spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
}

async function settle(ms = 300) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

test.describe('shared/port-allocation', () => {
  test('allocatePort returns valid TCP ports', async () => {
    const a = await allocatePort();
    const b = await allocatePort();
    for (const port of [a, b]) {
      expect(Number.isInteger(port)).toBe(true);
      expect(port).toBeGreaterThan(0);
      expect(port).toBeLessThan(65_536);
    }
  });
});

test.describe('shared/process-lifecycle', () => {
  test('closeChild terminates a running child and resolves', async () => {
    const child = spawnSleeper();
    await closeChild(child);
    expect(child.exitCode !== null || child.signalCode !== null).toBe(true);
  });

  test('closeChild is idempotent (a second call is a no-op)', async () => {
    const child = spawnSleeper();
    await closeChild(child);
    await closeChild(child); // must neither hang nor throw
    expect(child.exitCode !== null || child.signalCode !== null).toBe(true);
  });

  test('closeChild on an already-exited child returns immediately', async () => {
    const child = spawn(process.execPath, ['-e', 'process.exit(0)'], { stdio: 'ignore' });
    await new Promise((resolve) => child.once('exit', resolve));
    await closeChild(child); // guard short-circuits; resolves
  });
});

test.describe('shared/process-registry', () => {
  test('register marks, unregister clears, reap kills only registered processes', async () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'frostr-registry-'));
    process.env.FROSTR_TEST_PROCESS_REGISTRY_DIR = dir;
    const survivor = spawnSleeper();
    const doomed = spawnSleeper();
    try {
      // unregister removes the marker without killing the process
      registerProcess(survivor.pid);
      expect(existsSync(path.join(dir, String(survivor.pid)))).toBe(true);
      unregisterProcess(survivor.pid);
      expect(existsSync(path.join(dir, String(survivor.pid)))).toBe(false);

      // reap SIGKILLs whatever is still registered and clears the markers
      registerProcess(doomed.pid);
      reapRegisteredProcesses();
      await settle();
      expect(doomed.exitCode !== null || doomed.signalCode !== null || doomed.killed).toBe(true);
      expect(existsSync(path.join(dir, String(doomed.pid)))).toBe(false);

      // the unregistered survivor was never reaped
      expect(survivor.exitCode).toBeNull();
    } finally {
      await closeChild(survivor);
      await closeChild(doomed);
      delete process.env.FROSTR_TEST_PROCESS_REGISTRY_DIR;
    }
  });
});
