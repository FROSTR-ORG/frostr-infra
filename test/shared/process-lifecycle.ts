import type { ChildProcess } from 'node:child_process';

/**
 * Terminate a spawned child idempotently: send SIGTERM, escalate to SIGKILL if it
 * has not exited within `timeoutMs`, and always resolve. Safe to call more than
 * once — a call after the process has already exited is a no-op. Replaces the
 * per-fixture close() variants the audit flagged (double-close races, a home
 * close() with no SIGKILL escalation).
 */
export async function closeChild(
  child: ChildProcess,
  options: { timeoutMs?: number } = {},
): Promise<void> {
  const timeoutMs = options.timeoutMs ?? 1_000;
  if (child.exitCode !== null || child.signalCode !== null) return;
  await new Promise<void>((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(killTimer);
      clearTimeout(hardTimer);
      resolve();
    };
    // Escalate to SIGKILL if SIGTERM didn't take.
    const killTimer = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill('SIGKILL');
      }
    }, timeoutMs);
    // Guarantee resolution even if the 'exit' event was missed (e.g. the process
    // exited between the guard above and the listener attach).
    const hardTimer = setTimeout(finish, timeoutMs + 2_000);
    child.once('exit', finish);
    child.kill('SIGTERM');
  });
}
