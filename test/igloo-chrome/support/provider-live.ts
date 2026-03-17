import { expect, type Page } from '@playwright/test';

import {
  assertRuntimeReadiness,
  type RuntimeDiagnosticEvent,
  type RuntimeReadinessResult
} from './runtime';

export const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_000,
  tags: [],
  content: 'playwright live signEvent'
};

export async function prepareSignReady(
  callOffscreenRpc: <T>(rpcType: string, payload?: Record<string, unknown>) => Promise<T>,
  label: string
) {
  const readiness = await callOffscreenRpc<RuntimeReadinessResult>('runtime.prepare_sign');
  assertRuntimeReadiness(label, readiness, 'sign');
}

export async function prepareEcdhReady(
  callOffscreenRpc: <T>(rpcType: string, payload?: Record<string, unknown>) => Promise<T>,
  label: string
) {
  const readiness = await callOffscreenRpc<RuntimeReadinessResult>('runtime.prepare_ecdh');
  assertRuntimeReadiness(label, readiness, 'ecdh');
}

export async function approvePromptOnce(prompt: Page) {
  await prompt.waitForLoadState('domcontentloaded');
  await prompt
    .getByRole('button', { name: 'Allow once' })
    .evaluate((button: HTMLButtonElement) => button.click())
    .catch(() => {
      // The background closes the prompt as part of successful approval.
    });
}

export function buildSignFailureMessage(
  message: string | null,
  diagnostics: RuntimeDiagnosticEvent[]
) {
  return `signEvent failed: ${message}\n${JSON.stringify(diagnostics.slice(-8), null, 2)}`;
}
