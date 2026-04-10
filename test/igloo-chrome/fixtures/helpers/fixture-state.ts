const extensionPageErrors = new Map<string, string[]>();
let workerOnboardingFailureBundle: Record<string, unknown> | null = null;

export function clearFixtureDiagnostics() {
  extensionPageErrors.clear();
  workerOnboardingFailureBundle = null;
}

export function recordPageDiagnostic(url: string, message: string) {
  const existing = extensionPageErrors.get(url) ?? [];
  existing.push(message);
  if (existing.length > 25) {
    existing.splice(0, existing.length - 25);
  }
  extensionPageErrors.set(url, existing);
}

export function getPageDiagnostics() {
  return Object.fromEntries(extensionPageErrors);
}

export function getWorkerOnboardingFailureBundle() {
  return workerOnboardingFailureBundle;
}

export function setWorkerOnboardingFailureBundle(bundle: Record<string, unknown> | null) {
  workerOnboardingFailureBundle = bundle;
}
