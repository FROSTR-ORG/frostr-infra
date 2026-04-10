import { expect, type BrowserContext, type Page } from '@playwright/test';

import type { RuntimeDiagnosticEvent } from './runtime';

export const SIGN_EVENT_PAYLOAD = {
  kind: 1,
  created_at: 1_700_000_000,
  tags: [],
  content: 'playwright live signEvent'
};

export async function approvePromptOnce(prompt: Page) {
  await prompt.waitForLoadState('domcontentloaded');
  await prompt
    .getByRole('button', { name: 'Allow once' })
    .evaluate((button: HTMLButtonElement) => button.click())
    .catch(() => {
      // The background closes the prompt as part of successful approval.
    });
}

export async function runProviderActionWithApproval<T>(
  context: BrowserContext,
  serverOrigin: string,
  promptText: string,
  action: (page: Page) => Promise<T>
) {
  const page = await context.newPage();
  try {
    await page.goto(`${serverOrigin}/provider`);
    const promptPromise = context.waitForEvent(
      'page',
      (candidate) => candidate.url().includes('/prompt.html')
    );
    const resultPromise = action(page);
    const prompt = await promptPromise;
    await expect(prompt.getByText(promptText)).toBeVisible();
    await approvePromptOnce(prompt);
    return await resultPromise;
  } finally {
    await page.close();
  }
}

export function buildSignFailureMessage(
  message: string | null,
  diagnostics: RuntimeDiagnosticEvent[]
) {
  return `signEvent failed: ${message}\n${JSON.stringify(diagnostics.slice(-8), null, 2)}`;
}
