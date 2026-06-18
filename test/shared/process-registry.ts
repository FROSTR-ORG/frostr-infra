import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';

import { REPO_ROOT_DIR } from './repo-paths';

// PIDs of long-lived helper processes (local relays, the native signer relay) are
// recorded as marker files here so the Playwright global teardown can reap any
// that outlived their spec after a mid-test crash. This is SCOPED to this run's
// processes — never a blanket `pkill bifrost-devtools`, which would also kill a
// developer's `make dev` relay. Clean close() unregisters, so in the happy path
// the registry is empty at teardown.
//
// Caveat: a marker that survives a hard crash is cleared (and its PID SIGKILLed)
// by the next run's teardown; if that PID was recycled in the meantime the kill
// could hit an unrelated process. The window is small and test hosts are
// ephemeral, so this is accepted.
const REGISTRY_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'test-processes');

function markerPath(pid: number): string {
  return path.join(REGISTRY_DIR, String(pid));
}

export function registerProcess(pid: number | undefined): void {
  if (!pid) return;
  try {
    mkdirSync(REGISTRY_DIR, { recursive: true });
    writeFileSync(markerPath(pid), '');
  } catch {
    // best effort — the reaper is a safety net, not a correctness dependency
  }
}

export function unregisterProcess(pid: number | undefined): void {
  if (!pid) return;
  try {
    rmSync(markerPath(pid), { force: true });
  } catch {
    // best effort
  }
}

export function reapRegisteredProcesses(): void {
  let entries: string[];
  try {
    entries = readdirSync(REGISTRY_DIR);
  } catch {
    return; // nothing registered
  }
  for (const entry of entries) {
    const pid = Number(entry);
    if (Number.isInteger(pid) && pid > 0) {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        // already gone
      }
    }
    try {
      rmSync(markerPath(pid), { force: true });
    } catch {
      // ignore
    }
  }
}
