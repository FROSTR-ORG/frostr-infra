import { reapRegisteredProcesses } from './process-registry';

// Playwright globalTeardown (runs once in the main process after all workers): reap
// any registered helper processes (local relays, the native signer relay) that
// outlived their spec, e.g. after a mid-test crash that skipped close(). In the
// happy path the registry is empty and this is a no-op.
export default function globalTeardown(): void {
  reapRegisteredProcesses();
}
