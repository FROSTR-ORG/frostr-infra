type E2ELogLevel = 'debug' | 'info' | 'warn' | 'error';

export type E2EObservabilityEvent = {
  ts: string;
  ts_ms: number;
  level: E2ELogLevel;
  component: string;
  domain: string;
  event: string;
  [key: string]: unknown;
};

const E2E_EVENT_LIMIT = 2_000;
const e2eEvents: E2EObservabilityEvent[] = [];

function pushEvent(event: E2EObservabilityEvent) {
  e2eEvents.push(event);
  if (e2eEvents.length > E2E_EVENT_LIMIT) {
    e2eEvents.splice(0, e2eEvents.length - E2E_EVENT_LIMIT);
  }
}

function emit(event: E2EObservabilityEvent) {
  pushEvent(event);
  console.error(JSON.stringify(event));
}

export function clearE2EEvents() {
  e2eEvents.length = 0;
}

export function getE2EEvents() {
  return e2eEvents.slice();
}

export function logE2E(component: string, event: string, detail?: Record<string, unknown>) {
  const now = new Date();
  emit({
    ts: now.toISOString(),
    ts_ms: now.getTime(),
    level: 'info',
    component,
    domain: 'e2e',
    event,
    ...(detail ?? {})
  });
}

export async function withLoggedStep<T>(
  component: string,
  event: string,
  detail: Record<string, unknown> | undefined,
  run: () => Promise<T>
): Promise<T> {
  const startedAt = Date.now();
  logE2E(component, `${event}:start`, detail);
  try {
    const result = await run();
    logE2E(component, `${event}:ok`, {
      ...(detail ?? {}),
      elapsed_ms: Date.now() - startedAt
    });
    return result;
  } catch (error) {
    emit({
      ts: new Date().toISOString(),
      ts_ms: Date.now(),
      level: 'error',
      component,
      domain: 'e2e',
      event: `${event}:fail`,
      ...(detail ?? {}),
      elapsed_ms: Date.now() - startedAt,
      error_message: error instanceof Error ? error.message : String(error)
    });
    throw error;
  }
}
